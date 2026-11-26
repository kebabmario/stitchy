// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

/// Lightweight Markdown for notes: headings, bullets, quotes, code blocks,
/// inline styles and clickable `- [ ]` checklists (simple task lists).
enum Markdown {
    enum Block: Equatable {
        case heading(Int, String), task(done: Bool, text: String, line: Int), bullet(String), quote(String), code(String), paragraph(String), blank
    }

    static func parse(_ text: String) -> [Block] {
        var blocks: [Block] = []
        var code: [String]?
        for (i, raw) in text.components(separatedBy: "\n").enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                if let c = code { blocks.append(.code(c.joined(separator: "\n"))); code = nil } else { code = [] }
                continue
            }
            if code != nil { code?.append(raw); continue }
            if line.isEmpty { blocks.append(.blank); continue }
            if let (done, rest) = task(line) { blocks.append(.task(done: done, text: rest, line: i)); continue }
            if let level = ["### ", "## ", "# "].firstIndex(where: { line.hasPrefix($0) }) {
                blocks.append(.heading(3 - level, String(line.drop(while: { $0 == "#" }).dropFirst()))); continue
            }
            if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ") { blocks.append(.bullet(String(line.dropFirst(2)))); continue }
            if line.hasPrefix("> ") { blocks.append(.quote(String(line.dropFirst(2)))); continue }
            blocks.append(.paragraph(line))
        }
        if let c = code { blocks.append(.code(c.joined(separator: "\n"))) }   // unclosed fence
        return blocks
    }

    private static func task(_ line: String) -> (Bool, String)? {
        for prefix in ["- [ ] ", "* [ ] ", "- [x] ", "- [X] ", "* [x] "] where line.hasPrefix(prefix) {
            return (prefix.contains("x") || prefix.contains("X"), String(line.dropFirst(prefix.count)))
        }
        return nil
    }

    /// Flips the checkbox on `line`; other lines are untouched.
    static func toggleTask(in text: String, line: Int) -> String {
        var lines = text.components(separatedBy: "\n")
        guard lines.indices.contains(line) else { return text }
        let l = lines[line]
        if let r = l.range(of: "[ ]") { lines[line] = l.replacingCharacters(in: r, with: "[x]") }
        else if let r = l.range(of: "[x]") ?? l.range(of: "[X]") { lines[line] = l.replacingCharacters(in: r, with: "[ ]") }
        return lines.joined(separator: "\n")
    }

    static func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
}

struct MarkdownPreview: View {
    @Binding var text: String

    var body: some View {
        IslandScroll(axis: .vertical) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(Markdown.parse(text).enumerated()), id: \.offset) { _, block in row(block) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
        }
    }

    @ViewBuilder private func row(_ block: Markdown.Block) -> some View {
        switch block {
        case .heading(let level, let s):
            Text(Markdown.inline(s)).font(.system(size: level == 1 ? 16 : level == 2 ? 14 : 13, weight: .bold)).padding(.top, 2)
        case .task(let done, let s, let line):
            Button { withAnimation(.snappy) { text = Markdown.toggleTask(in: text, line: line) } } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: done ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(done ? Color.green : Color.secondaryText)
                        .contentTransition(.symbolEffect(.replace))
                    Text(Markdown.inline(s)).strikethrough(done).foregroundStyle(done ? Color.secondaryText : .white)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plainHit)
        case .bullet(let s):
            HStack(alignment: .firstTextBaseline, spacing: 6) { Text("•").foregroundStyle(Color.secondaryText); Text(Markdown.inline(s)) }
        case .quote(let s):
            HStack(spacing: 6) { Capsule().fill(.white.opacity(0.25)).frame(width: 2); Text(Markdown.inline(s)).foregroundStyle(Color.secondaryText) }
        case .code(let s):
            Text(s).font(.system(size: 11, design: .monospaced)).padding(6).frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        case .paragraph(let s):
            Text(Markdown.inline(s))
        case .blank:
            Color.clear.frame(height: 2)
        }
    }
}
