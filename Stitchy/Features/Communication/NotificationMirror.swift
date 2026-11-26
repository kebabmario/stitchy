// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import ApplicationServices
import Observation
import SwiftUI

/// Calls and messages, mirrored from macOS's own notification banners.
///
/// macOS has no public API for observing other apps' calls or messages.
/// The supported mechanism is the Accessibility API: with the user's
/// explicit consent, Stitchy watches only the Notification Center process
/// for new banner windows and reads the text in them. Scope is limited to:
///  - banners only (no other app windows are read),
///  - Messages, FaceTime and Phone, unless other apps are allowed,
///  - nothing stored: the last few items live in memory only.
/// Accept/Decline appear only when the banner itself shows those buttons,
/// and they press the banner's real buttons. No reply is offered.
@MainActor @Observable
final class NotificationMirror {
    struct Incoming: Identifiable, Equatable {
        enum Kind: Equatable { case message, call, other }
        let id = UUID()
        let date = Date()
        let kind: Kind
        let app: String
        let title: String
        let body: String?
        let canAccept: Bool
        let canDecline: Bool
        static func == (a: Incoming, b: Incoming) -> Bool { a.id == b.id }
    }

    private(set) var recent: [Incoming] = []
    private(set) var activeCall: Incoming?
    private(set) var callStarted: Date?
    private(set) var trusted = AXIsProcessTrusted()
    private(set) var isRunning = false
    @ObservationIgnored var onIncoming: ((Incoming) -> Void)?
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private var observer: AXObserver?
    @ObservationIgnored private var buttons: [UUID: (accept: AXUIElement?, decline: AXUIElement?)] = [:]

    nonisolated static let messageApps = ["Messages", "WhatsApp", "Telegram", "Signal"]
    nonisolated static let callApps = ["FaceTime", "Phone"]

    init(settings: AppSettings) { self.settings = settings }

    /// Shows macOS's Accessibility consent prompt. Only called from an
    /// explicit user action in Settings.
    func requestAccess() {
        let key = "AXTrustedCheckOptionPrompt"  // value of kAXTrustedCheckOptionPrompt
        trusted = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    func refreshTrust() { trusted = AXIsProcessTrusted() }

    func start() {
        refreshTrust()
        guard trusted, observer == nil,
              let nc = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.notificationcenterui").first else { return }
        var obs: AXObserver?
        guard AXObserverCreate(nc.processIdentifier, mirrorCallback, &obs) == .success, let obs else { return }
        let app = AXUIElementCreateApplication(nc.processIdentifier)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(obs, app, kAXWindowCreatedNotification as CFString, refcon)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        observer = obs
        isRunning = true
    }

    func stop() {
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode) }
        observer = nil
        isRunning = false
        recent.removeAll()
        buttons.removeAll()
        activeCall = nil
    }

    func clear() { recent.removeAll() }

    /// Presses the banner's own Accept / Decline button.
    func respond(_ item: Incoming, accept: Bool) {
        guard let pair = buttons[item.id], let button = accept ? pair.accept : pair.decline else { return }
        AXUIElementPerformAction(button, kAXPressAction as CFString)
        if accept { activeCall = item; callStarted = Date() } else { endCall() }
    }

    func endCall() {
        activeCall = nil
        callStarted = nil
    }

    fileprivate func bannerAppeared(_ window: AXUIElement) {
        // Banner text is filled in just after the window appears.
        let box = UncheckedBox(window)
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            self?.read(box.value)
        }
    }

    private func read(_ window: AXUIElement) {
        let banner = Self.extract(window)
        guard let parsed = Self.classify(texts: banner.texts, buttonTitles: banner.buttons.map(\.0)) else { return }
        let allowed = parsed.kind != .other || settings.mirrorOtherApps
        guard allowed else { return }
        let item = Incoming(kind: parsed.kind, app: parsed.app, title: parsed.title,
                            body: settings.mirrorHidePreviews ? nil : parsed.body,
                            canAccept: parsed.kind == .call && banner.buttons.contains { Self.isAccept($0.0) },
                            canDecline: parsed.kind == .call && banner.buttons.contains { Self.isDecline($0.0) })
        buttons[item.id] = (banner.buttons.first { Self.isAccept($0.0) }?.1, banner.buttons.first { Self.isDecline($0.0) }?.1)
        recent.insert(item, at: 0)
        if recent.count > 10 {
            for old in recent.dropFirst(10) { buttons[old.id] = nil }
            recent.removeLast(recent.count - 10)
        }
        islandLog.info("mirror banner kind=\(String(describing: parsed.kind), privacy: .public) app=\(parsed.app, privacy: .public)")
        onIncoming?(item)
    }

    // MARK: Accessibility tree reading (bounded)

    private static func attribute<T>(_ e: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    /// Visible strings and buttons of a banner, depth- and size-limited.
    static func extract(_ root: AXUIElement) -> (texts: [String], buttons: [(String, AXUIElement)]) {
        var texts: [String] = []
        var buttons: [(String, AXUIElement)] = []
        var stack: [(AXUIElement, Int)] = [(root, 0)]
        var visited = 0
        while let (e, depth) = stack.popLast(), visited < 80 {
            visited += 1
            let role: String? = attribute(e, kAXRoleAttribute)
            if role == kAXStaticTextRole, let v: String = attribute(e, kAXValueAttribute), !v.isEmpty { texts.append(v) }
            if role == kAXButtonRole {
                let title: String = attribute(e, kAXTitleAttribute) ?? attribute(e, kAXDescriptionAttribute) ?? ""
                if !title.isEmpty { buttons.append((title, e)) }
            }
            if depth < 10, let children: [AXUIElement] = attribute(e, kAXChildrenAttribute) {
                for child in children.reversed() { stack.append((child, depth + 1)) }
            }
        }
        return (texts, buttons)
    }

    nonisolated static func isAccept(_ t: String) -> Bool { ["accept", "answer"].contains { t.lowercased().contains($0) } }
    nonisolated static func isDecline(_ t: String) -> Bool { ["decline", "reject", "ignore"].contains { t.lowercased().contains($0) } }

    /// Banner text -> app, title, body. Pure; tested.
    nonisolated static func classify(texts raw: [String], buttonTitles: [String]) -> (kind: Incoming.Kind, app: String, title: String, body: String?)? {
        let texts = raw.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !texts.isEmpty else { return nil }
        let all = texts.joined(separator: " ").lowercased()
        let app = (messageApps + callApps).first { name in texts.contains { $0.caseInsensitiveCompare(name) == .orderedSame } } ?? texts[0]
        let rest = texts.filter { $0.caseInsensitiveCompare(app) != .orderedSame && !$0.lowercased().hasSuffix(" ago") && $0.lowercased() != "now" }
        let looksLikeCall = callApps.contains(app) || all.contains("incoming call") || all.contains("is calling")
            || buttonTitles.contains(where: isAccept)
        let kind: Incoming.Kind = looksLikeCall ? .call : (messageApps.contains(app) ? .message : .other)
        guard let title = rest.first else { return nil }
        let body = rest.dropFirst().joined(separator: " ")
        return (kind, app, title, body.isEmpty ? nil : body)
    }
}

/// AX callback on the main run loop.
private func mirrorCallback(_ observer: AXObserver, _ element: AXUIElement, _ notification: CFString, _ refcon: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    let mirror = Unmanaged<NotificationMirror>.fromOpaque(refcon).takeUnretainedValue()
    let box = UncheckedBox(element)
    let m = UncheckedBox(mirror)
    MainActor.assumeIsolated { m.value.bannerAppeared(box.value) }
}
