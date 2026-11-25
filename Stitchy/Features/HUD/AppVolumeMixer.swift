import AppKit
import AudioToolbox
import CoreAudio
import Observation

/// Droppy-style per-app volume ("Audio Control"), using public CoreAudio
/// process taps (macOS 14.2+). An app at 100 % is untouched. Below that,
/// Stitchy taps the app's audio with `mutedWhenTapped` (macOS silences the
/// original) and plays the tapped audio to the current output at the chosen
/// level through a private aggregate device. macOS asks once for audio
/// capture permission. Nothing is recorded or stored.
@MainActor @Observable
final class AppVolumeMixer {
    struct App: Identifiable, Equatable {
        let id: AudioObjectID        // CoreAudio process object
        let pid: pid_t
        let name: String
        let icon: NSImage?
        static func == (a: App, b: App) -> Bool { a.id == b.id && a.name == b.name }
    }

    private(set) var apps: [App] = []
    struct Output: Identifiable, Equatable { let id: AudioObjectID; let name: String }
    private(set) var outputs: [Output] = []
    private(set) var currentOutput: AudioObjectID?
    private(set) var volumes: [String: Float] = [:]   // by app name, survives relaunches of the app
    private(set) var lastError: String?
    @ObservationIgnored private var routes: [AudioObjectID: AnyObject] = [:]
    @ObservationIgnored private var listeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []

    static var isSupported: Bool {
        if #available(macOS 14.2, *) { return true }
        return false
    }

    func start() {
        guard listeners.isEmpty else { return }
        let system = AudioObjectID(kAudioObjectSystemObject)
        if let t = AudioHAL.listen(system, AudioHAL.address(kAudioHardwarePropertyProcessObjectList), { [weak self] in self?.refresh() }) { listeners.append(t) }
        if let t = AudioHAL.listen(system, AudioHAL.address(kAudioHardwarePropertyDefaultOutputDevice), { [weak self] in
            self?.rebuildRoutes()
            self?.refreshOutputs()
        }) { listeners.append(t) }
        if let t = AudioHAL.listen(system, AudioHAL.address(kAudioHardwarePropertyDevices), { [weak self] in self?.refreshOutputs() }) { listeners.append(t) }
        refreshOutputs()
        refresh()
    }

    func stop() {
        listeners.forEach(AudioHAL.remove)
        listeners.removeAll()
        teardownAll()
    }

    func volume(for app: App) -> Float { volumes[app.name] ?? 1 }

    func setVolume(_ value: Float, for app: App) {
        let v = min(max(value, 0), 1)
        volumes[app.name] = v
        guard #available(macOS 14.2, *) else { return }
        if v >= 0.995 {
            (routes.removeValue(forKey: app.id) as? TapRoute)?.teardown()
        } else if let route = routes[app.id] as? TapRoute {
            route.gain.value = v
        } else {
            do {
                routes[app.id] = try TapRoute(process: app.id, gain: v)
                lastError = nil
            } catch {
                lastError = (error as? TapRoute.Failure)?.message ?? "Couldn't control this app's volume."
            }
        }
    }

    /// Output devices (speakers, headphones, AirPlay, displays).
    func refreshOutputs() {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var addr = AudioHAL.address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr else { return }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return }
        outputs = ids.compactMap { id in
            var streams = AudioHAL.address(kAudioDevicePropertyStreams, kAudioObjectPropertyScopeOutput)
            var bytes: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &bytes) == noErr, bytes > 0,
                  let name = AudioHAL.name(id), !name.hasPrefix("Stitchy") else { return nil }
            return Output(id: id, name: name)
        }
        currentOutput = AudioHAL.defaultDevice(input: false)
    }

    func selectOutput(_ output: Output) {
        var addr = AudioHAL.address(kAudioHardwarePropertyDefaultOutputDevice)
        var id = output.id
        let status = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil,
                                                UInt32(MemoryLayout<AudioObjectID>.size), &id)
        lastError = status == noErr ? nil : "Couldn't switch to \(output.name)."
        refreshOutputs()
    }

    /// Apps currently playing audio.
    func refresh() {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var addr = AudioHAL.address(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr else { return }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return }
        let own = ProcessInfo.processInfo.processIdentifier
        var found: [App] = []
        for id in ids {
            guard let pid = AudioHAL.get(id, AudioHAL.address(kAudioProcessPropertyPID), pid_t(0)), pid != own,
                  let app = NSRunningApplication(processIdentifier: pid) ?? Self.owningApp(of: pid) else { continue }
            let running = AudioHAL.get(id, AudioHAL.address(kAudioProcessPropertyIsRunningOutput), UInt32(0)) == 1
            // Keep tapped apps listed even when the tap makes them look idle.
            guard running || routes[id] != nil else { continue }
            found.append(App(id: id, pid: pid, name: app.localizedName ?? "App", icon: app.icon))
        }
        // Helper processes (e.g. browser renderers) share their app's row.
        var seen = Set<String>()
        apps = found.filter { seen.insert($0.name).inserted }.sorted { $0.name < $1.name }
        // Drop routes whose process is gone.
        if #available(macOS 14.2, *) {
            for id in routes.keys where !ids.contains(id) { (routes.removeValue(forKey: id) as? TapRoute)?.teardown() }
        }
    }

    /// Re-creates taps on the new output device with the same levels.
    private func rebuildRoutes() {
        let current = apps.filter { routes[$0.id] != nil }
        teardownAll()
        for app in current { setVolume(volume(for: app), for: app) }
    }

    private func teardownAll() {
        if #available(macOS 14.2, *) { routes.values.forEach { ($0 as? TapRoute)?.teardown() } }
        routes.removeAll()
    }

    /// Helper processes (WebKit, Chrome renderers) map to their parent app.
    private static func owningApp(of pid: pid_t) -> NSRunningApplication? {
        var info = proc_bsdinfo()
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size)) > 0 else { return nil }
        let parent = pid_t(info.pbi_ppid)
        guard parent > 1 else { return nil }
        return NSRunningApplication(processIdentifier: parent).flatMap { $0.activationPolicy == .regular ? $0 : nil }
    }
}

/// Realtime-safe gain shared with the IO block.
final class GainBox: @unchecked Sendable {
    var value: Float
    init(_ v: Float) { value = v }
}

/// One app's tap → aggregate device → output, scaled by `gain`.
@available(macOS 14.2, *)
final class TapRoute {
    struct Failure: Error { let message: String }

    let gain: GainBox
    private var tapID = AudioObjectID(0)
    private var aggregateID = AudioObjectID(0)
    private var procID: AudioDeviceIOProcID?

    init(process: AudioObjectID, gain: Float) throws {
        self.gain = GainBox(gain)
        guard let output = AudioHAL.defaultDevice(input: false), let outputUID = Self.uid(of: output) else {
            throw Failure(message: "No audio output device.")
        }
        let desc = CATapDescription(stereoMixdownOfProcesses: [process])
        desc.uuid = UUID()
        desc.muteBehavior = .mutedWhenTapped
        desc.isPrivate = true
        guard AudioHardwareCreateProcessTap(desc, &tapID) == noErr else {
            throw Failure(message: "macOS didn't allow audio control. Allow Stitchy under Privacy & Security › Screen & System Audio Recording.")
        }
        let config: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Stitchy App Volume",
            kAudioAggregateDeviceUIDKey: "app.stitchy.volume.\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: desc.uuid.uuidString]],
        ]
        guard AudioHardwareCreateAggregateDevice(config as CFDictionary, &aggregateID) == noErr else {
            teardown()
            throw Failure(message: "Couldn't create the audio route.")
        }
        let box = self.gain
        let status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, nil) { _, input, _, output, _ in
            TapRoute.copy(input, to: output, gain: box.value)
        }
        guard status == noErr, AudioDeviceStart(aggregateID, procID) == noErr else {
            teardown()
            throw Failure(message: "Couldn't start the audio route.")
        }
    }

    /// Float32 copy with gain; extra output buffers/channels are silenced.
    static func copy(_ input: UnsafePointer<AudioBufferList>, to output: UnsafeMutablePointer<AudioBufferList>, gain: Float) {
        let ins = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let outs = UnsafeMutableAudioBufferListPointer(output)
        for (i, out) in outs.enumerated() {
            guard let dst = out.mData else { continue }
            let outCount = Int(out.mDataByteSize) / MemoryLayout<Float>.size
            let d = dst.assumingMemoryBound(to: Float.self)
            if i < ins.count, let src = ins[i].mData {
                let n = min(outCount, Int(ins[i].mDataByteSize) / MemoryLayout<Float>.size)
                let s = src.assumingMemoryBound(to: Float.self)
                for k in 0..<n { d[k] = s[k] * gain }
                if n < outCount { (d + n).update(repeating: 0, count: outCount - n) }
            } else {
                d.update(repeating: 0, count: outCount)
            }
        }
    }

    func teardown() {
        if aggregateID != 0 {
            if let procID {
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = 0
        }
        procID = nil
        if tapID != 0 {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = 0
        }
    }

    private static func uid(of device: AudioObjectID) -> String? {
        var addr = AudioHAL.address(kAudioDevicePropertyDeviceUID)
        var uid: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &uid) == noErr else { return nil }
        return uid?.takeRetainedValue() as String?
    }
}
