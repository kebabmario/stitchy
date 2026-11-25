import LocalAuthentication
import Observation
import Security

/// macOS owner authentication via LocalAuthentication. macOS decides the
/// method: Touch ID when available, otherwise the account password. Stitchy
/// never sees, stores or types the password.
@MainActor
enum SystemAuth {
    enum Outcome: Equatable, Sendable { case success, cancelled, failed(String) }

    /// What the island animates while an authentication runs.
    enum Phase: Equatable, Sendable { case scanning, success, failed }

    /// Set by AppServices so the island can show the Touch ID animation.
    /// macOS exposes no sensor events, so "scanning" spans the whole system prompt.
    static var onPhase: ((Phase) -> Void)?

    static var hasTouchID: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) && context.biometryType == .touchID
    }

    static var biometryDescription: String {
        hasTouchID ? "Touch ID available, password as fallback" : "Touch ID unavailable: macOS will ask for your password"
    }

    static func authenticate(reason: String) async -> Outcome {
        let context = LAContext()
        context.localizedFallbackTitle = "Use Password"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return .failed(error?.localizedDescription ?? "Authentication isn't available.")
        }
        onPhase?(.scanning)
        let outcome: Outcome
        do {
            try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            outcome = .success
        } catch let error as LAError {
            switch error.code {
            case .userCancel, .appCancel, .systemCancel, .userFallback: outcome = .cancelled
            default: outcome = .failed(error.localizedDescription)
            }
        } catch {
            outcome = .failed(error.localizedDescription)
        }
        onPhase?(outcome == .success ? .success : .failed)
        return outcome
    }

    /// Removes face data left by the old Face Unlock feature (removed).
    static func removeLegacyFaceData() {
        // No account attribute: matches every item under the old service.
        SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                       kSecAttrService as String: "app.stitchy.faceunlock"] as CFDictionary)
    }
}

/// "Require Authentication for Sensitive Actions". Every sensitive change
/// goes through `authorize`, inside the service methods themselves, so it
/// can't be skipped by opening a different settings screen.
@MainActor @Observable
final class SensitiveGate {
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private var lastSuccess: Date?
    /// One successful authentication covers related changes for a minute.
    static let grace: TimeInterval = 60
    private(set) var lastError: String?

    init(settings: AppSettings) { self.settings = settings }

    func authorize(_ reason: String) async -> Bool {
        guard settings.requireAuthForSensitive else { return true }
        if let lastSuccess, Date().timeIntervalSince(lastSuccess) < Self.grace { return true }
        switch await SystemAuth.authenticate(reason: reason) {
        case .success:
            lastSuccess = Date()
            lastError = nil
            return true
        case .cancelled:
            lastError = nil
            return false
        case .failed(let message):
            lastError = message
            return false
        }
    }

    /// Turning protection on proves ownership first; turning it off passes the gate.
    func setRequireSensitive(_ on: Bool) async {
        guard on != settings.requireAuthForSensitive else { return }
        if on {
            guard await SystemAuth.authenticate(reason: "protect sensitive Stitchy settings") == .success else { return }
            lastSuccess = Date()
        } else {
            guard await authorize("stop protecting sensitive Stitchy settings") else { return }
        }
        settings.applyAuthorized(.requireAuthForSensitive(on))
    }
}

/// Protection for private Stitchy sections (Notes, Clipboard): Touch ID or
/// the account password through macOS.
@MainActor @Observable
final class PrivateLock {
    private(set) var unlockedUntil: Date?
    private(set) var lastError: String?
    private(set) var isUnlocking = false
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let gate: SensitiveGate

    init(settings: AppSettings, gate: SensitiveGate) {
        self.settings = settings
        self.gate = gate
    }

    var isLocked: Bool {
        guard settings.privateSectionsLocked else { return false }
        return (unlockedUntil ?? .distantPast) < Date()
    }

    func unlock() async {
        guard !isUnlocking else { return }
        isUnlocking = true
        defer { isUnlocking = false }
        switch await SystemAuth.authenticate(reason: "show your private Stitchy notes and clipboard") {
        case .success:
            unlockedUntil = Date().addingTimeInterval(5 * 60)
            lastError = nil
        case .cancelled: lastError = nil
        case .failed(let message): lastError = message
        }
    }

    func lock() { unlockedUntil = nil }

    /// Locking is free; removing the lock is a sensitive action.
    func setLocking(_ on: Bool) async {
        if !on, !(await gate.authorize("turn off the private sections lock")) { return }
        settings.applyAuthorized(.privateSectionsLocked(on))
        if on { lock() }
    }
}
