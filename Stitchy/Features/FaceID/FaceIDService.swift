@preconcurrency import AVFoundation
import LocalAuthentication
import Observation
import Security
import Vision

/// Stitchy Face ID: a camera-based *presence and similarity* experience.
///
/// What it is: when you start it, the webcam runs briefly; Vision finds a
/// face and computes an image feature print of it, which is compared with
/// the prints saved at enrollment. Everything runs on-device; frames are
/// never stored or sent anywhere, and only the numeric feature prints are
/// kept, in the Keychain.
///
/// What it is NOT: Apple Face ID. A regular RGB webcam has no depth or
/// infrared sensing and Vision's feature prints are not a face-identity
/// model, so a photo or a similar-looking person can match. It is never
/// used to authenticate anything. Protected Stitchy sections use
/// LocalAuthentication (Touch ID / password) instead; see `PrivateLock`.
@MainActor @Observable
final class FaceIDService {
    enum Phase: Equatable {
        case idle
        case enrolling(progress: Double)
        case checking
        case finished(String)
        case failed(String)
    }

    enum Match: Equatable {
        case recognized(similarity: Double)
        case notRecognized(similarity: Double)
        case noFace
    }

    private(set) var phase: Phase = .idle {
        didSet { islandLog.info("faceid \(String(describing: self.phase), privacy: .public)") }
    }
    private(set) var cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
    private(set) var isEnrolled = FaceKeychain.load() != nil
    private(set) var cameraRunning = false
    private(set) var faceVisible = false
    private(set) var lastMatch: Match?
    let session = AVCaptureSession()
    @ObservationIgnored private let processor = FaceFrameProcessor()
    @ObservationIgnored private var configured = false

    static let enrollmentSamples = 6

    func requestCamera() async {
        if cameraStatus == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .video)
        }
        cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
    }

    /// Starts the camera. Only ever called from an explicit user action.
    func startCamera() -> Bool {
        guard cameraStatus == .authorized else { return false }
        if !configured {
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
                phase = .failed("No camera available.")
                return false
            }
            session.beginConfiguration()
            session.sessionPreset = .medium
            session.addInput(input)
            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(processor, queue: processor.queue)
            if session.canAddOutput(output) { session.addOutput(output) }
            session.commitConfiguration()
            configured = true
        }
        processor.onFace = { [weak self] visible in
            Task { @MainActor in self?.faceVisible = visible }
        }
        let session = self.session
        processor.queue.async { session.startRunning() }
        cameraRunning = true
        return true
    }

    func stopCamera() {
        let session = self.session
        processor.queue.async { session.stopRunning() }
        processor.collect(count: 0) { _ in }
        cameraRunning = false
        faceVisible = false
    }

    /// Collects several feature prints of one face and saves them.
    func enroll() async {
        guard startCamera() else { return }
        phase = .enrolling(progress: 0)
        let prints = await collect(Self.enrollmentSamples, timeout: 15) { [weak self] n in
            self?.phase = .enrolling(progress: Double(n) / Double(Self.enrollmentSamples))
        }
        stopCamera()
        guard prints.count == Self.enrollmentSamples,
              let data = try? NSKeyedArchiver.archivedData(withRootObject: prints, requiringSecureCoding: true),
              FaceKeychain.save(data) else {
            phase = .failed("Couldn't see a single face clearly. Try again in even light.")
            return
        }
        isEnrolled = true
        phase = .finished("Enrolled. Use “Check Now” to try it.")
    }

    /// One short presence + similarity check.
    @discardableResult
    func check() async -> Match {
        guard let enrolled = Self.enrolledPrints() else {
            phase = .failed("Not enrolled.")
            return .noFace
        }
        guard startCamera() else { return .noFace }
        phase = .checking
        let prints = await collect(2, timeout: 4) { _ in }
        stopCamera()
        let match = Self.compare(prints, to: enrolled)
        lastMatch = match
        switch match {
        case .noFace: phase = .finished("No face in view.")
        case .recognized(let s): phase = .finished("Looks like you (similarity \(Int(s * 100))%).")
        case .notRecognized(let s): phase = .finished("Doesn't match the enrolled face (similarity \(Int(s * 100))%).")
        }
        return match
    }

    func deleteEnrollment() {
        FaceKeychain.delete()
        isEnrolled = false
        lastMatch = nil
        phase = .idle
    }

    /// Vision observations are immutable once produced; boxed to cross threads.
    private struct Prints: @unchecked Sendable { let value: [VNFeaturePrintObservation] }

    private func collect(_ count: Int, timeout: TimeInterval, progress: @escaping @MainActor (Int) -> Void) async -> [VNFeaturePrintObservation] {
        let box: Prints = await withCheckedContinuation { continuation in
            let done = OSAllocatedFlag()
            processor.collect(count: count, progress: { n in Task { @MainActor in progress(n) } }) { prints in
                if done.set() { continuation.resume(returning: Prints(value: prints)) }
            }
            processor.queue.asyncAfter(deadline: .now() + timeout) { [processor] in
                let partial = processor.cancelCollection()
                if done.set() { continuation.resume(returning: Prints(value: partial)) }
            }
        }
        return box.value
    }

    private static func enrolledPrints() -> [VNFeaturePrintObservation]? {
        guard let data = FaceKeychain.load() else { return nil }
        return try? NSKeyedUnarchiver.unarchivedArrayOfObjects(ofClass: VNFeaturePrintObservation.self, from: data)
    }

    /// Threshold is derived from how much the enrollment samples differ from
    /// each other, so it adapts to the camera and lighting.
    nonisolated static func compare(_ probes: [VNFeaturePrintObservation], to enrolled: [VNFeaturePrintObservation]) -> Match {
        guard !probes.isEmpty, enrolled.count > 1 else { return .noFace }
        func distance(_ a: VNFeaturePrintObservation, _ b: VNFeaturePrintObservation) -> Float {
            var d: Float = .greatestFiniteMagnitude
            try? a.computeDistance(&d, to: b)
            return d
        }
        var spread: Float = 0
        for i in enrolled.indices { for j in enrolled.indices where j > i { spread = max(spread, distance(enrolled[i], enrolled[j])) } }
        let threshold = max(spread * 1.25, 0.1)
        let best = probes.flatMap { p in enrolled.map { distance(p, $0) } }.min() ?? .greatestFiniteMagnitude
        let similarity = Double(max(0, 1 - best / (threshold * 2)))
        return best <= threshold ? .recognized(similarity: similarity) : .notRecognized(similarity: similarity)
    }
}

/// Thread-safe one-shot flag.
final class OSAllocatedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    /// Returns true the first time only.
    func set() -> Bool { lock.withLock { defer { value = true }; return !value } }
}

/// Runs Vision on camera frames off the main thread. Frames are processed
/// in memory and dropped immediately.
final class FaceFrameProcessor: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "app.stitchy.faceid")
    var onFace: (@Sendable (Bool) -> Void)?
    private var target = 0
    private var prints: [VNFeaturePrintObservation] = []
    private var progress: (@Sendable (Int) -> Void)?
    private var completion: (@Sendable ([VNFeaturePrintObservation]) -> Void)?
    private var lastSample = Date.distantPast
    private var frameCounter = 0

    func collect(count: Int, progress: (@Sendable (Int) -> Void)? = nil, completion: @escaping @Sendable ([VNFeaturePrintObservation]) -> Void) {
        queue.async {
            self.target = count
            self.prints = []
            self.progress = progress
            self.completion = count == 0 ? nil : completion
        }
    }

    /// Called on `queue`. Returns whatever was collected so far.
    func cancelCollection() -> [VNFeaturePrintObservation] {
        let partial = prints
        target = 0
        completion = nil
        return partial
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        frameCounter += 1
        guard frameCounter % 3 == 0, let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let handler = VNImageRequestHandler(cvPixelBuffer: pixels, orientation: .up)
        let faces = VNDetectFaceRectanglesRequest()
        try? handler.perform([faces])
        let found = faces.results ?? []
        onFace?(found.count == 1)
        guard target > 0, found.count == 1, let face = found.first,
              Date().timeIntervalSince(lastSample) > 0.35 else { return }
        // Feature print of the face region only (expanded slightly).
        let box = face.boundingBox.insetBy(dx: -face.boundingBox.width * 0.15, dy: -face.boundingBox.height * 0.15)
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        let printRequest = VNGenerateImageFeaturePrintRequest()
        printRequest.regionOfInterest = box
        try? handler.perform([printRequest])
        guard let observation = printRequest.results?.first else { return }
        lastSample = Date()
        prints.append(observation)
        progress?(prints.count)
        if prints.count >= target {
            let result = prints
            target = 0
            completion?(result)
            completion = nil
        }
    }
}

/// Enrollment feature prints in the login Keychain (never on disk elsewhere).
enum FaceKeychain {
    private static var query: [String: Any] { [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "app.stitchy.faceid",
        kSecAttrAccount as String: "enrollment",
    ] }

    static func save(_ data: Data) -> Bool {
        delete()
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    static func load() -> Data? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        return SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess ? result as? Data : nil
    }

    static func delete() { SecItemDelete(query as CFDictionary) }
}

/// Real protection for private Stitchy sections (Notes, Clipboard):
/// LocalAuthentication with Touch ID or the account password as fallback.
@MainActor @Observable
final class PrivateLock {
    private(set) var unlockedUntil: Date?
    private(set) var lastError: String?
    @ObservationIgnored private let settings: AppSettings

    init(settings: AppSettings) { self.settings = settings }

    var isLocked: Bool {
        guard settings.privateSectionsLocked else { return false }
        return (unlockedUntil ?? .distantPast) < Date()
    }

    func unlock() async {
        let context = LAContext()
        context.localizedFallbackTitle = "Use Password"
        do {
            try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "show your private Stitchy notes and clipboard")
            unlockedUntil = Date().addingTimeInterval(5 * 60)
            lastError = nil
        } catch {
            lastError = (error as? LAError)?.code == .userCancel ? nil : error.localizedDescription
        }
    }

    func lock() { unlockedUntil = nil }
}
