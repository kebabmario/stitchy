import AppKit
import Foundation

/// Runs AppleScript (Apple Events) off the main thread.
///
/// Apple Events are Apple's supported way to read and control Music and
/// Spotify. They require the user's one-time Automation consent; Stitchy
/// only asks after the user opts in from the Music tab.
enum AppleScriptRunner {
    private static let queue = DispatchQueue(label: "app.stitchy.applescript", qos: .userInitiated)

    enum Failure: Error, Sendable {
        case notPermitted      // -1743: user denied Automation
        case notRunning        // -600
        case other(Int)
    }

    static func run<T: Sendable>(
        _ source: String,
        parse: @escaping @Sendable (NSAppleEventDescriptor) -> T?
    ) async -> Result<T?, Failure> {
        await withCheckedContinuation { continuation in
            queue.async {
                var error: NSDictionary?
                guard let script = NSAppleScript(source: source) else {
                    continuation.resume(returning: .failure(.other(-1)))
                    return
                }
                let result = script.executeAndReturnError(&error)
                if let error {
                    let code = error[NSAppleScript.errorNumber] as? Int ?? -1
                    switch code {
                    case -1743: continuation.resume(returning: .failure(.notPermitted))
                    case -600, -609: continuation.resume(returning: .failure(.notRunning))
                    default: continuation.resume(returning: .failure(.other(code)))
                    }
                } else {
                    continuation.resume(returning: .success(parse(result)))
                }
            }
        }
    }

    enum Permission: Sendable { case granted, denied, notDetermined, appNotRunning }

    /// Checks (and optionally asks for) Automation consent for `bundleID`.
    /// Asking blocks until the user answers the system prompt, so this runs
    /// on the background queue.
    static func permission(for bundleID: String, ask: Bool) async -> Permission {
        await withCheckedContinuation { continuation in
            queue.async {
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
