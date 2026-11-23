import SwiftUI

/// Live activity in the compact notch: the top activity's glyph on the left
/// of the notch, its value on the right, and a small hint of the next one.
struct CompactIslandView: View {
    let activities: [IslandActivity]
    let notchWidth: CGFloat
    @Environment(AppSettings.self) private var settings

    var body: some View {
        let primary = activities.first
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                if let primary { ActivityGlyph(activity: primary, size: 18) }
                if activities.count > 1 {
                    Image(systemName: activities[1].symbol)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(activities[1].tint.opacity(0.8))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // The notch itself stays empty, like the real hardware.
            Color.clear.frame(width: notchWidth - 20)
            Group {
                if let primary { ActivityValue(activity: primary, compact: true) }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity)
    }
}

/// Leading glyph for an activity (artwork, progress ring or symbol).
struct ActivityGlyph: View {
    let activity: IslandActivity
    var size: CGFloat = 18
    @Environment(NowPlayingService.self) private var nowPlaying

    var body: some View {
        switch activity.kind {
        case .music:
            ArtworkView(image: nowPlaying.artwork, size: size + 2, radius: 5, placeholderIcon: nowPlaying.player?.icon)
        case .countdown(let timer):
            TimelineView(.periodic(from: .timelineAnchor, by: 1)) { context in
                ProgressRing(fraction: timer.fraction(at: context.date), color: activity.tint, lineWidth: 2.5)
                    .frame(width: size - 2, height: size - 2)
            }
        case .pomodoro(let pomodoro):
            TimelineView(.periodic(from: .timelineAnchor, by: 1)) { context in
                ProgressRing(fraction: pomodoro.timer.fraction(at: context.date), color: activity.tint, lineWidth: 2.5)
                    .frame(width: size - 2, height: size - 2)
            }
        case .download(let d):
            ZStack {
                if let f = d.fraction { ProgressRing(fraction: f, color: .blue, lineWidth: 2.5) }
                Image(systemName: "arrow.down").font(.system(size: 8, weight: .bold)).foregroundStyle(.blue)
            }
            .frame(width: size - 2, height: size - 2)
        case .camera, .microphone:
            Circle().fill(activity.tint).frame(width: 8, height: 8)
                .overlay(Circle().fill(activity.tint.opacity(0.35)).frame(width: 14, height: 14))
        default:
            Image(systemName: activity.symbol)
                .font(.system(size: size * 0.65, weight: .semibold))
                .foregroundStyle(activity.tint)
        }
    }
}

/// Trailing value for an activity (time left, percent, visualizer).
struct ActivityValue: View {
    let activity: IslandActivity
    var compact = false
    @Environment(NowPlayingService.self) private var nowPlaying
    @Environment(AppSettings.self) private var settings
    @Environment(PrivacyGuard.self) private var privacy

    var body: some View {
        Group {
            switch activity.kind {
            case .music:
                EqualizerView(color: NSColor(nowPlaying.accent), animating: settings.animatedVisualizer && !settings.reduceMotion)
                    .frame(width: 18, height: 14)
            case .countdown(let timer):
                TimelineView(.periodic(from: .timelineAnchor, by: 1)) { context in
                    Text(timer.phase == .finished ? "Done" : timer.remaining(at: context.date).clockString)
                        .opacity(timer.isPaused ? 0.55 : 1)
                }
            case .pomodoro(let p):
                TimelineView(.periodic(from: .timelineAnchor, by: 1)) { context in
                    Text(p.timer.phase == .finished ? "Done" : p.timer.remaining(at: context.date).clockString)
                        .opacity(p.timer.isPaused ? 0.55 : 1)
                }
            case .stopwatch(let s):
                TimelineView(.periodic(from: .timelineAnchor, by: 1)) { context in
                    Text(s.elapsed(at: context.date).clockStringFloor).opacity(s.isRunning ? 1 : 0.55)
                }
            case .download(let d):
                if let f = d.fraction { Text(f, format: .percent.precision(.fractionLength(0))) } else { Image(systemName: "ellipsis") }
            case .airDrop:
                Image(systemName: "ellipsis")
            case .camera:
                TimelineView(.periodic(from: .timelineAnchor, by: 1)) { context in
                    Text(compact ? "Camera" : (privacy.cameraSince.map { context.date.timeIntervalSince($0).clockStringFloor } ?? ""))
                }
            case .microphone:
                TimelineView(.periodic(from: .timelineAnchor, by: 1)) { context in
                    Text(privacy.microphoneSince.map { context.date.timeIntervalSince($0).clockStringFloor } ?? "Mic")
                }
            }
        }
        .font(.system(size: 13, weight: .semibold).monospacedDigit())
        .foregroundStyle(activity.tint)
        .lineLimit(1)
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
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .frame(maxHeight: .infinity)
    }
}

/// Volume / mute / output indicator. Symbol left of the notch, level right.
struct HUDIslandView: View {
    let event: HUDEvent
    let notchWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: event.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(event.tint)
                .contentTransition(.symbolEffect(.replace))
                .frame(maxWidth: .infinity, alignment: .leading)
            Color.clear.frame(width: notchWidth - 20)
            Group {
                if let level = event.level {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.2))
                            Capsule().fill(.white).frame(width: geo.size.width * min(max(level, 0), 1))
                        }
                    }
                    .frame(width: 52, height: 5)
                    .animation(.spring(response: 0.25, dampingFraction: 0.9), value: level)
                } else {
                    Text(event.title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .frame(maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(event.title)
    }
}
