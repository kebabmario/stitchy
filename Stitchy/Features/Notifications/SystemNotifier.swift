// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Observation
import UserNotifications

/// Thin wrapper over UserNotifications for Stitchy's own alerts (timer done).
/// Authorization is requested lazily, the first time a timer starts.
/// Stitchy cannot and does not read other apps' notifications.
@MainActor @Observable
final class SystemNotifier: NSObject, UNUserNotificationCenterDelegate {
    private(set) var status: UNAuthorizationStatus = .notDetermined

    /// nil when running outside an app bundle (e.g. `swift run`), where
    /// UNUserNotificationCenter would crash.
    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : .current()
    }

    func configure() {
        center?.delegate = self
        refreshStatus()
    }

    func refreshStatus() {
        center?.getNotificationSettings { settings in
            let status = settings.authorizationStatus
            Task { @MainActor [weak self] in self?.status = status }
        }
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        guard let center else { return false }
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        refreshStatus()
        return granted
    }

    func schedule(id: String, title: String, body: String, after interval: TimeInterval) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, interval), repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    func cancel(id: String) {
        center?.removePendingNotificationRequests(withIdentifiers: [id])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}
