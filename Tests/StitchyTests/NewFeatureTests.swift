import AppKit
import CoreAudio
import Foundation
import Testing
@testable import Stitchy

struct LyricsTests {
    @Test func parsesLRCAndFindsCurrentLine() throws {
        let lrc = """
        [ar:Someone]
        [00:01.50] First line
        [00:05.00][00:20.00] Chorus
        [00:09.25]Third
        """
        let lines = try #require(LyricsService.parseLRC(lrc))
        #expect(lines.map(\.text) == ["First line", "Chorus", "Third", "Chorus"])
        #expect(LyricsService.index(in: lines, at: 0.5) == nil)
        #expect(LyricsService.index(in: lines, at: 6) == 1)
        #expect(LyricsService.index(in: lines, at: 25) == 3)
        #expect(LyricsService.parseLRC("plain text only") == nil)
    }
}

@MainActor
struct ShelfActionTests {
    @Test func zipAndConvertCreateNewFilesAndKeepOriginals() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let text = dir.appendingPathComponent("notes.txt")
        try Data("hello".utf8).write(to: text)
        let image = NSImage(size: NSSize(width: 8, height: 8), flipped: false) { r in NSColor.red.setFill(); r.fill(); return true }
        let png = dir.appendingPathComponent("pic.png")
        try NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!.write(to: png)

        let shelf = FileShelf()
        shelf.add([text, png])
        await shelf.compress([shelf.items[0]])
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("notes.zip").path))
        await shelf.compress([shelf.items[0]])                     // second zip doesn't overwrite
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("notes 2.zip").path))
        shelf.convertImage(shelf.items[1], toPNG: false)
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("pic.jpg").path))
        #expect(FileManager.default.fileExists(atPath: text.path) && FileManager.default.fileExists(atPath: png.path))
        #expect(shelf.isImage(shelf.items[1]) && !shelf.isImage(shelf.items[0]))
    }
}

struct DeviceTests {
    @Test func bluetoothSymbols() {
        #expect(BluetoothMonitor.symbol(name: "Myrixx's AirPods Pro", major: 0x04, minor: 0) == "airpodspro")
        #expect(BluetoothMonitor.symbol(name: "Magic Keyboard", major: 0x05, minor: 0x10) == "keyboard")
        #expect(BluetoothMonitor.symbol(name: "Speaker", major: 0x04, minor: 0) == "headphones")
        #expect(BluetoothMonitor.symbol(name: "Thing", major: 0x1F, minor: 0) == "dot.radiowaves.left.and.right")
    }
}

@MainActor
struct LyricsCacheTests {
    @Test func servesFromDiskCacheWithoutNetwork() async {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let lines = [LyricsService.Line(time: 1, text: "Hello"), LyricsService.Line(time: 4, text: "World")]
        LyricsService(cacheDirectory: dir).writeDisk("Song|Artist", .synced(lines))

        let service = LyricsService(cacheDirectory: dir)
        await service.load(title: "Song", artist: "Artist", album: "", duration: 200)
        #expect(service.state == .synced(lines))
        #expect(service.networkRequests == 0)
        #expect(service.line(at: 4.5) == "World")
        await service.load(title: "Song", artist: "Artist", album: "", duration: 200)   // same song: no new lookup
        #expect(service.networkRequests == 0)
    }

    @Test func notFoundFallsBackToEmbeddedLyrics() async {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        LyricsService(cacheDirectory: dir).writeDisk("Rare|Band", .notFound)
        let service = LyricsService(cacheDirectory: dir)
        await service.load(title: "Rare", artist: "Band", album: "", duration: nil, embedded: "Line one\nLine two")
        #expect(service.state == .plain("Line one\nLine two"))
        #expect(service.networkRequests == 0)
    }
}

@MainActor
struct IslandModeTests {
    @Test func lyricStripOnlyForMusicWithSyncedLyrics() {
        let settings = AppSettings(defaults: UserDefaults(suiteName: "stitchy.tests.\(UUID())")!)
        let model = IslandModel(settings: settings)
        #expect(model.mode(hasLiveActivity: true, lyricStrip: true) == .liveLyrics)
        #expect(model.mode(hasLiveActivity: true, lyricStrip: false) == .live)
        #expect(model.mode(hasLiveActivity: false, lyricStrip: true) == .compact)
        model.menuBarHeight = 30
        let g = model.geometry
        #expect(g.size(.liveLyrics, tab: .home).height == 30 + IslandGeometry.lyricStrip)
        model.lyricsExpanded = true
        #expect(model.geometry.expanded(for: .music).height == g.expanded(for: .music).height + 150)
    }
}

struct AppleScriptRunnerTests {
    @Test func targetAppParsing() {
        #expect(AppleScriptRunner.targetApp(of: "tell application \"Spotify\" to playpause") == "Spotify")
        #expect(AppleScriptRunner.targetApp(of: "tell application \"Notes\"\n get name\nend tell") == "Notes")
        #expect(AppleScriptRunner.targetApp(of: "return 1") == "general")
    }

    @Test func plainScriptRunsWithTimeoutWrapper() async {
        let r = await AppleScriptRunner.run("return 2 + 3") { $0.int32Value }
        if case .success(let v) = r { #expect(v == 5) } else { Issue.record("expected success, got \(r)") }
    }
}

@Suite struct FocusShortcutTests {
    @Test func picksOnOffPairByTopic() {
        let names = ["Morning Routine", "Sleep Focus On", "Sleep Focus Off", "Turn Lights On"]
        let pair = FocusService.focusPair(in: names)
        #expect(pair?.on == "Sleep Focus On")
        #expect(pair?.off == "Sleep Focus Off")
    }

    @Test func ignoresWordsThatOnlyContainOnOrOff() {
        // "Focus Monitor" contains "on" but not as a word; no "off" partner.
        #expect(FocusService.focusPair(in: ["Focus Monitor", "Offline Focus"]) == nil)
    }
}

@Suite struct ScreenshotWatcherTests {
    @Test func reportsEachScreenshotOnceAndSkipsTempFiles() {
        var seen: Set<String> = []
        let first = ScreenshotWatcher.newPaths(["/d/Screenshot 1.png", "/d/.Screenshot 2.png"], seen: &seen)
        #expect(first == ["/d/Screenshot 1.png"])
        let second = ScreenshotWatcher.newPaths(["/d/Screenshot 1.png", "/d/Screenshot 3.png"], seen: &seen)
        #expect(second == ["/d/Screenshot 3.png"])
    }
}

@Suite struct DroppyRoundTests {
    @Test func focusShortcutIsAValidSetFocusWorkflow() throws {
        for on in [true, false] {
            let data = try PropertyListSerialization.data(fromPropertyList: FocusService.workflow(focusOn: on), format: .binary, options: 0)
            let back = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
            let action = try #require((back["WFWorkflowActions"] as? [[String: Any]])?.first)
            #expect(action["WFWorkflowActionIdentifier"] as? String == "is.workflow.actions.dnd.set")
            #expect((action["WFWorkflowActionParameters"] as? [String: Any])?["Enabled"] as? Bool == on)
        }
    }

    @Test func installedPairIsPreferred() {
        let pair = FocusService.focusPair(in: ["Focus On", "Focus Off", FocusService.installedOnName, FocusService.installedOffName])
        #expect(pair?.on == FocusService.installedOnName)
    }

    @available(macOS 14.2, *)
    @Test func tapCopyScalesAndSilencesExtraChannels() {
        var input: [Float] = [1, -0.5, 0.25, 1]
        var out0 = [Float](repeating: 9, count: 6)
        var out1 = [Float](repeating: 9, count: 2)
        input.withUnsafeMutableBytes { inRaw in
            out0.withUnsafeMutableBytes { o0 in
                out1.withUnsafeMutableBytes { o1 in
                    let inList = AudioBufferList.allocate(maximumBuffers: 1)
                    inList[0] = AudioBuffer(mNumberChannels: 2, mDataByteSize: UInt32(inRaw.count), mData: inRaw.baseAddress)
                    let outList = AudioBufferList.allocate(maximumBuffers: 2)
                    outList[0] = AudioBuffer(mNumberChannels: 2, mDataByteSize: UInt32(o0.count), mData: o0.baseAddress)
                    outList[1] = AudioBuffer(mNumberChannels: 2, mDataByteSize: UInt32(o1.count), mData: o1.baseAddress)
                    TapRoute.copy(inList.unsafePointer, to: outList.unsafeMutablePointer, gain: 0.5)
                    inList.unsafeMutablePointer.deallocate()
                    outList.unsafeMutablePointer.deallocate()
                }
            }
        }
        #expect(out0 == [0.5, -0.25, 0.125, 0.5, 0, 0])
        #expect(out1 == [0, 0])
    }
}

@Suite struct PhaseATests {
    @Test func cpuLoadBetweenSamples() {
        let a = SystemStats.CPUTicks(busy: 100, total: 400)
        let b = SystemStats.CPUTicks(busy: 150, total: 500)
        #expect(SystemStats.cpuLoad(from: a, to: b) == 0.5)
        #expect(SystemStats.cpuLoad(from: b, to: a) == 0)   // counter reset never goes negative
        #expect(SystemStats.memoryUsed().map { $0 > 0 && $0 <= 1 } == true)
    }

    @Test func awakeText() {
        let now = Date()
        #expect(SystemControls.awakeText(until: nil, now: now) == "Awake until turned off")
        #expect(SystemControls.awakeText(until: now.addingTimeInterval(41 * 60 + 5), now: now) == "Awake · 42 min left")
        #expect(SystemControls.awakeText(until: now.addingTimeInterval(65 * 60), now: now) == "Awake · 1 h 05 min left")
    }

    @Test func codeDetection() {
        #expect(ClipboardHistory.Entry.looksLikeCode("func greet() {\n    print(\"hi\")\n}"))
        #expect(ClipboardHistory.Entry.looksLikeCode("const x = a => a * 2;"))
        #expect(!ClipboardHistory.Entry.looksLikeCode("Meet me at the station at five."))
        #expect(!ClipboardHistory.Entry.looksLikeCode("https://example.com/a?b=c"))
    }

    @Test @MainActor func shelfReorderAndResize() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("StitchyPhaseA-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let urls = try ["a", "b", "c"].map { name -> URL in
            let u = dir.appendingPathComponent("\(name).txt"); try Data(name.utf8).write(to: u); return u
        }
        let shelf = FileShelf()
        shelf.add(urls)
        #expect(shelf.place([urls[2]], before: shelf.items[0]))
        #expect(shelf.items.map(\.url.lastPathComponent) == ["c.txt", "a.txt", "b.txt"])

        // 200×100 PNG → longest side 50, original untouched.
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 200, pixelsHigh: 100, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let png = dir.appendingPathComponent("p.png")
        try rep.representation(using: .png, properties: [:])!.write(to: png)
        let out = dir.appendingPathComponent("p 50px.png")
        #expect(FileShelf.writeResized(from: png, to: out, maxPixels: 50))
        #expect(NSBitmapImageRep(data: try Data(contentsOf: out))?.pixelsWide == 50)
        #expect(!FileShelf.writeResized(from: png, to: out, maxPixels: 50))   // never overwrites
        #expect(NSBitmapImageRep(data: try Data(contentsOf: png))?.pixelsWide == 200)
    }
}

@Suite struct PhaseBTests {
    @Test func calculatorEvaluates() throws {
        let c = Calculator()
        #expect(try c.evaluate("2 × (3 + 4)") == 14)
        #expect(try c.evaluate("2^3^2") == 512)             // right-associative
        #expect(try c.evaluate("-2^2") == -4)
        #expect(try c.evaluate("2^-1") == 0.5)
        #expect(try c.evaluate("10 % 4 + 5!") == 122)
        #expect(try c.evaluate("√(16) + ln(e)") == 5)
        #expect(try c.evaluate("1.5e3 / 3") == 500)
        #expect(abs(try Calculator(degrees: true).evaluate("sin(30)") - 0.5) < 1e-12)
        #expect(throws: Calculator.Failure.domain) { try c.evaluate("1/0") }
        #expect(throws: Calculator.Failure.syntax) { try c.evaluate("2 +") }
        #expect(throws: Calculator.Failure.syntax) { try c.evaluate("(1") }
        #expect(throws: Calculator.Failure.syntax) { try c.evaluate("foo(2)") }
        #expect(Calculator.format(14) == "14")
        #expect(Calculator.format(1.0 / 3) == "0.3333333333")
    }

    @Test func devTools() {
        #expect(DevTool.base64Encode.run("hi") == .text("aGk="))
        #expect(DevTool.base64Decode.run("aGk") == .text("hi"))             // missing padding ok
        #expect(DevTool.urlEncode.run("a b&c") == .text("a%20b%26c"))
        #expect(DevTool.urlDecode.run("a%20b+c") == .text("a b c"))
        #expect(DevTool.jsonMinify.run("{ \"b\": 1 }") == .text("{\"b\":1}"))
        #expect(DevTool.jsonFormat.run("{oops") == .error("Not valid JSON."))
        if case .text(let h) = DevTool.hashes.run("abc") {
            #expect(h.contains("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"))
            #expect(h.contains("900150983cd24fb0d6963f7d28e17f72"))
        } else { Issue.record("hashes failed") }
        if case .text(let t) = DevTool.timestamp.run("1700000000000") { #expect(t.contains("Unix      1700000000")) } else { Issue.record("ts") }
        #expect(DevTool.color.run("#34C759") == .text("HEX  #34C759\nRGB  rgb(52, 199, 89)\nHSL  hsl(135, 59%, 49%)"))
        if case .text(let t) = DevTool.color.run("hsl(135, 59%, 49%)") { #expect(t.hasPrefix("HEX  #33C758") || t.hasPrefix("HEX  #34C759") || t.hasPrefix("HEX  #33C759")) }
        // header {"alg":"HS256"} payload {"sub":"1","exp":0}
        if case .text(let t) = DevTool.jwt.run("eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIiwiZXhwIjowfQ.sig") {
            #expect(t.contains("\"alg\" : \"HS256\"") && t.contains("exp:") && t.contains("Signature not verified"))
        } else { Issue.record("jwt") }
        #expect(DevTool.qrImage("https://example.com") != nil)
    }

    @Test func snapLayouts() {
        let v = CGRect(x: 0, y: 0, width: 1200, height: 800)
        let cur = CGRect(x: 10, y: 10, width: 600, height: 400)
        #expect(WindowSnapper.Layout.leftHalf.frame(in: v, current: cur) == CGRect(x: 0, y: 0, width: 600, height: 800))
        #expect(WindowSnapper.Layout.topRight.frame(in: v, current: cur) == CGRect(x: 600, y: 400, width: 600, height: 400))
        #expect(WindowSnapper.Layout.centerThird.frame(in: v, current: cur) == CGRect(x: 400, y: 0, width: 400, height: 800))
        #expect(WindowSnapper.Layout.center.frame(in: v, current: cur) == CGRect(x: 300, y: 200, width: 600, height: 400))
        #expect(WindowSnapper.Layout.maximize.frame(in: v, current: cur) == v)
    }
}

@Suite struct PhaseCTests {
    /// Renders text into an image and reads it back with Vision.
    @Test func ocrReadsRenderedText() throws {
        let size = NSSize(width: 640, height: 160)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.white.setFill(); rect.fill()
            ("Stitchy reads this" as NSString).draw(at: NSPoint(x: 30, y: 60), withAttributes: [.font: NSFont.systemFont(ofSize: 48), .foregroundColor: NSColor.black])
            return true
        }
        let cg = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let text = try CaptureService.recognize(cg)
        #expect(text.lowercased().contains("stitchy reads this"))
    }

    @Test func pdfTextIsExtracted() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("stitchy-\(UUID()).pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 400, height: 200)
        let consumer = try #require(CGDataConsumer(data: data as CFMutableData))
        let ctx = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
        ctx.beginPDFPage(nil)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        ("Hello PDF" as NSString).draw(at: NSPoint(x: 40, y: 90), withAttributes: [.font: NSFont.systemFont(ofSize: 28)])
        NSGraphicsContext.current = nil
        ctx.endPDFPage(); ctx.closePDF()
        try (data as Data).write(to: url)
        #expect(try await CaptureService.text(from: url).contains("Hello PDF"))
    }

    @Test func cutoutNeverOverwrites() throws {
        let dir = FileManager.default.temporaryDirectory
        let existing = dir.appendingPathComponent("stitchy-exists-\(UUID()).png")
        try Data("x".utf8).write(to: existing)
        defer { try? FileManager.default.removeItem(at: existing) }
        #expect(try CaptureService.writeCutout(from: existing, to: existing) == false)
    }

    @Test func xcodeManifestLatestBuild() throws {
        let manifest: [String: Any] = ["logs": [
            "A": ["timeStartedRecording": 700_000_000.0, "timeStoppedRecording": 700_000_012.5, "title": "Build Stitchy",
                  "schemeIdentifier-schemeName": "Stitchy",
                  "primaryObservable": ["highLevelStatus": "S", "totalNumberOfErrors": 0, "totalNumberOfWarnings": 2]],
            "B": ["timeStartedRecording": 700_000_100.0, "timeStoppedRecording": 700_000_130.0, "title": "Build App",
                  "schemeIdentifier-schemeName": "App",
                  "primaryObservable": ["highLevelStatus": "E", "totalNumberOfErrors": 3, "totalNumberOfWarnings": 0]],
        ]]
        let data = try PropertyListSerialization.data(fromPropertyList: manifest, format: .xml, options: 0)
        let build = try #require(XcodeBuildMonitor.latestBuild(in: data))
        #expect(build.scheme == "App" && !build.succeeded && build.errors == 3 && build.duration == 30)
        #expect(XcodeBuildMonitor.latestBuild(in: Data("nope".utf8)) == nil)
    }

    @Test func agentLogParsing() {
        func p(_ s: String, _ a: AgentActivityMonitor.Agent = .claude) -> AgentActivityMonitor.Parsed? { AgentActivityMonitor.parse(Data(s.utf8), agent: a) }
        let edit = p(#"{"type":"assistant","cwd":"/Users/me/proj","isSidechain":false,"timestamp":"2026-11-25T10:00:00.000Z","message":{"stop_reason":"tool_use","content":[{"type":"text"},{"type":"tool_use","name":"Edit","input":{"file_path":"/Users/me/proj/A.swift","old_string":"secret"}}]}}"#)
        #expect(edit?.event == .tool("Editing A.swift") && edit?.cwd == "/Users/me/proj" && edit?.timestamp != nil)
        let bash = p(#"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"export TOKEN=abc"}}]}}"#)
        #expect(bash?.event == .tool("Running a command"))   // command text never shown
        #expect(p(#"{"type":"assistant","isSidechain":false,"message":{"stop_reason":"end_turn","content":[{"type":"text"}]}}"#)?.event == .finished)
        #expect(p(#"{"type":"assistant","isSidechain":true,"message":{"stop_reason":"end_turn","content":[{"type":"text"}]}}"#)?.event == .thinking)
        #expect(p(#"{"type":"user","message":{}}"#) == nil)
        #expect(p(#"{"type":"response_item","payload":{"type":"function_call","name":"shell","arguments":"{}"}}"#, .codex)?.event == .tool("Running a command"))
        #expect(p(#"{"type":"event_msg","payload":{"type":"task_complete"}}"#, .codex)?.event == .finished)
        #expect(p(#"{"type":"turn_context","payload":{"cwd":"/x/repo"}}"#, .codex)?.cwd == "/x/repo")
        #expect(AgentActivityMonitor.describeClaude("mcp__github__create_issue", [:]) == "Using create issue")
    }
}

@Suite struct CutoutRealImageTests {
    /// Uses a system sample photo when present (skipped otherwise).
    @Test func removesBackgroundFromSystemPhoto() throws {
        let photo = URL(fileURLWithPath: "/Library/User Pictures/Flowers/Dahlia.heic")
        guard FileManager.default.fileExists(atPath: photo.path) else { return }
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("stitchy-cutout-\(UUID()).png")
        defer { try? FileManager.default.removeItem(at: out) }
        #expect(try CaptureService.writeCutout(from: photo, to: out))
        let rep = try #require(NSBitmapImageRep(data: try Data(contentsOf: out)))
        #expect(rep.hasAlpha)
        // A corner pixel should now be transparent.
        #expect((rep.colorAt(x: 0, y: 0)?.alphaComponent ?? 1) < 0.1)
    }
}

@Suite struct AgentMonitorLiveTests {
    @Test @MainActor func watchesAppendedLogLines() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("stitchy-home-\(UUID())")
        let dir = home.appendingPathComponent(".claude/projects/-tmp-demo")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let log = dir.appendingPathComponent("s.jsonl")
        try Data(#"{"type":"assistant","message":{"stop_reason":"end_turn","content":[]}}"#.utf8 + [0x0A]).write(to: log)   // old turn: ignored

        let monitor = AgentActivityMonitor(home: home)
        var finished: [AgentActivityMonitor.Session] = []
        monitor.onFinished = { finished.append($0) }
        monitor.start()
        defer { monitor.stop() }
        try await Task.sleep(for: .milliseconds(600))

        func append(_ s: String) throws {
            let h = try FileHandle(forWritingTo: log); defer { try? h.close() }
            try h.seekToEnd(); try h.write(contentsOf: Data(s.utf8) + [0x0A])
        }
        let now = ISO8601DateFormatter().string(from: Date())
        try append(#"{"type":"assistant","cwd":"/tmp/demo","timestamp":"\#(now)","message":{"stop_reason":"tool_use","content":[{"type":"tool_use","name":"Read","input":{"file_path":"/tmp/demo/README.md"}}]}}"#)
        for _ in 0..<40 where monitor.live == nil { try await Task.sleep(for: .milliseconds(100)) }
        #expect(monitor.live?.status == "Reading README.md")
        #expect(monitor.live?.project == "demo")

        try append(#"{"type":"assistant","cwd":"/tmp/demo","timestamp":"\#(now)","message":{"stop_reason":"end_turn","content":[{"type":"text"}]}}"#)
        for _ in 0..<40 where finished.isEmpty { try await Task.sleep(for: .milliseconds(100)) }
        #expect(finished.count == 1 && finished.first?.agent == .claude)
        #expect(monitor.live == nil)
    }
}

@Suite struct PhaseDTests {
    @Test func markdownParsingAndTasks() {
        let text = "# Title\n- [ ] milk\n- [x] eggs\n- plain\n> quote\n```\nlet a = 1\n```\nhello **bold**"
        let blocks = Markdown.parse(text)
        #expect(blocks.first == .heading(1, "Title"))
        #expect(blocks.contains(.task(done: false, text: "milk", line: 1)))
        #expect(blocks.contains(.task(done: true, text: "eggs", line: 2)))
        #expect(blocks.contains(.bullet("plain")) && blocks.contains(.quote("quote")) && blocks.contains(.code("let a = 1")))
        #expect(blocks.last == .paragraph("hello **bold**"))
        let toggled = Markdown.toggleTask(in: text, line: 1)
        #expect(toggled.components(separatedBy: "\n")[1] == "- [x] milk")
        #expect(Markdown.toggleTask(in: toggled, line: 2).components(separatedBy: "\n")[2] == "- [ ] eggs")
        #expect(Markdown.toggleTask(in: text, line: 99) == text)
    }

    @Test @MainActor func breakReminderCountsActiveTimeOnly() {
        let b = BreakReminder()
        b.interval = 3 * 60
        var fired: [BreakReminder.Suggestion] = []
        b.onReminder = { fired.append($0) }
        b.tick(idle: 2); b.tick(idle: 2)
        b.tick(idle: 400)                  // a real break resets
        b.tick(idle: 2); b.tick(idle: 2)
        #expect(fired.isEmpty)
        b.tick(idle: 2)
        #expect(fired.count == 1)
        b.isQuiet = { true }               // during a call
        b.tick(idle: 1); b.tick(idle: 1); b.tick(idle: 1)
        #expect(fired.count == 1)
        #expect(BreakReminder.idleSeconds() >= 0)
    }

    @Test func combinePDFAndCompressJPEG() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("stitchy-d-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 300, pixelsHigh: 200, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let png = dir.appendingPathComponent("a.png")
        try rep.representation(using: .png, properties: [:])!.write(to: png)
        let pdf = dir.appendingPathComponent("Combined.pdf")
        #expect(FileShelf.writeCombinedPDF([png, png], to: pdf) == 2)
        let again = FileShelf.writeCombinedPDF([png, pdf], to: dir.appendingPathComponent("Two.pdf"))
        #expect(again == 3)                                            // image + 2 PDF pages
        #expect(FileShelf.writeCombinedPDF([png], to: pdf) == 0)       // never overwrites
        let jpg = dir.appendingPathComponent("a compressed.jpg")
        #expect(FileShelf.writeCompressedJPEG(from: png, to: jpg, quality: 0.6)?.contains("→") == true)
        #expect(NSBitmapImageRep(data: try Data(contentsOf: jpg))?.pixelsWide == 300)
        #expect(FileShelf.writeCompressedJPEG(from: png, to: jpg, quality: 0.6) == nil)
    }
}

import AVFoundation

@Suite struct VideoCompressionTests {
    @Test func exportsHEVCCopy() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("stitchy-v-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let src = dir.appendingPathComponent("clip.mov")
        // 1 s, 320×240, H.264.
        let writer = try AVAssetWriter(outputURL: src, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 320, AVVideoHeightKey: 240])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: 320, kCVPixelBufferHeightKey as String: 240])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<30 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
            let b = try #require(buffer)
            CVPixelBufferLockBaseAddress(b, [])
            memset(CVPixelBufferGetBaseAddress(b), Int32(frame * 8), CVPixelBufferGetDataSize(b))
            CVPixelBufferUnlockBaseAddress(b, [])
            adaptor.append(b, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 30))
        }
        input.markAsFinished()
        await writer.finishWriting()
        #expect(writer.status == .completed)

        let out = dir.appendingPathComponent("clip compressed.mp4")
        #expect(await FileShelf.exportVideo(src, to: out))
        let tracks = try await AVURLAsset(url: out).loadTracks(withMediaType: .video)
        #expect(!tracks.isEmpty)
        #expect(await FileShelf.exportVideo(src, to: out) == false)   // never overwrites
    }
}

@Suite struct PhaseETests {
    @Test func launcherQuickCommands() {
        #expect(Launcher.calculation("12*7") == "84")
        #expect(Launcher.calculation("sqrt(16)") == "4")
        #expect(Launcher.calculation("Safari") == nil)
        #expect(Launcher.calculation("2024") == nil)          // a plain number isn't a calculation
        #expect(Launcher.argument("todo  buy milk ", prefixes: ["todo "]) == "buy milk")
        #expect(Launcher.argument("todo ", prefixes: ["todo "]) == nil)
        #expect(Launcher.thingsURL("buy milk & eggs")?.absoluteString == "things:///add?title=buy%20milk%20%26%20eggs")
        let obs = Launcher.obsidianURL("idea")?.absoluteString ?? ""
        #expect(obs.hasPrefix("obsidian://new?file=Stitchy%20Inbox") && obs.contains("append=true"))
    }

    @Test func annotationRendersMarks() throws {
        // 200×100 white image with a checkerboard on the right half (for blur).
        let ctx = try #require(CGContext(data: nil, width: 200, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(.white); ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 100))
        ctx.setFillColor(.black)
        for x: Int in 100..<200 {
            for y: Int in 0..<100 where (x + y) % 2 == 0 {
                ctx.fill(CGRect(x: CGFloat(x), y: CGFloat(y), width: 1, height: 1))
            }
        }
        let base = try #require(ctx.makeImage())
        let marks = [
            Mark(kind: .box, start: CGPoint(x: 0.05, y: 0.1), end: CGPoint(x: 0.4, y: 0.9), color: .systemRed),
            Mark(kind: .blur, start: CGPoint(x: 0.5, y: 0), end: CGPoint(x: 1, y: 1), color: .systemRed),
        ]
        let out = try #require(AnnotationRenderer.render(base, marks: marks))
        #expect(out.width == 200 && out.height == 100)
        let rep = NSBitmapImageRep(cgImage: out)
        // Box edge at x≈10 is red.
        let edge = try #require(rep.colorAt(x: 10, y: 50)?.usingColorSpace(.sRGB))
        #expect(edge.redComponent > 0.7 && edge.greenComponent < 0.5)
        // Untouched white stays white.
        #expect((rep.colorAt(x: 45, y: 50)?.usingColorSpace(.sRGB)?.greenComponent ?? 0) > 0.95)
        // Blurred checkerboard: neighbouring pixels become (nearly) the same.
        let a = rep.colorAt(x: 150, y: 50)!.usingColorSpace(.sRGB)!.whiteComponentApprox
        let b = rep.colorAt(x: 151, y: 50)!.usingColorSpace(.sRGB)!.whiteComponentApprox
        #expect(abs(a - b) < 0.1)
    }

    @Test @MainActor func screenshotFolderExists() {
        #expect(FileManager.default.fileExists(atPath: AnnotationEditor.screenshotFolder().path))
    }
}

private extension NSColor {
    var whiteComponentApprox: CGFloat { (redComponent + greenComponent + blueComponent) / 3 }
}

@Suite struct PhaseFTests {
    @Test func duplicateFilter() {
        var f = DuplicateFilter()
        let t0 = Date()
        let a = ActivityEvent(symbol: "x", tint: .red, title: "Build Succeeded", detail: "App · 12s")
        let b = ActivityEvent(symbol: "x", tint: .red, title: "Build Succeeded", detail: "App · 30s")
        let r1 = f.allows(a, now: t0)
        let r2 = f.allows(a, now: t0.addingTimeInterval(1))     // same alert twice
        let r3 = f.allows(b, now: t0.addingTimeInterval(1))     // different detail
        let r4 = f.allows(a, now: t0.addingTimeInterval(5))     // after the window
        #expect(r1 && !r2 && r3 && r4)
    }

    @Test func dockPanelPlacement() {
        let visible = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let size = CGSize(width: 300, height: 150)
        let bottomIcon = CGRect(x: 980, y: 0, width: 40, height: 40)
        let p1 = DockPreviews.panelOrigin(icon: bottomIcon, size: size, dock: .bottom, visible: visible)
        #expect(p1 == CGPoint(x: 692, y: 48))                    // clamped inside the right edge
        let leftIcon = CGRect(x: 0, y: 400, width: 40, height: 40)
        #expect(DockPreviews.panelOrigin(icon: leftIcon, size: size, dock: .left, visible: visible) == CGPoint(x: 48, y: 345))
        let rightIcon = CGRect(x: 960, y: 780, width: 40, height: 40)
        #expect(DockPreviews.panelOrigin(icon: rightIcon, size: size, dock: .right, visible: visible) == CGPoint(x: 652, y: 642))
    }
}

@Suite struct DroppyHomeTests {
    @Test func batteryLowShowsSliverNotEmpty() {
        let low = BatterySnapshot(hasBattery: true, percent: 6)
        #expect(low.symbol == "battery.25percent" && low.tint == .red)
        #expect(BatterySnapshot(hasBattery: true, percent: 18).tint == .yellow)
    }

    @Test func airPodsBatteryParsing() {
        let json = #"{"SPBluetoothDataType":[{"device_connected":[{"Ana's AirPods Pro":{"device_batteryLevelLeft":"80%","device_batteryLevelRight":"75 %","device_batteryLevelCase":"40%"}}]}]}"#
        let levels = BluetoothMonitor.parseBattery(Data(json.utf8), name: "Ana's AirPods Pro")
        #expect(levels?.text == "L 80% · R 75% · Case 40%")
        #expect(levels?.lowest == 75)
        #expect(BluetoothMonitor.parseBattery(Data(json.utf8), name: "Other") == nil)
    }

    @Test func trackedFolderSkipsPartials() {
        #expect(FolderTracker.newEntries(["a.txt", "b.pdf", "c.crdownload", "d.part"], known: ["a.txt"]) == ["b.pdf"])
    }

    @Test func downloadDetail() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("stitchy-dl-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let f = dir.appendingPathComponent("Report.pdf")
        try Data(count: 2048).write(to: f)
        let detail = DownloadsMonitor.completionDetail(f)
        #expect(detail.hasPrefix("Report.pdf · ") && detail.hasSuffix(" · \(dir.lastPathComponent)"))
    }

    @Test @MainActor func fileTrayActions() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("stitchy-tray-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = dir.appendingPathComponent("a.txt"), b = dir.appendingPathComponent("b.txt")
        try Data("a".utf8).write(to: a); try Data("b".utf8).write(to: b)
        // Copy into a folder: never overwrites, originals stay.
        let folder = dir.appendingPathComponent("Box")
        #expect(FileShelf.copy([a, b], into: folder, createFolder: true) == 2)
        #expect(FileShelf.copy([a], into: folder, createFolder: false) == 1)
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
        #expect(names == ["a 2.txt", "a.txt", "b.txt"])
        #expect(FileManager.default.fileExists(atPath: a.path))

        // Smaller PDF: a new file, original untouched, never overwrites.
        let pdf = dir.appendingPathComponent("doc.pdf")
        #expect(FileShelf.writeCombinedPDF([a], to: pdf) == 0)          // text isn't an image/PDF
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 400, pixelsHigh: 300, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let png = dir.appendingPathComponent("p.png")
        try rep.representation(using: .png, properties: [:])!.write(to: png)
        #expect(FileShelf.writeCombinedPDF([png], to: pdf) == 1)
        let small = dir.appendingPathComponent("doc smaller.pdf")
        #expect(FileShelf.writeSmallerPDF(from: pdf, to: small)?.contains("→") == true)
        #expect(FileShelf.writeSmallerPDF(from: pdf, to: small) == nil)

        // Pinned items survive Clear.
        let key = "data.shelfPinned"
        let saved = UserDefaults.standard.stringArray(forKey: key)
        defer { UserDefaults.standard.set(saved, forKey: key) }
        UserDefaults.standard.removeObject(forKey: key)
        let shelf = FileShelf()
        shelf.add([a, b])
        shelf.togglePin(shelf.items[0])
        shelf.clear()
        #expect(shelf.items.map(\.url.lastPathComponent) == ["a.txt"])
        shelf.togglePin(shelf.items[0])
    }
}

@Suite struct LockScreenAndBubbleTests {
    @Test func depthClockFormat() {
        var c = DateComponents(); c.year = 2026; c.month = 1; c.day = 2; c.hour = 16; c.minute = 4
        let date = Calendar(identifier: .gregorian).date(from: c)!
        #expect(DepthArtwork.clock(date, locale: Locale(identifier: "en_US")) == "4:04")
        #expect(DepthArtwork.clock(date, locale: Locale(identifier: "en_GB")) == "16:04")
    }

    @Test func lockScreenLyricLines() {
        let lines: [LyricsService.Line] = [.init(time: 0, text: "One"), .init(time: 5, text: ""), .init(time: 10, text: "Three")]
        let (cur, next) = LockScreenNowPlaying.lines(.synced(lines), at: 1)
        #expect(cur == "One" && next == "Three")
        #expect(LockScreenNowPlaying.lines(.notFound, at: 1) == (nil, nil))
    }
}

@Suite struct LockScreenLayoutTests {
    @Test func playerSitsLowAndCentred() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let f = LockScreenArtController.playerFrame(in: screen)
        #expect(f.midX == screen.midX)
        // Bottom edge (AppKit y-up) is 95% down from the top, like Apple's full-screen art layout.
        #expect(abs((screen.maxY - f.minY) - 900 * 0.95) < 0.5)
        #expect(f.width <= 660 && f.height == 290)
    }
}
