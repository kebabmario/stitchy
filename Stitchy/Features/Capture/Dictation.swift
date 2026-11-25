import AVFoundation
import Observation
import Speech

/// Voice to text with Apple's Speech framework. Uses on-device recognition
/// whenever the Mac supports it for the language (then no audio leaves the
/// Mac). The microphone runs only between Start and Stop.
@MainActor @Observable
final class Dictation {
    private(set) var transcript = ""
    private(set) var isRecording = false
    private(set) var isOnDevice = false
    private(set) var lastError: String?
    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored var onFinished: ((String) -> Void)?

    func toggle() { if isRecording { stop() } else { Task { await start() } } }

    func start() async {
        guard !isRecording else { return }
        lastError = nil
        let speech = await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) } }
        guard speech == .authorized else { lastError = "Allow Stitchy under Privacy & Security › Speech Recognition."; return }
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined { _ = await AVCaptureDevice.requestAccess(for: .audio) }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            lastError = "Allow Stitchy under Privacy & Security › Microphone."
            return
        }
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else { lastError = "Speech recognition isn't available right now."; return }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        isOnDevice = recognizer.supportsOnDeviceRecognition
        request.requiresOnDeviceRecognition = isOnDevice
        request.addsPunctuation = true

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
        do {
            engine.prepare()
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            lastError = "Couldn't start the microphone."
            return
        }
        transcript = ""
        self.engine = engine
        self.request = request
        isRecording = true
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let final = result?.isFinal ?? false
            Task { @MainActor in
                guard let self else { return }
                if let text { self.transcript = text }
                if final || error != nil { self.finish() }
            }
        }
    }

    /// Stops listening; the final text arrives shortly after.
    func stop() {
        guard isRecording else { return }
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        request?.endAudio()
    }

    private func finish() {
        guard isRecording else { return }
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        engine = nil
        request = nil
        task = nil
        isRecording = false
        if !transcript.isEmpty { onFinished?(transcript) }
    }
}
