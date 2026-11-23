import SwiftUI

/// Home: time, next event, every live activity, battery and network.
struct DashboardView: View {
    @Environment(IslandModel.self) private var model
    @Environment(AppServices.self) private var services
    @Environment(AppSettings.self) private var settings
    @Environment(BatteryMonitor.self) private var battery
    @Environment(NetworkMonitor.self) private var network
    @Environment(CalendarService.self) private var calendar
    @Environment(FaceIDService.self) private var faceID

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 0) {
                TimelineView(.everyMinute) { context in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(context.date, format: .dateTime.hour().minute())
                            .font(.system(size: 42, weight: .semibold, design: .rounded).monospacedDigit())
                        Text(context.date, format: .dateTime.weekday(.wide).month(.wide).day())
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.secondaryText)
                    }
                }
                if let next = calendar.nextTimed {
                    Button { model.select(.calendar) } label: {
                        HStack(spacing: 6) {
                            Capsule().fill(next.color).frame(width: 3, height: 14)
                            Text(next.title).lineLimit(1)
                            Text(next.start, style: .relative).foregroundStyle(Color.secondaryText)
                        }
                        .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 6)
                }
                Spacer(minLength: 8)
                liveList
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 14) {
                if settings.batteryEnabled { BatteryStatus(snapshot: battery.snapshot, lowPower: battery.isLowPowerMode) }
                NetworkStatus()
                if settings.faceIDEnabled { FaceStatus() }
            }
            .frame(width: 150, alignment: .leading)
            .padding(.top, 6)
        }
        .onAppear { network.refreshSignal() }
    }

    /// Every live activity; each row opens its page.
    private var liveList: some View {
        let activities = services.activities
        return VStack(alignment: .leading, spacing: 5) {
            if activities.isEmpty {
                Label("Nothing in progress", systemImage: "checkmark.circle")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.tertiaryText)
            }
            ForEach(activities.prefix(4)) { activity in
                Button { model.select(activity.tab) } label: {
                    HStack(spacing: 8) {
                        ActivityGlyph(activity: activity, size: 16).frame(width: 20)
                        Text(activity.title).font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                        Spacer(minLength: 4)
                        ActivityValue(activity: activity).font(.system(size: 11))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct BatteryStatus: View {
    let snapshot: BatterySnapshot
    let lowPower: Bool

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                ProgressRing(fraction: Double(snapshot.percent) / 100, color: lowPower ? .yellow : snapshot.tint, lineWidth: 3.5)
                Image(systemName: snapshot.isPluggedIn ? "bolt.fill" : "battery.100percent")
                    .font(.system(size: snapshot.isPluggedIn ? 11 : 8, weight: .bold))
                    .foregroundStyle(snapshot.isPluggedIn ? .green : .white.opacity(0.7))
            }
            .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(snapshot.hasBattery ? "\(snapshot.percent)%" : "AC Power")
                    .font(.system(size: 14, weight: .semibold).monospacedDigit())
                Text(lowPower ? "Low Power Mode" : snapshot.timeText ?? snapshot.statusText)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(lowPower ? .yellow : Color.secondaryText)
            }
            .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

struct NetworkStatus: View {
    @Environment(NetworkMonitor.self) private var network

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if network.kind == .wifi, let signal = network.signal {
                    Image(systemName: "wifi", variableValue: signal)
                } else {
                    Image(systemName: network.symbol)
                }
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(network.kind == .offline ? Color.secondaryText : .blue)
            .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(network.title).font(.system(size: 13, weight: .semibold))
                Text(network.subtitle).font(.system(size: 10.5, weight: .medium)).foregroundStyle(Color.secondaryText)
            }
            .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Face ID glance shortcut + result, only when the feature is enabled.
struct FaceStatus: View {
    @Environment(FaceIDService.self) private var faceID

    var body: some View {
        Button { Task { await faceID.check() } } label: {
            HStack(spacing: 10) {
                Image(systemName: faceID.cameraRunning ? "camera.fill" : "faceid")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(faceID.cameraRunning ? .green : .white.opacity(0.8))
                    .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Face ID Glance").font(.system(size: 12, weight: .semibold))
                    Text(statusText).font(.system(size: 10.5, weight: .medium)).foregroundStyle(Color.secondaryText)
                }
                .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!faceID.isEnrolled || faceID.cameraRunning)
    }

    private var statusText: String {
        if !faceID.isEnrolled { return "Set up in Settings" }
        if faceID.cameraRunning { return "Looking…" }
        switch faceID.lastMatch {
        case .recognized: return "Welcome back"
        case .notRecognized: return "Not recognized"
        case .noFace: return "No face seen"
        case nil: return "Tap to check"
        }
    }
}
