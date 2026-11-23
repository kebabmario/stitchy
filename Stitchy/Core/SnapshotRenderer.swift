import AppKit
import SwiftUI

/// Development aid: `Stitchy --snapshots <dir>` renders each island state to
/// PNG with ImageRenderer and exits. Used to review the design without a
/// screen recording permission. Run the bare binary (not the .app) so no
/// notification permission is requested.
@MainActor
enum SnapshotRenderer {
    private(set) static var isRendering = false

    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshots"), i + 1 < args.count else { return false }
        isRendering = true
        let dir = URL(fileURLWithPath: args[i + 1])
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let services = AppServices()
        services.battery.start()
        services.network.start()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        services.shelf.add([URL(fileURLWithPath: "/System/Applications/Calculator.app"), URL(fileURLWithPath: "/etc/hosts"), URL(fileURLWithPath: "/Library/Desktop Pictures")])
        services.feed.add(ActivityEvent(symbol: "bolt.fill", tint: .green, title: "Charging", detail: "Power adapter", trailing: "80%"))
        services.feed.add(ActivityEvent(symbol: "timer", tint: .orange, title: "Timer Done", detail: "5 min timer finished"))
        let model = services.island

        func render(_ name: String) {
            let view = IslandRootView()
                .frame(width: IslandMetrics.panel.width, height: IslandMetrics.panel.height)
                .background(Color(white: 0.82))
                .environment(services.island).environment(services.settings).environment(services.feed)
                .environment(services.battery).environment(services.network).environment(services.nowPlaying)
                .environment(services.timer).environment(services.shelf).environment(services.downloads)
                .environment(services.notifier)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
            try? png.write(to: dir.appendingPathComponent("\(name).png"))
        }

        render("1-compact")
        model.setHovering(true); render("2-compact-hover"); model.setHovering(false)
        model.present(ActivityEvent(symbol: "bolt.fill", tint: .green, title: "Charging", detail: "96W power adapter", trailing: "82%"))
        render("3-alert")
        model.dismissAlert()
        for tab in IslandTab.allCases {
            model.expand(.click, tab: tab)
            render("4-expanded-\(tab.rawValue)")
        }
        model.collapse()
        services.timer.setDuration(25 * 60)
        services.timer.start()
        render("5-compact-timer")
        model.expand(.click, tab: .timer)
        render("6-expanded-timer-running")
        print("Snapshots written to \(dir.path)")
        return true
    }
}
