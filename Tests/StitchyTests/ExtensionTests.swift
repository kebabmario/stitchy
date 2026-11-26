// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import AppKit
import SwiftUI
import Testing
@testable import Stitchy

@Suite struct ExtensionModelTests {
    @Test func treeEditing() {
        var root = ExtComponent(kind: .container)
        let a = ExtComponent(kind: .text), box = ExtComponent(kind: .container), b = ExtComponent(kind: .number)
        let i1 = root.insert(a, into: root.id), i2 = root.insert(box, into: root.id), i3 = root.insert(b, into: box.id)
        let i4 = root.insert(ExtComponent(kind: .text), into: a.id)          // text isn't a container
        #expect(i1 && i2 && i3 && !i4)
        #expect(root.parent(of: b.id)?.0 == box.id)
        // Move b to the top level, before a.
        let moved = root.remove(b.id)!
        root.insert(moved, into: root.id, at: 0)
        #expect(root.children.map(\.id) == [b.id, a.id, box.id])
        var edited = root.find(a.id)!
        edited.text = "Hello"
        let updated = root.update(edited)
        #expect(updated && root.find(a.id)?.text == "Hello")
        let copy = box.duplicated()
        #expect(copy.id != box.id)
        #expect(root.count == 4)
    }

    @Test @MainActor func storePersistsAndDuplicates() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("stitchy-ext-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ExtensionStore(directory: dir)
        var e = store.create()
        e.name = "Weather"
        e.root.children = [ExtComponent(kind: .heading)]
        e.dataSource = DataSource(url: "https://api.example.com/v1", refreshSeconds: 120)
        store.update(e)
        let copy = store.duplicate(e.id)
        store.setEnabled(e.id, false)
        store.saveNow()

        let reloaded = ExtensionStore(directory: dir)
        #expect(reloaded.extensions.count == 2)
        #expect(reloaded.extensionNamed(e.id)?.enabled == false)
        #expect(reloaded.extensionNamed(e.id)?.dataSource?.url == "https://api.example.com/v1")
        #expect(reloaded.extensionNamed(copy!.id)?.name == "Weather Copy")
        #expect(reloaded.enabled.map(\.id) == [copy!.id])
        let raw = try String(contentsOf: dir.appendingPathComponent("extensions.json"), encoding: .utf8)
        #expect(raw.contains("\"formatVersion\" : \(StitchyExtension.formatVersion)"))
        reloaded.delete(copy!.id)
        #expect(reloaded.extensions.count == 1)
    }
}

@Suite struct ExtensionDataTests {
    let json: Any = try! JSONSerialization.jsonObject(with: Data(#"""
    {"city":"Lisbon","main":{"temp":18.5,"ok":true},"tags":["a","b"],
     "items":[{"title":"One","score":3,"img":"https://x.com/a.png"},{"title":"Two","score":5}],
     "when":"2030-01-02T10:00:00Z","nothing":null}
    """#.utf8))

    @Test func paths() {
        #expect(JSONPath.string(JSONPath.value("city", in: json)) == "Lisbon")
        #expect(JSONPath.number(JSONPath.value("main.temp", in: json)) == 18.5)
        #expect(JSONPath.string(JSONPath.value("main.ok", in: json)) == "true")
        #expect(JSONPath.string(JSONPath.value("items[1].title", in: json)) == "Two")
        #expect(JSONPath.string(JSONPath.value("tags[0]", in: json)) == "a")
        #expect(JSONPath.value("items[9].title", in: json) == nil)          // missing index
        #expect(JSONPath.value("nope.deeper", in: json) == nil)             // missing key
        #expect(JSONPath.value("nothing", in: json) == nil)                 // null
        #expect(JSONPath.date(JSONPath.value("when", in: json)) != nil)
        #expect(JSONPath.segments("a[0][1].b") == [.key("a"), .index(0), .index(1), .key("b")])
    }

    @Test func discovery() {
        let root = JSONField.discover(json)
        let names = root.children.map(\.name)
        #expect(names == ["city", "items", "main", "nothing", "tags", "when"])
        let items = root.children.first { $0.name == "items" }!
        #expect(items.kind == .array && items.count == 2)
        let title = items.children.first { $0.name == "title" }!
        #expect(title.path == "items[0].title" && title.itemPath == "title" && title.sample == "One")
        #expect(items.children.first { $0.name == "img" }?.suggestedComponent == .image)
        #expect(root.children.first { $0.name == "main" }?.children.first { $0.name == "ok" }?.kind == .bool)
        #expect(root.children.first { $0.name == "nothing" }?.kind == .null)
        #expect(root.children.first { $0.name == "when" }?.suggestedComponent == .date)
        #expect(items.suggestedComponent == .list)
    }

    @Test func fetcherRules() throws {
        #expect(throws: ExtensionFetcher.Failure.self) { try ExtensionFetcher.request(for: DataSource(url: "http://example.com"), token: nil) }
        #expect(throws: ExtensionFetcher.Failure.self) { try ExtensionFetcher.request(for: DataSource(url: "file:///etc/passwd"), token: nil) }
        #expect(throws: ExtensionFetcher.Failure.self) { try ExtensionFetcher.request(for: DataSource(url: "not a url"), token: nil) }
        #expect((try? ExtensionFetcher.request(for: DataSource(url: "http://localhost:8080/x"), token: nil)) != nil)

        var s = DataSource(url: "https://api.example.com/v1?a=1")
        s.query = [.init(key: "q", value: "rain"), .init(key: "", value: "skip")]
        s.auth = .bearer
        let r = try ExtensionFetcher.request(for: s, token: "secret")
        #expect(r.url?.absoluteString == "https://api.example.com/v1?a=1&q=rain")
        #expect(r.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
        #expect(r.httpMethod == "GET")
        s.auth = .apiKeyQuery
        s.authName = "key"
        #expect(try ExtensionFetcher.request(for: s, token: "k1").url?.absoluteString.hasSuffix("&key=k1") == true)
        #expect(throws: ExtensionFetcher.Failure.notJSON) { try ExtensionFetcher.parse(Data("<html>".utf8)) }
        #expect(throws: ExtensionFetcher.Failure.tooLarge) { try ExtensionFetcher.parse(Data(count: ExtensionFetcher.maxBytes + 1)) }
    }
}

@Suite struct ExtensionRendererTests {
    @Test func helpersAreSafe() {
        let now = Date(timeIntervalSince1970: 0)
        #expect(ExtComponentView.countdown(to: now, now: now) == "Now")
        #expect(ExtComponentView.countdown(to: now.addingTimeInterval(65), now: now) == "1:05")
        #expect(ExtComponentView.countdown(to: now.addingTimeInterval(3 * 86_400 + 7200), now: now) == "3d 2h")
        #expect(ExtComponentView.imageURL("http://example.com/a.png") == nil)
        #expect(ExtComponentView.imageURL("file:///etc/passwd") == nil)
        #expect(ExtComponentView.imageURL("https://example.com/a.png") != nil)
        #expect(ExtComponentView.linkURL("javascript:alert(1)", value: nil) == nil)
        #expect(ExtComponentView.linkURL("", value: "file:///tmp") == nil)
        #expect(ExtComponentView.linkURL("https://x.com/s?q={value}", value: "a b")?.absoluteString == "https://x.com/s?q=a%20b")
    }
}

@Suite struct ExtensionAutomationTests {
    private func doc(_ json: String) -> JSONDoc { JSONDoc(root: try! JSONSerialization.jsonObject(with: Data(json.utf8))) }

    @Test func conditions() {
        let d = doc(#"{"price": 105.5, "status": "Online", "ok": true, "name": "BTC"}"#)
        func c(_ path: String, _ op: ExtAutomation.Op, _ v: String = "") -> Bool {
            ExtAutomation.holds(.init(path: path, op: op, value: v), doc: d.root, previous: nil)
        }
        #expect(c("price", .greater, "100"))
        #expect(!c("price", .less, "100"))
        #expect(c("status", .equals, "online"))
        #expect(c("status", .contains, "lin"))
        #expect(c("ok", .isTrue))
        #expect(c("missing", .missing))
        #expect(!c("name", .changes))
        #expect(ExtAutomation.fill("{name} at {price}, {nope}", doc: d.root) == "BTC at 105.5, –")
    }

    @MainActor @Test func engineIsEdgeTriggeredWithCooldown() {
        var ext = StitchyExtension.blank()
        var a = ExtAutomation()
        a.conditions = [.init(path: "v", op: .greater, value: "10")]
        a.title = "High {v}"
        a.cooldownMinutes = 5
        ext.automations = [a]
        let engine = ExtensionAutomationEngine()
        let t0 = Date(timeIntervalSince1970: 0)
        let baseline = engine.evaluate(ext, doc: doc(#"{"v": 1}"#), now: t0)
        let rise = engine.evaluate(ext, doc: doc(#"{"v": 20}"#), now: t0)
        let stay = engine.evaluate(ext, doc: doc(#"{"v": 30}"#), now: t0.addingTimeInterval(600))
        let dip = engine.evaluate(ext, doc: doc(#"{"v": 1}"#), now: t0.addingTimeInterval(700))
        let tooSoon = engine.evaluate(ext, doc: doc(#"{"v": 50}"#), now: t0.addingTimeInterval(100))
        let again = engine.evaluate(ext, doc: doc(#"{"v": 1}"#), now: t0.addingTimeInterval(800))
        let later = engine.evaluate(ext, doc: doc(#"{"v": 60}"#), now: t0.addingTimeInterval(900))
        #expect(baseline.isEmpty)
        #expect(rise.map(\.title) == ["High 20"])
        #expect(stay.isEmpty)
        #expect(dip.isEmpty)
        #expect(tooSoon.isEmpty)
        #expect(again.isEmpty)
        #expect(later.map(\.title) == ["High 60"])
    }

    @Test func oldFilesDecodeWithoutAutomations() throws {
        let v1 = try JSONEncoder().encode(StitchyExtension.blank())
        var obj = try JSONSerialization.jsonObject(with: v1) as! [String: Any]
        obj["automations"] = nil
        obj["formatVersion"] = 1
        let decoded = try JSONDecoder().decode(StitchyExtension.self, from: JSONSerialization.data(withJSONObject: obj))
        #expect(decoded.automations.isEmpty)
    }
}

@Suite struct ExtensionShareTests {
    @Test func exportDropsSecretsAndImportArrivesOff() throws {
        var ext = StitchyExtension.blank(named: "Weather")
        var s = DataSource()
        s.url = "https://user:pw@api.example.com/v1?city=Paris&api_key=SECRET1"
        s.headers = [.init(key: "Authorization", value: "Bearer SECRET2"), .init(key: "Accept", value: "application/json")]
        s.query = [.init(key: "appid", value: "x"), .init(key: "token", value: "SECRET3")]
        ext.dataSource = s
        var a = ExtAutomation()
        a.enabled = true
        ext.automations = [a]
        let data = try ExtensionShare.exportData(ext)
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("SECRET"))
        #expect(!text.contains("pw@"))
        #expect(text.contains("city=Paris"))
        #expect(text.contains("application\\/json") || text.contains("application/json"))

        let imported = try ExtensionShare.importData(data)
        #expect(imported.id != ext.id)
        #expect(!imported.enabled)
        #expect(imported.automations.allSatisfy { !$0.enabled })
        #expect(imported.name == "Weather")
    }

    @Test func importRejectsJunk() {
        #expect(throws: ExtensionShare.Failure.unreadable) { try ExtensionShare.importData(Data("{}".utf8)) }
        #expect(throws: ExtensionShare.Failure.tooLarge) { try ExtensionShare.importData(Data(count: ExtensionShare.maxImportBytes + 1)) }
    }
}

@Suite struct ExtensionIconTests {
    @MainActor @Test func iconListAndImages() throws {
        #expect(ExtensionEditorView.icons.count >= 70)
        #expect(ExtensionEditorView.icons.first == ExtIconImage.rocket)
        #expect(ExtIconImage.normalized(Data("not an image".utf8)) == nil)
        let src = NSImage(size: NSSize(width: 300, height: 100), flipped: false) { r in NSColor.systemPink.setFill(); r.fill(); return true }
        let tiff = try #require(src.tiffRepresentation)
        let png = try #require(ExtIconImage.normalized(tiff))
        let out = try #require(NSBitmapImageRep(data: png))
        #expect(out.pixelsWide == 128 && out.pixelsHigh == 128)
        #expect(png.count <= ExtIconImage.maxBytes)
        if let dir = ProcessInfo.processInfo.environment["STITCHY_PREVIEW_OUT"] {
            let r = ImageRenderer(content: RocketShape().fill(Color.white, style: FillStyle(eoFill: true)).frame(width: 120, height: 120).padding(20).background(Color.purple))
            try r.nsImage?.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:]) }?
                .write(to: URL(fileURLWithPath: dir).appendingPathComponent("rocket.png"))
        }
    }
}

@Suite struct ExtensionSourcesTests {
    @Test func templatesAndCombinedPaths() throws {
        let primary = try JSONSerialization.jsonObject(with: Data(#"{"results":[{"net":"2026-11-27T08:35:00Z","pad":{"latitude":34.6}}]}"#.utf8))
        let weather = try JSONSerialization.jsonObject(with: Data(#"{"hourly":{"precipitation_probability":[20]}}"#.utf8))
        let combo = ExtSources(primary: primary, extras: ["weather": weather])
        #expect(ExtTemplate.resolve("{results[0].pad.latitude}", root: combo) == "34.6")
        #expect(ExtTemplate.resolve("{results[0].net|hour}", root: combo) == "2026-11-27T08:00")
        #expect(ExtTemplate.resolve("{results[0].net|date}", root: combo) == "2026-11-27")
        #expect(ExtTemplate.resolve("{nope}", root: combo) == nil)
        #expect(JSONPath.number(JSONPath.value("$weather.hourly.precipitation_probability[0]", in: combo)) == 20)
        #expect(JSONPath.number(JSONPath.value("results[0].pad.latitude", in: combo)) == 34.6)
        let fields = JSONField.discover(combo)
        #expect(fields.children.contains { $0.path == "$weather" })
        // Cache round-trip keeps both parts.
        let data = try JSONSerialization.data(withJSONObject: combo.cacheObject)
        let back = try ExtensionFetcher.parse(data)
        #expect(JSONPath.number(JSONPath.value("$weather.hourly.precipitation_probability[0]", in: back.root)) == 20)
        #expect(ExtraSource.cleanName("My Weather!") == "myweather")
    }

    @Test func olderComponentsDecode() throws {
        let json = #"{"id":"6F0C2C1E-1B7B-4C38-9E57-5E4B7F3B7A11","kind":"ring","maximum":50}"#
        let c = try JSONDecoder().decode(ExtComponent.self, from: Data(json.utf8))
        #expect(c.kind == .ring && c.maximum == 50 && !c.invert && c.children.isEmpty)
    }
}

@Suite struct ExtensionFeedTests {
    let rss = #"""
    <?xml version="1.0"?><rss version="2.0" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:media="http://search.yahoo.com/mrss/"><channel><title>T</title>
    <item><title>First &amp; best</title><link>https://ex.com/1</link><dc:creator><![CDATA[Ann]]></dc:creator><pubDate>Wed, 25 Nov 2026 12:00:28 +0000</pubDate>
    <category><![CDATA[AI]]></category><category>Science</category><description><![CDATA[<p>Hello <b>world</b> &#8230;</p><img src="https://ex.com/a.jpg?x=1&amp;y=2">]]></description>
    <media:content url="https://ex.com/m.jpg" medium="image"/></item>
    <item><title>Second</title><link>https://ex.com/2</link><pubDate>Tue, 24 Nov 2026 08:00:00 GMT</pubDate></item></channel></rss>
    """#
    let atom = #"""
    <?xml version="1.0"?><feed xmlns="http://www.w3.org/2005/Atom"><title>V</title>
    <entry><title type="html"><![CDATA[Only entry]]></title><link rel="alternate" href="https://v.com/1"/><published>2026-11-25T08:00:00-05:00</published>
    <category term="Tech"/><author><name>Bo</name></author></entry></feed>
    """#

    @Test func parsesRSSAndAtom() throws {
        let r = try ExtensionFetcher.parse(Data(rss.utf8)).root
        #expect(JSONPath.string(JSONPath.value("rss.channel.item[0].title", in: r)) == "First & best")
        #expect(JSONPath.string(JSONPath.value("rss.channel.item[0].dc:creator", in: r)) == "Ann")
        #expect(JSONPath.string(JSONPath.value("rss.channel.item[0].category[0]", in: r)) == "AI")
        #expect(JSONPath.string(JSONPath.value("rss.channel.item[0].description", in: r)) == "Hello world …")
        #expect(JSONPath.string(JSONPath.value("rss.channel.item[0].description.#image", in: r)) == "https://ex.com/a.jpg?x=1&y=2")
        #expect(JSONPath.string(JSONPath.value("rss.channel.item[0].media:content.@url", in: r)) == "https://ex.com/m.jpg")
        #expect(JSONPath.date(JSONPath.value("rss.channel.item[1].pubDate", in: r)) != nil)
        let a = try ExtensionFetcher.parse(Data(atom.utf8)).root
        #expect(JSONPath.string(JSONPath.value("feed.entry.title", in: a)) == "Only entry")
        #expect(JSONPath.string(JSONPath.value("feed.entry.link[0].@href ?? feed.entry.link.@href", in: a)) == "https://v.com/1")
        #expect(JSONPath.string(JSONPath.value("feed.entry.category[0].@term ?? feed.entry.category.@term", in: a)) == "Tech")
        #expect(ExtXML.parse(Data("{not xml".utf8)) == nil)
        let entity = #"<?xml version="1.0"?><!DOCTYPE r [<!ENTITY x SYSTEM "file:///etc/passwd">]><r>&x;</r>"#
        #expect(!(JSONPath.string(JSONPath.value("r", in: ExtXML.parse(Data(entity.utf8)))) ?? "").contains("root:"))
    }

    @Test func mergesSortsAndDedupes() throws {
        let hn = try JSONSerialization.jsonObject(with: Data(#"{"hits":[{"title":"First & Best!","created_at":"2026-11-25T13:00:00Z"},{"title":"Old","created_at":"2026-11-20T00:00:00Z"}]}"#.utf8))
        let feed = try ExtensionFetcher.parse(Data(rss.utf8)).root
        let scope = ExtSources(primary: [String: Any](), extras: ["hn": hn, "ars": feed])
        var list = ExtComponent(kind: .list)
        list.binding = "Hacker News = $hn.hits, Ars = $ars.rss.channel.item"
        list.sortBy = "created_at ?? pubDate"
        list.dedupeBy = "title"
        list.maxItems = 10
        let rows = ExtComponentView.listRows(list, scope: scope)
        let titles = rows.map { JSONPath.string(JSONPath.value("title", in: $0)) ?? "" }
        let sources = rows.map { JSONPath.string(JSONPath.value("@source", in: $0)) ?? "" }
        #expect(titles == ["First & Best!", "Second", "Old"])
        #expect(sources == ["Hacker News", "Ars", "Hacker News"])
    }

    @Test func templatesStayInsideTheURLPath() throws {
        let data = try JSONSerialization.jsonObject(with: Data(#"{"id":123,"evil":"../x","host":"evil.com","repo":"a/b"}"#.utf8))
        #expect(ExtTemplate.resolveURL("https://hn.example/v0/item/{id}.json", root: data) == "https://hn.example/v0/item/123.json")
        #expect(ExtTemplate.resolveURL("https://hn.example/{evil}", root: data) == nil)
        #expect(ExtTemplate.resolveURL("https://hn.example/{repo}", root: data) == nil)
        #expect(ExtTemplate.resolveURL("https://{host}/x", root: data) == nil)
        let now = Date(timeIntervalSince1970: 1_795_600_000)
        #expect(ExtTemplate.resolve("created:>{@now|date-7}", root: nil, now: now) == "created:>2026-11-18")
        #expect(ExtTemplate.resolve("t>{@now|unix-2}", root: nil, now: now) == "t>\(1_795_600_000 - 172_800)")
        #expect(ExtComponentView.linkURL("{link ?? url}", value: nil, scope: ["url": "https://a.com/x"]) == URL(string: "https://a.com/x"))
        #expect(ExtComponentView.linkURL("{link}", value: nil, scope: ["link": "javascript:alert(1)"]) == nil)
    }

    @Test func oldStylesDecode() throws {
        let s = try JSONDecoder().decode(ExtStyle.self, from: Data(#"{"fontSize":20}"#.utf8))
        #expect(s.fontSize == 20 && s.lineLimit == nil && s.spacing == 8)
    }
}

@Suite struct ExtensionShareTemplateTests {
    @Test func exportKeepsURLTemplates() throws {
        var e = StitchyExtension.blank()
        e.dataSource = DataSource(url: "https://a.com/x")
        var x = ExtraSource(name: "item")
        x.source.url = "https://a.com/item/{[0]}.json"
        e.extraSources = [x]
        let back = try ExtensionShare.importData(ExtensionShare.exportData(e))
        #expect(back.extraSources.first?.source.url == "https://a.com/item/{[0]}.json")
    }
}
