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

extension IslandView {
    /// Bubble `index` (0 = right, 1 = left), pushed just outside the island.
    @ViewBuilder func bubble(at index: Int, side: CGFloat, geometry: IslandGeometry) -> some View {
        let bubbles = services.bubbleActivities
        if bubbles.indices.contains(index) {
            IslandBubble(activity: bubbles[index], geometry: geometry)
                .offset(x: side * (IslandBubble.size(for: geometry).width + IslandBubble.gap))
                .transition(.scale(scale: 0.4, anchor: side > 0 ? .leading : .trailing).combined(with: .opacity))
                .id(bubbles[index].id)
        }
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
            case .auth:
                if let card = model.authCard {
                    AuthCardView(card: card, geometry: geometry)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.7)).animation(.spring(response: 0.42, dampingFraction: 0.7).delay(0.05)),
                            removal: .opacity.combined(with: .scale(scale: 0.85)).animation(.easeIn(duration: 0.14))))
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
                    if mode == .liveLyrics {
                        Group {
                            if case .agent? = activities.first?.kind { AgentStripLine() } else { CompactLyricLine() }
                        }
                        .frame(height: IslandGeometry.lyricStrip, alignment: .top)
                    }
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
        .overlay(alignment: .topTrailing) { bubble(at: 0, side: 1, geometry: geometry) }
        .overlay(alignment: .topLeading) { bubble(at: 1, side: -1, geometry: geometry) }
        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: services.bubbleActivities.map(\.id))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Stitchy")
    }
}
