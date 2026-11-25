import SwiftUI

/// Fills the transparent panel and pins the island to its top centre.
struct IslandRootView: View {
    var body: some View {
        VStack(spacing: 0) {
            IslandView()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
    }
}

/// The single black notch that morphs between compact, live activity,
/// alert, HUD and expanded.
///
/// One view owns one `NotchShape` whose size and radii animate; content is
/// swapped inside it and clipped by it. Its top edge never moves, so every
/// state reads as the same surface growing down from the display edge.
struct IslandView: View {
    @Environment(IslandModel.self) private var model
    @Environment(AppServices.self) private var services

    var body: some View {
        let activities = services.compactActivities
        let mode = services.islandMode
        let geometry = model.geometry
        let size = services.islandSize(mode)
        let shape = NotchShape(shoulder: geometry.shoulder(mode), bottomRadius: geometry.bottomRadius(mode), topRadius: geometry.topRadius(mode))
        let inset = max(geometry.shoulder(mode), geometry.style == .island && mode == .expanded ? 6 : 0)

        ZStack(alignment: .top) {
            switch mode {
            case .expanded:
                ExpandedIslandView()
                    .padding(.horizontal, inset)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .top))
                            .animation(.easeOut(duration: 0.24).delay(0.06)),
                        removal: .opacity.animation(.easeIn(duration: 0.1))
                    ))
            case .alert:
                if let alert = model.alert {
                    AlertIslandView(event: alert)
                        .padding(.horizontal, inset)
                        .id(alert.id)
                        .transition(.blurReplace.animation(.easeOut(duration: 0.22)))
                }
            case .hud:
                if let hud = model.hud {
                    HUDIslandView(event: hud, notchWidth: geometry.notchWidth)
                        .padding(.horizontal, inset)
                        .transition(.blurReplace.animation(.easeOut(duration: 0.18)))
                }
            case .live, .liveLyrics:
                VStack(spacing: 0) {
                    CompactIslandView(activities: activities, notchWidth: geometry.notchWidth)
                        .frame(height: geometry.notchHeight)
                    if mode == .liveLyrics { CompactLyricLine().frame(height: IslandGeometry.lyricStrip, alignment: .top) }
                }
                .padding(.horizontal, inset)
                .transition(.blurReplace.animation(.easeOut(duration: 0.2)))
            case .compact, .hover:
                Color.clear
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .background(.black)
        .clipShape(shape)
        .contentShape(shape)
        // No shadow layer at all unless expanded: a zero-opacity shadow still
        // forces an offscreen pass on every repaint of the compact island.
        .shadow(color: .black.opacity(mode == .expanded ? 0.45 : 0), radius: mode == .expanded ? 18 : 0, y: mode == .expanded ? 8 : 0)
        .onTapGesture {
            if !model.isExpanded { model.handleCompactClick() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Stitchy")
    }
}
