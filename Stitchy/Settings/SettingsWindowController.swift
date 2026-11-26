// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import SwiftUI

/// Native preferences window: toolbar tabs via NSTabViewController, each
/// page a SwiftUI grouped Form.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let services: AppServices

    init(services: AppServices) {
        self.services = services
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        func page(_ title: String, _ symbol: String, height: CGFloat, _ view: some View) {
            let host = NSHostingController(rootView: view.stitchyEnvironment(services).frame(width: 540, height: height))
            // Fixed size: automatic sizing recomputed the Form's size on every
            // display cycle (measured ~5 % CPU while the island animated).
            host.sizingOptions = []
            host.preferredContentSize = NSSize(width: 540, height: height)
            let item = NSTabViewItem(viewController: host)
            item.label = title
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            tabs.addTabViewItem(item)
        }
        page("General", "gearshape", height: 400, GeneralSettingsView())
        page("Island", "rectangle.topthird.inset.filled", height: 640, IslandSettingsView())
        page("Features", "square.grid.2x2", height: 640, FeaturesSettingsView())
        page("Clipboard", "doc.on.clipboard", height: 520, ClipboardSettingsView())
        page("Launcher", "magnifyingglass", height: 460, LauncherSettingsView())
        page("Privacy", "hand.raised", height: 560, PrivacySettingsView())
        page("Extensions", "puzzlepiece.extension", height: 520, ExtensionsSettingsView())

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func show() {
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
