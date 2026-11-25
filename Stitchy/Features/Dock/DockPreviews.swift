import AppKit
import ApplicationServices
import ScreenCaptureKit
import SwiftUI

/// Droppy/DockDoor-style live window previews: hover an app in the Dock and
/// its windows appear above the icon; click one to bring it forward.
///  - Accessibility: the Dock reports which icon is under the pointer
///    (`AXSelectedChildrenChanged`) and raises/unminimizes the window you pick.
///  - Screen Recording: ScreenCaptureKit thumbnails of that app's windows,
///    captured only while you hover, never stored.
@MainActor @Observable
final class DockPreviews {
    struct Preview: Identifiable {
        let id: CGWindowID
        let title: String
        let image: NSImage?
        let minimized: Bool
    }

    private(set) var app: NSRunningApplication?
    private(set) var previews: [Preview] = []
    private(set) var needsPermission = false
    @ObservationIgnored private var observer: AXObserver?
    @ObservationIgnored private var dockList: AXUIElement?
    @ObservationIgnored private var panel: NSPanel?
    @ObservationIgnored private var hideTask: Task<Void, Never>?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var pointerInPanel = false
    @ObservationIgnored private var retryTask: Task<Void, Never>?

    var isRunning: Bool { observer != nil }

    func start() {
        guard observer == nil else { return }
        let prompt = ["AXTrustedCheckOptionPrompt": true] as CFDictionary   // kAXTrustedCheckOptionPrompt
        guard AXIsProcessTrustedWithOptions(needsPermission ? nil : prompt) else {
            // Ask once, then retry quietly until the user allows Accessibility.
            needsPermission = true
            retryTask?.cancel()
            retryTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                self?.start()
            }
            return
        }
        if !CGPreflightScreenCaptureAccess() { CGRequestScreenCaptureAccess() }
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return }
        let dockApp = AXUIElementCreateApplication(dock.processIdentifier)
        guard let list = (Self.attribute(dockApp, kAXChildrenAttribute) as [AXUIElement]?)?.first(where: {
            (Self.attribute($0, kAXRoleAttribute) as String?) == kAXListRole
        }) else { return }
        var obs: AXObserver?
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            let me = Unmanaged<DockPreviews>.fromOpaque(refcon).takeUnretainedValue()
            MainActor.assumeIsolated { me.selectionChanged() }
        }
        guard AXObserverCreate(dock.processIdentifier, callback, &obs) == .success, let obs else { return }
        AXObserverAddNotification(obs, list, kAXSelectedChildrenChangedNotification as CFString, Unmanaged.passUnretained(self).toOpaque())
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        observer = obs
        dockList = list
        needsPermission = false
    }

    func stop() {
        retryTask?.cancel()
        needsPermission = false
        if let observer, let dockList {
            AXObserverRemoveNotification(observer, dockList, kAXSelectedChildrenChangedNotification as CFString)
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observer = nil
        dockList = nil
        hide()
    }

    // MARK: Dock hover

    private func selectionChanged() {
        guard let dockList,
              let item = (Self.attribute(dockList, kAXSelectedChildrenAttribute) as [AXUIElement]?)?.first,
              (Self.attribute(item, kAXSubroleAttribute) as String?) == "AXApplicationDockItem",
              let url = Self.attribute(item, kAXURLAttribute) as URL?,
              let running = NSWorkspace.shared.runningApplications.first(where: { $0.bundleURL?.standardizedFileURL == url.standardizedFileURL })
        else { scheduleHide(); return }
        hideTask?.cancel()
        guard running != app || panel?.isVisible != true else { return }
        app = running
        previews = []
        let anchor = Self.frame(of: item)
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            let shots = await Self.capture(pid: running.processIdentifier)
            guard !Task.isCancelled, let self, self.app == running else { return }
            self.previews = shots
            if shots.isEmpty { self.hide() } else { self.show(above: anchor) }
        }
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, let self, !self.pointerInPanel else { return }
            self.hide()
        }
    }

    func pointerInPanel(_ inside: Bool) {
        pointerInPanel = inside
        if inside { hideTask?.cancel() } else { scheduleHide() }
    }

    private func hide() {
        loadTask?.cancel()
        panel?.orderOut(nil)
        app = nil
        previews = []
        pointerInPanel = false
    }

    // MARK: Panel

    private func show(above anchor: CGRect?) {
        if panel == nil {
            let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.level = .popUpMenu
            p.backgroundColor = .clear
            p.isOpaque = false
            p.hasShadow = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            p.hidesOnDeactivate = false
            let host = NSHostingView(rootView: DockPreviewView(model: self))
            host.sizingOptions = [.preferredContentSize]
            p.contentView = host
            panel = p
        }
        guard let panel, let screen = NSScreen.screens.first else { return }
        panel.layoutIfNeeded()
        let size = panel.contentView?.fittingSize ?? CGSize(width: 300, height: 200)
        // AX frames are top-left based on the primary screen; convert to AppKit.
        let primaryHeight = screen.frame.height
        let a = anchor ?? CGRect(x: NSEvent.mouseLocation.x, y: primaryHeight - 80, width: 1, height: 1)
        let icon = CGRect(x: a.minX, y: primaryHeight - a.maxY, width: a.width, height: a.height)
        let target = NSScreen.screens.first { $0.frame.contains(NSPoint(x: icon.midX, y: icon.midY)) } ?? screen
        let origin = Self.panelOrigin(icon: icon, size: size, dock: Self.dockEdge(), visible: target.visibleFrame)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
    }

    enum DockEdge: String { case bottom, left, right }

    /// The Dock's screen edge from its own preferences (default bottom).
    static func dockEdge() -> DockEdge {
        DockEdge(rawValue: UserDefaults(suiteName: "com.apple.dock")?.string(forKey: "orientation") ?? "") ?? .bottom
    }

    /// Beside the hovered icon, on the side away from the Dock, kept on screen.
    nonisolated static func panelOrigin(icon: CGRect, size: CGSize, dock: DockEdge, visible: CGRect) -> CGPoint {
        func clampX(_ x: CGFloat) -> CGFloat { min(max(x, visible.minX + 8), visible.maxX - size.width - 8) }
        func clampY(_ y: CGFloat) -> CGFloat { min(max(y, visible.minY + 8), visible.maxY - size.height - 8) }
        switch dock {
        case .bottom: return CGPoint(x: clampX(icon.midX - size.width / 2), y: icon.maxY + 8)
        case .left: return CGPoint(x: icon.maxX + 8, y: clampY(icon.midY - size.height / 2))
        case .right: return CGPoint(x: icon.minX - size.width - 8, y: clampY(icon.midY - size.height / 2))
        }
    }

    func select(_ preview: Preview) {
        guard let app else { return }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        let windows: [AXUIElement] = Self.attribute(axApp, kAXWindowsAttribute) ?? []
        let match = windows.first { (Self.attribute($0, kAXTitleAttribute) as String?) == preview.title } ?? windows.first
        if let match {
            AXUIElementSetAttributeValue(match, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            AXUIElementPerformAction(match, kAXRaiseAction as CFString)
        }
        app.activate()
        hide()
    }

    // MARK: Helpers

    nonisolated static func capture(pid: pid_t) async -> [Preview] {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false) else { return [] }
        let windows = content.windows.filter {
            $0.owningApplication?.processID == pid && $0.windowLayer == 0 && $0.frame.width > 120 && $0.frame.height > 80
                && !($0.title ?? "").isEmpty
        }.prefix(6)
        var result: [Preview] = []
        for w in windows {
            let config = SCStreamConfiguration()
            let scale = min(1, 360 / max(w.frame.width, 1))
            config.width = Int(w.frame.width * scale * 2)
            config.height = Int(w.frame.height * scale * 2)
            config.showsCursor = false
            let image = try? await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: w), configuration: config)
            result.append(Preview(id: w.windowID, title: w.title ?? "", image: image.map { NSImage(cgImage: $0, size: .zero) },
                                  minimized: !w.isOnScreen))
        }
        return result
    }

    private static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?, sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posRef, let sizeRef else { return nil }
        var point = CGPoint.zero, size = CGSize.zero
        AXValueGetValue(posRef as! AXValue, .cgPoint, &point)   // AX guarantees AXValue for these attributes
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        return CGRect(origin: point, size: size)
    }
}

struct DockPreviewView: View {
    let model: DockPreviews

    var body: some View {
        HStack(spacing: 10) {
            ForEach(model.previews) { preview in
                Button { model.select(preview) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Group {
                            if let image = preview.image {
                                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                            } else {
                                Color.white.opacity(0.06)
                            }
                        }
                        .frame(width: 180, height: 112)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .opacity(preview.minimized ? 0.6 : 1)
                        HStack(spacing: 4) {
                            if preview.minimized { Image(systemName: "minus.circle.fill").foregroundStyle(.yellow) }
                            Text(preview.title).lineLimit(1)
                        }
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 180, alignment: .leading)
                    }
                    .padding(6)
                    .modifier(HoverHighlight())
                }
                .buttonStyle(PressableStyle())
                .help(preview.title)
            }
        }
        .padding(10)
        .foregroundStyle(.white)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.black.opacity(0.85))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.1), lineWidth: 0.5)))
        .onHover { model.pointerInPanel($0) }
        .environment(\.colorScheme, .dark)
    }
}
