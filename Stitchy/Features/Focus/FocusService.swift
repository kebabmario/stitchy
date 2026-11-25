import AppKit
import Intents
import Observation

/// Focus integration using only public mechanisms:
///  - Reading: `INFocusStatusCenter` says whether *a* Focus is on (not which
///    one) after the user authorizes it. macOS posts no change notification
///    to apps, so Stitchy re-reads when the island opens and when the app
///    becomes active.
///  - Changing: there is no public API. Stitchy runs two Shortcuts the user
///    picks (made with the "Set Focus" action), so macOS stays in charge.
@MainActor @Observable
final class FocusService {
    enum Access: Equatable { case unknown, authorized, denied, unavailable }

    private(set) var access: Access = .unknown
    private(set) var isFocused: Bool?
    private(set) var lastError: String?
    @ObservationIgnored private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
        readAccess()
    }

    private func readAccess() {
        switch INFocusStatusCenter.default.authorizationStatus {
        case .authorized: access = .authorized
        case .denied: access = .denied
        case .restricted: access = .unavailable
        default: access = .unknown
        }
    }

    func requestAccess() async {
        let status = await withCheckedContinuation { c in
            INFocusStatusCenter.default.requestAuthorization { c.resume(returning: $0) }
        }
        access = switch status { case .authorized: .authorized; case .denied: .denied; case .restricted: .unavailable; default: .unknown }
        refresh()
    }

    func refresh() {
        readAccess()
        guard access == .authorized else { return }
        isFocused = INFocusStatusCenter.default.focusStatus.isFocused
    }

    var canSwitch: Bool { !settings.focusOnShortcut.isEmpty && !settings.focusOffShortcut.isEmpty }

    /// Runs the user's "Focus on"/"Focus off" Shortcut.
    func setFocus(_ on: Bool) async {
        let name = on ? settings.focusOnShortcut : settings.focusOffShortcut
        guard !name.isEmpty else { return }
        lastError = nil
        let ok = await Self.runShortcut(name)
        if !ok { lastError = "The Shortcut “\(name)” didn't run." }
        try? await Task.sleep(for: .milliseconds(600))
        refresh()
        if access != .authorized, ok { isFocused = on }   // best effort without read access
    }

    nonisolated static let installedOnName = "Stitchy Focus On"
    nonisolated static let installedOffName = "Stitchy Focus Off"

    /// The moon button. Uses the configured or detected Shortcut pair; with
    /// none in the library, creates Stitchy's own pair and opens it in
    /// Shortcuts (the user clicks "Add Shortcut"). Returns false when the
    /// user still has to add them.
    func toggleFocus() async -> Bool {
        let names = await Self.listShortcuts()
        let library = Set(names)
        if !(library.contains(settings.focusOnShortcut) && library.contains(settings.focusOffShortcut)) {
            settings.focusOnShortcut = ""
            settings.focusOffShortcut = ""
            if let pair = Self.focusPair(in: names) {
                settings.focusOnShortcut = pair.on
                settings.focusOffShortcut = pair.off
            }
        }
        guard canSwitch else {
            lastError = await Self.installShortcuts() ? nil : "Couldn't create the Focus Shortcuts."
            return false
        }
        await setFocus(isFocused != true)
        return true
    }

    /// Writes, signs and opens Do Not Disturb on/off Shortcuts. Shortcuts
    /// shows its own "Add Shortcut" sheet for each; nothing is added silently.
    nonisolated static func installShortcuts() async -> Bool {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("StitchyShortcuts", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var signed: [URL] = []
        for (name, on) in [(installedOnName, true), (installedOffName, false)] {
            let raw = dir.appendingPathComponent("raw-\(on).shortcut")
            let out = dir.appendingPathComponent("\(name).shortcut")
            guard let data = try? PropertyListSerialization.data(fromPropertyList: workflow(focusOn: on), format: .binary, options: 0),
                  (try? data.write(to: raw)) != nil else { return false }
            try? FileManager.default.removeItem(at: out)
            guard await run(["sign", "--mode", "anyone", "--input", raw.path, "--output", out.path]) else { return false }
            signed.append(out)
        }
        await MainActor.run { signed.forEach { NSWorkspace.shared.open($0) } }
        return true
    }

    /// A one-action Shortcut: Set Focus › Do Not Disturb › on/off.
    nonisolated static func workflow(focusOn: Bool) -> [String: Any] {
        [
            "WFWorkflowClientVersion": "2607.0.2",
            "WFWorkflowMinimumClientVersion": 900,
            "WFWorkflowIcon": ["WFWorkflowIconStartColor": 463140863, "WFWorkflowIconGlyphNumber": 59511],
            "WFWorkflowImportQuestions": [Any](),
            "WFWorkflowTypes": [Any](),
            "WFWorkflowInputContentItemClasses": [Any](),
            "WFWorkflowActions": [[
                "WFWorkflowActionIdentifier": "is.workflow.actions.dnd.set",
                "WFWorkflowActionParameters": [
                    "Enabled": focusOn,
                    "FocusModes": ["Identifier": "com.apple.donotdisturb.mode.default", "DisplayString": "Do Not Disturb"],
                ] as [String: Any],
            ] as [String: Any]],
        ]
    }

    nonisolated private static func run(_ args: [String]) async -> Bool {
        await withCheckedContinuation { c in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
                p.arguments = args
                p.standardOutput = FileHandle.nullDevice
                p.standardError = FileHandle.nullDevice
                do { try p.run(); p.waitUntilExit(); c.resume(returning: p.terminationStatus == 0) } catch { c.resume(returning: false) }
            }
        }
    }

    nonisolated static func focusPair(in names: [String]) -> (on: String, off: String)? {
        if names.contains(installedOnName), names.contains(installedOffName) { return (installedOnName, installedOffName) }
        for topic in ["focus", "sleep", "do not disturb", "dnd"] {
            let matches = names.filter { $0.lowercased().contains(topic) }
            func pick(_ word: String) -> String? {
                matches.first { $0.lowercased().split(whereSeparator: { !$0.isLetter }).contains(Substring(word)) }
            }
            if let on = pick("on"), let off = pick("off") { return (on, off) }
        }
        return nil
    }

    nonisolated static func listShortcuts() async -> [String] {
        await withCheckedContinuation { c in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process(), pipe = Pipe()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
                p.arguments = ["list"]
                p.standardOutput = pipe
                p.standardError = FileHandle.nullDevice
                do { try p.run() } catch { c.resume(returning: []); return }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                c.resume(returning: String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init))
            }
        }
    }

    nonisolated static func runShortcut(_ name: String) async -> Bool {
        await withCheckedContinuation { c in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
                p.arguments = ["run", name]
                p.standardOutput = FileHandle.nullDevice
                p.standardError = FileHandle.nullDevice
                do { try p.run(); p.waitUntilExit(); c.resume(returning: p.terminationStatus == 0) } catch { c.resume(returning: false) }
            }
        }
    }
}
