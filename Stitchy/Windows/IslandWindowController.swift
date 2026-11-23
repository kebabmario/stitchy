import AppKit
import SwiftUI

/// Positions the island panel and turns raw pointer events into island
/// behaviour: hover-to-expand, collapse-on-exit, click-outside, Escape and
/// file-drag detection.
///
/// Why event monitors instead of tracking areas: the panel is a fixed,
/// mostly transparent canvas. It ignores mouse events everywhere except the
/// island's current shape (so it never blocks the menu bar or windows
/// below), and a window that ignores mouse events gets no tracking events.
/// Global + local `NSEvent` monitors for moves/clicks/drags need no special
/// permission and are fully event-driven (no polling).
@MainActor
final class IslandWindowController: NSObject {
    private let services: AppServices
    private let panel: IslandPanel
    private var model: IslandModel { services.island }
    private var settings: AppSettings { services.settings }

    private var monitors: [Any] = []
    private var hoverTask: Task<Void, Never>?
    private var collapseTask: Task<Void, Never>?
    private var dragBaseline = NSPasteboard(name: .drag).changeCount
    private var isDragging = false
    private(set) var isVisible = false

    /// Extra slack around the island so tiny pointer jitter at the edge
    /// doesn't flicker between states.
    private let hoverMargin: CGFloat = 6
    private let exitDelay: Duration = .milliseconds(260)

    init(services: AppServices) {
        self.services = services
        panel = IslandPanel(size: IslandMetrics.panel)
        super.init()

        let root = IslandRootView()
            .environment(services.island)
            .environment(services.settings)
            .environment(services.feed)
            .environment(services.battery)
            .environment(services.network)
            .environment(services.nowPlaying)
            .environment(services.timer)
            .environment(services.shelf)
            .environment(services.downloads)
            .environment(services.notifier)
        let host = IslandHostingView(rootView: root)
        host.sizingOptions = []
        panel.contentView = host

        model.onExpansionChange = { [weak self] expanded, source in
            self?.expansionChanged(expanded, source: source)
        }

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(reposition), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(spaceChanged), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        observeContinuously { [weak self] in
            guard let self else { return }
            _ = (self.settings.topGap, self.settings.horizontalOffset, self.settings.display)
            self.reposition()
        }
    }

    // MARK: Visibility

    func show() {
        guard !isVisible else { return }
        isVisible = true
        reposition()
        panel.orderFrontRegardless()
        installMonitors()
    }

    func hide() {
        guard isVisible else { return }
        isVisible = false
        model.collapse()
        removeMonitors()
        panel.orderOut(nil)
    }

    @objc private func reposition() {
        guard let screen = ScreenLocator.screen(for: settings.display) else { return }
        let size = IslandMetrics.panel
        let visible = screen.frame
        var x = visible.midX - size.width / 2 + settings.horizontalOffset
        x = min(max(x, visible.minX), visible.maxX - size.width)
        let frame = NSRect(
            x: x.rounded(),
            y: (visible.maxY - settings.topGap - size.height).rounded(),
            width: size.width, height: size.height
        )
        if panel.frame != frame { panel.setFrame(frame, display: true) }
    }

    @objc private func spaceChanged() {
        if isVisible { panel.orderFrontRegardless() }
    }

    // MARK: Geometry

    private var screen: NSScreen? { panel.screen ?? ScreenLocator.screen(for: settings.display) }

    /// The island's target shape in screen coordinates (bottom-left origin).
    private var islandRect: NSRect {
        let activity = LiveActivity.resolve(settings: settings, timer: services.timer,
                                            downloads: services.downloads, nowPlaying: services.nowPlaying)
        let size = IslandMetrics.size(expanded: model.isExpanded, tab: model.tab, hasAlert: model.alert != nil,
                                      activity: activity, hovering: model.isHovering)
        let frame = panel.frame
        return NSRect(x: frame.midX - size.width / 2, y: frame.maxY - size.height, width: size.width, height: size.height)
    }

    /// Where the pointer counts as "on the island". Extends up to the top
    /// edge of the display so slamming the cursor to the top centre works.
    private var hitRect: NSRect {
        var r = islandRect.insetBy(dx: -hoverMargin, dy: -hoverMargin)
        if let top = screen?.frame.maxY, r.maxY < top { r.size.height = top - r.minY }
        return r
    }

    /// Generous "magnet" zone used while dragging files.
    private var dropZone: NSRect {
        model.isExpanded ? hitRect.insetBy(dx: -24, dy: -24) : hitRect.insetBy(dx: -90, dy: -50)
    }

    // MARK: Event monitors

    private func installMonitors() {
        guard monitors.isEmpty else { return }
        let global: [(NSEvent.EventTypeMask, (NSEvent.EventType) -> Void)] = [
            ([.mouseMoved], { [weak self] _ in self?.pointerMoved() }),
            ([.leftMouseDragged], { [weak self] _ in self?.dragMoved() }),
            ([.leftMouseDown, .rightMouseDown], { [weak self] _ in self?.clickedOutside() }),
            ([.leftMouseUp], { [weak self] _ in self?.dragEnded() }),
        ]
        for (mask, handler) in global {
            if let m = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { event in
                let type = event.type
                MainActor.assumeIsolated { handler(type) }
            }) { monitors.append(m) }
        }
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .leftMouseDown, .leftMouseUp, .keyDown], handler: { [weak self] event in
            guard let self else { return event }
            // keyCode raises an exception on non-key events, so read it only for keys.
            let type = event.type, keyCode = type == .keyDown ? event.keyCode : 0
            let consumed = MainActor.assumeIsolated { self.handleLocal(type, keyCode: keyCode) }
            return consumed ? nil : event
        }) { monitors.append(m) }
    }

    private func removeMonitors() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }

    /// Returns true when the event was consumed.
    private func handleLocal(_ type: NSEvent.EventType, keyCode: UInt16) -> Bool {
        switch type {
        case .mouseMoved: pointerMoved()
        case .leftMouseDragged: dragMoved()
        case .leftMouseDown:
            dragBaseline = NSPasteboard(name: .drag).changeCount
            // Interacting with a hover-opened island pins it open.
            model.clickJustPinned = false
            if model.isExpanded, model.source == .hover || model.source == .drag,
               hitRect.contains(NSEvent.mouseLocation) {
                model.clickJustPinned = true
                model.expand(.click)
            }
        case .leftMouseUp: dragEnded()
        case .keyDown where keyCode == 53 && model.isExpanded: // Escape
            model.collapse()
            return true
        default: break
        }
        return false
    }

    // MARK: Pointer behaviour

    private func setInteractive(_ interactive: Bool) {
        if panel.ignoresMouseEvents == interactive { panel.ignoresMouseEvents = !interactive }
    }

    private func pointerMoved() {
        let inside = hitRect.contains(NSEvent.mouseLocation)
        setInteractive(inside)
        guard inside != model.isHovering else { return }
        model.setHovering(inside)
        islandLog.info("hover \(inside, privacy: .public) island=\(NSStringFromRect(self.islandRect), privacy: .public)")
        inside ? pointerEntered() : pointerExited()
    }

    private func pointerEntered() {
        collapseTask?.cancel()
        guard !model.isExpanded, settings.hoverToExpand else { return }
        hoverTask?.cancel()
        hoverTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(self.settings.hoverDelay))
            guard !Task.isCancelled, self.model.isHovering, !self.model.isExpanded else { return }
            self.model.expand(.hover)
            Haptics.tap(self.settings.haptics)
        }
    }

    private func pointerExited() {
        hoverTask?.cancel()
        guard model.isExpanded, model.source == .hover || model.source == .drag, settings.collapseOnExit else { return }
        scheduleCollapse()
    }

    private func scheduleCollapse() {
        collapseTask?.cancel()
        collapseTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.exitDelay)
            guard !Task.isCancelled, !self.model.isHovering, !self.isDragging else { return }
            self.model.collapse()
        }
    }

    private func clickedOutside() {
        // Global monitor: the click landed outside our panel.
        dragBaseline = NSPasteboard(name: .drag).changeCount
        if model.isExpanded { model.collapse() }
    }

    // MARK: File drags

    /// A drag session in any app writes to the shared drag pasteboard, so a
    /// changed changeCount during a mouse drag means "something is being
    /// dragged". The drop target itself filters for file URLs. No
    /// pasteboard *contents* are read here.
    private func dragMoved() {
        if !isDragging {
            guard NSPasteboard(name: .drag).changeCount != dragBaseline else { return }
            isDragging = true
            model.isFileDragActive = true
            islandLog.info("drag started")
        }
        guard settings.shelfEnabled else { return }
        let point = NSEvent.mouseLocation
        if dropZone.contains(point) {
            collapseTask?.cancel()
            setInteractive(true)
            if !model.isExpanded {
                model.expand(.drag, tab: .shelf)
                Haptics.tap(settings.haptics)
            }
        } else if model.isExpanded, model.source == .drag {
            setInteractive(false)
            scheduleCollapse()
        }
    }

    private func dragEnded() {
        guard isDragging else { return }
        isDragging = false
        model.isFileDragActive = false
        dragBaseline = NSPasteboard(name: .drag).changeCount
        // Mouse-moved events aren't delivered during a drag; resync hover.
        let inside = hitRect.contains(NSEvent.mouseLocation)
        model.setHovering(inside)
        setInteractive(inside)
        if model.isExpanded, model.source == .drag { scheduleCollapse() }
    }

    // MARK: Focus

    private func expansionChanged(_ expanded: Bool, source: IslandModel.Source) {
        if expanded {
            collapseTask?.cancel()
            if source == .click || source == .menu {
                panel.allowsKey = true
                panel.makeKey()
            }
        } else {
            hoverTask?.cancel()
            relinquishKey()
        }
        pointerMoved()
    }

    /// Re-ordering the panel without key status hands keyboard focus back to
    /// whatever app the user was in.
    private func relinquishKey() {
        guard panel.allowsKey else { return }
        panel.allowsKey = false
        if panel.isKeyWindow, isVisible {
            panel.orderOut(nil)
            panel.orderFrontRegardless()
        }
    }
}
