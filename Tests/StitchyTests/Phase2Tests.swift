// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
@testable import Stitchy

struct WeatherParsingTests {
    static let fixture = """
    {"utc_offset_seconds":3600,
     "current":{"temperature_2m":12.4,"apparent_temperature":10.1,"relative_humidity_2m":81,"weather_code":61,"wind_speed_10m":14.2,"is_day":1},
     "hourly":{"time":["2030-01-01T10:00","2030-01-01T11:00"],"temperature_2m":[12.4,13.0],"precipitation_probability":[70,null],"weather_code":[61,3]},
     "daily":{"time":["2030-01-01","2030-01-02"],"weather_code":[61,0],"temperature_2m_max":[14.0,16.5],"temperature_2m_min":[8.0,7.5],"precipitation_probability_max":[80,5]}}
    """

    @Test func parsesForecast() throws {
        let (c, hours, days) = try WeatherService.parse(Data(Self.fixture.utf8), now: Date(timeIntervalSince1970: 0))
        #expect(c.temperature == 12.4 && c.humidity == 81 && c.isDay)
        #expect(hours.count == 2 && hours[0].rain == 70 && hours[1].rain == nil)
        #expect(days.map(\.high) == [14.0, 16.5])
        #expect(WeatherService.describe(61).text == "Rain")
        #expect(WeatherService.describe(0, isDay: false).symbol == "moon.stars.fill")
    }

    @Test func requestContainsOnlyCoordinatesAndUnits() {
        let url = WeatherService.url(for: .init(name: "Home", latitude: 51.5, longitude: -0.12), fahrenheit: true).absoluteString
        #expect(url.contains("latitude=51.5") && url.contains("temperature_unit=fahrenheit"))
        #expect(!url.contains("Home"))
    }

    /// Live check against Open-Meteo: STITCHY_LIVE_NET=1 Scripts/test.sh --filter liveOpenMeteo
    @Test func liveOpenMeteo() async throws {
        guard ProcessInfo.processInfo.environment["STITCHY_LIVE_NET"] == "1" else { return }
        let (c, hours, days) = try await WeatherService.fetch(.init(name: "Cupertino", latitude: 37.32, longitude: -122.03), fahrenheit: false)
        print("LIVE weather: \(c.temperature)°C code \(c.code), \(hours.count) hours, \(days.count) days")
        #expect(hours.count >= 12 && days.count == 7)
    }
}

struct BannerClassificationTests {
    @Test func message() throws {
        let r = try #require(NotificationMirror.classify(texts: ["Messages", "Alex", "Are you coming tonight?", "now"], buttonTitles: ["Close"]))
        #expect(r.kind == .message && r.app == "Messages" && r.title == "Alex" && r.body == "Are you coming tonight?")
    }

    @Test func faceTimeCallWithButtons() throws {
        let r = try #require(NotificationMirror.classify(texts: ["FaceTime", "Sam", "FaceTime Video"], buttonTitles: ["Decline", "Accept"]))
        #expect(r.kind == .call && r.title == "Sam")
        #expect(NotificationMirror.isAccept("Accept") && NotificationMirror.isDecline("Decline"))
    }

    @Test func otherAppIsOther() throws {
        let r = try #require(NotificationMirror.classify(texts: ["Script Editor", "Build finished", "All tests passed"], buttonTitles: []))
        #expect(r.kind == .other && r.app == "Script Editor" && r.title == "Build finished")
        #expect(NotificationMirror.classify(texts: ["  "], buttonTitles: []) == nil)
    }
}

@MainActor
struct ClipboardUpgradeTests {
    @Test func pinsSurviveLimitAndClear() {
        let settings = AppSettings(defaults: UserDefaults(suiteName: "stitchy.tests.\(UUID())")!)
        settings.clipboardHistorySize = 2
        let h = ClipboardHistory(settings: settings)
        h.record(.init(content: .text("keep me"), sourceApp: nil))
        h.togglePin(h.entries[0])
        for t in ["a", "b", "c"] { h.record(.init(content: .text(t), sourceApp: nil)) }
        #expect(h.entries.map(\.preview).sorted() == ["b", "c", "keep me"])
        h.clear()
        #expect(h.entries.map(\.preview) == ["keep me"])
        #expect(h.search("KEEP").count == 1 && h.search("zzz").isEmpty)
    }

    @Test func smartActions() {
        func smart(_ t: String) -> ClipboardHistory.Entry.Smart? { ClipboardHistory.Entry(content: .text(t), sourceApp: nil).smart }
        if case .link(let u) = smart("https://apple.com/mac") { #expect(u.host == "apple.com") } else { Issue.record("link") }
        if case .email = smart("me@example.com") {} else { Issue.record("email") }
        if case .color = smart("#FF8800") {} else { Issue.record("color") }
        #expect(smart("just some words") == nil)
        #expect(smart("not a link: http") == nil)
    }
}

struct NetworkCounterTests {
    @Test func rateMath() {
        let a = NetworkCounters.Sample(time: 10, received: 1_000, sent: 500)
        let b = NetworkCounters.Sample(time: 12, received: 5_000, sent: 300)    // sent counter wrapped
        let r = NetworkCounters.rate(a, b)
        #expect(r.down == 2_000 && r.up == 0)
        #expect(NetworkCounters.sample().received > 0)
    }
}
