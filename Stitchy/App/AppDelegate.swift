// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var services: AppServices!
    private var island: IslandWindowController!
    private var statusBar: StatusBarController!
    private var settingsWindow: SettingsWindowController?
    private var shelfService: ShelfServiceProvider?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let services = AppServices()
        self.services = services

        island = IslandWindowController(services: services)
        services.island.openSettings = { [weak self] in self?.showSettings() }

        statusBar = StatusBarController(
            isIslandVisible: { services.settings.islandVisible },
            onOpen: { [weak self] in self?.openIsland() },
            onToggleIsland: { services.settings.islandVisible.toggle() },
            onSettings: { [weak self] in self?.showSettings() }
        )

        services.start()
        let provider = ShelfServiceProvider(shelf: services.shelf, island: services.island)
        shelfService = provider
        NSApp.servicesProvider = provider
        NSUpdateDynamicServices()
        observeContinuously { [weak self] in
            guard let self else { return }
            if self.services.settings.islandVisible { self.island.show() } else { self.island.hide() }
        }
    }

    /// Re-opening the app from Finder/Spotlight while it runs shows Settings,
    /// since an agent app has no other window to bring forward.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    private func openIsland() {
        services.settings.islandVisible = true
        island.show()
        services.island.expand(.menu)
    }

    func showSettings() {
        if settingsWindow == nil { settingsWindow = SettingsWindowController(services: services) }
        settingsWindow?.show()
    }
}
