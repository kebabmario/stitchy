// SPDX-License-Identifier: GPL-3.0-or-later
import AudioToolbox
import CoreAudio
import Foundation
import Observation

/// Small CoreAudio helpers (public HAL API).
enum AudioHAL {
    static func address(_ selector: AudioObjectPropertySelector,
                        _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static func get<T>(_ object: AudioObjectID, _ addr: AudioObjectPropertyAddress, _ initial: T) -> T? {
        var addr = addr
        var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        guard AudioObjectHasProperty(object, &addr),
              AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    static func defaultDevice(input: Bool) -> AudioObjectID? {
        let sel = input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice
        let id = get(AudioObjectID(kAudioObjectSystemObject), address(sel), AudioObjectID(0))
        return id == 0 ? nil : id
    }

    static func name(_ device: AudioObjectID) -> String? {
        var addr = address(kAudioObjectPropertyName)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &name) == noErr else { return nil }
        return name?.takeRetainedValue() as String?
    }

    /// Registers a listener on the main queue; returns a token for removal.
    static func listen(_ object: AudioObjectID, _ addr: AudioObjectPropertyAddress,
                       _ handler: @escaping @MainActor () -> Void) -> (AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)? {
        var addr = addr
        guard AudioObjectHasProperty(object, &addr) else { return nil }
        let block: AudioObjectPropertyListenerBlock = { _, _ in MainActor.assumeIsolated { handler() } }
        guard AudioObjectAddPropertyListenerBlock(object, &addr, .main, block) == noErr else { return nil }
        return (object, addr, block)
    }

    static func remove(_ token: (AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)) {
        var addr = token.1
        AudioObjectRemovePropertyListenerBlock(token.0, &addr, .main, token.2)
    }
}

/// Output volume, mute and output-device changes for the System HUD.
/// Brightness is not included: macOS has no public API for it.
@MainActor @Observable
final class AudioMonitor {
    enum Change: Equatable { case volume, mute, output }

    private(set) var volume: Float = 0
    private(set) var isMuted = false
    private(set) var outputName = ""
    @ObservationIgnored var onChange: ((Change) -> Void)?
    @ObservationIgnored private var tokens: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    @ObservationIgnored private var deviceTokens: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    @ObservationIgnored private var device: AudioObjectID?

    private let volumeAddr = AudioHAL.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyScopeOutput)
    private let muteAddr = AudioHAL.address(kAudioDevicePropertyMute, kAudioDevicePropertyScopeOutput)

    func start() {
        guard tokens.isEmpty else { return }
        if let t = AudioHAL.listen(AudioObjectID(kAudioObjectSystemObject), AudioHAL.address(kAudioHardwarePropertyDefaultOutputDevice), { [weak self] in
            self?.bindDevice(announce: true)
        }) { tokens.append(t) }
        bindDevice(announce: false)
    }

    func stop() {
        (tokens + deviceTokens).forEach(AudioHAL.remove)
        tokens.removeAll()
        deviceTokens.removeAll()
    }

    private func bindDevice(announce: Bool) {
        deviceTokens.forEach(AudioHAL.remove)
        deviceTokens.removeAll()
        guard let device = AudioHAL.defaultDevice(input: false) else { return }
        self.device = device
        outputName = AudioHAL.name(device) ?? "Output"
        volume = AudioHAL.get(device, volumeAddr, Float32(0)) ?? 0
        isMuted = (AudioHAL.get(device, muteAddr, UInt32(0)) ?? 0) != 0
        if let t = AudioHAL.listen(device, volumeAddr, { [weak self] in self?.readVolume() }) { deviceTokens.append(t) }
        if let t = AudioHAL.listen(device, muteAddr, { [weak self] in self?.readMute() }) { deviceTokens.append(t) }
        if announce { onChange?(.output) }
    }

    private func readVolume() {
        guard let device, let v = AudioHAL.get(device, volumeAddr, Float32(0)), abs(v - volume) > 0.001 else { return }
        volume = v
        onChange?(.volume)
    }

    private func readMute() {
        guard let device else { return }
        let muted = (AudioHAL.get(device, muteAddr, UInt32(0)) ?? 0) != 0
        guard muted != isMuted else { return }
        isMuted = muted
        onChange?(.mute)
    }

    var volumeSymbol: String {
        if isMuted || volume == 0 { return "speaker.slash.fill" }
        return "speaker.wave.3.fill"
    }
}
