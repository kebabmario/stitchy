import Foundation
import Observation

/// Live coding-agent activity from the session logs Claude Code
/// (`~/.claude/projects/**/*.jsonl`) and Codex (`~/.codex/sessions/**/*.jsonl`)
/// write while they work. Read-only and local. Stitchy shows only the tool in
/// use and a file name: never commands, prompts or replies.
@MainActor @Observable
final class AgentActivityMonitor {
    enum Agent: String {
        case claude = "Claude Code", codex = "Codex"
        /// Installed app whose icon represents this agent (see AppIcons).
        var appName: String { self == .claude ? "Claude" : "Codex" }
    }

    struct Session: Identifiable, Equatable {
        let id: String          // log file path
        let agent: Agent
        var project: String
        var status: String
        var updated: Date
        var started = Date()
    }

    enum Event: Equatable { case tool(String), thinking, finished }

    private(set) var sessions: [String: Session] = [:]
    @ObservationIgnored var onFinished: ((Session) -> Void)?
    @ObservationIgnored private var offsets: [String: UInt64] = [:]
    @ObservationIgnored private var watcher: FileWatcher?
    @ObservationIgnored private var pruneTask: Task<Void, Never>?
    @ObservationIgnored private var startedAt = Date()
    @ObservationIgnored private let home: URL
    /// A session with no new log lines for this long is no longer "live".
    static let idleTimeout: TimeInterval = 120

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) { self.home = home }

    /// The most recently active session.
    var live: Session? { sessions.values.max { $0.updated < $1.updated } }

    func start() {
        guard watcher == nil else { return }
        startedAt = Date()
        let roots = [".claude/projects", ".config/claude/projects", ".codex/sessions"].map { home.appendingPathComponent($0).path }
        watcher = FileWatcher(paths: roots, latency: 0.4) { [weak self] paths in
            for path in Set(paths) where path.hasSuffix(".jsonl") { self?.ingest(path) }
        }
    }

    func stop() {
        watcher = nil
        pruneTask?.cancel()
        pruneTask = nil
        sessions = [:]
        offsets = [:]
    }

    // MARK: Reading

    private func ingest(_ path: String) {
        guard let handle = FileHandle(forReadingAtPath: path) else { return }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        // First sight: only the tail, and only lines written after Stitchy started watching.
        let firstSight = offsets[path] == nil
        var start = offsets[path] ?? (size > 32_768 ? size - 32_768 : 0)
        if start > size { start = 0 }   // file was truncated or replaced
        try? handle.seek(toOffset: start)
        let data = handle.readDataToEndOfFile()
        // Keep a partial last line for next time.
        guard let lastNewline = data.lastIndex(of: 0x0A) else { offsets[path] = start; return }
        offsets[path] = start + UInt64(data.distance(from: data.startIndex, to: lastNewline) + 1)
        let agent: Agent = path.contains("/.codex/") ? .codex : .claude
        for line in data[data.startIndex...lastNewline].split(separator: 0x0A) {
            guard let parsed = Self.parse(Data(line), agent: agent) else { continue }
            // Undated lines can't be placed in time, so first sight skips them too (no stale "finished").
            if firstSight, (parsed.timestamp ?? .distantPast) < startedAt.addingTimeInterval(-5) { continue }
            apply(parsed, path: path, agent: agent)
        }
    }

    private func apply(_ parsed: Parsed, path: String, agent: Agent) {
        var session = sessions[path] ?? Session(id: path, agent: agent, project: "", status: "Working", updated: Date())
        if let cwd = parsed.cwd { session.project = URL(fileURLWithPath: cwd).lastPathComponent }
        session.updated = Date()
        switch parsed.event {
        case .tool(let status): session.status = status
        case .thinking: session.status = "Thinking"
        case .finished:
            sessions[path] = nil
            onFinished?(session)
            return
        }
        sessions[path] = session
        schedulePrune()
    }

    private func schedulePrune() {
        guard pruneTask == nil else { return }
        pruneTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                guard let self else { return }
                let cutoff = Date().addingTimeInterval(-Self.idleTimeout)
                self.sessions = self.sessions.filter { $0.value.updated > cutoff }
                if self.sessions.isEmpty { self.pruneTask = nil; return }
            }
        }
    }

    // MARK: Parsing (pure, tested)

    struct Parsed: Equatable { var event: Event; var cwd: String?; var timestamp: Date? }

    nonisolated static func parse(_ line: Data, agent: Agent) -> Parsed? {
        guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return nil }
        let timestamp = (obj["timestamp"] as? String).flatMap { iso($0) }
        switch agent {
        case .claude:
            guard obj["type"] as? String == "assistant", let message = obj["message"] as? [String: Any] else { return nil }
            let sidechain = obj["isSidechain"] as? Bool ?? false
            let cwd = obj["cwd"] as? String
            if message["stop_reason"] as? String == "end_turn", !sidechain { return Parsed(event: .finished, cwd: cwd, timestamp: timestamp) }
            let content = message["content"] as? [[String: Any]] ?? []
            if let tool = content.last(where: { $0["type"] as? String == "tool_use" }), let name = tool["name"] as? String {
                return Parsed(event: .tool(describeClaude(name, tool["input"] as? [String: Any] ?? [:])), cwd: cwd, timestamp: timestamp)
            }
            return Parsed(event: .thinking, cwd: cwd, timestamp: timestamp)
        case .codex:
            let payload = obj["payload"] as? [String: Any] ?? [:]
            let kind = payload["type"] as? String
            switch (obj["type"] as? String, kind) {
            case ("event_msg", "task_complete"?): return Parsed(event: .finished, cwd: nil, timestamp: timestamp)
            case ("event_msg", "agent_reasoning"?): return Parsed(event: .thinking, cwd: nil, timestamp: timestamp)
            case ("response_item", "function_call"?), ("response_item", "custom_tool_call"?):
                let name = payload["name"] as? String ?? "tool"
                let status = switch name {
                case "shell", "exec_command", "local_shell": "Running a command"
                case "apply_patch": "Editing files"
                case "update_plan": "Planning"
                default: "Using \(name)"
                }
                return Parsed(event: .tool(status), cwd: nil, timestamp: timestamp)
            case ("session_meta", _), ("turn_context", _):
                guard let cwd = payload["cwd"] as? String else { return nil }
                return Parsed(event: .thinking, cwd: cwd, timestamp: timestamp)
            default: return nil
            }
        }
    }

    /// Tool name plus at most a file name; commands and queries are never shown.
    nonisolated static func describeClaude(_ name: String, _ input: [String: Any]) -> String {
        let file = (input["file_path"] as? String ?? input["notebook_path"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent }
        switch name {
        case "Edit", "MultiEdit", "Write", "NotebookEdit": return file.map { "Editing \($0)" } ?? "Editing"
        case "Read": return file.map { "Reading \($0)" } ?? "Reading"
        case "Bash": return "Running a command"
        case "Grep", "Glob": return "Searching"
        case "WebFetch", "WebSearch": return "Browsing the web"
        case "Task", "Agent": return "Running a subagent"
        case "TodoWrite": return "Planning"
        default:
            if name.hasPrefix("mcp__") {   // mcp__server__tool_name → "Using tool name"
                return "Using \((name.components(separatedBy: "__").last ?? "a tool").replacingOccurrences(of: "_", with: " "))"
            }
            return "Using \(name)"
        }
    }

    nonisolated private static func iso(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }
}
