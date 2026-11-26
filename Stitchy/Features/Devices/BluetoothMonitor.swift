// SPDX-License-Identifier: GPL-3.0-or-later
import IOBluetooth
import Observation
import SwiftUI

/// Bluetooth connections via IOBluetooth's public connect/disconnect
/// notifications (event-driven). macOS asks once for Bluetooth access.
/// Battery levels of AirPods and similar aren't exposed by public API, so
/// they aren't shown.
@MainActor @Observable
final class BluetoothMonitor: NSObject {
    struct Device: Identifiable, Equatable {
        let id: String
        let name: String
        let symbol: String
    }

    private(set) var connected: [Device] = []
    @ObservationIgnored var onEvent: ((ActivityEvent) -> Void)?
    @ObservationIgnored private var connectNote: IOBluetoothUserNotification?
    @ObservationIgnored private var disconnectNotes: [String: IOBluetoothUserNotification] = [:]
    @ObservationIgnored private var announcing = false

    func start() {
        guard connectNote == nil else { return }
        connectNote = IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(didConnect(_:device:)))
        // The registration replays already-connected devices; don't announce those.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            self?.announcing = true
        }
    }

    func stop() {
        connectNote?.unregister()
        connectNote = nil
        disconnectNotes.values.forEach { $0.unregister() }
        disconnectNotes.removeAll()
        connected.removeAll()
        announcing = false
    }

    @objc nonisolated private func didConnect(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        let info = Self.describe(device)
        // IOBluetooth delivers these on the main thread; the box only
        // carries the device reference into the main-actor closure.
        let box = UncheckedBox(device)
        MainActor.assumeIsolated {
            let device = box.value
            guard !connected.contains(where: { $0.id == info.id }) else { return }
            connected.append(info)
            disconnectNotes[info.id] = device.register(forDisconnectNotification: self, selector: #selector(didDisconnect(_:device:)))
            if announcing {
                onEvent?(ActivityEvent(symbol: info.symbol, tint: .blue, title: info.name, detail: "Connected", tab: .home))
                if Self.isAudio(info) { announceBattery(of: info) }
            }
        }
    }

    // MARK: Headphone battery

    nonisolated static func isAudio(_ d: Device) -> Bool {
        d.symbol.contains("airpods") || d.symbol.contains("beats") || d.symbol.contains("headphones")
    }

    /// AirPods/Beats report battery a moment after connecting; macOS exposes it
    /// through `system_profiler SPBluetoothDataType` (public tool, read-only).
    private func announceBattery(of device: Device) {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard let levels = await Self.batteryLevels(named: device.name), let self else { return }
            self.onEvent?(ActivityEvent(symbol: device.symbol, tint: levels.lowest <= 20 ? .red : .green, title: device.name,
                                        detail: levels.text, trailing: "\(levels.lowest)%", tab: .home))
        }
    }

    struct BatteryLevels: Equatable {
        var left: Int?, right: Int?, caseLevel: Int?, main: Int?
        var lowest: Int { [left, right, main].compactMap { $0 }.min() ?? caseLevel ?? 0 }
        var text: String {
            var parts: [String] = []
            if let left { parts.append("L \(left)%") }
            if let right { parts.append("R \(right)%") }
            if let main { parts.append("\(main)%") }
            if let caseLevel { parts.append("Case \(caseLevel)%") }
            return parts.joined(separator: " · ")
        }
    }

    nonisolated static func batteryLevels(named name: String) async -> BatteryLevels? {
        let json: Data? = await withCheckedContinuation { c in
            DispatchQueue.global(qos: .utility).async {
                let p = Process(), pipe = Pipe()
                p.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
                p.arguments = ["SPBluetoothDataType", "-json"]
                p.standardOutput = pipe
                p.standardError = FileHandle.nullDevice
                do { try p.run() } catch { c.resume(returning: nil); return }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                c.resume(returning: data)
            }
        }
        return json.flatMap { parseBattery($0, name: name) }
    }

    /// Reads "device_batteryLevel*" for the named connected device.
    nonisolated static func parseBattery(_ data: Data, name: String) -> BatteryLevels? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let controllers = root["SPBluetoothDataType"] as? [[String: Any]] else { return nil }
        for controller in controllers {
            for entry in controller["device_connected"] as? [[String: Any]] ?? [] {
                guard let props = entry[name] as? [String: Any] else { continue }
                func level(_ key: String) -> Int? { (props[key] as? String).flatMap { Int($0.filter(\.isNumber)) } }
                let levels = BatteryLevels(left: level("device_batteryLevelLeft"), right: level("device_batteryLevelRight"),
                                           caseLevel: level("device_batteryLevelCase"), main: level("device_batteryLevelMain"))
                return levels.text.isEmpty ? nil : levels
            }
        }
        return nil
    }

    @objc nonisolated private func didDisconnect(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        let id = device.addressString ?? ""
        MainActor.assumeIsolated {
            guard let device = connected.first(where: { $0.id == id }) else { return }
            connected.removeAll { $0.id == id }
            disconnectNotes.removeValue(forKey: id)?.unregister()
            onEvent?(ActivityEvent(symbol: device.symbol, tint: .gray, title: device.name, detail: "Disconnected", tab: .home))
        }
    }

    nonisolated static func describe(_ device: IOBluetoothDevice) -> Device {
        let name = device.name ?? "Bluetooth Device"
        return Device(id: device.addressString ?? name, name: name,
                      symbol: symbol(name: name, major: device.deviceClassMajor, minor: device.deviceClassMinor))
    }

    /// SF Symbol from the device name and Bluetooth class of device.
    nonisolated static func symbol(name: String, major: BluetoothDeviceClassMajor, minor: BluetoothDeviceClassMinor) -> String {
        let n = name.lowercased()
        if n.contains("airpods max") { return "airpodsmax" }
        if n.contains("airpods pro") { return "airpodspro" }
        if n.contains("airpods") { return "airpods" }
        if n.contains("beats") { return "beats.headphones" }
        if n.contains("keyboard") { return "keyboard" }
        if n.contains("trackpad") { return "rectangle.and.hand.point.up.left" }
        if n.contains("mouse") { return "magicmouse" }
        if n.contains("watch") { return "applewatch" }
        switch major {
        case 0x04: return "headphones"                      // audio/video
        case 0x05: return minor & 0x10 != 0 ? "keyboard" : "computermouse"   // peripheral
        case 0x02: return "iphone"
        case 0x01: return "laptopcomputer"
        default: return "dot.radiowaves.left.and.right"
        }
    }
}

/// Carries a non-Sendable reference across an isolation boundary when the
/// caller guarantees it stays on one thread.
struct UncheckedBox<T>: @unchecked Sendable { let value: T; init(_ v: T) { value = v } }
