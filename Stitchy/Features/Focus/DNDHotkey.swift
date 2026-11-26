// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Do Not Disturb in one click, without the Shortcuts app.
///
/// macOS has no public API for apps to switch Do Not Disturb (its service only
/// accepts Apple's own apps). It does have a built-in keyboard shortcut, "Turn
/// Do Not Disturb On/Off" (System Settings › Keyboard › Keyboard Shortcuts),
/// unassigned by default. With the user's OK, Stitchy assigns it ⌃⌥⌘D once and
/// then presses it (posting a key event needs Accessibility).
enum DNDHotkey {
    /// com.apple.symbolichotkeys id of "Turn Do Not Disturb On/Off".
    static let symbolicID = "175"
    static let keyCode = CGKeyCode(kVK_ANSI_D)
    static var flags: CGEventFlags { [.maskControl, .maskAlternate, .maskCommand] }
    /// Symbolic hotkey parameters: (character, virtual key code, modifier mask).
    static let parameters: [Int] = [100, kVK_ANSI_D, 0x40000 | 0x80000 | 0x100000]
    static let display = "⌃⌥⌘D"

    private static var domain: CFString { "com.apple.symbolichotkeys" as CFString }
    private static var key: CFString { "AppleSymbolicHotKeys" as CFString }

    /// True when "Turn Do Not Disturb On/Off" is enabled with our key combination.
    static var isAssigned: Bool {
        guard let all = CFPreferencesCopyAppValue(key, domain) as? [String: Any],
              let entry = all[symbolicID] as? [String: Any], (entry["enabled"] as? Bool) == true,
              let value = entry["value"] as? [String: Any], let params = value["parameters"] as? [Int] else { return false }
        return params == parameters
    }

    /// Assigns the shortcut in the user's keyboard settings and applies it without logging out.
    @discardableResult
    static func assign() -> Bool {
        var all = (CFPreferencesCopyAppValue(key, domain) as? [String: Any]) ?? [:]
        all[symbolicID] = ["enabled": true, "value": ["type": "standard", "parameters": parameters]] as [String: Any]
        CFPreferencesSetAppValue(key, all as CFDictionary, domain)
        guard CFPreferencesAppSynchronize(domain) else { return false }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings")
        p.arguments = ["-u"]
        try? p.run()
        p.waitUntilExit()
        return isAssigned
    }

    /// Presses the shortcut. Returns false without Accessibility permission.
    @discardableResult
    static func press() -> Bool {
        guard AXIsProcessTrusted() else { return false }
        let src = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: down) else { return false }
            e.flags = flags
            e.post(tap: .cghidEventTap)
        }
        return true
    }
}
