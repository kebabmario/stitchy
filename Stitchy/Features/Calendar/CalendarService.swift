import EventKit
import Observation
import SwiftUI

/// Today's schedule and meeting reminders via EventKit.
/// Access is requested only when the user taps "Connect Calendar".
@MainActor @Observable
final class CalendarService: NSObject {
    struct Event: Identifiable, Equatable {
        let id: String
        let title: String
        let start: Date
        let end: Date
        let isAllDay: Bool
        let color: Color
        let location: String?
    }

    enum Access { case unknown, granted, denied }

    private(set) var events: [Event] = []
    private(set) var access: Access = .unknown
    @ObservationIgnored var onEvent: ((ActivityEvent) -> Void)?
    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private var reminderTask: Task<Void, Never>?
    @ObservationIgnored private var remindedIDs: Set<String> = []
    @ObservationIgnored private var observing = false

    init(settings: AppSettings) {
        self.settings = settings
        super.init()
        access = Self.currentAccess
    }

    static var currentAccess: Access {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .granted
        case .denied, .restricted, .writeOnly: .denied
        default: .unknown
        }
    }

    func requestAccess() async {
        let granted = (try? await store.requestFullAccessToEvents()) ?? false
        access = granted ? .granted : .denied
        if granted {
            settings.calendarEnabled = true
            start()
        }
    }

    func start() {
        access = Self.currentAccess
        guard access == .granted else { return }
        if !observing {
            observing = true
            NotificationCenter.default.addObserver(self, selector: #selector(storeChanged), name: .EKEventStoreChanged, object: store)
        }
        refresh()
    }

    func stop() {
        NotificationCenter.default.removeObserver(self)
        observing = false
        reminderTask?.cancel()
        events.removeAll()
    }

    @objc private func storeChanged() { refresh() }

    /// Events from now until the end of tomorrow.
    func refresh() {
        guard access == .granted else { return }
        let now = Date()
        let end = Calendar.current.date(byAdding: .day, value: 2, to: Calendar.current.startOfDay(for: now)) ?? now
        let predicate = store.predicateForEvents(withStart: Calendar.current.startOfDay(for: now), end: end, calendars: nil)
        events = store.events(matching: predicate)
            .filter { $0.endDate > now }
            .sorted { $0.startDate < $1.startDate }
            .prefix(20)
            .map { e in
                Event(id: e.eventIdentifier ?? UUID().uuidString, title: e.title ?? "Untitled",
                      start: e.startDate, end: e.endDate, isAllDay: e.isAllDay,
                      color: Color(cgColor: e.calendar.cgColor), location: e.location)
            }
        scheduleReminder()
    }

    var today: [Event] { events.filter { Calendar.current.isDateInToday($0.start) || $0.start < Date() } }
    var nextTimed: Event? { events.first { !$0.isAllDay && $0.end > Date() } }

    /// One sleeping task until the next reminder time; no polling.
    private func scheduleReminder() {
        reminderTask?.cancel()
        let lead = settings.meetingReminderMinutes * 60
        guard let next = events.first(where: { !$0.isAllDay && $0.start > Date() && !remindedIDs.contains($0.id) }) else { return }
        let fireIn = max(0, next.start.timeIntervalSinceNow - lead)
        reminderTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(fireIn), tolerance: .seconds(1))
            guard !Task.isCancelled, let self else { return }
            self.remindedIDs.insert(next.id)
            let minutes = max(0, Int(next.start.timeIntervalSinceNow / 60))
            self.onEvent?(ActivityEvent(
                symbol: "calendar", tint: .red, title: next.title,
                detail: minutes == 0 ? "Starting now" : "Starts in \(minutes) min",
                trailing: next.start.formatted(date: .omitted, time: .shortened),
                tab: .calendar, alertDuration: 8
            ))
            self.scheduleReminder()
        }
    }
}
