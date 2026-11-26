// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import Observation

/// External drives via NSWorkspace mount notifications; one-tap eject.
@MainActor @Observable
final class DrivesMonitor: NSObject {
    struct Drive: Identifiable, Equatable {
        let id: URL
        let name: String
    }

    private(set) var drives: [Drive] = []
    private(set) var ejecting: Set<URL> = []
    @ObservationIgnored var onEvent: ((ActivityEvent) -> Void)?
    @ObservationIgnored private var started = false

    func start() {
        guard !started else { return }
        started = true
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self, selector: #selector(mounted(_:)), name: NSWorkspace.didMountNotification, object: nil)
        nc.addObserver(self, selector: #selector(unmounted(_:)), name: NSWorkspace.didUnmountNotification, object: nil)
        drives = Self.removableVolumes()
    }

    func stop() {
        guard started else { return }
        started = false
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        drives.removeAll()
    }

    static func removableVolumes() -> [Drive] {
        let keys: [URLResourceKey] = [.volumeIsRemovableKey, .volumeIsEjectableKey, .volumeLocalizedNameKey, .volumeIsInternalKey]
        return (FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? [])
            .compactMap { url in
                guard let v = try? url.resourceValues(forKeys: Set(keys)),
                      v.volumeIsEjectable == true || (v.volumeIsRemovable == true && v.volumeIsInternal != true) else { return nil }
                return Drive(id: url, name: v.volumeLocalizedName ?? url.lastPathComponent)
            }
    }

    @objc private func mounted(_ note: Notification) {
        let before = Set(drives.map(\.id))
        drives = Self.removableVolumes()
        for d in drives where !before.contains(d.id) {
            onEvent?(ActivityEvent(symbol: "externaldrive.fill", tint: .blue, title: d.name, detail: "Drive connected", tab: .home))
        }
    }

    @objc private func unmounted(_ note: Notification) {
        let before = drives
        drives = Self.removableVolumes()
        for d in before where !drives.contains(d) {
            let wasOurs = ejecting.remove(d.id) != nil
            onEvent?(ActivityEvent(symbol: "checkmark.circle.fill", tint: .green, title: d.name,
                                   detail: wasOurs ? "Safe to disconnect" : "Drive removed", tab: .home))
        }
    }

    func eject(_ drive: Drive) {
        ejecting.insert(drive.id)
        do {
            try NSWorkspace.shared.unmountAndEjectDevice(at: drive.id)
        } catch {
            ejecting.remove(drive.id)
            onEvent?(ActivityEvent(symbol: "exclamationmark.triangle.fill", tint: .orange, title: "Couldn't eject \(drive.name)",
                                   detail: "A file on it may still be open.", tab: .home))
        }
    }
}
