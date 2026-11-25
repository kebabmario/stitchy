import SwiftUI

/// Timers page: a "New timer" well, running timers, stopwatch and Focus.
struct TimersView: View {
    enum Mode: Hashable { case timers, stopwatch, focus }
    @State private var mode: Mode = .timers

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Segmented(options: [(.timers, "Timers"), (.stopwatch, "Stopwatch"), (.focus, "Focus")], selection: $mode)
            Group {
                switch mode {
                case .timers: CountdownsView()
                case .stopwatch: StopwatchView()
                case .focus: FocusView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .transition(.blurReplace)
        }
    }
}

/// Fixed-width capsule action used on the Timers pages.
struct ActionCapsule: View {
    var title: String
    var tint: Color
    var prominent = false
    var action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 78, height: 28)
                .foregroundStyle(prominent ? .black : tint)
                .background(Capsule().fill(prominent ? tint : tint.opacity(0.12)))
                .opacity(isEnabled ? 1 : 0.4)
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(title)
    }
}

/// Apple Clock-style round button: tinted fill, coloured label, inner ring.
struct ClockButton: View {
    var title: String
    var tint: Color
    var size: CGFloat = 54
    var action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: size * 0.24, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(Circle().fill(tint.opacity(0.22)))
                .overlay(Circle().strokeBorder(.black, lineWidth: 2).padding(2.5))
                .overlay(Circle().strokeBorder(tint.opacity(0.22), lineWidth: 1).padding(4.5))
                .opacity(isEnabled ? 1 : 0.4)
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(title)
    }
}

/// Rounded, monospaced digits (Stitchy's numeral style).
private func clockDigits(_ text: String, size: CGFloat) -> some View {
    Text(text)
        .font(DS.numerals(size, weight: .medium))
        .contentTransition(.numericText(countsDown: true))
}

private struct CountdownsView: View {
    @Environment(TimerStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @State private var minutes = 5
    private let presets = [1, 3, 5, 10, 15, 25, 45, 60]

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.m) {
            VStack(spacing: DS.Space.s) {
                HStack(spacing: DS.Space.s) {
                    IconButton(symbol: "minus", size: 10, diameter: 24, help: "One minute less") { minutes = max(1, minutes - 1) }
                    clockDigits(TimeInterval(minutes * 60).clockString, size: 34)
                        .frame(maxWidth: .infinity)
                    IconButton(symbol: "plus", size: 10, diameter: 24, help: "One minute more") { minutes = min(720, minutes + 1) }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 4) {
                    ForEach(presets, id: \.self) { m in
                        Button { withAnimation(.snappy) { minutes = m } } label: {
                            Text(m < 60 ? "\(m)m" : "1h")
                                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                                .frame(maxWidth: .infinity).frame(height: 20)
                                .foregroundStyle(minutes == m ? .black : .white.opacity(0.85))
                                .background(Capsule().fill(minutes == m ? Color.orange : .white.opacity(0.08)))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                Button {
                    withAnimation(.snappy) { _ = store.addCountdown(seconds: TimeInterval(minutes * 60)) }
                } label: {
                    Label("Start", systemImage: "play.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity).frame(height: 28)
                        .foregroundStyle(.black)
                        .background(Capsule().fill(Color.orange))
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableStyle())
            }
            .frame(width: 180)
            .well(padding: 10)

            VStack(alignment: .leading, spacing: 0) {
                SectionLabel("Running").padding(.bottom, 4)
                if store.countdowns.isEmpty {
                    Text("Start as many timers as you like.")
                        .font(DS.caption).foregroundStyle(Color.tertiaryText)
                } else {
                    IslandScroll(axis: .vertical) {
                        VStack(spacing: 0) {
                            ForEach(store.countdowns, id: \.id) { timer in
                                CountdownRow(timer: timer)
                                if timer.id != store.countdowns.last?.id { Divider().overlay(.white.opacity(0.08)) }
                            }
                        }
                    }
                }
            }
        }
        .onAppear { minutes = max(1, Int(settings.timerDuration / 60)) }
    }
}

private struct CountdownRow: View {
    let timer: TimerService
    @Environment(TimerStore.self) private var store

    var body: some View {
        TimelineView(.periodic(from: .timelineAnchor, by: timer.isRunning ? 1 : 3600)) { context in
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 0) {
                    clockDigits(timer.phase == .finished ? "0:00" : timer.remaining(at: context.date).clockString, size: 22)
                        .foregroundStyle(timer.phase == .finished ? .orange : .white.opacity(timer.isPaused ? 0.5 : 1))
                    Text(timer.phase == .finished ? "\(timer.label) · Done" : timer.label)
                        .font(DS.caption).foregroundStyle(Color.secondaryText)
                }
                Spacer(minLength: 4)
                ZStack {
                    ProgressRing(fraction: timer.phase == .idle ? 1 : timer.fraction(at: context.date), color: .orange, lineWidth: 2.5)
                    Group {
                        switch timer.phase {
                        case .running: Button { timer.pause() } label: { Image(systemName: "pause.fill") }
                        case .paused: Button { timer.resume() } label: { Image(systemName: "play.fill") }
                        case .finished, .idle: Button { timer.start() } label: { Image(systemName: "arrow.clockwise") }
                        }
                    }
                    .buttonStyle(.plainHit)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.orange)
                }
                .frame(width: 34, height: 34)
                Button { withAnimation(.snappy) { store.remove(timer) } } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Color.secondaryText)
                        .frame(width: 26, height: 26).modifier(CircleBackground(filled: false, tint: .white, hovering: false))
                }
                .buttonStyle(PressableStyle())
                .help("Cancel timer")
            }
            .padding(.vertical, 6)
        }
    }
}

private struct StopwatchView: View {
    @Environment(TimerStore.self) private var store

    var body: some View {
        let sw = store.stopwatch
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: DS.Space.m) {
                TimelineView(.periodic(from: .timelineAnchor, by: sw.isRunning ? 0.05 : 3600)) { context in
                    clockDigits(Self.format(sw.elapsed(at: context.date)), size: 34)
                }
                HStack(spacing: DS.Space.s) {
                    if sw.isRunning {
                        ActionCapsule(title: "Lap", tint: .white) { sw.lap() }
                        ActionCapsule(title: "Stop", tint: .red, prominent: true) { sw.pause() }
                    } else {
                        ActionCapsule(title: "Reset", tint: .white) { withAnimation(.snappy) { sw.reset() } }
                            .disabled(!sw.isActive)
                        ActionCapsule(title: "Start", tint: .green, prominent: true) { sw.start() }
                    }
                }
            }
            .padding(.top, DS.Space.s)
            .frame(width: 200)
            .well(padding: 10)
            IslandScroll(axis: .vertical) {
                VStack(spacing: 0) {
                    ForEach(Array(sw.laps.enumerated()), id: \.offset) { index, lap in
                        HStack {
                            Text("Lap \(sw.laps.count - index)")
                            Spacer()
                            Text(Self.format(lap)).monospacedDigit()
                        }
                        .font(.system(size: 12))
                        .padding(.vertical, 5)
                        Divider().overlay(.white.opacity(0.08))
                    }
                    if sw.laps.isEmpty {
                        Text("Laps appear here.").font(DS.caption).foregroundStyle(Color.tertiaryText).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    static func format(_ t: TimeInterval) -> String {
        let cs = Int((t * 100).rounded(.down)) % 100
        return t.clockStringFloor + String(format: ".%02d", cs)
    }
}

private struct FocusView: View {
    @Environment(TimerStore.self) private var store

    var body: some View {
        let p = store.pomodoro
        let timer = p.timer
        HStack(spacing: 22) {
            TimelineView(.periodic(from: .timelineAnchor, by: timer.isRunning ? 1 : 3600)) { context in
                ZStack {
                    ProgressRing(fraction: timer.phase == .idle ? 1 : timer.fraction(at: context.date), color: p.phase.tint, lineWidth: 5)
                    VStack(spacing: 0) {
                        clockDigits(timer.phase == .finished ? "0:00" : timer.remaining(at: context.date).clockString, size: 26)
                        Text(p.phase.title).font(DS.caption).foregroundStyle(p.phase.tint)
                    }
                }
                .frame(width: 118, height: 118)
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 5) {
                    ForEach(0..<p.sessionsPerCycle, id: \.self) { i in
                        Circle().fill(i < p.cycleCount ? Color.red : .white.opacity(0.15)).frame(width: 7, height: 7)
                    }
                    Text("\(p.todayFocusCount) today").font(.system(size: 11, weight: .medium)).foregroundStyle(Color.secondaryText).padding(.leading, 4)
                }
                HStack(spacing: DS.Space.s) {
                    ActionCapsule(title: "Skip", tint: .white) { p.skip() }
                    switch timer.phase {
                    case .running: ActionCapsule(title: "Pause", tint: .orange, prominent: true) { timer.pause() }
                    case .paused: ActionCapsule(title: "Resume", tint: .green, prominent: true) { timer.resume() }
                    case .idle, .finished: ActionCapsule(title: "Start", tint: .green, prominent: true) { p.start() }
                    }
                }
                Button("Reset cycle") { p.reset() }
                    .buttonStyle(.plainHit).font(.system(size: 10.5, weight: .medium)).foregroundStyle(Color.tertiaryText)
            }
            Spacer(minLength: 0)
        }
    }
}
