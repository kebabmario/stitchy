import CoreWLAN
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
