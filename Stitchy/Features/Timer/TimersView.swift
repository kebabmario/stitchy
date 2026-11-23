import SwiftUI

/// Timers page: multiple countdowns, a stopwatch and Pomodoro focus.
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

private struct CountdownsView: View {
    @Environment(TimerStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @State private var minutes = 5
    private let presets = [1, 5, 10, 25, 45]

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    IconButton(symbol: "minus", size: 10, diameter: 24, help: "One minute less") { minutes = max(1, minutes - 1) }
                    Text(TimerService.describe(TimeInterval(minutes * 60)))
                        .font(.system(size: 17, weight: .semibold).monospacedDigit())
                        .frame(minWidth: 70)
                        .contentTransition(.numericText())
                    IconButton(symbol: "plus", size: 10, diameter: 24, help: "One minute more") { minutes = min(720, minutes + 1) }
                }
                HStack(spacing: 5) {
                    ForEach(presets, id: \.self) { m in
                        Button { withAnimation(.snappy) { minutes = m } } label: {
                            Text("\(m)m")
                                .font(.system(size: 10.5, weight: .semibold))
                                .frame(width: 32, height: 20)
                                .foregroundStyle(minutes == m ? .black : .white.opacity(0.8))
                                .background(Capsule().fill(minutes == m ? Color.orange : .white.opacity(0.09)))
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                PillButton(title: "Start Timer", symbol: "play.fill", tint: .orange, prominent: true) {
                    withAnimation(.snappy) { _ = store.addCountdown(seconds: TimeInterval(minutes * 60)) }
                }
            }
            .frame(width: 186, alignment: .leading)

            IslandScroll(axis: .vertical) {
                VStack(spacing: 8) {
                    if store.countdowns.isEmpty {
                        Text("Timers you start appear here. Several can run at once.")
                            .font(.system(size: 11)).foregroundStyle(Color.tertiaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(store.countdowns, id: \.id) { CountdownRow(timer: $0) }
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
            HStack(spacing: 9) {
                ProgressRing(fraction: timer.phase == .idle ? 1 : timer.fraction(at: context.date), color: .orange, lineWidth: 3)
                    .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 0) {
                    Text(timer.phase == .finished ? "Done" : timer.remaining(at: context.date).clockString)
                        .font(.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(timer.phase == .finished ? .orange : .white)
                    Text(timer.label).font(.system(size: 10)).foregroundStyle(Color.secondaryText)
                }
                Spacer(minLength: 4)
                switch timer.phase {
                case .running: IconButton(symbol: "pause.fill", size: 9, diameter: 24, tint: .orange, help: "Pause") { timer.pause() }
                case .paused: IconButton(symbol: "play.fill", size: 9, diameter: 24, tint: .orange, help: "Resume") { timer.resume() }
                case .finished, .idle: IconButton(symbol: "arrow.clockwise", size: 9, diameter: 24, tint: .orange, help: "Restart") { timer.start() }
                }
                IconButton(symbol: "arrow.counterclockwise", size: 9, diameter: 24, help: "Reset") { timer.reset() }
                IconButton(symbol: "xmark", size: 9, diameter: 24, help: "Remove") { withAnimation(.snappy) { store.remove(timer) } }
            }
        }
    }
}

private struct StopwatchView: View {
    @Environment(TimerStore.self) private var store

    var body: some View {
        let sw = store.stopwatch
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                TimelineView(.periodic(from: .timelineAnchor, by: sw.isRunning ? 0.1 : 3600)) { context in
                    Text(Self.format(sw.elapsed(at: context.date)))
                        .font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
                }
                HStack(spacing: 8) {
                    if sw.isRunning {
                        PillButton(title: "Pause", symbol: "pause.fill", tint: .yellow, prominent: true) { sw.pause() }
                        PillButton(title: "Lap", symbol: "flag.fill") { sw.lap() }
                    } else {
                        PillButton(title: sw.isActive ? "Resume" : "Start", symbol: "play.fill", tint: .yellow, prominent: true) { sw.start() }
                        PillButton(title: "Reset", symbol: "arrow.counterclockwise") { withAnimation(.snappy) { sw.reset() } }
                            .disabled(!sw.isActive)
                    }
                }
            }
            .frame(width: 200, alignment: .leading)
            IslandScroll(axis: .vertical) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(sw.laps.enumerated()), id: \.offset) { index, lap in
                        HStack {
                            Text("Lap \(sw.laps.count - index)").foregroundStyle(Color.secondaryText)
                            Spacer()
                            Text(Self.format(lap)).monospacedDigit()
                        }
                        .font(.system(size: 11, weight: .medium))
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
        HStack(spacing: 20) {
            TimelineView(.periodic(from: .timelineAnchor, by: timer.isRunning ? 1 : 3600)) { context in
                ZStack {
                    ProgressRing(fraction: timer.phase == .idle ? 1 : timer.fraction(at: context.date), color: p.phase.tint, lineWidth: 6)
                    VStack(spacing: 0) {
                        Text(timer.phase == .finished ? "Done" : timer.remaining(at: context.date).clockString)
                            .font(.system(size: 21, weight: .semibold, design: .rounded).monospacedDigit())
                        Text(p.phase.title).font(.system(size: 10, weight: .medium)).foregroundStyle(Color.secondaryText)
                    }
                }
                .frame(width: 104, height: 104)
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 5) {
                    ForEach(0..<p.sessionsPerCycle, id: \.self) { i in
                        Circle().fill(i < p.cycleCount ? Color.red : .white.opacity(0.15)).frame(width: 7, height: 7)
                    }
                    Text("\(p.todayFocusCount) today").font(.system(size: 11, weight: .medium)).foregroundStyle(Color.secondaryText)
                        .padding(.leading, 4)
                }
                HStack(spacing: 8) {
                    switch timer.phase {
                    case .running:
                        PillButton(title: "Pause", symbol: "pause.fill", tint: p.phase.tint, prominent: true) { timer.pause() }
                    case .paused:
                        PillButton(title: "Resume", symbol: "play.fill", tint: p.phase.tint, prominent: true) { timer.resume() }
                    case .idle, .finished:
                        PillButton(title: p.phase == .focus ? "Start Focus" : "Start Break", symbol: "play.fill", tint: p.phase.tint, prominent: true) { p.start() }
                    }
                    PillButton(title: "Skip", symbol: "forward.end.fill") { p.skip() }
                }
                Button("Reset cycle") { p.reset() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Color.tertiaryText)
            }
            Spacer(minLength: 0)
        }
    }
}
