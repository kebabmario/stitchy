// SPDX-License-Identifier: GPL-3.0-or-later
import CoreAudio
import CoreMediaIO
import Foundation
import Observation

/// Camera and microphone activity indicator ("Camera Guard").
///
/// Uses the public "device is running somewhere" properties: CoreMediaIO
/// for cameras and CoreAudio for the default input device. Both are
/// event-driven and need no camera/microphone permission, because they only
/// say *whether* a device is in use. macOS does not tell third-party apps
/// *which* app is using it, so Stitchy doesn't claim to know.
@MainActor @Observable
final class PrivacyGuard {
    private(set) var cameraActive = false
    private(set) var microphoneActive = false
    private(set) var cameraSince: Date?
    private(set) var microphoneSince: Date?
    @ObservationIgnored var onChange: ((_ camera: Bool, _ mic: Bool) -> Void)?
    @ObservationIgnored private var audioTokens: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    @ObservationIgnored private var cameraTokens: [(CMIOObjectID, CMIOObjectPropertyAddress, CMIOObjectPropertyListenerBlock)] = []
    @ObservationIgnored private var running = false
    /// The state found at start-up is shown, not announced as a change.
    @ObservationIgnored private var announce = false

    func start() {
        guard !running else { return }
        running = true
        if let t = AudioHAL.listen(AudioObjectID(kAudioObjectSystemObject), AudioHAL.address(kAudioHardwarePropertyDefaultInputDevice), { [weak self] in
            self?.bindMicrophone()
        }) { audioTokens.append(t) }
        bindMicrophone()
        var devicesAddr = Self.cmio(CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices))
        let block: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in MainActor.assumeIsolated { self?.bindCameras() } }
        if CMIOObjectAddPropertyListenerBlock(CMIOObjectID(kCMIOObjectSystemObject), &devicesAddr, .main, block) == noErr {
            cameraTokens.append((CMIOObjectID(kCMIOObjectSystemObject), devicesAddr, block))
        }
        bindCameras()
        announce = true
    }

    func stop() {
        announce = false
        audioTokens.forEach(AudioHAL.remove)
        audioTokens.removeAll()
        removeCameraTokens(all: true)
        running = false
        cameraActive = false
        microphoneActive = false
    }

    // MARK: Microphone

    private let micRunning = AudioHAL.address(kAudioDevicePropertyDeviceIsRunningSomewhere)
    @ObservationIgnored private var micToken: (AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)?

    private func bindMicrophone() {
        if let micToken { AudioHAL.remove(micToken) }
        micToken = nil
        guard let device = AudioHAL.defaultDevice(input: true) else { setMic(false); return }
        micToken = AudioHAL.listen(device, micRunning) { [weak self] in self?.readMicrophone(device) }
        readMicrophone(device)
    }

    private func readMicrophone(_ device: AudioObjectID) {
        setMic((AudioHAL.get(device, micRunning, UInt32(0)) ?? 0) != 0)
    }

    private func setMic(_ active: Bool) {
        guard active != microphoneActive else { return }
        microphoneActive = active
        microphoneSince = active ? Date() : nil
        islandLog.info("privacy camera=\(self.cameraActive, privacy: .public) mic=\(self.microphoneActive, privacy: .public)")
        if announce { onChange?(cameraActive, microphoneActive) }
    }

    // MARK: Cameras

    private static func cmio(_ selector: CMIOObjectPropertySelector) -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(mSelector: selector, mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                  mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
    }

    @ObservationIgnored private var cameraDevices: [CMIOObjectID] = []

    private func bindCameras() {
        removeCameraTokens(all: false)
        var addr = Self.cmio(CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices))
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &addr, 0, nil, &size) == noErr else { return }
        var devices = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &addr, 0, nil, size, &used, &devices) == noErr else { return }
        cameraDevices = devices
        for device in devices {
            var runAddr = Self.cmio(CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere))
            let block: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in MainActor.assumeIsolated { self?.readCameras() } }
            if CMIOObjectAddPropertyListenerBlock(device, &runAddr, .main, block) == noErr {
                cameraTokens.append((device, runAddr, block))
            }
        }
        readCameras()
    }

    private func readCameras() {
        let active = cameraDevices.contains { device in
            var addr = Self.cmio(CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere))
            var value: UInt32 = 0
            var used: UInt32 = 0
            return CMIOObjectGetPropertyData(device, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &used, &value) == noErr && value != 0
        }
        guard active != cameraActive else { return }
        cameraActive = active
        cameraSince = active ? Date() : nil
        islandLog.info("privacy camera=\(self.cameraActive, privacy: .public) mic=\(self.microphoneActive, privacy: .public)")
        if announce { onChange?(cameraActive, microphoneActive) }
    }

    private func removeCameraTokens(all: Bool) {
        cameraTokens.removeAll { token in
            let isSystem = token.0 == CMIOObjectID(kCMIOObjectSystemObject)
            guard all || !isSystem else { return false }
            var addr = token.1
            CMIOObjectRemovePropertyListenerBlock(token.0, &addr, .main, token.2)
            return true
        }
    }
}
