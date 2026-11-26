// SPDX-License-Identifier: GPL-3.0-or-later
import CoreAudio
import IOKit.pwr_mgt
import Observation

/// Keep Awake (IOPM assertion) and microphone mute (CoreAudio input mute).
@MainActor @Observable
final class SystemControls {
    private(set) var keepAwakeUntil: Date?
    private(set) var isKeepingAwake = false
    private(set) var micMuted = false
    @ObservationIgnored private var assertion: IOPMAssertionID = 0
    @ObservationIgnored private var expiry: Task<Void, Never>?

    /// nil duration = until turned off. The display may dim but won't sleep.
    func keepAwake(for duration: TimeInterval?) {
        stopKeepingAwake()
        let reason = "Stitchy Keep Awake" as CFString
        guard IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                          IOPMAssertionLevel(kIOPMAssertionLevelOn), reason, &assertion) == kIOReturnSuccess else { return }
        isKeepingAwake = true
        if let duration {
            keepAwakeUntil = Date().addingTimeInterval(duration)
            expiry = Task { [weak self] in
                try? await Task.sleep(for: .seconds(duration))
                guard !Task.isCancelled else { return }
                self?.stopKeepingAwake()
            }
        }
    }

    /// "Awake · 42 min left", "Awake · 1 h 05 min left" or "Awake until turned off".
    nonisolated static func awakeText(until: Date?, now: Date) -> String {
        guard let until else { return "Awake until turned off" }
        let minutes = max(Int((until.timeIntervalSince(now) / 60).rounded(.up)), 0)
        return minutes >= 60 ? String(format: "Awake · %d h %02d min left", minutes / 60, minutes % 60) : "Awake · \(minutes) min left"
    }

    func stopKeepingAwake() {
        expiry?.cancel()
        expiry = nil
        if isKeepingAwake { IOPMAssertionRelease(assertion) }
        isKeepingAwake = false
        keepAwakeUntil = nil
    }

    // MARK: Microphone

    private let muteAddr = AudioHAL.address(kAudioDevicePropertyMute, kAudioDevicePropertyScopeInput)

    func refreshMic() {
        guard let device = AudioHAL.defaultDevice(input: true) else { return }
        micMuted = (AudioHAL.get(device, muteAddr, UInt32(0)) ?? 0) != 0
    }

    /// Mutes the default input device for every app. Returns false when the
    /// device has no settable mute control.
    @discardableResult
    func setMicMuted(_ muted: Bool) -> Bool {
        guard let device = AudioHAL.defaultDevice(input: true) else { return false }
        var addr = muteAddr
        var settable: DarwinBoolean = false
        guard AudioObjectHasProperty(device, &addr),
              AudioObjectIsPropertySettable(device, &addr, &settable) == noErr, settable.boolValue else { return false }
        var value: UInt32 = muted ? 1 : 0
        let ok = AudioObjectSetPropertyData(device, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr
        refreshMic()
        return ok
    }
}
