import Observation
import SwiftUI

/// In-memory history of Stitchy's own events (timers, downloads, power, shelf).
@MainActor @Observable
final class ActivityFeed {
    private(set) var items: [ActivityEvent] = []
    private(set) var unread = 0
    private let limit = 30

    func add(_ event: ActivityEvent) {
        items.insert(event, at: 0)
        if items.count > limit { items.removeLast(items.count - limit) }
        unread += 1
    }

    func markRead() { unread = 0 }

    func clear() {
        items.removeAll()
        unread = 0
    }
}
