import Foundation
import Observation
import SwiftUI

/// Stopwatch stored as accumulated time + start date: no ticking.
@MainActor @Observable
final class Stopwatch {
    private(set) var startedAt: Date?
    private(set) var accumulated: TimeInterval = 0
    private(set) var laps: [TimeInterval] = []
    @ObservationIgnored private let now: () -> Date

    init(now: @escaping () -> Date = Date.init) { self.now = now }

    var isRunning: Bool { startedAt != nil }
    var isActive: Bool { isRunning || accumulated > 0 }

    func elapsed(at date: Date? = nil) -> TimeInterval {
        accumulated + (startedAt.map { (date ?? now()).timeIntervalSince($0) } ?? 0)
    }

    func start() { if startedAt == nil { startedAt = now() } }

    func pause() {
        guard let startedAt else { return }
        accumulated += now().timeIntervalSince(startedAt)
        self.startedAt = nil
    }

    func lap() { if isRunning { laps.insert(elapsed(), at: 0) } }

    func reset() {
        startedAt = nil
        accumulated = 0
        laps.removeAll()
    }
}

/// Pomodoro: focus sessions alternating with short and long breaks.
/// Each completed session is recorded in a small persisted history.
@MainActor @Observable
final class Pomodoro {
    enum Phase: String, Codable, Sendable {
        case focus, shortBreak, longBreak
        var title: String {
            switch self {
            case .focus: "Focus"
            case .shortBreak: "Short Break"
            case .longBreak: "Long Break"
            }
        }
        var tint: Color { self == .focus ? .red : .mint }
    }

    struct Session: Codable, Identifiable, Sendable {
        var id = UUID()
        var phase: Phase
        var minutes: Double
        var completedAt: Date
    }

    private(set) var phase: Phase = .focus
    /// Focus sessions completed in the current cycle.
    private(set) var cycleCount = 0
    private(set) var history: [Session]
    let timer: TimerService
    @ObservationIgnored private let settings: AppSettings?

    init(settings: AppSettings?, notifier: SystemNotifier?) {
        self.settings = settings
        timer = TimerService(settings: settings, notifier: notifier, label: "Focus",
                             duration: (settings?.focusMinutes ?? 25) * 60)
        history = settings?.data([Session].self, key: "pomodoroHistory") ?? []
        timer.completionTitle = "Focus Session Complete"
        timer.onFinish = { [weak self] in self?.advance() }
    }

    var todayFocusCount: Int {
        history.filter { $0.phase == .focus && Calendar.current.isDateInToday($0.completedAt) }.count
    }

    var sessionsPerCycle: Int { Int(settings?.sessionsPerLongBreak ?? 4) }

    func minutes(for phase: Phase) -> Double {
        switch phase {
        case .focus: settings?.focusMinutes ?? 25
        case .shortBreak: settings?.shortBreakMinutes ?? 5
        case .longBreak: settings?.longBreakMinutes ?? 15
        }
    }

    func start() {
        if timer.phase == .idle || timer.phase == .finished { configure(phase) }
        timer.start()
    }

    func skip() {
        timer.reset()
        move(to: nextPhase(afterCompleting: false))
    }

    func reset() {
        timer.reset()
        cycleCount = 0
        move(to: .focus)
    }

    func clearHistory() {
        history.removeAll()
        settings?.setData(history, key: "pomodoroHistory")
    }

    /// Exposed for tests; normally called when the timer finishes.
    func advance() {
        history.insert(Session(phase: phase, minutes: minutes(for: phase), completedAt: Date()), at: 0)
        if history.count > 200 { history.removeLast(history.count - 200) }
        settings?.setData(history, key: "pomodoroHistory")
        let next = nextPhase(afterCompleting: true)
        move(to: next)
    }

    private func nextPhase(afterCompleting: Bool) -> Phase {
        guard phase == .focus else { return .focus }
        if afterCompleting { cycleCount += 1 }
        if cycleCount >= sessionsPerCycle {
            cycleCount = 0
            return .longBreak
        }
        return .shortBreak
    }

    private func move(to newPhase: Phase) {
        phase = newPhase
        configure(newPhase)
    }

    private func configure(_ phase: Phase) {
        timer.label = phase.title
        timer.completionTitle = phase == .focus ? "Focus Session Complete" : "Break Over"
        if timer.phase == .finished { timer.reset() }
        timer.setDuration(minutes(for: phase) * 60)
    }
}

/// All timers: any number of countdowns, a stopwatch and Pomodoro.
@MainActor @Observable
final class TimerStore {
    private(set) var countdowns: [TimerService] = []
    let stopwatch = Stopwatch()
    let pomodoro: Pomodoro
    @ObservationIgnored var onEvent: ((ActivityEvent) -> Void)? {
        didSet {
            countdowns.forEach { $0.onEvent = onEvent }
            pomodoro.timer.onEvent = onEvent
        }
    }
    @ObservationIgnored private let settings: AppSettings?
    @ObservationIgnored private let notifier: SystemNotifier?

    init(settings: AppSettings?, notifier: SystemNotifier?) {
        self.settings = settings
        self.notifier = notifier
        pomodoro = Pomodoro(settings: settings, notifier: notifier)
    }

    /// Countdowns that are running, paused or finished, most urgent first.
    var activeCountdowns: [TimerService] {
        countdowns.filter(\.isActive).sorted { lhs, rhs in
            if lhs.phase == .finished { return true }
            if rhs.phase == .finished { return false }
            return lhs.remaining() < rhs.remaining()
        }
    }

    @discardableResult
    func addCountdown(seconds: TimeInterval, label: String? = nil, start: Bool = true) -> TimerService {
        let timer = TimerService(settings: settings, notifier: notifier,
                                 label: label ?? TimerService.describe(seconds), duration: seconds)
        timer.onEvent = onEvent
        countdowns.append(timer)
        settings?.timerDuration = seconds
        if start { timer.start() }
        return timer
    }

    func remove(_ timer: TimerService) {
        timer.reset()
        countdowns.removeAll { $0.id == timer.id }
    }

    func stopAll() {
        countdowns.forEach { $0.reset() }
        countdowns.removeAll()
        stopwatch.reset()
        pomodoro.reset()
    }
}
