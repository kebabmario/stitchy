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

    static let weatherFixture = """
    {"utc_offset_seconds":0,"current":{"temperature_2m":18.6,"apparent_temperature":17.9,"relative_humidity_2m":64,"weather_code":2,"wind_speed_10m":11.0,"is_day":1},
     "hourly":{"time":["2030-01-01T10:00","2030-01-01T11:00","2030-01-01T12:00","2030-01-01T13:00","2030-01-01T14:00","2030-01-01T15:00","2030-01-01T16:00","2030-01-01T17:00"],
     "temperature_2m":[18.6,19.4,20.1,20.8,20.2,19.0,17.6,16.3],"precipitation_probability":[0,5,10,40,65,30,10,0],"weather_code":[2,2,3,61,63,80,2,1]},
     "daily":{"time":["2030-01-01","2030-01-02","2030-01-03","2030-01-04","2030-01-05"],"weather_code":[2,61,0,3,80],
     "temperature_2m_max":[21.0,17.0,24.0,19.0,16.0],"temperature_2m_min":[13.0,11.0,14.0,12.0,9.0],"precipitation_probability_max":[65,90,0,20,70],
     "sunrise":["2030-01-01T07:51","2030-01-02T07:51","2030-01-03T07:51","2030-01-04T07:51","2030-01-05T07:51"],
     "sunset":["2030-01-01T17:26","2030-01-02T17:27","2030-01-03T17:28","2030-01-04T17:29","2030-01-05T17:30"],"uv_index_max":[4.2,2.0,5.5,3.1,1.8]}}
    """

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

        // Preview data (no network, no real accounts).
        let art = NSImage(size: NSSize(width: 300, height: 300), flipped: false) { r in
            NSGradient(colors: [.systemPink, .systemPurple, .systemIndigo])!.draw(in: r, angle: -45)
            NSColor.white.withAlphaComponent(0.25).setFill(); NSBezierPath(ovalIn: r.insetBy(dx: 70, dy: 70)).fill(); return true
        }
        services.nowPlaying.loadPreview(.init(id: "p", title: "Midnight Drive", artist: "Neon Coast", album: "Afterglow", duration: 214), artwork: art)
        services.lyrics.loadPreview([.init(time: 40, text: "Streetlights fading out behind us"), .init(time: 45, text: "We were chasing every signal"),
                                     .init(time: 50, text: "Turn the radio up, don't look back"), .init(time: 55, text: "Till the morning finds us"),
                                     .init(time: 60, text: "Somewhere past the coastline")])
        services.weather.loadPreview(Data(Self.weatherFixture.utf8), place: .init(name: "Lisbon", latitude: 38.7, longitude: -9.1))
        services.settings.weatherEnabled = true
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
        model.expand(.click, tab: .music)
        model.lyricsExpanded = true
        render("09-lyrics-expanded")
        model.collapse()
        services.timers.stopAll()
        render("10-compact-lyric-strip")
        services.settings.style = .island
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        render("07-island-compact")
        model.expand(.click, tab: .home)
        render("08-island-expanded")
        services.settings.style = .notch
        print("Snapshots written to \(dir.path)")
        return true
    }
}
