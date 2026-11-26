// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

/// Home: time, next event, every live activity, battery and network.
struct DashboardView: View {
    @Environment(IslandModel.self) private var model
    @Environment(AppServices.self) private var services
    @Environment(AppSettings.self) private var settings
    @Environment(BatteryMonitor.self) private var battery
    @Environment(NetworkMonitor.self) private var network
    @Environment(CalendarService.self) private var calendar

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.m) {
            VStack(alignment: .leading, spacing: 0) {
                TimelineView(.everyMinute) { context in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.date, format: .dateTime.hour().minute())
                            .font(DS.numerals(44))
                            .contentTransition(.numericText())
                        Text(context.date, format: .dateTime.weekday(.wide).month(.wide).day())
                            .font(DS.caption)
                            .foregroundStyle(Color.secondaryText)
                    }
                }
                if let next = calendar.nextTimed {
                    Button { model.select(.calendar) } label: {
                        HStack(spacing: 6) {
                            Capsule().fill(next.color).frame(width: 3, height: 13)
                            Text(next.title).lineLimit(1)
                            Text(next.start, style: .relative).foregroundStyle(Color.secondaryText)
                        }
                        .font(DS.caption)
                    }
                    .buttonStyle(.plainHit)
                    .padding(.top, DS.Space.s)
                }
                Spacer(minLength: DS.Space.s)
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel("Now")
                    CommunicationStrip()
                    liveList
                    DevicesList()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 9) {
                if settings.batteryEnabled { BatteryStatus(snapshot: battery.snapshot, lowPower: battery.isLowPowerMode) }
                NetworkStatus()
                Rectangle().fill(.white.opacity(0.07)).frame(height: 0.5)
                SystemStatsView()
                ControlToggles()
            }
            .frame(width: 150, alignment: .leading)
            .well(padding: 11)
        }
        .onAppear { network.refreshSignal() }
    }

    /// Every live activity; each row opens its page.
    private var liveList: some View {
        let activities = services.activities
        return VStack(alignment: .leading, spacing: 5) {
            if activities.isEmpty {
                Text("Nothing running").font(DS.caption).foregroundStyle(Color.tertiaryText)
            }
            ForEach(activities.prefix(4)) { activity in
                Button { model.select(activity.tab) } label: {
                    HStack(spacing: 8) {
                        ActivityGlyph(activity: activity, size: 16).frame(width: 20)
                        Text(activity.title).font(DS.body).foregroundStyle(.white.opacity(0.9)).lineLimit(1)
                        Spacer(minLength: 4)
                        ActivityValue(activity: activity).font(.system(size: 11))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plainHit)
            }
        }
    }
}

struct BatteryStatus: View {
    let snapshot: BatterySnapshot
    let lowPower: Bool

    var body: some View {
        HStack(spacing: 9) {
            ZStack {
                ProgressRing(fraction: Double(snapshot.percent) / 100, color: lowPower ? .yellow : snapshot.tint, lineWidth: 3.5)
                Image(systemName: snapshot.isPluggedIn ? "bolt.fill" : "battery.100percent")
                    .font(.system(size: snapshot.isPluggedIn ? 11 : 8, weight: .bold))
                    .foregroundStyle(snapshot.isPluggedIn ? .green : .white.opacity(0.7))
            }
            .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(snapshot.hasBattery ? "\(snapshot.percent)%" : "AC Power")
                    .font(DS.numerals(14))
                Text(lowPower ? "Low Power Mode" : snapshot.timeText ?? snapshot.statusText)
                    .font(DS.caption)
                    .foregroundStyle(lowPower ? .yellow : Color.secondaryText)
            }
            .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

struct NetworkStatus: View {
    @Environment(NetworkMonitor.self) private var network
    @State private var speed: (down: Double, up: Double)?

    var body: some View {
        HStack(spacing: 9) {
            Group {
                if network.kind == .wifi, let signal = network.signal {
                    Image(systemName: "wifi", variableValue: signal)
                } else {
                    Image(systemName: network.symbol)
                }
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(network.kind == .offline ? Color.secondaryText : .blue)
            .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(network.title).font(DS.title)
                if let speed, network.kind != .offline {
                    Text("↓ \(NetworkCounters.format(speed.down))  ↑ \(NetworkCounters.format(speed.up))")
                        .font(.system(size: 10, weight: .medium).monospacedDigit()).foregroundStyle(Color.secondaryText)
                } else {
                    Text(network.subtitle).font(DS.caption).foregroundStyle(Color.secondaryText)
                }
            }
            .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .task {
            // Only while visible: one counter read per second.
            var last = NetworkCounters.sample()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                let now = NetworkCounters.sample()
                withAnimation(.easeOut(duration: 0.2)) { speed = NetworkCounters.rate(last, now) }
                last = now
            }
        }
    }
}

/// Control Center-style round toggles.
struct ControlToggles: View {
    @Environment(AppVolumeMixer.self) private var mixer
    @State private var showMixer = false
    @State private var focusNote: String?
    @Environment(SystemControls.self) private var controls
    @Environment(FocusService.self) private var focus

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            toggles
            if controls.isKeepingAwake {
                // Remaining time; ticks once a minute only while Keep Awake is on.
                TimelineView(.periodic(from: .timelineAnchor, by: 60)) { context in
                    Text(SystemControls.awakeText(until: controls.keepAwakeUntil, now: context.date))
                        .font(.system(size: 10, weight: .medium).monospacedDigit()).foregroundStyle(.yellow.opacity(0.9))
                }
                .transition(.opacity)
            }
            if let focusNote {
                Text(focusNote).font(.system(size: 10, weight: .medium)).foregroundStyle(Color.secondaryText)
                    .fixedSize(horizontal: false, vertical: true).transition(.opacity)
            }
        }
        .onAppear { controls.refreshMic(); focus.refresh() }
    }

    private var toggles: some View {
        HStack(spacing: 8) {
            keepAwakeMenu
            toggle(controls.micMuted ? "mic.slash.fill" : "mic.fill", on: controls.micMuted, tint: .red,
                   help: controls.micMuted ? "Unmute microphone" : "Mute microphone for all apps") {
                controls.setMicMuted(!controls.micMuted)
            }
            toggle("moon.fill", on: focus.isFocused == true, tint: .indigo,
                   help: focus.isFocused == true ? "Turn Do Not Disturb off" : "Turn Do Not Disturb on") {
                Task {
                    let message = await focus.toggleDoNotDisturb()
                    withAnimation { focusNote = message }
                }
            }
            if AppVolumeMixer.isSupported {
                toggle("slider.horizontal.3", on: showMixer, tint: .white, help: "App volumes") {
                    mixer.start()
                    showMixer.toggle()
                }
                .popover(isPresented: $showMixer, arrowEdge: .bottom) { AppVolumePanel() }
            }
        }
    }

    /// Keep Awake: pick a duration, indefinitely, or turn it off.
    private var keepAwakeMenu: some View {
        Menu {
            ForEach([(15, "15 Minutes"), (60, "1 Hour"), (120, "2 Hours"), (240, "4 Hours"), (480, "8 Hours")], id: \.0) { minutes, title in
                Button(title) { controls.keepAwake(for: TimeInterval(minutes * 60)) }
            }
            Button("Until I Turn It Off") { controls.keepAwake(for: nil) }
            if controls.isKeepingAwake {
                Divider()
                Button("Turn Off Keep Awake") { controls.stopKeepingAwake() }
            }
        } label: {
            Image(systemName: controls.isKeepingAwake ? "cup.and.saucer.fill" : "cup.and.saucer")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(controls.isKeepingAwake ? .black : .white)
                .frame(width: 30, height: 30)
                .modifier(CircleBackground(filled: controls.isKeepingAwake, tint: .yellow, hovering: false))
                .contentShape(Circle())
        }
        .menuStyle(.button)
        .buttonStyle(PressableStyle())
        .menuIndicator(.hidden)
        .fixedSize()
        .help(controls.isKeepingAwake ? "Keep Awake is on" : "Keep Mac awake")
        .accessibilityLabel("Keep Awake")
    }

    private func toggle(_ symbol: String, on: Bool, tint: Color, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(on ? .black : .white)
                .frame(width: 30, height: 30)
                .modifier(CircleBackground(filled: on, tint: tint, hovering: false))
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(PressableStyle())
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Droppy-style per-app volume sliders.
struct AppVolumePanel: View {
    @Environment(AppVolumeMixer.self) private var mixer

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !mixer.outputs.isEmpty {
                Picker("Output", selection: Binding(
                    get: { mixer.currentOutput ?? 0 },
                    set: { id in if let o = mixer.outputs.first(where: { $0.id == id }) { mixer.selectOutput(o) } })) {
                    ForEach(mixer.outputs) { Text($0.name).tag($0.id) }
                }
                Divider()
            }
            Text("App Volume").font(.headline)
            if mixer.apps.isEmpty {
                Text("No apps are playing audio.").foregroundStyle(.secondary).font(.callout)
            }
            ForEach(mixer.apps) { app in
                HStack(spacing: 8) {
                    if let icon = app.icon { Image(nsImage: icon).resizable().frame(width: 20, height: 20) }
                    Text(app.name).lineLimit(1).frame(width: 92, alignment: .leading)
                    Slider(value: Binding(get: { Double(mixer.volume(for: app)) },
                                          set: { mixer.setVolume(Float($0), for: app) }), in: 0...1)
                    Text("\(Int((mixer.volume(for: app) * 100).rounded()))%")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 34, alignment: .trailing)
                }
            }
            if let error = mixer.lastError {
                Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(width: 300)
        .onAppear { mixer.refresh(); mixer.refreshOutputs() }
    }
}

/// Connected Bluetooth devices and external drives.
struct DevicesList: View {
    @Environment(BluetoothMonitor.self) private var bluetooth
    @Environment(DrivesMonitor.self) private var drives
    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if settings.bluetoothEnabled {
                ForEach(bluetooth.connected.prefix(2)) { d in
                    Label(d.name, systemImage: d.symbol).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.8)).lineLimit(1)
                }
            }
            if settings.drivesEnabled {
                ForEach(drives.drives) { drive in
                    HStack(spacing: 6) {
                        Label(drive.name, systemImage: "externaldrive.fill").font(.system(size: 11, weight: .medium)).lineLimit(1)
                        Button { drives.eject(drive) } label: { Image(systemName: "eject.fill").font(.system(size: 9, weight: .bold)) }
                            .buttonStyle(.plainHit).foregroundStyle(Color.secondaryText).help("Eject \(drive.name)")
                    }
                    .foregroundStyle(.white.opacity(0.8))
                }
            }
        }
    }
}

/// Incoming call (with real Accept/Decline when the banner has them) and
/// the latest message, from the opt-in Notification Mirror.
struct CommunicationStrip: View {
    @Environment(NotificationMirror.self) private var mirror
    @Environment(AppSettings.self) private var settings

    var body: some View {
        if settings.mirrorEnabled {
            if let call = mirror.activeCall {
                HStack(spacing: 8) {
                    Image(systemName: "phone.fill").foregroundStyle(.green)
                    Text(call.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    TimelineView(.periodic(from: .timelineAnchor, by: 1)) { c in
                        Text(mirror.callStarted.map { c.date.timeIntervalSince($0).clockStringFloor } ?? "")
                            .font(.system(size: 11).monospacedDigit()).foregroundStyle(Color.secondaryText)
                    }
                    Spacer()
                    Button("End") { mirror.endCall() }.buttonStyle(PressableStyle()).font(.system(size: 11, weight: .semibold)).foregroundStyle(.red)
                }
                .padding(.bottom, 4)
            } else if let item = mirror.recent.first, Date().timeIntervalSince(item.date) < 120 {
                HStack(spacing: 8) {
                    Image(systemName: item.kind == .call ? "phone.arrow.down.left.fill" : "message.fill")
                        .foregroundStyle(item.kind == .call ? .green : .blue)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(item.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        if let body = item.body { Text(body).font(.system(size: 10.5)).foregroundStyle(Color.secondaryText).lineLimit(1) }
                    }
                    Spacer(minLength: 4)
                    if item.canDecline { ClockButton(title: "✕", tint: .red, size: 26) { mirror.respond(item, accept: false) } }
                    if item.canAccept { ClockButton(title: "✓", tint: .green, size: 26) { mirror.respond(item, accept: true) } }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .padding(.bottom, 4)
            }
        }
    }
}
