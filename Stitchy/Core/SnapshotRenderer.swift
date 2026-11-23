import AppKit
import SwiftUI

/// Development aid: `Stitchy --snapshots <dir>` renders each island state to
/// PNG with ImageRenderer and exits. Used to review the design without a
/// Screen Recording permission. Run the bare binary (not the .app) so no
/// notification permission is requested. A grey band stands in for the
/// menu bar so the attachment to the top edge is visible.
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
        services.island.menuBarHeight = 30
        services.shelf.add([URL(fileURLWithPath: "/System/Applications/Calculator.app"), URL(fileURLWithPath: "/etc/hosts")])
        services.feed.add(ActivityEvent(symbol: "bolt.fill", tint: .green, title: "Charging", detail: "Power adapter", trailing: "80%"))
        services.clipboard.record(.init(content: .text("https://developer.apple.com/documentation/swiftui"), sourceApp: "Safari"))
        services.clipboard.record(.init(content: .text("let island = NotchShape(shoulder: 8, bottomRadius: 12)"), sourceApp: "Xcode"))
        services.notes.create("Groceries\nOat milk, coffee, lemons")
        let model = services.island

        func render(_ name: String) {
            let view = ZStack(alignment: .top) {
                Color(white: 0.86)
                Color(white: 0.74).frame(height: 30)  // menu bar stand-in
                IslandRootView()
            }
            .frame(width: IslandGeometry.panel.width, height: IslandGeometry.panel.height)
            .stitchyEnvironment(services)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
            try? png.write(to: dir.appendingPathComponent("\(name).png"))
        }

        render("01-compact")
        model.setHovering(true); render("02-hover"); model.setHovering(false)
        model.present(ActivityEvent(symbol: "bolt.fill", tint: .green, title: "Charging", detail: "96W power adapter", trailing: "82%"))
        render("03-alert")
        model.dismissAlert()
        model.showHUD(HUDEvent(symbol: "speaker.wave.3.fill", title: "MacBook Speakers", level: 0.62))
        render("04-hud")
        RunLoop.main.run(until: Date().addingTimeInterval(1.8))
        services.timers.addCountdown(seconds: 25 * 60, label: "Tea")
        services.timers.stopwatch.start()
        render("05-live-timer")
        for tab in IslandTab.allCases {
            model.expand(.click, tab: tab)
            render("06-expanded-\(tab.rawValue)")
        }
        print("Snapshots written to \(dir.path)")
        return true
    }
}
