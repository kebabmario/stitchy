import AppKit
import Observation
import SwiftUI

enum IslandTab: String, CaseIterable, Identifiable, Sendable {
    case home, music, timer, shelf, notes, calendar, launcher, activity

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .music: "Music"
        case .timer: "Timers"
        case .shelf: "Shelf"
        case .notes: "Notes"
        case .calendar: "Calendar"
        case .launcher: "Launcher"
        case .activity: "Activity"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .music: "music.note"
        case .timer: "timer"
        case .shelf: "tray.full.fill"
        case .notes: "note.text"
        case .calendar: "calendar"
        case .launcher: "magnifyingglass"
        case .activity: "bell.fill"
        }
    }

    /// Height of the tab's content area. The island animates between these.
    var contentHeight: CGFloat {
        switch self {
        case .home: 168
        case .music: 136
        case .timer: 176
        case .shelf: 156
        case .notes: 176
        case .calendar: 168
        case .launcher: 176
        case .activity: 188
        }
    }
}

/// Geometry of the attached notch. All values in points.
///
/// The island hangs from the top edge of the display like a MacBook notch:
/// square top edge with small concave "shoulders" that blend into the
/// screen edge, and rounded bottom corners. Resting width/height come from
/// Settings; the height defaults to the menu bar height so it reads as a
/// real notch.
struct IslandGeometry: Equatable {
    var notchWidth: CGFloat
    var notchHeight: CGFloat
    var expandedWidth: CGFloat

    static let headerHeight: CGFloat = 28
    static let headerSpacing: CGFloat = 10
    /// Concave shoulder radius where the island meets the top edge.
    static let shoulder: CGFloat = 8
    static let expandedShoulder: CGFloat = 14
    static let bottomPadding: CGFloat = 18

    /// The panel is a fixed transparent canvas big enough for the largest
    /// state plus its shadow; only the island itself receives mouse events.
    static let panel = CGSize(width: 680, height: 380)

    var compact: CGSize { CGSize(width: notchWidth + 2 * Self.shoulder, height: notchHeight) }
    var compactHover: CGSize { CGSize(width: compact.width + 12, height: notchHeight + 4) }
    /// Live activities sit on both sides of the notch, like the Dynamic Island.
    var compactLive: CGSize { CGSize(width: compact.width + 128, height: notchHeight) }
    var alert: CGSize { CGSize(width: max(compact.width + 170, 360), height: notchHeight + 30) }
    var hud: CGSize { CGSize(width: compact.width + 150, height: notchHeight) }

    var expandedTopPadding: CGFloat { max(6, (notchHeight - Self.headerHeight) / 2) }

    func expandedHeight(for tab: IslandTab) -> CGFloat {
        expandedTopPadding + Self.headerHeight + Self.headerSpacing + tab.contentHeight + Self.bottomPadding
    }

    func expanded(for tab: IslandTab) -> CGSize {
        CGSize(width: expandedWidth + 2 * Self.expandedShoulder, height: expandedHeight(for: tab))
    }

    enum Mode: Equatable { case compact, hover, live, alert, hud, expanded }

    func size(_ mode: Mode, tab: IslandTab) -> CGSize {
        switch mode {
        case .compact: compact
        case .hover: compactHover
        case .live: compactLive
        case .alert: alert
        case .hud: hud
        case .expanded: expanded(for: tab)
        }
    }

    func shoulder(_ mode: Mode) -> CGFloat { mode == .expanded ? Self.expandedShoulder : Self.shoulder }

    func bottomRadius(_ mode: Mode) -> CGFloat {
        switch mode {
        case .expanded: 34
        case .alert: 22
        default: min(notchHeight * 0.42, 14)
        }
    }
}

/// UI state of the island: compact, showing a live alert or HUD, or expanded.
@MainActor @Observable
final class IslandModel {
    enum Source { case hover, click, drag, menu }

    private(set) var isExpanded = false
    private(set) var source: Source = .hover
    private(set) var tab: IslandTab = .home
    private(set) var alert: ActivityEvent?
    private(set) var hud: HUDEvent?
    var isHovering = false
    var isFileDragActive = false
    var isDropTargeted = false
    /// Height of the menu bar on the island's screen; the default notch height.
    var menuBarHeight: CGFloat = 32
    /// Incremented to ask the launcher to focus its search field.
    var focusSearchToken = 0

    /// Set when a mouse-down pins a hover-opened island, so the same click's
    /// mouse-up on the header doesn't immediately close it again.
    @ObservationIgnored var clickJustPinned = false
    @ObservationIgnored var openSettings: () -> Void = {}
    @ObservationIgnored var onExpansionChange: ((Bool, Source) -> Void)?
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private var alertTask: Task<Void, Never>?
    @ObservationIgnored private var hudTask: Task<Void, Never>?

    init(settings: AppSettings) {
        self.settings = settings
    }

    var geometry: IslandGeometry {
        let h = settings.notchHeight > 0 ? settings.notchHeight : max(menuBarHeight, 24)
        return IslandGeometry(notchWidth: settings.notchWidth, notchHeight: h, expandedWidth: settings.expandedWidth)
    }

    func mode(hasLiveActivity: Bool) -> IslandGeometry.Mode {
        if isExpanded { return .expanded }
        if alert != nil { return .alert }
        if hud != nil { return .hud }
        if hasLiveActivity { return .live }
        return isHovering ? .hover : .compact
    }

    func expand(_ source: Source, tab: IslandTab? = nil) {
        if let tab { select(tab, animated: isExpanded) }
        if isExpanded {
            // Upgrading a hover/drag expansion to a pinned one.
            if source == .click || source == .menu {
                islandLog.info("pin source=\(String(describing: source), privacy: .public)")
                self.source = source
                onExpansionChange?(true, source)
            }
            return
        }
        self.source = source
        islandLog.info("expand source=\(String(describing: source), privacy: .public) tab=\(self.tab.rawValue, privacy: .public)")
        alertTask?.cancel()
        hudTask?.cancel()
        withAnimation(settings.expandAnimation) {
            isExpanded = true
            alert = nil
            hud = nil
        }
        onExpansionChange?(true, source)
    }

    func collapse() {
        guard isExpanded else { return }
        islandLog.info("collapse")
        withAnimation(settings.collapseAnimation) {
            isExpanded = false
            isDropTargeted = false
        }
        onExpansionChange?(false, source)
    }

    /// After a drop the island behaves as if opened by hover, so it closes
    /// when the pointer leaves.
    func convertToHover() {
        if source == .drag { source = .hover }
    }

    func select(_ tab: IslandTab, animated: Bool = true) {
        guard tab != self.tab else { return }
        if animated {
            withAnimation(settings.expandAnimation) { self.tab = tab }
        } else {
            self.tab = tab
        }
    }

    /// Opens the launcher pinned, with its search field focused.
    func openLauncher() {
        expand(.menu, tab: .launcher)
        focusSearchToken += 1
    }

    /// Click on empty header space: closes a pinned island (click-to-toggle).
    func headerTapped() {
        if clickJustPinned {
            clickJustPinned = false
            return
        }
        collapse()
    }

    func handleCompactClick() {
        if let alert {
            expand(.click, tab: alert.tab)
        } else if settings.clickToExpand {
            expand(.click)
        }
    }

    /// Shows a transient live alert while the island is compact.
    func present(_ event: ActivityEvent) {
        guard !isExpanded else { return }
        islandLog.info("alert \(event.title, privacy: .public)")
        alertTask?.cancel()
        withAnimation(settings.expandAnimation) { alert = event }
        let id = event.id
        alertTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(event.alertDuration))
            guard !Task.isCancelled else { return }
            self?.dismissAlert(id)
        }
    }

    func dismissAlert(_ id: UUID? = nil) {
        guard let alert, id == nil || alert.id == id else { return }
        withAnimation(settings.collapseAnimation) { self.alert = nil }
    }

    /// Shows a compact system indicator (volume, mute, output).
    /// Repeated changes update it in place and extend its lifetime.
    func showHUD(_ event: HUDEvent) {
        guard !isExpanded, alert == nil else { return }
        islandLog.info("hud \(event.title, privacy: .public) level=\(event.level ?? -1, privacy: .public)")
        hudTask?.cancel()
        if hud == nil {
            withAnimation(settings.expandAnimation) { hud = event }
        } else {
            hud = event
        }
        hudTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled, let self else { return }
            withAnimation(self.settings.collapseAnimation) { self.hud = nil }
        }
    }

    func setHovering(_ hovering: Bool) {
        guard hovering != isHovering else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { isHovering = hovering }
    }
}

/// A compact system indicator.
struct HUDEvent: Equatable {
    var symbol: String
    var tint: Color = .white
    var title: String
    /// 0...1 level bar, or nil for a text-only indicator.
    var level: Double?
}
