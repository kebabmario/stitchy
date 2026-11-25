import SwiftUI
import Translation

/// On-device translation with Apple's Translation framework (macOS 15+).
/// Languages download through macOS the first time; text never leaves the Mac.
@available(macOS 15.0, *)
struct TranslateView: View {
    @Environment(IslandModel.self) private var model
    @State private var input = ""
    @State private var output = ""
    @State private var error: String?
    @State private var target = Locale.Language(identifier: "en")
    @State private var configuration: TranslationSession.Configuration?
    @State private var working = false

    static let languages: [(String, String)] = [
        ("en", "English"), ("es", "Spanish"), ("fr", "French"), ("de", "German"), ("it", "Italian"), ("pt-BR", "Portuguese"),
        ("nl", "Dutch"), ("tr", "Turkish"), ("ru", "Russian"), ("uk", "Ukrainian"), ("pl", "Polish"), ("ar", "Arabic"),
        ("hi", "Hindi"), ("id", "Indonesian"), ("th", "Thai"), ("vi", "Vietnamese"), ("ja", "Japanese"), ("ko", "Korean"),
        ("zh-Hans", "Chinese (Simplified)"), ("zh-Hant", "Chinese (Traditional)"),
    ]

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .topLeading) {
                    if input.isEmpty {
                        Text("Text to translate (language is detected)").font(.system(size: 11.5)).foregroundStyle(Color.tertiaryText).padding(.leading, 5)
                    }
                    TextEditor(text: $input).font(.system(size: 11.5)).scrollContentBackground(.hidden)
                }
                .padding(6)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                HStack(spacing: 6) {
                    Menu {
                        ForEach(Self.languages, id: \.0) { code, name in
                            Button(name) { target = Locale.Language(identifier: code); translate() }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.right").font(.system(size: 9, weight: .bold)).foregroundStyle(Color.secondaryText)
                            Text(Self.name(of: target)).font(.system(size: 11, weight: .semibold))
                            Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(Color.secondaryText)
                        }
                        .padding(.horizontal, 10).frame(height: 22)
                        .background(Capsule().fill(.white.opacity(0.08))).contentShape(Capsule())
                    }
                    .menuStyle(.button).buttonStyle(PressableStyle()).menuIndicator(.hidden).fixedSize()
                    Spacer(minLength: 4)
                    IconButton(symbol: "doc.on.clipboard", size: 10, diameter: 24, help: "Paste and translate") {
                        if let s = NSPasteboard.general.string(forType: .string) { input = s; translate() }
                    }
                    PillButton(title: working ? "Translating…" : "Translate", tint: .white, prominent: true) { translate() }
                        .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .frame(width: 240)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    SectionLabel("Translation")
                    Spacer()
                    if !output.isEmpty {
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(output, forType: .string)
                        }
                        .buttonStyle(.plainHit).font(.system(size: 10, weight: .medium)).foregroundStyle(Color.secondaryText)
                    }
                }
                IslandScroll(axis: .vertical) {
                    Text(error ?? (output.isEmpty ? "Runs on this Mac. macOS may download a language the first time." : output))
                        .font(.system(size: 11.5)).foregroundStyle(error != nil ? .orange : output.isEmpty ? Color.tertiaryText : .white)
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .well(padding: 10)
        }
        .onChange(of: model.translateRequest, initial: true) { _, text in
            guard let text else { return }
            input = text
            model.translateRequest = nil
            translate()
        }
        .translationTask(configuration) { session in
            let text = input
            // The framework hands the session to this closure only; it isn't shared elsewhere.
            nonisolated(unsafe) let session = session
            do {
                let response = try await session.translate(text)
                output = response.targetText
                error = nil
            } catch {
                self.error = "Couldn't translate: \(error.localizedDescription)"
            }
            working = false
        }
    }

    private func translate() {
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        working = true
        if configuration?.target == target {
            configuration?.invalidate()   // same languages: run again with the new text
        } else {
            configuration = TranslationSession.Configuration(source: nil, target: target)
        }
    }

    static func name(of language: Locale.Language) -> String {
        languages.first { Locale.Language(identifier: $0.0).minimalIdentifier == language.minimalIdentifier }?.1
            ?? Locale.current.localizedString(forIdentifier: language.minimalIdentifier) ?? language.minimalIdentifier
    }
}
