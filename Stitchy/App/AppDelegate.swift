import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var services: AppServices!
    private var island: IslandWindowController!
    private var statusBar: StatusBarController!
    private var settingsWindow: SettingsWindowController?

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
