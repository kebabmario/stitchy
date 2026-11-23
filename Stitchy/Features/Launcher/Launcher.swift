import AppKit
import Observation

/// Quick Launcher: user-configured items plus Stitchy actions and installed
/// apps, searchable from the island.
///
/// Shortcuts are run with Apple's `/usr/bin/shortcuts` tool, and only the
/// ones the user added to the launcher ("approved") can be run.
@MainActor @Observable
final class Launcher {
    struct Item: Identifiable, Codable, Hashable {
        enum Kind: String, Codable { case app, folder, shortcut }
        var id = UUID()
        var kind: Kind
        var name: String
        /// File path for apps/folders, shortcut name for shortcuts.
        var target: String
    }

    struct Action: Identifiable {
        let id: String
        let title: String
        let symbol: String
        var isAvailable: @MainActor () -> Bool = { true }
        let run: @MainActor () -> Void
    }

    enum Result: Identifiable {
        case item(Item)
        case action(Action)
        case app(URL)

        var id: String {
            switch self {
            case .item(let i): "item-\(i.id)"
            case .action(let a): "action-\(a.id)"
            case .app(let u): "app-\(u.path)"
            }
        }
    }

    private(set) var items: [Item]
    @ObservationIgnored var actions: [Action] = []
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private var installedApps: [URL]?
    private(set) var availableShortcuts: [String]?
    private(set) var lastError: String?

    init(settings: AppSettings) {
        self.settings = settings
        items = settings.data([Item].self, key: "launcherItems") ?? []
    }

    func search(_ query: String) -> [Result] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let matches: (String) -> Bool = { q.isEmpty || $0.localizedCaseInsensitiveContains(q) }
        var results: [Result] = items.filter { matches($0.name) }.map(Result.item)
        results += actions.filter { $0.isAvailable() && matches($0.title) }.map(Result.action)
        if !q.isEmpty {
            let configured = Set(items.filter { $0.kind == .app }.map(\.target))
            results += apps().filter { !configured.contains($0.path) && matches($0.deletingPathExtension().lastPathComponent) }
                .prefix(8).map(Result.app)
        }
        return results
    }

    func run(_ result: Result) {
        islandLog.info("launcher run \(result.id, privacy: .public)")
        lastError = nil
        switch result {
        case .action(let action): action.run()
        case .app(let url): NSWorkspace.shared.openApplication(at: url, configuration: .init())
        case .item(let item):
            switch item.kind {
            case .app: NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: item.target), configuration: .init())
            case .folder: NSWorkspace.shared.open(URL(fileURLWithPath: item.target, isDirectory: true))
            case .shortcut: runShortcut(item.target)
            }
        }
    }

    func add(_ item: Item) {
        guard !items.contains(where: { $0.kind == item.kind && $0.target == item.target }) else { return }
        items.append(item)
        persist()
    }

    func remove(_ item: Item) {
        items.removeAll { $0.id == item.id }
        persist()
    }

    private func persist() { settings.setData(items, key: "launcherItems") }

    /// Installed apps, enumerated once on first search.
    private func apps() -> [URL] {
        if let installedApps { return installedApps }
        let dirs = ["/Applications", "/System/Applications", "/System/Applications/Utilities", NSHomeDirectory() + "/Applications"]
        let found = dirs.flatMap { dir in
            ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [])
                .filter { $0.hasSuffix(".app") }
                .map { URL(fileURLWithPath: dir).appendingPathComponent($0) }
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        installedApps = found
        return found
    }

    /// Lists the user's Shortcuts so they can approve some for the launcher.
    func loadShortcuts() async {
        availableShortcuts = await Self.runTool(["list"])?.split(separator: "\n").map(String.init).sorted()
    }

    private func runShortcut(_ name: String) {
        Task {
            if await Self.runTool(["run", name]) == nil { lastError = "Couldn't run “\(name)”." }
        }
    }

    nonisolated private static func runTool(_ args: [String]) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
                process.arguments = args
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice
                do {
                    try process.run()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    continuation.resume(returning: process.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
