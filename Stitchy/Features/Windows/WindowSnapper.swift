// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Optional window snapping by keyboard shortcut (Accessibility). Halves,
/// quarters, thirds, two-thirds, maximize, center and move to the next display.
/// Shortcuts use Carbon hotkeys, so no Input Monitoring is needed.
@MainActor
final class WindowSnapper {
    enum Layout: Int, CaseIterable {
        case leftHalf = 1, rightHalf, topHalf, bottomHalf
        case topLeft, topRight, bottomLeft, bottomRight
        case leftThird, centerThird, rightThird, leftTwoThirds, rightTwoThirds
        case maximize, center, nextDisplay

        /// (key, modifiers) for the default shortcut.
        var shortcut: (Int, Int) {
            let co = controlKey | optionKey
            switch self {
            case .leftHalf: return (kVK_LeftArrow, co)
            case .rightHalf: return (kVK_RightArrow, co)
            case .topHalf: return (kVK_UpArrow, co)
            case .bottomHalf: return (kVK_DownArrow, co)
            case .topLeft: return (kVK_ANSI_U, co)
            case .topRight: return (kVK_ANSI_I, co)
            case .bottomLeft: return (kVK_ANSI_J, co)
            case .bottomRight: return (kVK_ANSI_K, co)
            case .leftThird: return (kVK_ANSI_D, co)
            case .centerThird: return (kVK_ANSI_F, co)
            case .rightThird: return (kVK_ANSI_G, co)
            case .leftTwoThirds: return (kVK_ANSI_E, co)
            case .rightTwoThirds: return (kVK_ANSI_T, co)
            case .maximize: return (kVK_Return, co)
            case .center: return (kVK_ANSI_C, co)
            case .nextDisplay: return (kVK_RightArrow, co | cmdKey)
            }
        }

        /// Target frame inside `visible` (AppKit coordinates, origin bottom-left).
        func frame(in v: CGRect, current: CGRect) -> CGRect {
            let w = v.width, h = v.height
            switch self {
            case .leftHalf: return CGRect(x: v.minX, y: v.minY, width: w / 2, height: h)
            case .rightHalf: return CGRect(x: v.midX, y: v.minY, width: w / 2, height: h)
            case .topHalf: return CGRect(x: v.minX, y: v.midY, width: w, height: h / 2)
            case .bottomHalf: return CGRect(x: v.minX, y: v.minY, width: w, height: h / 2)
            case .topLeft: return CGRect(x: v.minX, y: v.midY, width: w / 2, height: h / 2)
            case .topRight: return CGRect(x: v.midX, y: v.midY, width: w / 2, height: h / 2)
            case .bottomLeft: return CGRect(x: v.minX, y: v.minY, width: w / 2, height: h / 2)
            case .bottomRight: return CGRect(x: v.midX, y: v.minY, width: w / 2, height: h / 2)
            case .leftThird: return CGRect(x: v.minX, y: v.minY, width: w / 3, height: h)
            case .centerThird: return CGRect(x: v.minX + w / 3, y: v.minY, width: w / 3, height: h)
            case .rightThird: return CGRect(x: v.minX + 2 * w / 3, y: v.minY, width: w / 3, height: h)
            case .leftTwoThirds: return CGRect(x: v.minX, y: v.minY, width: 2 * w / 3, height: h)
            case .rightTwoThirds: return CGRect(x: v.minX + w / 3, y: v.minY, width: 2 * w / 3, height: h)
            case .maximize: return v
            case .center, .nextDisplay:
                let size = CGSize(width: min(current.width, w), height: min(current.height, h))
                return CGRect(x: v.midX - size.width / 2, y: v.midY - size.height / 2, width: size.width, height: size.height)
            }
        }
    }

    private var hotKeys: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    var onNeedsPermission: (() -> Void)?
    nonisolated static let signature = OSType(0x5354_4357)   // 'STCW'

    func start() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), snapCallback, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
        for layout in Layout.allCases {
            var ref: EventHotKeyRef?
            let (key, mods) = layout.shortcut
            if RegisterEventHotKey(UInt32(key), UInt32(mods), EventHotKeyID(signature: Self.signature, id: UInt32(layout.rawValue)),
                                   GetApplicationEventTarget(), 0, &ref) == noErr, let ref { hotKeys.append(ref) }
        }
        // Ask for Accessibility up front so the first shortcut works.
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)   // kAXTrustedCheckOptionPrompt
    }

    func stop() {
        hotKeys.forEach { UnregisterEventHotKey($0) }
        hotKeys.removeAll()
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }

    func apply(_ layout: Layout) {
        guard AXIsProcessTrusted() else { onNeedsPermission?(); return }
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &ref) == .success, let ref else { return }
        let window = ref as! AXUIElement   // AX returns an AXUIElement for this attribute
        guard let axFrame = Self.frame(of: window) else { return }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        // AX frames are top-left based on the primary display; AppKit is bottom-left.
        let current = CGRect(x: axFrame.minX, y: primaryHeight - axFrame.maxY, width: axFrame.width, height: axFrame.height)
        let screens = NSScreen.screens
        guard var screen = screens.max(by: { $0.frame.intersection(current).area < $1.frame.intersection(current).area }) else { return }
        if layout == .nextDisplay, screens.count > 1, let i = screens.firstIndex(of: screen) { screen = screens[(i + 1) % screens.count] }
        let target = layout.frame(in: screen.visibleFrame, current: current).integral
        let axTarget = CGRect(x: target.minX, y: primaryHeight - target.maxY, width: target.width, height: target.height)
        // Size, position, size: apps that clamp size to the old screen settle correctly.
        Self.set(window, size: axTarget.size)
        Self.set(window, origin: axTarget.origin)
        Self.set(window, size: axTarget.size)
    }

    private static func frame(of window: AXUIElement) -> CGRect? {
        var p: CFTypeRef?, s: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &p) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &s) == .success, let p, let s else { return nil }
        var point = CGPoint.zero, size = CGSize.zero
        AXValueGetValue(p as! AXValue, .cgPoint, &point)
        AXValueGetValue(s as! AXValue, .cgSize, &size)
        return CGRect(origin: point, size: size)
    }

    private static func set(_ window: AXUIElement, origin: CGPoint) {
        var o = origin
        if let v = AXValueCreate(.cgPoint, &o) { AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, v) }
    }

    private static func set(_ window: AXUIElement, size: CGSize) {
        var s = size
        if let v = AXValueCreate(.cgSize, &s) { AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, v) }
    }
}

private extension CGRect {
    var area: CGFloat { isNull ? 0 : width * height }
}

private func snapCallback(_ next: EventHandlerCallRef?, _ event: EventRef?, _ data: UnsafeMutableRawPointer?) -> OSStatus {
    guard let id = carbonHotKeyID(event), id.signature == WindowSnapper.signature,
          let layout = WindowSnapper.Layout(rawValue: Int(id.id)), let data else { return OSStatus(eventNotHandledErr) }
    let snapper = Unmanaged<WindowSnapper>.fromOpaque(data).takeUnretainedValue()
    MainActor.assumeIsolated { snapper.apply(layout) }
    return noErr
}
