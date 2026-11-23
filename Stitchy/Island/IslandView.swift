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

/// The single black shape that morphs between compact, alert and expanded.
///
/// One view owns one shape whose size and corner radii animate; content is
/// swapped inside it and clipped by it. That is what makes the three states
/// read as the same physical object growing downward from the top edge.
struct IslandView: View {
    @Environment(IslandModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(TimerService.self) private var timer
    @Environment(NowPlayingService.self) private var nowPlaying
    @Environment(DownloadsMonitor.self) private var downloads

    var body: some View {
        let activity = liveActivity
        let size = size(for: activity)
        let shape = UnevenRoundedRectangle(cornerRadii: radii(for: size), style: .continuous)

        ZStack(alignment: .top) {
            if model.isExpanded {
                ExpandedIslandView()
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.94, anchor: .top))
                            .animation(.easeOut(duration: 0.24).delay(0.05)),
                        removal: .opacity.animation(.easeIn(duration: 0.1))
                    ))
            } else if let alert = model.alert {
                AlertIslandView(event: alert)
                    .id(alert.id)
                    .transition(.blurReplace.animation(.easeOut(duration: 0.22)))
            } else {
                CompactIslandView(activity: activity)
                    .transition(.blurReplace.animation(.easeOut(duration: 0.2)))
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .background(.black)
        .clipShape(shape)
        .contentShape(shape)
        .shadow(color: .black.opacity(model.isExpanded ? 0.4 : 0), radius: 16, y: 6)
        .onTapGesture {
            if !model.isExpanded { model.handleCompactClick() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Stitchy")
    }

    private var liveActivity: LiveActivity {
        LiveActivity.resolve(settings: settings, timer: timer, downloads: downloads, nowPlaying: nowPlaying)
    }

    private func size(for activity: LiveActivity) -> CGSize {
        IslandMetrics.size(expanded: model.isExpanded, tab: model.tab, hasAlert: model.alert != nil,
                           activity: activity, hovering: model.isHovering)
    }

    private func radii(for size: CGSize) -> RectangleCornerRadii {
        if model.isExpanded { return IslandMetrics.expandedRadii }
        let r = size.height / 2
        return RectangleCornerRadii(topLeading: r, bottomLeading: r, bottomTrailing: r, topTrailing: r)
    }
}

/// What the compact island shows on its leading/trailing sides.
enum LiveActivity: Equatable {
    case none, timer, download, music

    @MainActor
    static func resolve(settings: AppSettings, timer: TimerService, downloads: DownloadsMonitor, nowPlaying: NowPlayingService) -> LiveActivity {
        guard settings.compactActivities else { return .none }
        if settings.timerEnabled, timer.isActive { return .timer }
        if settings.downloadsEnabled, !downloads.active.isEmpty { return .download }
        if settings.musicEnabled, nowPlaying.isPlaying { return .music }
        return .none
    }
}
