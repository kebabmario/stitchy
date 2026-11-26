// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit

/// Shows the island above the macOS lock screen.
///
/// Adapted from SkyLightWindow by Lakr Aream (MIT, see
/// ThirdParty/SkyLightWindow-LICENSE): https://github.com/Lakr233/SkyLightWindow
///
/// ⚠️ Private API. SkyLight has no headers or documentation; these are the
/// functions WindowServer itself uses. Stitchy creates one WindowServer
/// "space" at the level Notification Center uses on the lock screen and
/// moves the island panel into it. It does not touch the login window or
/// authentication in any way. Every symbol is checked, so if a future macOS
/// removes one, the feature simply turns itself off instead of crashing.
@MainActor
final class LockScreenPresenter {
    private typealias MainConnectionID = @convention(c) () -> Int32
    private typealias SpaceCreate = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias SpaceSetAbsoluteLevel = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias ShowSpaces = @convention(c) (Int32, CFArray) -> Int32
    private typealias AddWindowsToSpace = @convention(c) (Int32, Int32, CFArray, Int32) -> Int32

    /// kSLSSpaceAbsoluteLevelNotificationCenterAtScreenLock
    private static let lockScreenLevel: Int32 = 400

    private let connection: Int32
    private let space: Int32
    private let addWindows: AddWindowsToSpace
    private let showSpaces: ShowSpaces
    private(set) var attachedWindows: Set<Int> = []

    static let shared = LockScreenPresenter()

    private init?() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", RTLD_NOW),
              let mainID = dlsym(handle, "SLSMainConnectionID"),
              let create = dlsym(handle, "SLSSpaceCreate"),
              let setLevel = dlsym(handle, "SLSSpaceSetAbsoluteLevel"),
              let show = dlsym(handle, "SLSShowSpaces"),
              let add = dlsym(handle, "SLSSpaceAddWindowsAndRemoveFromSpaces") else {
            islandLog.error("lockscreen: SkyLight symbols unavailable; feature disabled")
            return nil
        }
        connection = unsafeBitCast(mainID, to: MainConnectionID.self)()
        space = unsafeBitCast(create, to: SpaceCreate.self)(connection, 1, 0)
        let levelResult = unsafeBitCast(setLevel, to: SpaceSetAbsoluteLevel.self)(connection, space, Self.lockScreenLevel)
        let showResult = unsafeBitCast(show, to: ShowSpaces.self)(connection, [space] as CFArray)
        addWindows = unsafeBitCast(add, to: AddWindowsToSpace.self)
        showSpaces = unsafeBitCast(show, to: ShowSpaces.self)
        islandLog.info("lockscreen: space \(self.space, privacy: .public) level=\(levelResult, privacy: .public) show=\(showResult, privacy: .public)")
    }

    /// Shows the lock-screen space again (macOS may hide it when the login
    /// prompt wakes, e.g. after a key press).
    func reshowSpace() { _ = showSpaces(connection, [space] as CFArray) }

    /// Moves the window into the lock-screen space. Returns false on error.
    @discardableResult
    func attach(_ window: NSWindow) -> Bool {
        guard window.windowNumber > 0 else { return false }
        window.canBecomeVisibleWithoutLogin = true   // public NSWindow API
        let result = addWindows(connection, space, [window.windowNumber] as CFArray, 7)
        islandLog.info("lockscreen: attach window \(window.windowNumber, privacy: .public) result=\(result, privacy: .public)")
        if result == 0 { attachedWindows.insert(window.windowNumber) }
        return result == 0
    }
}

/// Lock state from the system's public distributed notifications.
@MainActor
final class ScreenLockObserver: NSObject {
    var onChange: ((Bool) -> Void)?

    override init() {
        super.init()
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(self, selector: #selector(locked), name: .init("com.apple.screenIsLocked"), object: nil)
        dnc.addObserver(self, selector: #selector(unlocked), name: .init("com.apple.screenIsUnlocked"), object: nil)
    }

    @objc private func locked() { onChange?(true) }
    @objc private func unlocked() { onChange?(false) }
}
