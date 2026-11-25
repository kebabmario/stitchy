import CoreWLAN
import Darwin
import Network
import Observation

/// Connectivity via NWPathMonitor (event-driven, no permission). Wi‑Fi signal
/// strength comes from CoreWLAN; the network *name* (SSID) is deliberately not
/// shown because macOS only reveals it to apps with Location access.
@MainActor @Observable
final class NetworkMonitor {
    enum Kind: Sendable { case wifi, ethernet, other, offline }

    private(set) var kind: Kind = .offline
    /// 0...1, Wi‑Fi only. Refreshed when the dashboard appears.
    private(set) var signal: Double?
    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private var started = false

    func start() {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { [weak self] path in
            let kind: Kind
            if path.status != .satisfied { kind = .offline }
            else if path.usesInterfaceType(.wifi) { kind = .wifi }
            else if path.usesInterfaceType(.wiredEthernet) { kind = .ethernet }
            else { kind = .other }
            Task { @MainActor in
                self?.kind = kind
                self?.refreshSignal()
            }
        }
        monitor.start(queue: .main)
    }

    func refreshSignal() {
        guard kind == .wifi, let rssi = CWWiFiClient.shared().interface()?.rssiValue(), rssi != 0 else {
            signal = nil
            return
        }
        // -90 dBm (unusable) ... -50 dBm (excellent)
        signal = min(max((Double(rssi) + 90) / 40, 0.05), 1)
    }

    var title: String {
        switch kind {
        case .wifi: "Wi‑Fi"
        case .ethernet: "Ethernet"
        case .other: "Network"
        case .offline: "Offline"
        }
    }

    var subtitle: String {
        switch kind {
        case .offline: "Not connected"
        case .wifi:
            switch signal ?? 0 {
            case 0.66...: "Strong signal"
            case 0.33...: "Good signal"
            case 0.01...: "Weak signal"
            default: "Connected"
            }
        default: "Connected"
        }
    }

    var symbol: String {
        switch kind {
        case .wifi: "wifi"
        case .ethernet: "cable.connector"
        case .other: "network"
        case .offline: "wifi.slash"
        }
    }
}

/// Network throughput from interface byte counters (getifaddrs, public
/// BSD API). Sampled only while the Home page is visible.
enum NetworkCounters {
    struct Sample: Sendable { let time: TimeInterval; let received: UInt64; let sent: UInt64 }

    static func sample() -> Sample {
        var rx: UInt64 = 0, tx: UInt64 = 0
        var addrs: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&addrs) == 0, let first = addrs {
            var p: UnsafeMutablePointer<ifaddrs>? = first
            while let cur = p {
                let name = String(cString: cur.pointee.ifa_name)
                if cur.pointee.ifa_addr?.pointee.sa_family == UInt8(AF_LINK), !name.hasPrefix("lo"),
                   let data = cur.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) {
                    rx += UInt64(data.pointee.ifi_ibytes)
                    tx += UInt64(data.pointee.ifi_obytes)
                }
                p = cur.pointee.ifa_next
            }
            freeifaddrs(addrs)
        }
        return Sample(time: ProcessInfo.processInfo.systemUptime, received: rx, sent: tx)
    }

    /// Bytes per second between two samples (counter wrap treated as 0).
    static func rate(_ a: Sample, _ b: Sample) -> (down: Double, up: Double) {
        let dt = max(b.time - a.time, 0.001)
        let down = b.received >= a.received ? Double(b.received - a.received) / dt : 0
        let up = b.sent >= a.sent ? Double(b.sent - a.sent) / dt : 0
        return (down, up)
    }

    static func format(_ bps: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bps), countStyle: .binary) + "/s"
    }
}
