// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Observation

/// Coding-agent usage from *local* logs only. Nothing is estimated beyond
/// what the files contain.
///
///  - Claude Code writes every assistant message (with its token usage) to
///    ~/.claude/projects/<project>/<session>.jsonl. Stitchy sums those,
///    de-duplicating repeated entries of the same message. Claude's plan
///    limits are not stored locally, so no "remaining quota" is shown; the
///    5-hour block is computed the same way the open-source ccusage tool does.
///  - Codex CLI writes `token_count` events with `rate_limits`
///    (used percent and reset time) to ~/.codex/sessions; when present they
///    are shown as reported.
///  - Cursor keeps no documented local usage data, so it is listed as
///    unsupported.
@MainActor @Observable
final class AIUsageMonitor {
    struct ClaudeSummary: Sendable, Equatable {
        var blockTokens = 0
        var blockStart: Date?
        var blockEnd: Date?
        var todayTokens = 0
        var todayMessages = 0
        var todayCacheReads = 0
        var activeSessions = 0
        var lastActivity: Date?
        var topModel: String?
    }

    struct CodexLimit: Sendable, Equatable {
        var usedPercent: Double
        var windowMinutes: Int?
        var resetsAt: Date?
    }

    struct CodexSummary: Sendable, Equatable {
        var primary: CodexLimit?
        var secondary: CodexLimit?
        var lastActivity: Date?
    }

    private(set) var claude: ClaudeSummary?
    private(set) var codex: CodexSummary?
    private(set) var claudeFound = false
    private(set) var codexFound = false
    private(set) var lastRefresh: Date?
    private(set) var isRefreshing = false
    @ObservationIgnored private let scanner = UsageScanner()

    var cursorInstalled: Bool {
        FileManager.default.fileExists(atPath: NSHomeDirectory() + "/Library/Application Support/Cursor")
    }

    /// Reads only new bytes since the previous scan, on a background thread.
    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        let scanner = self.scanner
        Task.detached(priority: .utility) {
            let result = scanner.scan()
            await MainActor.run {
                self.claude = result.claude
                self.codex = result.codex
                self.claudeFound = result.claudeFound
                self.codexFound = result.codexFound
                self.lastRefresh = Date()
                self.isRefreshing = false
            }
        }
    }
}

/// Incremental JSONL reader. Keeps per-file byte offsets so each refresh
/// parses only appended lines.
final class UsageScanner: @unchecked Sendable {
    struct Result: Sendable {
        var claude: AIUsageMonitor.ClaudeSummary?
        var codex: AIUsageMonitor.CodexSummary?
        var claudeFound: Bool
        var codexFound: Bool
    }

    private struct Message { var date: Date; var tokens: Int; var cacheRead: Int; var model: String }

    private let lock = NSLock()
    private var offsets: [String: UInt64] = [:]
    private var messages: [String: Message] = [:]   // key: message id + request id
    private var codexLatest: AIUsageMonitor.CodexSummary?
    private let home: URL

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) { self.home = home }

    func scan() -> Result {
        lock.lock(); defer { lock.unlock() }
        let now = Date()
        let claudeRoots = [home.appendingPathComponent(".claude/projects"), home.appendingPathComponent(".config/claude/projects")]
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        for root in claudeRoots {
            for file in recentFiles(in: root, ext: "jsonl", since: now.addingTimeInterval(-36 * 3600)) {
                read(file) { parseClaude($0) }
            }
        }
        // Forget messages older than 36 h.
        messages = messages.filter { $0.value.date > now.addingTimeInterval(-36 * 3600) }

        let codexRoot = home.appendingPathComponent(".codex/sessions")
        let codexFound = FileManager.default.fileExists(atPath: codexRoot.path)
        if codexFound {
            for file in recentFiles(in: codexRoot, ext: "jsonl", since: now.addingTimeInterval(-7 * 86400)).sorted(by: { $0.1 < $1.1 }) {
                read(file) { parseCodex($0) }
            }
        }
        return Result(claude: claudeRoots.isEmpty ? nil : summarize(now: now, roots: claudeRoots),
                      codex: codexLatest, claudeFound: !claudeRoots.isEmpty, codexFound: codexFound)
    }

    private func recentFiles(in root: URL, ext: String, since: Date) -> [(URL, Date)] {
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else { return [] }
        var out: [(URL, Date)] = []
        for case let url as URL in e where url.pathExtension == ext {
            if let m = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, m > since {
                out.append((url, m))
            }
        }
        return out
    }

    private func read(_ file: (URL, Date), line: (Data) -> Void) {
        let path = file.0.path
        guard let handle = try? FileHandle(forReadingFrom: file.0) else { return }
        defer { try? handle.close() }
        var start = offsets[path] ?? 0
        let size = (try? handle.seekToEnd()) ?? 0
        if size < start { start = 0 }  // file was truncated/rewritten
        guard size > start else { return }
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd() else { return }
        // Only consume complete lines; a partial last line is read next time.
        guard let lastNewline = data.lastIndex(of: UInt8(ascii: "\n")) else { return }
        let complete = data[data.startIndex...lastNewline]
        for chunk in complete.split(separator: UInt8(ascii: "\n")) { line(Data(chunk)) }
        offsets[path] = start + UInt64(complete.count)
    }

    private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private func date(_ value: Any?) -> Date? {
        guard let s = value as? String else { return nil }
        return iso.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }

    private func parseClaude(_ data: Data) {
        // Cheap pre-filter before JSON parsing.
        guard data.range(of: Data("\"usage\"".utf8)) != nil,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              obj["type"] as? String == "assistant",
              let message = obj["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any],
              let when = date(obj["timestamp"]) else { return }
        let key = "\(message["id"] as? String ?? UUID().uuidString)|\(obj["requestId"] as? String ?? "")"
        func n(_ k: String) -> Int { (usage[k] as? NSNumber)?.intValue ?? 0 }
        messages[key] = Message(date: when,
                                tokens: n("input_tokens") + n("output_tokens") + n("cache_creation_input_tokens"),
                                cacheRead: n("cache_read_input_tokens"),
                                model: message["model"] as? String ?? "")
    }

    private func parseCodex(_ data: Data) {
        guard data.range(of: Data("rate_limits".utf8)) != nil,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        let payload = obj["payload"] as? [String: Any] ?? obj
        guard let limits = payload["rate_limits"] as? [String: Any] else { return }
        let when = date(obj["timestamp"]) ?? Date()
        func limit(_ k: String) -> AIUsageMonitor.CodexLimit? {
            guard let l = limits[k] as? [String: Any], let used = (l["used_percent"] as? NSNumber)?.doubleValue else { return nil }
            var reset: Date?
            if let secs = (l["resets_in_seconds"] as? NSNumber)?.doubleValue { reset = when.addingTimeInterval(secs) }
            if let at = (l["resets_at"] as? NSNumber)?.doubleValue { reset = Date(timeIntervalSince1970: at) }
            return .init(usedPercent: used, windowMinutes: (l["window_minutes"] as? NSNumber)?.intValue, resetsAt: reset)
        }
        codexLatest = .init(primary: limit("primary"), secondary: limit("secondary"), lastActivity: when)
    }

    private func summarize(now: Date, roots: [URL]) -> AIUsageMonitor.ClaudeSummary {
        var s = AIUsageMonitor.ClaudeSummary()
        let all = messages.values.sorted { $0.date < $1.date }
        let startOfDay = Calendar.current.startOfDay(for: now)
        var models: [String: Int] = [:]
        for m in all where m.date >= startOfDay {
            s.todayTokens += m.tokens
            s.todayCacheReads += m.cacheRead
            s.todayMessages += 1
            models[m.model, default: 0] += m.tokens
        }
        s.topModel = models.max { $0.value < $1.value }?.key
        s.lastActivity = all.last?.date
        // 5-hour blocks: a block starts at the hour of its first message.
        var blockStart: Date?
        var blockTokens = 0
        for m in all {
            if let start = blockStart, m.date < start.addingTimeInterval(5 * 3600) {
                blockTokens += m.tokens
            } else {
                let comps = Calendar.current.dateComponents([.year, .month, .day, .hour], from: m.date)
                blockStart = Calendar.current.date(from: comps)
                blockTokens = m.tokens
            }
        }
        if let start = blockStart, now < start.addingTimeInterval(5 * 3600) {
            s.blockStart = start
            s.blockEnd = start.addingTimeInterval(5 * 3600)
            s.blockTokens = blockTokens
        }
        let fiveMinutesAgo = now.addingTimeInterval(-300)
        s.activeSessions = roots.flatMap { recentFiles(in: $0, ext: "jsonl", since: fiveMinutesAgo) }.count
        return s
    }
}
