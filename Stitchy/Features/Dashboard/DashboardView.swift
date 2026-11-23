import SwiftUI

/// Home page: time, date, a glance at what's going on, battery and network.
struct DashboardView: View {
    @Environment(IslandModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(BatteryMonitor.self) private var battery
    @Environment(NetworkMonitor.self) private var network
    @Environment(TimerService.self) private var timer
    @Environment(NowPlayingService.self) private var nowPlaying
    @Environment(FileShelf.self) private var shelf
    @Environment(DownloadsMonitor.self) private var downloads

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                TimelineView(.everyMinute) { context in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(context.date, format: .dateTime.hour().minute())
                            .font(.system(size: 44, weight: .semibold, design: .rounded).monospacedDigit())
                            .contentTransition(.numericText())
                        Text(context.date, format: .dateTime.weekday(.wide).month(.wide).day())
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.secondaryText)
                    }
                }
                Spacer(minLength: 8)
                overview
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 8) {
                if settings.batteryEnabled { BatteryTile(snapshot: battery.snapshot, lowPower: battery.isLowPowerMode) }
                NetworkTile()
            }
            .frame(width: 168)
        }
        .onAppear { network.refreshSignal() }
    }

    /// One row per live thing; each jumps to its tab.
    private var overview: some View {
        let rows = overviewRows
        return VStack(alignment: .leading, spacing: 5) {
            if rows.isEmpty {
                Label("Nothing in progress", systemImage: "checkmark.circle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.tertiaryText)
            }
            ForEach(rows, id: \.title) { row in
                Button { model.select(row.tab) } label: {
                    HStack(spacing: 7) {
                        Image(systemName: row.symbol)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(row.tint)
                            .frame(width: 20, height: 20)
                            .background(row.tint.opacity(0.18), in: Circle())
                        Text(row.title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private struct Row {
        var symbol: String
        var tint: Color
        var title: String
        var tab: IslandTab
    }

    private var overviewRows: [Row] {
        var rows: [Row] = []
        if settings.timerEnabled, timer.isActive {
            let title = switch timer.phase {
            case .finished: "Timer finished"
            case .paused: "Timer paused · \(timer.remaining().clockString)"
            default: "Timer · ends \(Date().addingTimeInterval(timer.remaining()).formatted(date: .omitted, time: .shortened))"
            }
            rows.append(Row(symbol: "timer", tint: .orange, title: title, tab: .timer))
        }
        if settings.musicEnabled, let track = nowPlaying.track {
            rows.append(Row(symbol: nowPlaying.isPlaying ? "play.fill" : "pause.fill", tint: .pink, title: "\(track.title) · \(track.artist)", tab: .music))
        }
        if settings.downloadsEnabled, !downloads.active.isEmpty {
            let n = downloads.active.count
            rows.append(Row(symbol: "arrow.down", tint: .blue, title: n == 1 ? "1 download in progress" : "\(n) downloads in progress", tab: .activity))
        }
        if settings.shelfEnabled, !shelf.items.isEmpty {
            let n = shelf.items.count
            rows.append(Row(symbol: "tray.full.fill", tint: .teal, title: n == 1 ? "1 file on Shelf" : "\(n) files on Shelf", tab: .shelf))
        }
        return Array(rows.prefix(3))
    }
}

struct BatteryTile: View {
    let snapshot: BatterySnapshot
    let lowPower: Bool

    var body: some View {
        Tile {
            HStack(spacing: 10) {
                ZStack {
                    ProgressRing(fraction: Double(snapshot.percent) / 100, color: lowPower ? .yellow : snapshot.tint, lineWidth: 4)
                    Image(systemName: snapshot.isPluggedIn ? "bolt.fill" : "battery.100percent")
                        .font(.system(size: snapshot.isPluggedIn ? 12 : 9, weight: .bold))
                        .foregroundStyle(snapshot.isPluggedIn ? .green : .white.opacity(0.7))
                }
                .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(snapshot.hasBattery ? "\(snapshot.percent)%" : "AC Power")
                        .font(.system(size: 15, weight: .semibold).monospacedDigit())
                    Text(lowPower ? "Low Power Mode" : snapshot.statusText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(lowPower ? .yellow : Color.secondaryText)
                    if let detail = snapshot.timeText ?? snapshot.adapterWatts.map({ "\($0)W adapter" }) {
                        Text(detail).font(.system(size: 10)).foregroundStyle(Color.tertiaryText)
                    }
                }
                .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct NetworkTile: View {
    @Environment(NetworkMonitor.self) private var network

    var body: some View {
        Tile {
            HStack(spacing: 10) {
                Group {
                    if network.kind == .wifi, let signal = network.signal {
                        Image(systemName: "wifi", variableValue: signal)
                    } else {
                        Image(systemName: network.symbol)
                    }
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(network.kind == .offline ? Color.secondaryText : .blue)
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.06), in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(network.title).font(.system(size: 13, weight: .semibold))
                    Text(network.subtitle).font(.system(size: 11, weight: .medium)).foregroundStyle(Color.secondaryText)
                }
                .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
