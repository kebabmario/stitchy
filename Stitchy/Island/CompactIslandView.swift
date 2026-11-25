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
        case .weather:
            Image(systemName: activity.symbol).symbolRenderingMode(.multicolor).font(.system(size: size * 0.7))
        case .agent(_, let agent, _):
            // The agent's own app icon from this Mac (nothing bundled); a symbol if it isn't installed.
            if let icon = AppIcons.icon(agent.appName) {
                Image(nsImage: icon).resizable().aspectRatio(contentMode: .fit).frame(width: size + 2, height: size + 2)
            } else {
                Image(systemName: activity.symbol).font(.system(size: size * 0.65, weight: .semibold)).foregroundStyle(activity.tint)
            }
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
    @Environment(WeatherService.self) private var weather
    @Environment(NotificationMirror.self) private var mirror
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
            case .keepAwake:
                Image(systemName: "infinity")
            case .agent(let status, _, let started):
                if compact {
                    // A pulsing dot and how long the agent has been working.
                    HStack(spacing: 5) {
                        LoadingRing(color: .orange, animating: !settings.reduceMotion).frame(width: 11, height: 11)
                        TimelineView(.periodic(from: .timelineAnchor, by: 1)) { context in
                            Text(context.date.timeIntervalSince(started).clockStringFloor)
                        }
                    }
                } else {
                    Text(status).font(DS.caption).truncationMode(.middle)
                }
            case .micMuted:
                Text("Muted")
            case .focus:
                Text("Focus")
            case .call:
                TimelineView(.periodic(from: .timelineAnchor, by: 1)) { context in
                    Text(mirror.callStarted.map { context.date.timeIntervalSince($0).clockStringFloor } ?? "Call")
                }
            case .weather:
                Text(weather.current.map { "\(Int($0.temperature.rounded()))°" } ?? "")
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
        .font(DS.numerals(13))
        .foregroundStyle(activity.tint)
        .lineLimit(1)
    }
}

/// A small spinning arc for "working" states. Core Animation rotates it in
/// the render server; a SwiftUI repeatForever would redraw the island every frame.
struct LoadingRing: NSViewRepresentable {
    var color: NSColor
    var animating: Bool
    var lineWidth: CGFloat = 1.8

    final class RingView: NSView {
        let track = CAShapeLayer(), arc = CAShapeLayer()
        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            for l in [track, arc] { l.fillColor = nil; l.lineCap = .round; layer?.addSublayer(l) }
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
        override func layout() {
            super.layout()
            for l in [track, arc] {
                l.frame = bounds
                l.path = CGPath(ellipseIn: bounds.insetBy(dx: l.lineWidth / 2 + 0.5, dy: l.lineWidth / 2 + 0.5), transform: nil)
            }
            arc.strokeEnd = 0.28
        }
    }

    func makeNSView(context: Context) -> RingView { RingView() }

    func updateNSView(_ view: RingView, context: Context) {
        view.track.strokeColor = color.withAlphaComponent(0.25).cgColor
        view.arc.strokeColor = color.cgColor
        view.track.lineWidth = lineWidth
        view.arc.lineWidth = lineWidth
        let key = "spin"
        if animating, view.arc.animation(forKey: key) == nil {
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = 0
            spin.toValue = -2 * Double.pi   // clockwise in AppKit's flipped-y layer space
            spin.duration = 0.9
            spin.repeatCount = .infinity
            view.arc.add(spin, forKey: key)
        } else if !animating {
            view.arc.removeAnimation(forKey: key)
        }
    }
}

/// A second or third live activity in its own small island beside the main
/// one: a mini notch in Notch style, a circle in Island style.
struct IslandBubble: View {
    let activity: IslandActivity
    let geometry: IslandGeometry
    @Environment(IslandModel.self) private var model

    static let gap: CGFloat = 6
    /// A touch taller than the island and nearly as wide as tall, so it reads round, not oval.
    static func size(for g: IslandGeometry) -> CGSize {
        let h = g.notchHeight + 4
        return CGSize(width: g.style == .island ? h : h + 2, height: h)
    }

    var body: some View {
        let size = Self.size(for: geometry)
        ZStack {
            if geometry.style == .island {
                Circle().fill(.black)
            } else {
                NotchShape(shoulder: 5, bottomRadius: size.width * 0.48, topRadius: 0).fill(.black)
            }
            ActivityGlyph(activity: activity, size: size.height * 0.5)
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .onTapGesture { model.expand(.click, tab: activity.tab) }
        .help(activity.title)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(activity.title)
        .accessibilityAddTraits(.isButton)
    }
}

/// Transient alert, e.g. "Charging 54%" or a new track.
struct AlertIslandView: View {
    let event: ActivityEvent
    @State private var appeared = false
    @Environment(AppSettings.self) private var settings

    /// "54%" becomes a ring; anything else stays text.
    private var percent: Double? {
        guard let t = event.trailing, t.hasSuffix("%"), let v = Double(t.dropLast()) else { return nil }
        return min(max(v / 100, 0), 1)
    }

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let artwork = event.artwork {
                    ArtworkView(image: artwork, size: 32, radius: 8)
                } else {
                    Image(systemName: event.symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(event.tint)
                        .frame(width: 32, height: 32)
                        .background(event.tint.opacity(0.16), in: Circle())
                        .symbolEffect(.bounce, value: appeared)
                }
            }
            .scaleEffect(appeared || settings.reduceMotion ? 1 : 0.6)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title).font(DS.title).foregroundStyle(.white)
                if let detail = event.detail, !detail.isEmpty {
                    Text(detail).font(DS.caption).foregroundStyle(.white.opacity(0.6))
                }
            }
            .lineLimit(1)
            Spacer(minLength: 4)
            if let trailing = event.trailing {
                if let percent {
                    ZStack {
                        ProgressRing(fraction: percent, color: event.tint, lineWidth: 3)
                        Text(trailing.dropLast()).font(DS.numerals(10)).foregroundStyle(.white)
                    }
                    .frame(width: 30, height: 30)
                } else {
                    Text(trailing).font(DS.numerals(15)).foregroundStyle(event.tint)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .frame(maxHeight: .infinity)
        .onAppear { withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { appeared = true } }
    }
}

/// Volume / mute / output indicator. Symbol left of the notch, level right.
struct HUDIslandView: View {
    let event: HUDEvent
    let notchWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if let auth = event.auth {
                    TouchIDGlyph(phase: auth, size: 14)
                } else {
                    Image(systemName: event.symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(event.tint)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
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

/// Under the island while a coding agent works: project and current step,
/// sliding in as the step changes. Tool and file name only.
struct AgentStripLine: View {
    @Environment(AgentActivityMonitor.self) private var agents

    var body: some View {
        let session = agents.live
        HStack(spacing: 5) {
            if let project = session?.project, !project.isEmpty {
                Text(project).font(.system(size: 10.5, weight: .bold)).foregroundStyle(.orange)
                Text("·").foregroundStyle(Color.tertiaryText)
            }
            Text(session?.status ?? "Working")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .truncationMode(.middle)
                .id(session?.status)
                .transition(.push(from: .bottom).combined(with: .opacity))
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: session?.status)
    }
}
