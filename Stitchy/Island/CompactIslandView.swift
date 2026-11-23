import SwiftUI

/// The resting capsule. Idle it is pure black, like the Dynamic Island;
/// with a live activity it shows a glyph on each side.
struct CompactIslandView: View {
    let activity: LiveActivity
    @Environment(TimerService.self) private var timer
    @Environment(NowPlayingService.self) private var nowPlaying
    @Environment(DownloadsMonitor.self) private var downloads
    @Environment(AppSettings.self) private var settings

    var body: some View {
        HStack(spacing: 0) {
            leading.frame(width: 26, height: 22, alignment: .leading)
            Spacer(minLength: 0)
            trailing.frame(minWidth: 26, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder private var leading: some View {
        switch activity {
        case .none: EmptyView()
        case .timer:
            TimelineView(.periodic(from: .now, by: 1)) { context in
                ProgressRing(fraction: timer.fraction(at: context.date), color: .orange, lineWidth: 2.5)
                    .frame(width: 17, height: 17)
            }
        case .download:
            let item = downloads.active.first
            ZStack {
                if let fraction = item?.fraction {
                    ProgressRing(fraction: fraction, color: .blue, lineWidth: 2.5)
                }
                Image(systemName: "arrow.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.blue)
            }
            .frame(width: 17, height: 17)
        case .music:
            ArtworkView(image: nowPlaying.artwork, size: 22, radius: 6, placeholderIcon: nowPlaying.player?.icon)
        }
    }

    @ViewBuilder private var trailing: some View {
        switch activity {
        case .none: EmptyView()
        case .timer:
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(timer.phase == .finished ? "Done" : timer.remaining(at: context.date).clockString)
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.orange)
                    .opacity(timer.isPaused ? 0.6 : 1)
            }
        case .download:
            if let fraction = downloads.active.first?.fraction {
                Text(fraction, format: .percent.precision(.fractionLength(0)))
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.blue)
            } else {
                Image(systemName: "ellipsis").foregroundStyle(.blue)
            }
        case .music:
            EqualizerView(color: NSColor(nowPlaying.accent), animating: settings.animatedVisualizer && !settings.reduceMotion)
                .frame(width: 18, height: 14)
        }
    }
}

/// Transient alert, e.g. "Charging 54%" or a new track.
struct AlertIslandView: View {
    let event: ActivityEvent

    var body: some View {
        HStack(spacing: 10) {
            if let artwork = event.artwork {
                ArtworkView(image: artwork, size: 32, radius: 8)
            } else {
                Image(systemName: event.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(event.tint)
                    .frame(width: 32, height: 32)
                    .background(event.tint.opacity(0.16), in: Circle())
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                if let detail = event.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .lineLimit(1)
            Spacer(minLength: 4)
            if let trailing = event.trailing {
                Text(trailing)
                    .font(.system(size: 15, weight: .semibold).monospacedDigit())
                    .foregroundStyle(event.tint)
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 18)
        .frame(maxHeight: .infinity)
    }
}
