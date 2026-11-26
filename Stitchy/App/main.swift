// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit

// Stitchy is an agent app (LSUIElement): no Dock icon, no main menu. The
// island panel and the status item are created by AppDelegate.
if SnapshotRenderer.runIfRequested() { exit(0) }

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
