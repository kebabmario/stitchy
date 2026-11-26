// SPDX-License-Identifier: GPL-3.0-or-later
import Carbon.HIToolbox
import Foundation

/// One global shortcut via Carbon's RegisterEventHotKey: the documented way
/// to register a hotkey without Accessibility or Input Monitoring access.
@MainActor
final class GlobalHotkey {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var observer: NSObjectProtocol?
    var onPress: (() -> Void)?

    nonisolated static let pressed = Notification.Name("StitchyHotkeyPressed")

    func register(_ preset: HotkeyPreset) {
        unregister()
        let (key, mods): (Int, Int) = switch preset {
        case .controlOptionSpace: (kVK_Space, controlKey | optionKey)
        case .optionCommandS: (kVK_ANSI_S, optionKey | cmdKey)
        case .controlCommandS: (kVK_ANSI_S, controlKey | cmdKey)
        }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), hotkeyCallback, 1, &spec, nil, &handler)
        let id = EventHotKeyID(signature: OSType(0x5354_4348), id: 1) // 'STCH'
        let status = RegisterEventHotKey(UInt32(key), UInt32(mods), id, GetApplicationEventTarget(), 0, &hotKey)
        islandLog.info("hotkey \(preset.rawValue, privacy: .public) register status=\(status, privacy: .public)")
        observer = NotificationCenter.default.addObserver(forName: Self.pressed, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onPress?() }
        }
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        if let observer { NotificationCenter.default.removeObserver(observer) }
        hotKey = nil
        handler = nil
        observer = nil
    }
}

private func hotkeyCallback(_ next: EventHandlerCallRef?, _ event: EventRef?, _ data: UnsafeMutableRawPointer?) -> OSStatus {
    // Only our launcher key (id 1); other Stitchy hotkeys (window snapping) pass through.
    guard let id = carbonHotKeyID(event), id.signature == OSType(0x5354_4348), id.id == 1 else { return OSStatus(eventNotHandledErr) }
    NotificationCenter.default.post(name: GlobalHotkey.pressed, object: nil)
    return noErr
}

func carbonHotKeyID(_ event: EventRef?) -> EventHotKeyID? {
    guard let event else { return nil }
    var id = EventHotKeyID()
    let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                   nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
    return status == noErr ? id : nil
}
