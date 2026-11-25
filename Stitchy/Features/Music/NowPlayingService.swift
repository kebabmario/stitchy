import AppKit
import Observation
import SwiftUI

/// Now-playing information for Apple Music and Spotify.
///
/// Why this approach: macOS 15.4+ blocks third-party apps from the private
/// MediaRemote framework, so there is no supported system-wide "now playing"
/// API. Instead:
///  1. Track title / artist / album / play state arrive through the
///     distributed notifications both apps broadcast on every change.
///     No permission needed, fully event-driven.
///  2. Artwork, playback position and transport controls use Apple Events,
///     which need one-time Automation consent. This is opt-in from the Music tab.
/// Browsers (YouTube etc.) and other players are not supported.
@MainActor @Observable
final class NowPlayingService: NSObject {
    enum Player: String, CaseIterable, Sendable {
        case music = "com.apple.Music"
        case spotify = "com.spotify.client"

        var name: String { self == .music ? "Music" : "Spotify" }
        var notification: Notification.Name {
            Notification.Name(self == .music ? "com.apple.Music.playerInfo" : "com.spotify.client.PlaybackStateChanged")
        }
        /// Cached: looked up once per player, not on every render.
        @MainActor var icon: NSImage? {
            if let cached = Self.icons[self] { return cached }
            let image = NSWorkspace.shared.urlForApplication(withBundleIdentifier: rawValue)
                .map { NSWorkspace.shared.icon(forFile: $0.path) }
            Self.icons[self] = image
            return image
        }
        @MainActor private static var icons: [Player: NSImage] = [:]
        var isRunning: Bool {
            !NSRunningApplication.runningApplications(withBundleIdentifier: rawValue).isEmpty
        }
    }

    enum State: Sendable { case playing, paused, stopped }

    struct Track: Equatable, Sendable {
        var id: String
        var title: String
        var artist: String
        var album: String
        var duration: TimeInterval?
    }

    private(set) var player: Player?
    private(set) var track: Track?
    private(set) var state: State = .stopped
    private(set) var artwork: NSImage?
    private(set) var accent: Color = .white
    private(set) var permission: AppleScriptRunner.Permission = .notDetermined
    /// Position at `positionDate`; extrapolated while playing.
    private(set) var position: TimeInterval?
    private(set) var positionDate = Date()

    @ObservationIgnored var onTrackChange: ((Track, NSImage?) -> Void)?
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private var started = false

    init(settings: AppSettings) {
        self.settings = settings
    }

    var isPlaying: Bool { state == .playing && track != nil }
    var controlsEnabled: Bool { settings.musicControlsEnabled }

    func elapsed(at date: Date) -> TimeInterval? {
        guard let position else { return nil }
        let value = state == .playing ? position + date.timeIntervalSince(positionDate) : position
        return min(value, track?.duration ?? value)
    }

    // MARK: Lifecycle

    func start() {
        guard !started else { return }
        started = true
        let center = DistributedNotificationCenter.default()
        center.addObserver(self, selector: #selector(musicChanged(_:)), name: Player.music.notification, object: nil)
        center.addObserver(self, selector: #selector(spotifyChanged(_:)), name: Player.spotify.notification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(appTerminated(_:)),
            name: NSWorkspace.didTerminateApplicationNotification, object: nil
        )
        if settings.musicControlsEnabled { Task { await refreshFromRunningPlayer() } }
    }

    func stop() {
        guard started else { return }
        started = false
        DistributedNotificationCenter.default().removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        clear()
    }

    private func clear() {
        player = nil
        track = nil
        state = .stopped
        artwork = nil
        position = nil
    }

    // MARK: Notifications (no permission required)

    @objc private func musicChanged(_ note: Notification) {
        handle(note.userInfo ?? [:], from: .music)
    }

    @objc private func spotifyChanged(_ note: Notification) {
        handle(note.userInfo ?? [:], from: .spotify)
    }

    @objc private func appTerminated(_ note: Notification) {
        let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        if let id = app?.bundleIdentifier, id == player?.rawValue { clear() }
    }

    private func handle(_ info: [AnyHashable: Any], from source: Player) {
        let newState: State = switch info["Player State"] as? String {
        case "Playing": .playing
        case "Paused": .paused
        default: .stopped
        }
        // Another player pausing shouldn't steal the island from the one playing.
        if let player, player != source, state == .playing, newState != .playing { return }

        guard newState != .stopped, let title = info["Name"] as? String else {
            if player == source || player == nil {
                islandLog.info("now playing cleared (\(source.name, privacy: .public))")
                clear()
            }
            return
        }

        let durationMS: Double? = source == .music
            ? (info["Total Time"] as? NSNumber)?.doubleValue
            : (info["Duration"] as? NSNumber)?.doubleValue
        let id = (info["PersistentID"] as? NSNumber)?.stringValue
            ?? info["Track ID"] as? String
            ?? "\(title)|\(info["Artist"] as? String ?? "")"
        let newTrack = Track(
            id: id, title: title,
            artist: info["Artist"] as? String ?? "",
            album: info["Album"] as? String ?? "",
            duration: durationMS.map { $0 / 1000 }
        )
        let isNewTrack = newTrack.id != track?.id || source != player

        // Keep the extrapolated position across play/pause.
        let now = Date()
        if isNewTrack {
            position = source == .spotify ? (info["Playback Position"] as? NSNumber)?.doubleValue ?? 0 : 0
        } else if let current = elapsed(at: now) {
            position = (info["Playback Position"] as? NSNumber)?.doubleValue ?? current
        }
        positionDate = now

        player = source
        state = newState
        track = newTrack
        islandLog.info("now playing \(source.name, privacy: .public) state=\(String(describing: newState), privacy: .public) new=\(isNewTrack, privacy: .public)")

        if isNewTrack {
            embeddedLyrics = nil
            // Keep the old art until the new one loads (crossfade); clear it
            // when artwork can't be fetched at all.
            if !settings.musicControlsEnabled { artwork = nil; accent = .white }
            if settings.musicControlsEnabled {
                Task { await refreshDetails(for: source, trackID: newTrack.id, announce: newState == .playing) }
            } else {
                onTrackChange?(newTrack, nil)
            }
        } else if settings.musicControlsEnabled, source == .music {
            Task { await refreshPosition() }
        }
    }

    // MARK: Apple Events (opt-in)

    /// Asks macOS for Automation consent for whichever player is available.
    func enableControls() async {
        settings.musicControlsEnabled = true
        let target = player ?? Player.allCases.first(where: \.isRunning)
        guard let target else {
            permission = .appNotRunning
            return
        }
        permission = await AppleScriptRunner.permission(for: target.rawValue, ask: true)
        if permission == .granted { await refreshFromRunningPlayer() }
    }

    func refreshPermission() async {
        guard let target = player ?? Player.allCases.first(where: \.isRunning) else { return }
        permission = await AppleScriptRunner.permission(for: target.rawValue, ask: false)
    }

    private func refreshFromRunningPlayer() async {
        guard let target = player ?? Player.allCases.first(where: \.isRunning) else { return }
        await refreshDetails(for: target, trackID: nil, announce: false)
    }

    /// Fetches state, position, duration and artwork for the current track.
    private func refreshDetails(for source: Player, trackID: String?, announce: Bool) async {
        guard source.isRunning else { return }
        let script = source == .music ? Self.musicStateScript : Self.spotifyStateScript
        let result = await AppleScriptRunner.run(script) { desc -> [String]? in
            // Numbers are read as doubles (not AppleScript strings) to avoid locale decimal commas.
            (1...max(desc.numberOfItems, 1)).compactMap { i -> String? in
                guard let item = desc.item(i) else { return nil }
                return i == 5 || i == 6 ? String(item.doubleValue) : item.stringValue ?? ""
            }
        }
        guard case .success(let fields?) = result else {
            if case .failure(.notPermitted) = result { permission = .denied }
            islandLog.info("now playing refresh failed for \(source.name, privacy: .public): \(String(describing: result), privacy: .public)")
            return
        }
        islandLog.info("now playing refresh \(source.name, privacy: .public) state=\(fields.first ?? "?", privacy: .public)")
        permission = .granted
        guard fields.count >= 7, fields[0] == "playing" || fields[0] == "paused" else { return }
        let id = fields[6]
        if trackID == nil {
            // Initial sync: build the track from the script result.
            player = source
            state = fields[0] == "playing" ? .playing : .paused
            track = Track(id: id, title: fields[1], artist: fields[2], album: fields[3], duration: Double(fields[4]))
            islandLog.info("now playing \(source.name, privacy: .public) synced at launch state=\(fields[0], privacy: .public)")
        } else if let current = track, let duration = Double(fields[4]) {
            track = Track(id: current.id, title: current.title, artist: current.artist, album: current.album, duration: duration)
        }
        position = Double(fields[5])
        positionDate = Date()

        let image = await loadArtwork(source: source, artworkURL: fields.count > 7 ? fields[7] : nil)
        guard track?.id == trackID || trackID == nil else { return }
        artwork = image
        accent = image?.averageColor().map(Color.init(nsColor:)) ?? .white
        await refreshExtras()
        if announce, let track { onTrackChange?(track, image) }
    }

    private func refreshPosition() async {
        guard let player, player.isRunning else { return }
        let result = await AppleScriptRunner.run("tell application \"\(player.name)\" to get player position") {
            $0.doubleValue
        }
        if case .success(let value?) = result {
            position = value
            positionDate = Date()
        }
    }

    private func loadArtwork(source: Player, artworkURL: String?) async -> NSImage? {
        switch source {
        case .music:
            let result = await AppleScriptRunner.run(
                "tell application \"Music\" to get raw data of artwork 1 of current track"
            ) { $0.data }
            if case .success(let data?) = result { return NSImage(data: data) }
            return nil
        case .spotify:
            // Spotify only exposes an https URL to its own artwork CDN.
            guard let artworkURL, let url = URL(string: artworkURL), url.scheme == "https",
                  let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
            return NSImage(data: data)
        }
    }

    // MARK: Controls

    func playPause() { send("playpause") { $0.state = $0.state == .playing ? .paused : .playing } }

    /// Dev aid for `--snapshots` renders only.
    func loadPreview(_ t: Track, artwork: NSImage?) {
        player = .spotify; track = t; state = .playing; self.artwork = artwork
        accent = artwork?.averageColor().map(Color.init(nsColor:)) ?? .white
        position = 47; positionDate = Date(); shuffle = true; repeatMode = .all; volume = 0.6
    }

    // MARK: Shuffle, repeat, volume, seek, embedded lyrics

    enum RepeatMode: String, Sendable { case off, all, one }

    private(set) var shuffle: Bool?
    private(set) var repeatMode: RepeatMode?
    /// 0…1 player volume (the app's own volume, not the system's).
    private(set) var volume: Double?
    /// Plain lyrics stored with an Apple Music track, if any.
    private(set) var embeddedLyrics: String?

    func refreshExtras() async {
        guard let player, player.isRunning, settings.musicControlsEnabled else { return }
        let script = player == .music
            ? "tell application \"Music\" to return {shuffle enabled, (song repeat as string), sound volume, lyrics of current track}"
            : "tell application \"Spotify\" to return {shuffling, repeating, sound volume, \"\"}"
        let result = await AppleScriptRunner.run(script) { d -> [String]? in
            guard d.numberOfItems >= 4 else { return nil }
            return [d.item(1)?.booleanValue == true ? "1" : "0", d.item(2)?.stringValue ?? (d.item(2)?.booleanValue == true ? "all" : "off"),
                    String(d.item(3)?.int32Value ?? 0), d.item(4)?.stringValue ?? ""]
        }
        guard case .success(let f?) = result else { return }
        shuffle = f[0] == "1"
        repeatMode = player == .spotify ? (f[1] == "1" || f[1] == "true" || f[1] == "all" ? .all : .off) : RepeatMode(rawValue: f[1]) ?? .off
        volume = Double(f[2]).map { $0 / 100 }
        embeddedLyrics = f[3].isEmpty ? nil : f[3]
    }

    func toggleShuffle() {
        guard let player, let current = shuffle else { return }
        shuffle = !current
        run(player == .music ? "set shuffle enabled to \(!current)" : "set shuffling to \(!current)")
    }

    /// Music cycles off → all → one; Spotify's scripting only has on/off.
    func cycleRepeat() {
        guard let player else { return }
        let next: RepeatMode = switch (player, repeatMode ?? .off) {
        case (.spotify, .off): .all
        case (.spotify, _): .off
        case (.music, .off): .all
        case (.music, .all): .one
        case (.music, .one): .off
        }
        repeatMode = next
        run(player == .music ? "set song repeat to \(next.rawValue)" : "set repeating to \(next != .off)")
    }

    func setVolume(_ value: Double) {
        volume = value
        volumeTask?.cancel()
        volumeTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))   // coalesce slider drags
            guard !Task.isCancelled, let self else { return }
            self.run("set sound volume to \(Int((value * 100).rounded()))")
        }
    }
    @ObservationIgnored private var volumeTask: Task<Void, Never>?

    func seek(to seconds: TimeInterval) {
        guard state != .stopped else { return }
        position = seconds
        positionDate = Date()
        run("set player position to \(Int(seconds))")
    }

    private func run(_ command: String) {
        guard let player, player.isRunning else { return }
        Task {
            let result = await AppleScriptRunner.run("tell application \"\(player.name)\" to \(command)") { _ in true }
            if case .failure(.notPermitted) = result { permission = .denied }
        }
    }
    func next() { send("next track") }
    func previous() { send(player == .spotify ? "previous track" : "back track") }

    private func send(_ command: String, optimistic: ((NowPlayingService) -> Void)? = nil) {
        guard let player, player.isRunning else { return }
        if let optimistic {
            position = elapsed(at: Date())
            positionDate = Date()
            optimistic(self)
        }
        Task {
            let result = await AppleScriptRunner.run("tell application \"\(player.name)\" to \(command)") { _ in true }
            if case .failure(.notPermitted) = result { permission = .denied }
        }
    }

    private static let musicStateScript = """
    tell application "Music"
        set s to player state as string
        if s is "stopped" then return {s}
        set t to current track
        return {s, name of t, artist of t, album of t, duration of t, player position, persistent ID of t}
    end tell
    """

    private static let spotifyStateScript = """
    tell application "Spotify"
        set s to player state as string
        if s is "stopped" then return {s}
        set t to current track
        return {s, name of t, artist of t, album of t, (duration of t) / 1000, player position, id of t, artwork url of t}
    end tell
    """
}
