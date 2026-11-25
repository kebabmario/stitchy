import AppKit
import Foundation

/// Runs AppleScript (Apple Events) off the main thread.
///
/// Apple Events are Apple's supported way to read and control Music and
/// Spotify. They require the user's one-time Automation consent; Stitchy
/// only asks after the user opts in from the Music tab.
enum AppleScriptRunner {
    enum Failure: Error, Sendable {
        case notPermitted      // -1743: user denied Automation
        case notRunning        // -600
        case timedOut          // -1712 or watchdog: the app didn't answer in time
        case other(Int)
    }

    /// One serial queue per target app, so an unresponsive app can only
    /// stall its own requests, never Notes or Music.
    private static let state = RunnerState()

    static func run<T: Sendable>(
        _ source: String,
        timeout: Int = 4,
        parse: @escaping @Sendable (NSAppleEventDescriptor) -> T?
    ) async -> Result<T?, Failure> {
        let target = targetApp(of: source)
        if state.isBackedOff(target) { return .failure(.timedOut) }
        let queue = state.queue(for: target)
        return await withCheckedContinuation { continuation in
            let once = OSAllocatedFlag()
            // Watchdog: compiling a `tell` block fetches the app's scripting
            // dictionary, which `with timeout` doesn't cover. If the app never
            // answers, give up, and back off from it for 30 s.
            DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(timeout + 3)) {
                if once.set() {
                    state.backOff(target)
                    continuation.resume(returning: .failure(.timedOut))
                }
            }
            queue.async {
                var error: NSDictionary?
                // Never wait on an unresponsive app for AppleScript's default
                // 2 minutes.
                let bounded = "with timeout of \(timeout) seconds\n\(source)\nend timeout"
                guard let script = NSAppleScript(source: bounded) else {
                    if once.set() { continuation.resume(returning: .failure(.other(-1))) }
                    return
                }
                let result = script.executeAndReturnError(&error)
                guard once.set() else { return }
                if let error {
                    let code = error[NSAppleScript.errorNumber] as? Int ?? -1
                    switch code {
                    case -1743: continuation.resume(returning: .failure(.notPermitted))
                    case -600, -609: continuation.resume(returning: .failure(.notRunning))
                    case -1712: continuation.resume(returning: .failure(.timedOut))
                    default: continuation.resume(returning: .failure(.other(code)))
                    }
                } else {
                    continuation.resume(returning: .success(parse(result)))
                }
            }
        }
    }

    /// `tell application "Spotify"` -> "Spotify".
    static func targetApp(of source: String) -> String {
        guard let r = source.range(of: #"application "([^"]+)""#, options: .regularExpression) else { return "general" }
        return String(source[r]).replacingOccurrences(of: "application ", with: "").replacingOccurrences(of: "\"", with: "")
    }

    enum Permission: Sendable { case granted, denied, notDetermined, appNotRunning }

    /// Checks (and optionally asks for) Automation consent for `bundleID`.
    /// Asking blocks until the user answers the system prompt, so this runs
    /// on the background queue.
    static func permission(for bundleID: String, ask: Bool) async -> Permission {
        await withCheckedContinuation { continuation in
            state.queue(for: "permission").async {
                let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
                let status = AEDeterminePermissionToAutomateTarget(
                    target.aeDesc, AEEventClass(typeWildCard), AEEventID(typeWildCard), ask
                )
                switch status {
                case noErr: continuation.resume(returning: .granted)
                case OSStatus(errAEEventNotPermitted): continuation.resume(returning: .denied)
                case OSStatus(procNotFound): continuation.resume(returning: .appNotRunning)
                default: continuation.resume(returning: .notDetermined)
                }
            }
        }
    }
}

extension NSAppleEventDescriptor {
    /// 1-based list access that tolerates missing items.
    func item(_ index: Int) -> NSAppleEventDescriptor? {
        index <= numberOfItems ? atIndex(index) : nil
    }
}

/// Per-app queues and back-off bookkeeping (thread-safe).
final class RunnerState: @unchecked Sendable {
    private let lock = NSLock()
    private var queues: [String: DispatchQueue] = [:]
    private var backoff: [String: Date] = [:]

    func queue(for target: String) -> DispatchQueue {
        lock.withLock {
            if let q = queues[target] { return q }
            let q = DispatchQueue(label: "app.stitchy.applescript.\(target)", qos: .userInitiated)
            queues[target] = q
            return q
        }
    }

    func backOff(_ target: String) { lock.withLock { backoff[target] = Date().addingTimeInterval(30) } }
    func isBackedOff(_ target: String) -> Bool { lock.withLock { (backoff[target] ?? .distantPast) > Date() } }
}
