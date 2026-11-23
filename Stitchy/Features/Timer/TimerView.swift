import SwiftUI

struct TimerView: View {
    @Environment(TimerService.self) private var timer
    private let presets: [Int] = [1, 5, 10, 25, 45]

    var body: some View {
        HStack(spacing: 22) {
            TimelineView(.periodic(from: .now, by: timer.isRunning ? 1 : 3600)) { context in
                ZStack {
                    ProgressRing(fraction: timer.phase == .idle ? 1 : timer.fraction(at: context.date), color: .orange, lineWidth: 7)
                        .animation(.linear(duration: 1), value: timer.fraction(at: context.date))
                    VStack(spacing: 0) {
                        Text(timer.phase == .finished ? "Done" : timer.remaining(at: context.date).clockString)
                            .font(.system(size: 24, weight: .semibold, design: .rounded).monospacedDigit())
                            .contentTransition(.numericText(countsDown: true))
                        Text(TimerService.describe(timer.total))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.secondaryText)
                    }
                }
                .frame(width: 112, height: 112)
            }

            VStack(alignment: .leading, spacing: 12) {
                if timer.phase == .idle {
                    durationPicker
                } else {
                    status
                }
                controls
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, 4)
    }

    private var durationPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                IconButton(symbol: "minus", size: 11, diameter: 26, help: "One minute less") {
                    timer.setDuration(timer.total - 60)
                }
                .disabled(timer.total <= 60)
                Text(TimerService.describe(timer.total))
                    .font(.system(size: 17, weight: .semibold).monospacedDigit())
                    .frame(minWidth: 78)
                    .contentTransition(.numericText())
                IconButton(symbol: "plus", size: 11, diameter: 26, help: "One minute more") {
                    timer.setDuration(timer.total + 60)
                }
            }
            HStack(spacing: 6) {
                ForEach(presets, id: \.self) { minutes in
                    let selected = Int(timer.total) == minutes * 60
                    Button { withAnimation(.snappy) { timer.setDuration(TimeInterval(minutes * 60)) } } label: {
                        Text("\(minutes)m")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 36, height: 22)
                            .foregroundStyle(selected ? .black : .white.opacity(0.8))
                            .background(Capsule().fill(selected ? Color.orange : .white.opacity(0.09)))
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
    }

    private var status: some View {
        VStack(alignment: .leading, spacing: 2) {
            switch timer.phase {
            case .running(let end):
                Text("Running").font(.system(size: 15, weight: .semibold))
                Text("Ends at \(end.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 12)).foregroundStyle(Color.secondaryText)
            case .paused:
                Text("Paused").font(.system(size: 15, weight: .semibold))
                Text("\(timer.remaining().clockString) left").font(.system(size: 12)).foregroundStyle(Color.secondaryText)
            case .finished:
                Text("Time's up").font(.system(size: 15, weight: .semibold)).foregroundStyle(.orange)
                Text("\(TimerService.describe(timer.total)) timer finished").font(.system(size: 12)).foregroundStyle(Color.secondaryText)
            case .idle:
                EmptyView()
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            switch timer.phase {
            case .idle:
                PillButton(title: "Start", symbol: "play.fill", tint: .orange, prominent: true) { timer.start() }
            case .running:
                PillButton(title: "Pause", symbol: "pause.fill", tint: .orange, prominent: true) { timer.pause() }
                PillButton(title: "Reset", symbol: "arrow.counterclockwise") { timer.reset() }
            case .paused:
                PillButton(title: "Resume", symbol: "play.fill", tint: .orange, prominent: true) { timer.resume() }
                PillButton(title: "Reset", symbol: "arrow.counterclockwise") { timer.reset() }
            case .finished:
                PillButton(title: "Restart", symbol: "arrow.clockwise", tint: .orange, prominent: true) { timer.start() }
                PillButton(title: "Dismiss", symbol: "xmark") { timer.reset() }
            }
        }
    }
}
