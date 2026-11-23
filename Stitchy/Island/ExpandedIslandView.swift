import SwiftUI

/// The expanded island: a tab header and one feature page.
struct ExpandedIslandView: View {
    @Environment(IslandModel.self) private var model
    @Environment(AppSettings.self) private var settings

    var body: some View {
        let geometry = model.geometry
        VStack(spacing: IslandGeometry.headerSpacing) {
            IslandHeader(tabs: visibleTabs)
                .frame(height: IslandGeometry.headerHeight)
            page
                .id(currentTab)
                .transition(.blurReplace)
                .frame(maxWidth: .infinity)
                .frame(height: currentTab.contentHeight, alignment: .top)
        }
        .padding(.top, geometry.expandedTopPadding)
        .padding(.horizontal, 18)
        .padding(.bottom, IslandGeometry.bottomPadding)
        .frame(width: geometry.expandedWidth, alignment: .top)
        .foregroundStyle(.white)
        .modifier(ShelfDropTarget())
    }

    private var visibleTabs: [IslandTab] {
        IslandTab.allCases.filter { tab in
            switch tab {
            case .home, .activity, .calendar: true
            case .music: settings.musicEnabled
            case .timer: settings.timerEnabled
            case .shelf: settings.shelfEnabled || settings.clipboardEnabled
            case .notes: settings.notesEnabled
            case .launcher: settings.launcherEnabled
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
        case .timer: TimersView()
        case .shelf: ShelfView()
        case .notes: PrivateGate { NotesView() }
        case .calendar: CalendarView()
        case .launcher: LauncherView()
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
        HStack(spacing: 0) {
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
                HStack(spacing: 4) {
                    Text("\(battery.snapshot.percent)%")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.7))
                    Image(systemName: battery.snapshot.symbol)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(battery.snapshot.tint, .white.opacity(0.4))
                        .font(.system(size: 13))
                }
                .padding(.trailing, 6)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Battery \(battery.snapshot.percent) percent, \(battery.snapshot.statusText)")
            }
            IconButton(symbol: "gearshape.fill", size: 11, diameter: 24, help: "Stitchy Settings") {
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
                .font(.system(size: 11.5, weight: .semibold))
                .frame(width: 32, height: 26)
                .foregroundStyle(.white.opacity(isSelected ? 1 : hovering ? 0.8 : 0.42))
                .background {
                    if isSelected {
                        Capsule().fill(.white.opacity(0.14)).matchedGeometryEffect(id: "tab", in: namespace)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if badge {
                        Circle().fill(.red).frame(width: 6, height: 6).offset(x: -5, y: 4)
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

/// Segmented pills used inside pages ("Timers · Stopwatch · Focus").
struct Segmented<T: Hashable>: View {
    let options: [(T, String)]
    @Binding var selection: T
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.0) { value, title in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { selection = value }
                } label: {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 10)
                        .frame(height: 22)
                        .foregroundStyle(.white.opacity(selection == value ? 1 : 0.5))
                        .background {
                            if selection == value {
                                Capsule().fill(.white.opacity(0.14)).matchedGeometryEffect(id: "seg", in: ns)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Capsule().fill(.white.opacity(0.05)))
    }
}

/// Hides private content until unlocked with LocalAuthentication.
struct PrivateGate<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(PrivateLock.self) private var lock

    var body: some View {
        if lock.isLocked {
            VStack(spacing: 8) {
                Image(systemName: "lock.fill").font(.system(size: 22, weight: .medium)).foregroundStyle(Color.secondaryText)
                Text("Private").font(.system(size: 14, weight: .semibold))
                Text("Unlock with Touch ID or your password.")
                    .font(.system(size: 11)).foregroundStyle(Color.secondaryText)
                PillButton(title: "Unlock", symbol: "touchid", tint: .white, prominent: true) {
                    Task { await lock.unlock() }
                }
                if let error = lock.lastError {
                    Text(error).font(.system(size: 10)).foregroundStyle(.red.opacity(0.8)).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            content
        }
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
