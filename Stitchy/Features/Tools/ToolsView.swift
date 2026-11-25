import SwiftUI
import UniformTypeIdentifiers

/// Tools tab: Calculator and Developer toolkit.
struct ToolsView: View {
    @Environment(IslandModel.self) private var model
    enum Mode: Hashable { case calculator, developer, capture, translate }
    @State private var mode: Mode = .calculator

    static var modes: [(Mode, String)] {
        var list: [(Mode, String)] = [(.calculator, "Calculator"), (.developer, "Developer"), (.capture, "Capture")]
        if #available(macOS 15.0, *) { list.append((.translate, "Translate")) }   // Translation framework
        return list
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Segmented(options: Self.modes, selection: $mode)
            Group {
                switch mode {
                case .calculator: CalculatorView()
                case .developer: DevToolsView()
                case .capture: CaptureView()
                case .translate:
                    if #available(macOS 15.0, *) { TranslateView() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .transition(.blurReplace)
        }
        .onChange(of: model.translateRequest, initial: true) { _, text in if text != nil { mode = .translate } }
    }
}

// MARK: - Calculator

private struct CalculatorView: View {
    @Environment(AppSettings.self) private var settings
    @State private var expression = ""
    @State private var scientific = false
    @State private var degrees = false
    @State private var history: [Entry] = []
    @State private var justEvaluated = false

    struct Entry: Codable, Hashable { var expression: String; var result: String }
    private static let historyKey = "calculatorHistory"

    private var preview: String? {
        guard !expression.isEmpty, let v = try? Calculator(degrees: degrees).evaluate(expression) else { return nil }
        return Calculator.format(v)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 6) {
                display
                keypad
            }
            historyList.frame(width: 140)
        }
        .onAppear { history = settings.data([Entry].self, key: Self.historyKey) ?? [] }
    }

    private var display: some View {
        HStack(alignment: .top, spacing: 6) {
            Button { withAnimation(.snappy) { scientific.toggle() } } label: {
                Text("f(x)").font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(scientific ? .black : .white)
                    .padding(.horizontal, 7).frame(height: 18)
                    .background(Capsule().fill(scientific ? Color.orange : .white.opacity(0.1)))
            }
            .buttonStyle(PressableStyle())
            .help(scientific ? "Basic keypad" : "Scientific keypad")
        VStack(alignment: .trailing, spacing: 0) {
            TextField("2 × (3 + 4)", text: $expression)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium, design: .rounded).monospacedDigit())
                .multilineTextAlignment(.trailing)
                .onSubmit(evaluate)
            Text(preview ?? " ")
                .font(.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(justEvaluated ? .white : Color.secondaryText)
                .lineLimit(1).minimumScaleFactor(0.5)
                .contentTransition(.numericText())
                .textSelection(.enabled)
        }
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .animation(.snappy, value: preview)
    }

    private var keypad: some View {
        let basic: [[String]] = [["C", "(", ")", "÷"], ["7", "8", "9", "×"], ["4", "5", "6", "−"], ["1", "2", "3", "+"], ["0", ".", "⌫", "="]]
        let sci: [[String]] = [["sin", "cos", "tan", "^"], ["asin", "acos", "atan", "!"], ["√", "ln", "log", "%"], ["π", "e", "abs", degrees ? "DEG" : "RAD"], ["(", ")", "⌫", "="]]
        return VStack(spacing: 3) {
            ForEach(Array((scientific ? sci : basic).enumerated()), id: \.offset) { _, row in
                HStack(spacing: 3) {
                    ForEach(row, id: \.self) { key in keyButton(key) }
                }
            }
        }
    }

    private func keyButton(_ key: String) -> some View {
        let isOp = ["÷", "×", "−", "+", "="].contains(key)
        return Button { press(key) } label: {
            Text(key)
                .font(.system(size: key.count > 2 ? 10 : 12, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity).frame(height: 20)
                .foregroundStyle(key == "=" ? .black : .white)
                .background(Capsule().fill(key == "=" ? Color.orange : .white.opacity(isOp ? 0.16 : 0.08)))
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(key)
    }

    private func press(_ key: String) {
        justEvaluated = false
        switch key {
        case "C": expression = ""
        case "⌫": if !expression.isEmpty { expression.removeLast() }
        case "=": evaluate()
        case "RAD", "DEG": degrees.toggle()
        case "sin", "cos", "tan", "asin", "acos", "atan", "ln", "log", "abs": expression += key + "("
        case "√": expression += "√("
        default: expression += key
        }
    }

    private func evaluate() {
        guard let result = preview else { return }
        let entry = Entry(expression: expression, result: result)
        history.insert(entry, at: 0)
        history = Array(history.prefix(30))
        settings.setData(history, key: Self.historyKey)
        withAnimation(.snappy) { justEvaluated = true }
        expression = result
    }

    private var historyList: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                SectionLabel("History")
                Spacer()
                if !history.isEmpty {
                    Button("Clear") {
                        withAnimation(.snappy) { history = [] }
                        settings.setData(history, key: Self.historyKey)
                    }
                    .buttonStyle(.plainHit).font(.system(size: 10, weight: .medium)).foregroundStyle(Color.tertiaryText)
                }
            }
            IslandScroll(axis: .vertical) {
                VStack(alignment: .trailing, spacing: 2) {
                    ForEach(history, id: \.self) { entry in
                        Button { expression = entry.result; justEvaluated = false } label: {
                            VStack(alignment: .trailing, spacing: 0) {
                                Text(entry.expression).font(.system(size: 9.5).monospacedDigit()).foregroundStyle(Color.tertiaryText)
                                Text(entry.result).font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                            }
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .modifier(HoverHighlight(cornerRadius: 8))
                        }
                        .buttonStyle(.plainHit)
                        .help("Use \(entry.result)")
                    }
                    if history.isEmpty {
                        Text("Results appear here.").font(.system(size: 10)).foregroundStyle(Color.tertiaryText).padding(.top, 8)
                    }
                }
            }
        }
    }
}

// MARK: - Developer toolkit

private struct DevToolsView: View {
    @State private var tool: DevTool = .jsonFormat
    @State private var input = ""
    @State private var output: DevTool.Output?
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Menu {
                ForEach(DevTool.allCases) { t in
                    Button(t.title) {
                        withAnimation(.snappy) { tool = t; output = nil }
                        run()
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(tool.title).font(.system(size: 11.5, weight: .semibold))
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(Color.secondaryText)
                }
                .padding(.horizontal, 10).frame(height: 22)
                .background(Capsule().fill(.white.opacity(0.08)))
                .contentShape(Capsule())
            }
            .menuStyle(.button).buttonStyle(PressableStyle()).menuIndicator(.hidden).fixedSize()
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .topLeading) {
                    if input.isEmpty {
                        Text(tool.placeholder).font(.system(size: 11.5)).foregroundStyle(Color.tertiaryText).padding(.top, 1).padding(.leading, 5)
                    }
                    TextEditor(text: $input)
                        .font(.system(size: 11.5, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .onChange(of: input) { _, _ in if tool != .uuid { run() } }
                }
                .padding(6)
                .frame(height: 52)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                HStack(alignment: .top, spacing: 8) {
                    outputView
                    VStack(spacing: 4) {
                        IconButton(symbol: "play.fill", size: 9, diameter: 22, help: "Run") { run() }
                        IconButton(symbol: copied ? "checkmark" : "doc.on.doc", size: 9, diameter: 22, help: "Copy result") { copy() }
                            .disabled(outputText == nil)
                    }
                }
            }
        }
    }

    private var outputText: String? {
        if case .text(let t)? = output, tool != .qr { return t }
        return nil
    }

    @ViewBuilder private var outputView: some View {
        Group {
            switch output {
            case .error(let message)?:
                Text(message).foregroundStyle(.red.opacity(0.85))
            case .text(let text)? where tool == .qr:
                if let image = DevTool.qrImage(text, size: 80) {
                    Image(nsImage: image).interpolation(.none).resizable().frame(width: 80, height: 80)
                        .padding(4).background(.white, in: RoundedRectangle(cornerRadius: 6))
                }
            case .text(let text)?:
                IslandScroll(axis: .vertical) {
                    Text(text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
            case nil:
                Text("Result appears here.").foregroundStyle(Color.tertiaryText)
            }
        }
        .font(.system(size: 10.5, design: .monospaced))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .well(padding: 8)
    }

    private func run() {
        if tool != .uuid, tool != .timestamp, input.isEmpty { output = nil; return }
        output = tool.run(input)
        copied = false
    }

    private func copy() {
        guard let outputText else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(outputText, forType: .string)
        withAnimation(.snappy) { copied = true }
    }
}

// MARK: - Capture

private struct CaptureView: View {
    @Environment(AppServices.self) private var services
    @Environment(Dictation.self) private var dictation
    @Environment(CaptureService.self) private var capture
    @Environment(IslandModel.self) private var model
    @State private var targeted = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                PillButton(title: "Capture Screen Text", symbol: "text.viewfinder", tint: .white, prominent: true) {
                    model.collapse()
                    Task { await capture.captureTextFromScreen() }
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                    chip("From File", "doc.text.magnifyingglass") {
                        choose(["public.image", "com.adobe.pdf"]) { url in Task { await capture.copyText(from: url) } }
                    }
                    chip("Cutout", "person.crop.rectangle") {
                        choose(["public.image"]) { url in Task { await capture.removeBackground(url) } }
                    }
                    chip("Annotate", "pencil.tip.crop.circle") {
                        model.collapse()
                        Task { if let url = await capture.captureRegion() { services.annotator.open(url, deleteSourceOnClose: true) } }
                    }
                    chip(dictation.isRecording ? "Stop" : "Dictate", dictation.isRecording ? "stop.circle.fill" : "waveform",
                         active: dictation.isRecording) { dictation.toggle() }
                    chip("Mirror", "person.crop.circle") {
                        model.collapse()
                        services.cameraMirror.toggle()
                    }
                }
                Text("Drop an image or PDF on the right to copy its text. Runs on this Mac.")
                    .font(.system(size: 10)).foregroundStyle(Color.tertiaryText).fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 190, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    SectionLabel(dictation.isRecording ? (dictation.isOnDevice ? "Listening on this Mac" : "Listening") : capture.isWorking ? "Reading" : "Last capture")
                    Spacer()
                    if let text = capture.lastText {
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(text, forType: .string)
                        }
                        .buttonStyle(.plainHit).font(.system(size: 10, weight: .medium)).foregroundStyle(Color.secondaryText)
                    }
                }
                IslandScroll(axis: .vertical) {
                    Text(dictation.isRecording ? (dictation.transcript.isEmpty ? "Speak now…" : dictation.transcript)
                         : capture.lastText ?? dictation.lastError ?? capture.lastError ?? "Captured text appears here and is copied to the clipboard.")
                        .font(.system(size: 11)).foregroundStyle(capture.lastText == nil && !dictation.isRecording ? Color.tertiaryText : .white)
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .well(padding: 10)
            .overlay(RoundedRectangle(cornerRadius: DS.wellRadius, style: .continuous).fill(.white.opacity(targeted ? 0.07 : 0)).allowsHitTesting(false))
            .modifier(CaptureDrop(targeted: $targeted))
        }
    }

    private func chip(_ title: String, _ symbol: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: .semibold))
                .labelStyle(.titleAndIcon)
                .foregroundStyle(active ? Color.black : Color.white)
                .frame(maxWidth: .infinity).frame(height: 26)
                .background(Capsule().fill(active ? Color.red : Color.white.opacity(0.09)))
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .help(title)
    }

    /// Open panel for one file. The island panel can't host a sheet, so Stitchy activates first.
    private func choose(_ types: [String], then: @escaping (URL) -> Void) {
        model.collapse()
        NSApp.activate()
        let panel = NSOpenPanel()
        panel.allowedContentTypes = types.compactMap { UTType($0) }
        panel.allowsMultipleSelection = false
        panel.begin { response in
            if response == .OK, let url = panel.url { then(url) }
        }
    }
}

private struct CaptureDrop: ViewModifier {
    @Binding var targeted: Bool
    @Environment(CaptureService.self) private var capture

    func body(content: Content) -> some View {
        if SnapshotRenderer.isRendering {
            content
        } else {
            content.dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first else { return false }
                Task { await capture.copyText(from: url) }
                return true
            } isTargeted: { targeted = $0 }
        }
    }
}
