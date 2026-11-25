import Foundation
import Observation

/// Lyrics for the playing track.
///
/// Sources, in order:
///  1. Cache (memory, then ~/Library/Caches/Stitchy/lyrics) — a song is
///     looked up at most once; "not found" is remembered for a day.
///  2. LRCLIB (lrclib.net), a free, open database of time-synced lyrics.
///     Sends title, artist, album and duration. Spotify exposes no lyrics
///     to other apps, and Stitchy doesn't scrape private endpoints.
///  3. Lyrics stored with an Apple Music track (via Music's scripting
///     dictionary): plain text, not synced, used when LRCLIB has nothing.
@MainActor @Observable
final class LyricsService {
    struct Line: Equatable, Sendable { let time: TimeInterval; let text: String }

    enum State: Equatable { case idle, loading, synced([Line]), plain(String), notFound, failed }

    private(set) var state: State = .idle
    @ObservationIgnored private var currentKey: String?

    @ObservationIgnored private var memory: [String: State] = [:]
    @ObservationIgnored private let cacheDir: URL
    /// Network requests made (for tests and diagnostics).
    @ObservationIgnored private(set) var networkRequests = 0

    init(cacheDirectory: URL? = nil) {
        cacheDir = cacheDirectory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Stitchy/lyrics", isDirectory: true)
    }

    func load(title: String, artist: String, album: String, duration: TimeInterval?, embedded: String? = nil) async {
        let key = "\(title)|\(artist)"
        guard key != currentKey else {
            // Embedded lyrics may arrive after the first lookup failed.
            if let embedded, !embedded.isEmpty, state == .notFound || state == .failed { state = .plain(embedded) }
            return
        }
        currentKey = key
        if let cached = memory[key] ?? readDisk(key) {
            memory[key] = cached
            state = cached == .notFound && embedded?.isEmpty == false ? .plain(embedded!) : cached
            return
        }
        state = .loading
        await fetch(key: key, title: title, artist: artist, album: album, duration: duration)
        if state == .notFound, let embedded, !embedded.isEmpty { state = .plain(embedded) }
    }

    private func fetch(key: String, title: String, artist: String, album: String, duration: TimeInterval?) async {
        networkRequests += 1
        var c = URLComponents(string: "https://lrclib.net/api/get")!
        c.queryItems = [.init(name: "track_name", value: title), .init(name: "artist_name", value: artist), .init(name: "album_name", value: album)]
        if let duration { c.queryItems?.append(.init(name: "duration", value: String(Int(duration.rounded())))) }
        var request = URLRequest(url: c.url!)
        request.setValue("Stitchy (macOS)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 8
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard currentKey == key else { return }
            if (response as? HTTPURLResponse)?.statusCode == 404 { remember(key, .notFound); return }
            let json = try JSONDecoder().decode(LRCLibResponse.self, from: data)
            if let synced = json.syncedLyrics, let lines = Self.parseLRC(synced), !lines.isEmpty {
                remember(key, .synced(lines))
            } else if let plain = json.plainLyrics, !plain.isEmpty {
                remember(key, .plain(plain))
            } else {
                remember(key, .notFound)
            }
        } catch {
            // Network failures aren't cached; the next play retries.
            if currentKey == key { state = .failed }
        }
    }

    private func remember(_ key: String, _ value: State) {
        let kind: String = switch value { case .synced(let l): "synced(\(l.count) lines)"; case .plain: "plain"; case .notFound: "notFound"; default: "other" }
        islandLog.info("lyrics fetched: \(kind, privacy: .public)")
        memory[key] = value
        if currentKey == key { state = value }
        writeDisk(key, value)
    }

    // MARK: Disk cache (small JSON per song; not-found expires after a day)

    private struct Cached: Codable { var synced: [CachedLine]?; var plain: String?; var notFound: Bool; var date: Date }
    private struct CachedLine: Codable { var t: Double; var s: String }

    private func file(_ key: String) -> URL {
        let safe = key.data(using: .utf8)!.base64EncodedString().replacingOccurrences(of: "/", with: "_").prefix(120)
        return cacheDir.appendingPathComponent(String(safe) + ".json")
    }

    /// Internal (not private) so tests can seed the cache.
    func writeDisk(_ key: String, _ value: State) {
        let entry: Cached
        switch value {
        case .synced(let l): entry = Cached(synced: l.map { CachedLine(t: $0.time, s: $0.text) }, plain: nil, notFound: false, date: Date())
        case .plain(let p): entry = Cached(synced: nil, plain: p, notFound: false, date: Date())
        case .notFound: entry = Cached(synced: nil, plain: nil, notFound: true, date: Date())
        default: return
        }
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        try? JSONEncoder().encode(entry).write(to: file(key), options: .atomic)
    }

    private func readDisk(_ key: String) -> State? {
        guard let data = try? Data(contentsOf: file(key)), let e = try? JSONDecoder().decode(Cached.self, from: data) else { return nil }
        if e.notFound { return Date().timeIntervalSince(e.date) < 86_400 ? .notFound : nil }
        if let s = e.synced { return .synced(s.map { Line(time: $0.t, text: $0.s) }) }
        return e.plain.map { .plain($0) }
    }

    /// Dev aid for `--snapshots` renders only.
    func loadPreview(_ lines: [Line]) { currentKey = "preview"; state = .synced(lines) }

    /// Current line text at a playback time, for the compact island.
    func line(at time: TimeInterval?) -> String? {
        guard case .synced(let lines) = state, let time, let i = Self.index(in: lines, at: time + 0.2) else { return nil }
        let text = lines[i].text
        return text.isEmpty ? nil : text
    }

    func clear() {
        currentKey = nil
        state = .idle
    }

    private struct LRCLibResponse: Decodable { let syncedLyrics: String?; let plainLyrics: String? }

    /// Parses "[mm:ss.xx] text" lines; nil if there are no timestamps.
    nonisolated static func parseLRC(_ text: String) -> [Line]? {
        let pattern = try! NSRegularExpression(pattern: #"\[(\d+):(\d+(?:\.\d+)?)\]"#)
        var lines: [Line] = []
        for raw in text.components(separatedBy: .newlines) {
            let range = NSRange(raw.startIndex..., in: raw)
            let matches = pattern.matches(in: raw, range: range)
            guard !matches.isEmpty, let last = matches.last, let tail = Range(last.range, in: raw) else { continue }
            let lyric = raw[tail.upperBound...].trimmingCharacters(in: .whitespaces)
            for m in matches {
                guard let mm = Range(m.range(at: 1), in: raw), let ss = Range(m.range(at: 2), in: raw),
                      let minutes = Double(raw[mm]), let seconds = Double(raw[ss]) else { continue }
                lines.append(Line(time: minutes * 60 + seconds, text: lyric))
            }
        }
        return lines.isEmpty ? nil : lines.sorted { $0.time < $1.time }
    }

    /// Index of the line being sung at `time`.
    nonisolated static func index(in lines: [Line], at time: TimeInterval) -> Int? {
        var lo = 0, hi = lines.count - 1, found: Int?
        while lo <= hi {
            let mid = (lo + hi) / 2
            if lines[mid].time <= time { found = mid; lo = mid + 1 } else { hi = mid - 1 }
        }
        return found
    }
}
