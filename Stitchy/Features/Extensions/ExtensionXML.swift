// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Turns XML (RSS, Atom and other feeds) into the same JSON-like tree
/// extensions bind to:
/// - an element with only text becomes a string;
/// - attributes become `@name`, repeated child elements become arrays,
///   mixed text becomes `#text`;
/// - text that is HTML is reduced to plain text, keeping its first image as `#image`.
/// External entities are never resolved.
enum ExtXML {
    static let maxNodes = 20_000, maxDepth = 32, maxText = 4_000

    static func parse(_ data: Data) -> Any? {
        let builder = Builder()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.shouldProcessNamespaces = false
        parser.delegate = builder
        guard parser.parse(), !builder.overflow, let root = builder.root else { return nil }
        return [root.name: value(root)]
    }

    final class Node {
        let name: String
        let attributes: [String: String]
        var children: [Node] = []
        var text = ""
        init(_ name: String, _ attributes: [String: String]) { self.name = name; self.attributes = attributes }
    }

    private final class Builder: NSObject, XMLParserDelegate {
        var root: Node?
        var stack: [Node] = []
        var count = 0
        var overflow = false

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
            count += 1
            guard count <= ExtXML.maxNodes, stack.count < ExtXML.maxDepth else { overflow = true; parser.abortParsing(); return }
            let node = Node(name, attributes)
            stack.last?.children.append(node)
            if root == nil { root = node }
            stack.append(node)
        }
        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) { _ = stack.popLast() }
        func parser(_ parser: XMLParser, foundCharacters string: String) { append(string) }
        func parser(_ parser: XMLParser, foundCDATA data: Data) { append(String(decoding: data, as: UTF8.self)) }
        private func append(_ s: String) {
            guard let top = stack.last, top.text.count < ExtXML.maxText * 4 else { return }
            top.text += s
        }
    }

    static func value(_ node: Node) -> Any {
        let text = node.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if node.children.isEmpty && node.attributes.isEmpty { return textValue(text) }
        var d: [String: Any] = [:]
        for (k, v) in node.attributes { d["@" + k] = v }
        var order: [String] = []
        var groups: [String: [Any]] = [:]
        for c in node.children {
            if groups[c.name] == nil { order.append(c.name) }
            groups[c.name, default: []].append(value(c))
        }
        for name in order { let g = groups[name]!; d[name] = g.count == 1 ? g[0] : g }
        if !text.isEmpty {
            let t = textValue(text)
            if let td = t as? [String: Any] { d.merge(td) { a, _ in a } } else { d["#text"] = t }
        }
        return d
    }

    /// Plain text stays a string; HTML becomes `{"#text": plain, "#image": firstImage}`.
    static func textValue(_ text: String) -> Any {
        guard text.contains("<"), text.contains(">") else { return String(decodeEntities(text).prefix(maxText)) }
        var d: [String: Any] = ["#text": plainText(fromHTML: text)]
        if let img = firstImage(inHTML: text) { d["#image"] = img }
        return d
    }

    static func plainText(fromHTML html: String) -> String {
        var s = html.replacingOccurrences(of: "<(script|style)[^>]*>.*?</\\1>", with: " ", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        s = decodeEntities(s).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return String(s.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxText))
    }

    static func firstImage(inHTML html: String) -> String? {
        guard let r = html.range(of: "<img[^>]+src\\s*=\\s*[\"']([^\"']+)[\"']", options: [.regularExpression, .caseInsensitive]) else { return nil }
        let tag = String(html[r])
        guard let q = tag.range(of: "src\\s*=\\s*[\"']", options: .regularExpression) else { return nil }
        let url = tag[q.upperBound...].prefix { $0 != "\"" && $0 != "'" }
        return decodeEntities(String(url))
    }

    static func decodeEntities(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var out = s
        for (k, v) in ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&apos;": "'", "&#39;": "'", "&nbsp;": " "] {
            out = out.replacingOccurrences(of: k, with: v)
        }
        // Numeric entities (&#8230; &#x2019;).
        while let r = out.range(of: "&#(x[0-9a-fA-F]+|[0-9]+);", options: .regularExpression) {
            let body = out[r].dropFirst(2).dropLast()
            let n = body.hasPrefix("x") ? UInt32(body.dropFirst(), radix: 16) : UInt32(body)
            out.replaceSubrange(r, with: n.flatMap(Unicode.Scalar.init).map { String(Character($0)) } ?? "")
        }
        return out
    }
}
