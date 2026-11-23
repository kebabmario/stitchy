import Foundation
import Observation
import SwiftUI

/// Countdown timer. State is stored as an end date (running) or a remaining
/// interval (paused), so no ticking is needed; views refresh once a second
/// only while they are on screen. A single sleeping task fires completion,
/// and a system notification is scheduled as a backup.
@MainActor @Observable
final class TimerService {
    enum Phase: Equatable, Sendable {
        case idle
        case running(end: Date)
        case paused(remaining: TimeInterval)
        case finished
    }

    private(set) var phase: Phase = .idle
    /// Length of the countdown that is running or about to start.
    private(set) var total: TimeInterval

    @ObservationIgnored var onEvent: ((ActivityEvent) -> Void)?
    @ObservationIgnored private let settings: AppSettings?
    @ObservationIgnored private let notifier: SystemNotifier?
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var completion: Task<Void, Never>?
    /// Holds off App Nap only while a countdown runs, so it ends on time.
    @ObservationIgnored private var activity: NSObjectProtocol?
    private static let notificationID = "stitchy.timer"

    init(settings: AppSettings?, notifier: SystemNotifier?, now: @escaping () -> Date = Date.init) {
        self.settings = settings
        self.notifier = notifier
        self.now = now
        total = settings?.timerDuration ?? 300
    }

    var isActive: Bool { phase != .idle }

    var isPaused: Bool {
        if case .paused = phase { return true }
        return false
    }

    var isRunning: Bool {
        if case .running = phase { return true }
        return false
    }

    func remaining(at date: Date? = nil) -> TimeInterval {
        switch phase {
        case .idle: return total
        case .running(let end): return max(0, end.timeIntervalSince(date ?? now()))
        case .paused(let remaining): return remaining
        case .finished: return 0
        }
    }

    /// 1 = full, 0 = done.
    func fraction(at date: Date? = nil) -> Double {
        total > 0 ? remaining(at: date) / total : 0
    }

    func setDuration(_ seconds: TimeInterval) {
        guard phase == .idle || phase == .finished else { return }
        total = min(max(seconds, 60), 12 * 3600)
        settings?.timerDuration = total
        phase = .idle
    }

    func start() {
        guard phase == .idle || phase == .finished else { return }
        run(for: total)
    }

    func pause() {
        guard case .running = phase else { return }
        phase = .paused(remaining: remaining())
        cancelCompletion()
    }

    func resume() {
        guard case .paused(let remaining) = phase else { return }
        run(for: remaining)
    }

    func reset() {
        phase = .idle
        cancelCompletion()
    }

    private func run(for seconds: TimeInterval) {
        islandLog.info("timer run \(seconds, privacy: .public)s")
        phase = .running(end: now().addingTimeInterval(seconds))
        completion?.cancel()
        if activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: "Timer running")
        }
        completion = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds), tolerance: .milliseconds(50), clock: .continuous)
            guard !Task.isCancelled else { return }
            self?.finish()
        }
        if let notifier {
            Task {
                if notifier.status == .notDetermined { await notifier.requestAuthorization() }
                // Re-check: the timer may have been paused while the prompt was up.
                guard case .running = self.phase else { return }
                notifier.schedule(
                    id: Self.notificationID, title: "Timer Done",
                    body: "Your \(Self.describe(total)) timer has finished.", after: remaining()
                )
            }
        }
    }

    /// Exposed for tests; normally called by the completion task.
    func finish() {
        guard case .running = phase else { return }
        phase = .finished
        completion = nil
        endActivity()
        islandLog.info("timer finished")
        onEvent?(ActivityEvent(
            symbol: "timer", tint: .orange, title: "Timer Done",
            detail: "\(Self.describe(total)) timer finished", trailing: "0:00",
            tab: .timer, alertDuration: 8
        ))
    }

    private func endActivity() {
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
    }

    private func cancelCompletion() {
        completion?.cancel()
        completion = nil
        endActivity()
        notifier?.cancel(id: Self.notificationID)
    }

    static func describe(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes >= 60 {
            let h = minutes / 60, m = minutes % 60
            return m == 0 ? "\(h) hr" : "\(h) hr \(m) min"
        }
        return "\(minutes) min"
    }
}
