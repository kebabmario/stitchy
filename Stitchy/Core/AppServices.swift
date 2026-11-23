import AppKit
import SwiftUI

/// Owns every long-lived service and wires their events together.
/// Services only start when their feature is enabled, so disabled features
/// cost nothing at runtime.
@MainActor @Observable
final class AppServices {
    @ObservationIgnored let settings = AppSettings()
    @ObservationIgnored let island: IslandModel
    @ObservationIgnored let feed = ActivityFeed()
    @ObservationIgnored let battery = BatteryMonitor()
    @ObservationIgnored let network = NetworkMonitor()
    @ObservationIgnored let nowPlaying: NowPlayingService
    @ObservationIgnored let timers: TimerStore
    @ObservationIgnored let shelf = FileShelf()
    @ObservationIgnored let downloads = DownloadsMonitor()
    @ObservationIgnored let notifier = SystemNotifier()
    @ObservationIgnored let clipboard: ClipboardHistory
    @ObservationIgnored let audio = AudioMonitor()
    @ObservationIgnored let privacy = PrivacyGuard()
    @ObservationIgnored let notes = NotesStore()
    @ObservationIgnored let calendar: CalendarService
    @ObservationIgnored let aiUsage = AIUsageMonitor()
    @ObservationIgnored let launcher: Launcher
    @ObservationIgnored let faceID = FaceIDService()
    @ObservationIgnored let privateLock: PrivateLock
    @ObservationIgnored let hotkey = GlobalHotkey()

    init() {
        island = IslandModel(settings: settings)
        nowPlaying = NowPlayingService(settings: settings)
        timers = TimerStore(settings: settings, notifier: notifier)
        clipboard = ClipboardHistory(settings: settings)
        calendar = CalendarService(settings: settings)
        launcher = Launcher(settings: settings)
        privateLock = PrivateLock(settings: settings)
        wire()
    }

    func start() {
        notifier.configure()
        network.start()
        observeContinuously { [weak self] in self?.applyFeatureToggles() }
    }

    /// Starts or stops services to match the toggles in Settings.
    private func applyFeatureToggles() {
        settings.batteryEnabled ? battery.start() : battery.stop()
        settings.musicEnabled ? nowPlaying.start() : nowPlaying.stop()
        settings.downloadsEnabled ? downloads.start() : downloads.stop()
        settings.clipboardEnabled ? clipboard.start() : clipboard.stop()
        settings.hudEnabled ? audio.start() : audio.stop()
        settings.privacyGuardEnabled ? privacy.start() : privacy.stop()
        settings.calendarEnabled ? calendar.start() : calendar.stop()
        if !settings.timerEnabled { timers.stopAll() }
        if settings.hotkeyEnabled {
            hotkey.register(settings.hotkey)
        } else {
            hotkey.unregister()
        }
    }

    func post(_ event: ActivityEvent) {
        guard settings.alertsEnabled else { return }
        if event.recordsInFeed { feed.add(event) }
        if event.showsAlert { island.present(event) }
    }

    private func wire() {
        battery.onEvent = { [weak self] in self?.post($0) }
        downloads.onEvent = { [weak self] in self?.post($0) }
        timers.onEvent = { [weak self] in self?.post($0) }
        calendar.onEvent = { [weak self] in self?.post($0) }
        shelf.onTransferEvent = { [weak self] in self?.post($0) }
        hotkey.onPress = { [weak self] in
            guard let self else { return }
            if self.island.isExpanded, self.island.tab == .launcher { self.island.collapse() } else { self.island.openLauncher() }
        }
        nowPlaying.onTrackChange = { [weak self] track, artwork in
            guard let self, self.settings.trackChangeAlerts else { return }
            self.post(ActivityEvent(
                symbol: "music.note", tint: .pink, title: track.title, detail: track.artist,
                artwork: artwork, tab: .music, recordsInFeed: false
            ))
        }
        shelf.onAdd = { [weak self] count in
            self?.post(ActivityEvent(
                symbol: "tray.and.arrow.down.fill", tint: .blue,
                title: count == 1 ? "Added 1 file to Shelf" : "Added \(count) files to Shelf",
                tab: .shelf, showsAlert: false
            ))
        }
        audio.onChange = { [weak self] change in
            guard let self, self.settings.hudEnabled else { return }
            let a = self.audio
            switch change {
            case .volume, .mute:
                self.island.showHUD(HUDEvent(symbol: a.volumeSymbol, title: a.isMuted ? "Muted" : a.outputName,
                                             level: a.isMuted ? 0 : Double(a.volume)))
            case .output:
                self.island.showHUD(HUDEvent(symbol: "hifispeaker.fill", tint: .blue, title: a.outputName))
            }
        }
        privacy.onChange = { [weak self] camera, mic in
            guard let self, self.settings.privacyGuardEnabled else { return }
            if camera || mic {
                self.post(ActivityEvent(symbol: camera ? "video.fill" : "mic.fill", tint: camera ? .green : .orange,
                                        title: camera ? "Camera Turned On" : "Microphone Turned On",
                                        detail: "macOS doesn't say which app", tab: .home, alertDuration: 2.4))
            }
        }
        launcher.actions = [
            .init(id: "timer5", title: "Start 5-Minute Timer", symbol: "timer") { [weak self] in
                self?.timers.addCountdown(seconds: 300)
                self?.island.select(.timer)
            },
            .init(id: "focus", title: "Start Focus Session", symbol: "brain.head.profile") { [weak self] in
                self?.timers.pomodoro.start()
                self?.island.select(.timer)
            },
            .init(id: "stopwatch", title: "Start Stopwatch", symbol: "stopwatch") { [weak self] in
                self?.timers.stopwatch.start()
                self?.island.select(.timer)
            },
            .init(id: "note", title: "New Note", symbol: "square.and.pencil") { [weak self] in
                self?.notes.create()
                self?.island.select(.notes)
            },
            .init(id: "clipboard", title: "Show Clipboard History", symbol: "doc.on.clipboard") { [weak self] in
                self?.island.select(.shelf)
            },
            .init(id: "glance", title: "Stitchy Face ID Glance", symbol: "faceid",
                  isAvailable: { [weak self] in self?.settings.faceIDEnabled == true && self?.faceID.isEnrolled == true }) { [weak self] in
                guard let self else { return }
                self.island.select(.home)
                Task { await self.faceID.check() }
            },
            .init(id: "settings", title: "Open Stitchy Settings", symbol: "gearshape") { [weak self] in
                self?.island.collapse()
                self?.island.openSettings()
            },
        ]
    }
}
