// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit

/// The menu bar presence: Open, Show/Hide Island, Settings, Quit.
@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let isIslandVisible: () -> Bool
    private let onOpen: () -> Void
    private let onToggleIsland: () -> Void
    private let onSettings: () -> Void
    private let toggleItem = NSMenuItem(title: "Hide Island", action: #selector(toggleIsland), keyEquivalent: "")

    init(
        isIslandVisible: @escaping () -> Bool,
        onOpen: @escaping () -> Void,
        onToggleIsland: @escaping () -> Void,
        onSettings: @escaping () -> Void
    ) {
        self.isIslandVisible = isIslandVisible
        self.onOpen = onOpen
        self.onToggleIsland = onToggleIsland
        self.onSettings = onSettings
        super.init()

        let image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "Stitchy")
        image?.isTemplate = true
        item.button?.image = image
        item.button?.toolTip = "Stitchy"

        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(makeItem("Open Stitchy", #selector(open)))
        toggleItem.target = self
        menu.addItem(toggleItem)
        menu.addItem(.separator())
        menu.addItem(makeItem("Settings…", #selector(settings), key: ","))
        menu.addItem(.separator())
        menu.addItem(makeItem("Quit Stitchy", #selector(quit), key: "q"))
        item.menu = menu
    }

    private func makeItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: key)
        menuItem.target = self
        return menuItem
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        toggleItem.title = isIslandVisible() ? "Hide Island" : "Show Island"
    }

    @objc private func open() { onOpen() }
    @objc private func toggleIsland() { onToggleIsland() }
    @objc private func settings() { onSettings() }
    @objc private func quit() { NSApp.terminate(nil) }
}
