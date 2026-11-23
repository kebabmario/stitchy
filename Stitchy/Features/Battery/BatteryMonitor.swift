import Foundation
import IOKit.ps
import Observation
import SwiftUI

struct BatterySnapshot: Equatable, Sendable {
    var hasBattery = false
    var percent = 0
    var isCharging = false
    var isPluggedIn = false
    var isCharged = false
    var minutesToEmpty: Int?
    var minutesToFull: Int?
    var adapterWatts: Int?

    var statusText: String {
        guard hasBattery else { return isPluggedIn ? "Power Adapter" : "No Battery" }
        if isCharged || (isPluggedIn && percent >= 100) { return "Fully Charged" }
        if isCharging { return "Charging" }
        if isPluggedIn { return "Not Charging" }
        return "On Battery"
    }

    var timeText: String? {
        func format(_ m: Int) -> String { m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m" }
        if isCharging, let m = minutesToFull { return "\(format(m)) until full" }
        if !isPluggedIn, let m = minutesToEmpty { return "\(format(m)) remaining" }
        return nil
    }

    var symbol: String {
        if isCharging || (isPluggedIn && hasBattery) { return "battery.100percent.bolt" }
        switch percent {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    var tint: Color {
        if isCharging || isPluggedIn { return .green }
        if percent <= 10 { return .red }
        if percent <= 20 { return .orange }
        return .white
    }

    /// Reads the current state from IOKit power-source APIs (no permission needed).
    static func read() -> BatterySnapshot {
        var snapshot = BatterySnapshot()
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return snapshot }
        let sourceType = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?
        snapshot.isPluggedIn = sourceType == kIOPMACPowerKey
        let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] ?? []
        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  desc[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            snapshot.hasBattery = true
            let current = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = desc[kIOPSMaxCapacityKey] as? Int ?? 100
            snapshot.percent = max > 0 ? Int((Double(current) / Double(max) * 100).rounded()) : current
            snapshot.isCharging = desc[kIOPSIsChargingKey] as? Bool ?? false
            snapshot.isCharged = desc[kIOPSIsChargedKey] as? Bool ?? false
            if let m = desc[kIOPSTimeToEmptyKey] as? Int, m > 0 { snapshot.minutesToEmpty = m }
            if let m = desc[kIOPSTimeToFullChargeKey] as? Int, m > 0 { snapshot.minutesToFull = m }
        }
        if snapshot.isPluggedIn,
           let adapter = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any] {
            snapshot.adapterWatts = adapter[kIOPSPowerAdapterWattsKey] as? Int
        }
        return snapshot
    }
}

/// Battery and power state, updated by IOKit's power-source notification
/// (event-driven, no polling).
@MainActor @Observable
final class BatteryMonitor: NSObject {
    private(set) var snapshot = BatterySnapshot()
    private(set) var isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
    @ObservationIgnored var onEvent: ((ActivityEvent) -> Void)?
    @ObservationIgnored private var source: CFRunLoopSource?

    func start() {
        guard source == nil else { return }
        snapshot = BatterySnapshot.read()
        if let src = IOPSNotificationCreateRunLoopSource(powerSourceCallback, nil)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
            source = src
        }
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(refresh), name: Self.powerChanged, object: nil)
        center.addObserver(self, selector: #selector(powerStateChanged), name: .NSProcessInfoPowerStateDidChange, object: nil)
    }

    func stop() {
        guard let source else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        self.source = nil
        NotificationCenter.default.removeObserver(self)
    }

    nonisolated static let powerChanged = Notification.Name("StitchyPowerSourceChanged")

    @objc private func refresh() {
        let old = snapshot
        let new = BatterySnapshot.read()
        guard new != old else { return }
        snapshot = new
        emitEvents(old: old, new: new)
    }

    @objc nonisolated private func powerStateChanged() {
        Task { @MainActor in self.isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled }
    }

    private func emitEvents(old: BatterySnapshot, new: BatterySnapshot) {
        guard new.hasBattery else { return }
        if new.isPluggedIn != old.isPluggedIn {
            onEvent?(ActivityEvent(
                symbol: new.isPluggedIn ? "bolt.fill" : "battery.75percent",
                tint: new.isPluggedIn ? .green : .white,
                title: new.isPluggedIn ? "Charging" : "On Battery",
                detail: new.isPluggedIn ? new.adapterWatts.map { "\($0)W power adapter" } : new.timeText,
                trailing: "\(new.percent)%", tab: .home
            ))
        } else if !new.isPluggedIn, let threshold = [20, 10].first(where: { new.percent <= $0 && old.percent > $0 }) {
            onEvent?(ActivityEvent(
                symbol: "battery.25percent", tint: threshold == 10 ? .red : .orange,
                title: "Low Battery", detail: new.timeText, trailing: "\(new.percent)%", tab: .home,
                alertDuration: 4
            ))
        } else if new.isCharged, !old.isCharged {
            onEvent?(ActivityEvent(
                symbol: "battery.100percent.bolt", tint: .green, title: "Fully Charged",
                trailing: "\(new.percent)%", tab: .home, showsAlert: false
            ))
        }
    }
}

/// IOKit C callback: forward to the main run loop via NotificationCenter
/// (the callback already runs on the main run loop we registered on).
private func powerSourceCallback(_ context: UnsafeMutableRawPointer?) {
    NotificationCenter.default.post(name: BatteryMonitor.powerChanged, object: nil)
}
