import CoreGraphics
import Foundation

/// Gentle break reminders after a stretch of active use. Counts only time
/// you're actually at the Mac (idle time from CoreGraphics resets the count)
/// and stays quiet while the camera or microphone is in use (calls).
@MainActor
final class BreakReminder {
    struct Suggestion: Equatable { let symbol: String; let title: String; let detail: String }

    static let suggestions = [
        Suggestion(symbol: "eye", title: "Rest your eyes", detail: "Look at something 6 m away for 20 seconds"),
        Suggestion(symbol: "figure.walk", title: "Time to move", detail: "Stand up and stretch for a minute"),
        Suggestion(symbol: "drop.fill", title: "Drink some water", detail: "A short break helps you focus"),
        Suggestion(symbol: "wind", title: "Breathe", detail: "In for 4, hold for 4, out for 4. Three times"),
    ]

    var onReminder: ((Suggestion) -> Void)?
    var isQuiet: () -> Bool = { false }
    var interval: TimeInterval = 50 * 60
    private var task: Task<Void, Never>?
    private var active: TimeInterval = 0
    private var next = 0

    func start() {
        guard task == nil else { return }
        active = 0
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                self?.tick(idle: Self.idleSeconds())
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    /// Seconds since the last keyboard, mouse or trackpad input.
    nonisolated static func idleSeconds() -> TimeInterval {
        [CGEventType.keyDown, .mouseMoved, .leftMouseDown, .scrollWheel, .flagsChanged]
            .map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }.min() ?? 0
    }

    /// One minute passed. A real break (5+ minutes idle) starts the count over.
    func tick(idle: TimeInterval) {
        if idle >= 5 * 60 { active = 0; return }
        if idle < 60 { active += 60 }
        guard active >= interval, !isQuiet() else { return }
        active = 0
        onReminder?(Self.suggestions[next % Self.suggestions.count])
        next += 1
    }
}
