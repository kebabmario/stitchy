import AppKit
import SwiftUI

/// Native preferences window: toolbar tabs via NSTabViewController, each
/// page a SwiftUI grouped Form.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    init(services: AppServices) {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        func page(_ title: String, _ symbol: String, height: CGFloat, _ view: some View) {
            let host = NSHostingController(rootView: view
                .environment(services.settings)
                .environment(services.nowPlaying)
                .environment(services.notifier)
                .environment(services.downloads)
                .frame(width: 500, height: height))
            host.sizingOptions = [.preferredContentSize]
            let item = NSTabViewItem(viewController: host)
            item.label = title
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            tabs.addTabViewItem(item)
        }
        page("General", "gearshape", height: 330, GeneralSettingsView())
        page("Island", "capsule", height: 560, IslandSettingsView())
        page("Features", "square.grid.2x2", height: 500, FeaturesSettingsView())
        page("Permissions", "hand.raised", height: 430, PermissionsSettingsView())

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
