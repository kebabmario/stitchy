// SPDX-License-Identifier: GPL-3.0-or-later
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
        guard ok else { lastError = "The Shortcut “\(name)” didn't run."; return }
        // Show it right away; macOS reports the new Focus state to apps a few seconds late,
        // so an immediate re-read would show the old state and the island wouldn't update.
        isFocused = on
        try? await Task.sleep(for: .seconds(3))
        if access == .authorized, let real = INFocusStatusCenter.default.focusStatus.isFocused { isFocused = real }
    }

    nonisolated static let installedOnName = "Stitchy Focus On"
    nonisolated static let installedOffName = "Stitchy Focus Off"

    /// The moon button: Do Not Disturb via macOS's own keyboard shortcut (see DNDHotkey).
    /// Returns a message to show when something is needed, or nil when it toggled.
    func toggleDoNotDisturb() async -> String? {
        if !DNDHotkey.isAssigned {
            guard await Self.confirmAssign() else { return "Do Not Disturb needs its keyboard shortcut. Click the moon again to set it up." }
            guard DNDHotkey.assign() else { return "Couldn't assign the keyboard shortcut." }
            try? await Task.sleep(for: .milliseconds(400))   // let macOS pick up the new shortcut
        }
        guard AXIsProcessTrusted() else {
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)   // kAXTrustedCheckOptionPrompt
            return "Allow Stitchy in Privacy & Security › Accessibility, then click the moon again."
        }
        DNDHotkey.press()
        let on = isFocused != true
        isFocused = on
        // macOS reports the new state to apps a few seconds late; sync when we can read it.
        try? await Task.sleep(for: .seconds(3))
        refresh()
        if access != .authorized { isFocused = on }
        return nil
    }

    /// One-time consent before changing a system keyboard setting.
    private static func confirmAssign() async -> Bool {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Turn on Do Not Disturb with one click?"
        alert.informativeText = "macOS doesn't let apps switch Do Not Disturb directly. Stitchy can assign \(DNDHotkey.display) to macOS's built-in \"Turn Do Not Disturb On/Off\" keyboard shortcut (System Settings › Keyboard › Keyboard Shortcuts) and press it for you. You can change or remove it there at any time."
        alert.addButton(withTitle: "Assign \(DNDHotkey.display)")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
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
