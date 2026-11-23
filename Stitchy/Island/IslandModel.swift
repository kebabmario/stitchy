import AppKit
import Observation
import SwiftUI

enum IslandTab: String, CaseIterable, Identifiable, Sendable {
    case home, music, timer, shelf, activity

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .music: "Music"
        case .timer: "Timer"
        case .shelf: "Shelf"
        case .activity: "Activity"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .music: "music.note"
        case .timer: "timer"
        case .shelf: "tray.full.fill"
        case .activity: "bell.fill"
        }
    }

    /// Height of the tab's content area. The island animates between these.
    var contentHeight: CGFloat {
        switch self {
        case .home: 150
        case .music: 132
        case .timer: 132
        case .shelf: 132
        case .activity: 176
        }
    }
}

/// Geometry of the island. All values in points.
enum IslandMetrics {
    static let compact = CGSize(width: 132, height: 36)
    static let compactHover = CGSize(width: 142, height: 38)
    static let compactLive = CGSize(width: 224, height: 36)
    static let alert = CGSize(width: 330, height: 52)
    static let expandedWidth: CGFloat = 430
    static let headerHeight: CGFloat = 28
    static let expandedPadding = EdgeInsets(top: 10, leading: 18, bottom: 16, trailing: 18)
    static let headerSpacing: CGFloat = 10

    /// The panel is a fixed transparent canvas big enough for the largest
    /// state plus its shadow; only the island itself receives mouse events.
    static let panel = CGSize(width: 560, height: 320)

    static func expandedHeight(for tab: IslandTab) -> CGFloat {
        expandedPadding.top + headerHeight + headerSpacing + tab.contentHeight + expandedPadding.bottom
    }

    /// Target size of the island for a given state. Shared by the view
    /// (what it draws) and the window controller (where it accepts the
    /// pointer), so hit-testing never depends on mid-animation layout.
    static func size(expanded: Bool, tab: IslandTab, hasAlert: Bool, activity: LiveActivity, hovering: Bool) -> CGSize {
        if expanded { return CGSize(width: expandedWidth, height: expandedHeight(for: tab)) }
        if hasAlert { return alert }
        if activity != .none { return compactLive }
        return hovering ? compactHover : compact
    }

    static let expandedRadii = RectangleCornerRadii(topLeading: 24, bottomLeading: 36, bottomTrailing: 36, topTrailing: 24)
}

/// UI state of the island: compact, showing a live alert, or expanded.
@MainActor @Observable
final class IslandModel {
    enum Source { case hover, click, drag, menu }

    private(set) var isExpanded = false
    private(set) var source: Source = .hover
    private(set) var tab: IslandTab = .home
    private(set) var alert: ActivityEvent?
    var isHovering = false
    var isFileDragActive = false
    var isDropTargeted = false

    /// Set when a mouse-down pins a hover-opened island, so the same click's
    /// mouse-up on the header doesn't immediately close it again.
    @ObservationIgnored var clickJustPinned = false
    @ObservationIgnored var openSettings: () -> Void = {}
    @ObservationIgnored var onExpansionChange: ((Bool, Source) -> Void)?
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private var alertTask: Task<Void, Never>?

    init(settings: AppSettings) {
        self.settings = settings
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
        withAnimation(settings.expandAnimation) {
            isExpanded = true
            alert = nil
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

    func setHovering(_ hovering: Bool) {
        guard hovering != isHovering else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { isHovering = hovering }
    }
}
