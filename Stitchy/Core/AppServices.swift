import AppKit
import SwiftUI

/// Owns every long-lived service and wires their events together.
/// Services only start when their feature is enabled, so disabled features
/// cost nothing at runtime.
@MainActor
final class AppServices {
    let settings = AppSettings()
    let island: IslandModel
    let feed = ActivityFeed()
    let battery = BatteryMonitor()
    let network = NetworkMonitor()
    let nowPlaying: NowPlayingService
    let timer: TimerService
    let shelf = FileShelf()
    let downloads = DownloadsMonitor()
    let notifier = SystemNotifier()

    init() {
        island = IslandModel(settings: settings)
        nowPlaying = NowPlayingService(settings: settings)
        timer = TimerService(settings: settings, notifier: notifier)
        wire()
    }

    func start() {
        notifier.configure()
        network.start()
        observeContinuously { [weak self] in self?.applyFeatureToggles() }
    }

    /// Starts or stops services to match the feature toggles in Settings.
    private func applyFeatureToggles() {
        settings.batteryEnabled ? battery.start() : battery.stop()
        settings.musicEnabled ? nowPlaying.start() : nowPlaying.stop()
        settings.downloadsEnabled ? downloads.start() : downloads.stop()
        if !settings.timerEnabled { timer.reset() }
    }

    func post(_ event: ActivityEvent) {
        guard settings.alertsEnabled else { return }
        if event.recordsInFeed { feed.add(event) }
        if event.showsAlert { island.present(event) }
    }

    private func wire() {
        battery.onEvent = { [weak self] in self?.post($0) }
        downloads.onEvent = { [weak self] in self?.post($0) }
        timer.onEvent = { [weak self] in self?.post($0) }
        nowPlaying.onTrackChange = { [weak self] track, artwork in
            guard let self, self.settings.compactActivities else { return }
            self.post(ActivityEvent(
                symbol: "music.note", tint: .pink, title: track.title, detail: track.artist,
                artwork: artwork, tab: .music, recordsInFeed: false
            ))
        }
        shelf.onAdd = { [weak self] count in
            self?.post(ActivityEvent(
                symbol: "tray.and.arrow.down.fill", tint: .blue,
                title: count == 1 ? "Added 1 file to Shelf" : "Added \(count) files to Shelf",
                tab: .shelf, showsAlert: false
            ))
        }
    }
}
