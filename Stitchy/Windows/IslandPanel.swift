// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import SwiftUI

/// Borderless, transparent, non-activating panel that hosts the island.
///
/// - Non-activating: clicking the island never brings Stitchy forward or
///   steals focus from the app you're using.
/// - It only becomes key while the island is pinned open by a click, so the
///   Escape key can dismiss it; it hands focus back on collapse.
/// - Status-bar level so it draws over the (empty) centre of the menu bar.
final class IslandPanel: NSPanel {
    var allowsKey = false

    init(size: CGSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .none
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        ignoresMouseEvents = true
    }

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }

    /// Borderless windows may sit over the menu bar; don't let AppKit push us down.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Hosting view that accepts the first click, so controls respond even
/// though Stitchy is never the active app.
final class IslandHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
