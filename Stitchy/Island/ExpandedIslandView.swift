import SwiftUI

/// The expanded island: a tab header and one feature page.
struct ExpandedIslandView: View {
    @Environment(IslandModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(FileShelf.self) private var shelf

    var body: some View {
        VStack(spacing: IslandMetrics.headerSpacing) {
            IslandHeader(tabs: visibleTabs)
                .frame(height: IslandMetrics.headerHeight)
            page
                .id(currentTab)
                .transition(.blurReplace)
                .frame(maxWidth: .infinity)
                .frame(height: currentTab.contentHeight, alignment: .top)
        }
        .padding(IslandMetrics.expandedPadding)
        .frame(width: IslandMetrics.expandedWidth, alignment: .top)
        .foregroundStyle(.white)
        .modifier(ShelfDropTarget())
    }

    private var visibleTabs: [IslandTab] {
        IslandTab.allCases.filter { tab in
            switch tab {
            case .home, .activity: true
            case .music: settings.musicEnabled
            case .timer: settings.timerEnabled
            case .shelf: settings.shelfEnabled
            }
        }
    }

    private var currentTab: IslandTab {
        visibleTabs.contains(model.tab) ? model.tab : .home
    }

    @ViewBuilder private var page: some View {
        switch currentTab {
        case .home: DashboardView()
        case .music: MusicView()
        case .timer: TimerView()
        case .shelf: ShelfView()
        case .activity: ActivityView()
        }
    }
}

struct IslandHeader: View {
    let tabs: [IslandTab]
    @Environment(IslandModel.self) private var model
    @Environment(BatteryMonitor.self) private var battery
    @Environment(AppSettings.self) private var settings
    @Environment(ActivityFeed.self) private var feed
    @Namespace private var selection

    var body: some View {
        HStack(spacing: 2) {
            ForEach(tabs) { tab in
                TabButton(tab: tab, isSelected: model.tab == tab, badge: tab == .activity && feed.unread > 0, namespace: selection) {
                    model.select(tab)
                }
            }
            // Empty header space toggles the island closed (click-to-toggle).
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { model.headerTapped() }
            if settings.batteryEnabled, battery.snapshot.hasBattery {
                HStack(spacing: 5) {
                    Text("\(battery.snapshot.percent)%")
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.75))
                    Image(systemName: battery.snapshot.symbol)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(battery.snapshot.tint, .white.opacity(0.4))
                        .font(.system(size: 14))
                }
                .padding(.trailing, 6)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Battery \(battery.snapshot.percent) percent, \(battery.snapshot.statusText)")
            }
            IconButton(symbol: "gearshape.fill", size: 12, help: "Stitchy Settings") {
                model.collapse()
                model.openSettings()
            }
        }
    }
}

private struct TabButton: View {
    let tab: IslandTab
    let isSelected: Bool
    let badge: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: tab.symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 34, height: 26)
                .foregroundStyle(.white.opacity(isSelected ? 1 : hovering ? 0.8 : 0.45))
                .background {
                    if isSelected {
                        Capsule().fill(.white.opacity(0.14)).matchedGeometryEffect(id: "tab", in: namespace)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if badge {
                        Circle().fill(.red).frame(width: 6, height: 6).offset(x: -6, y: 4)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(tab.title)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Dropping files anywhere on the expanded island adds them to the shelf.
private struct ShelfDropTarget: ViewModifier {
    @Environment(IslandModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(FileShelf.self) private var shelf

    func body(content: Content) -> some View {
        if SnapshotRenderer.isRendering {
            content  // ImageRenderer can't draw AppKit-backed drop targets
        } else {
            content.dropDestination(for: URL.self) { urls, _ in
                guard settings.shelfEnabled else { return false }
                let added = shelf.add(urls)
                model.select(.shelf)
                model.convertToHover()
                return added > 0
            } isTargeted: { targeted in
                model.isDropTargeted = targeted && settings.shelfEnabled
            }
        }
    }
}
