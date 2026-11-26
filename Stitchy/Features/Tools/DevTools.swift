// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import CoreImage.CIFilterBuiltins
import CryptoKit
import Foundation

/// Developer toolkit. Everything runs locally; nothing is sent anywhere.
enum DevTool: String, CaseIterable, Identifiable {
    case base64Encode, base64Decode, urlEncode, urlDecode, jsonFormat, jsonMinify
    case hashes, jwt, timestamp, uuid, color, qr

    var id: String { rawValue }

    var title: String {
        switch self {
        case .base64Encode: "Base64 Encode"
        case .base64Decode: "Base64 Decode"
        case .urlEncode: "URL Encode"
        case .urlDecode: "URL Decode"
        case .jsonFormat: "JSON Format"
        case .jsonMinify: "JSON Minify"
        case .hashes: "Hashes"
        case .jwt: "JWT Inspector"
        case .timestamp: "Timestamp"
        case .uuid: "UUID"
        case .color: "Color"
        case .qr: "QR Code"
        }
    }

    var placeholder: String {
        switch self {
        case .base64Decode: "Base64 text"
        case .urlDecode: "percent-encoded text"
        case .jsonFormat, .jsonMinify: "{\"json\": true}"
        case .jwt: "eyJhbGciOi…"
        case .timestamp: "Unix time (s or ms) or ISO date; empty = now"
        case .uuid: "Press Run for a new UUID"
        case .color: "#34C759, rgb(52,199,89) or hsl(135,59%,49%)"
        case .qr: "Text or link to encode"
        default: "Text"
        }
    }

    enum Output: Equatable { case text(String), error(String) }

    func run(_ input: String, now: Date = Date()) -> Output {
        switch self {
        case .base64Encode: return .text(Data(input.utf8).base64EncodedString())
        case .base64Decode:
            let cleaned = input.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let data = Self.base64Data(cleaned) else { return .error("Not valid Base64.") }
            return String(data: data, encoding: .utf8).map(Output.text) ?? .text("\(data.count) bytes of binary data")
        case .urlEncode:
            var allowed = CharacterSet.urlQueryAllowed
            allowed.remove(charactersIn: "&=+?/#")
            return .text(input.addingPercentEncoding(withAllowedCharacters: allowed) ?? input)
        case .urlDecode:
            return input.replacingOccurrences(of: "+", with: " ").removingPercentEncoding.map(Output.text) ?? .error("Invalid percent-encoding.")
        case .jsonFormat, .jsonMinify:
            guard let obj = try? JSONSerialization.jsonObject(with: Data(input.utf8), options: [.fragmentsAllowed]) else {
                return .error("Not valid JSON.")
            }
            let opts: JSONSerialization.WritingOptions = self == .jsonFormat
                ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed] : [.withoutEscapingSlashes, .fragmentsAllowed]
            return (try? JSONSerialization.data(withJSONObject: obj, options: opts)).flatMap { String(data: $0, encoding: .utf8) }.map(Output.text)
                ?? .error("Couldn't format.")
        case .hashes:
            let d = Data(input.utf8)
            func hex<D: Sequence>(_ digest: D) -> String where D.Element == UInt8 { digest.map { String(format: "%02x", $0) }.joined() }
            return .text("""
            MD5     \(hex(Insecure.MD5.hash(data: d)))
            SHA-1   \(hex(Insecure.SHA1.hash(data: d)))
            SHA-256 \(hex(SHA256.hash(data: d)))
            SHA-512 \(hex(SHA512.hash(data: d)))
            """)
        case .jwt: return Self.decodeJWT(input)
        case .timestamp: return Self.timestamp(input, now: now)
        case .uuid: return .text(UUID().uuidString)
        case .color: return Self.color(input)
        case .qr: return input.isEmpty ? .error("Enter text to encode.") : .text(input)
        }
    }

    // MARK: Helpers

    static func base64Data(_ s: String) -> Data? {
        var t = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")   // base64url too
        t += String(repeating: "=", count: (4 - t.count % 4) % 4)
        return Data(base64Encoded: t)
    }

    /// Decodes header and payload. Does NOT verify the signature.
    static func decodeJWT(_ token: String) -> Output {
        let parts = token.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".").map(String.init)
        guard parts.count >= 2 else { return .error("A JWT has three parts separated by dots.") }
        func pretty(_ part: String) -> String? {
            guard let data = base64Data(part), let obj = try? JSONSerialization.jsonObject(with: data),
                  let out = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) else { return nil }
            return String(data: out, encoding: .utf8)
        }
        guard let header = pretty(parts[0]), let payload = pretty(parts[1]) else { return .error("Header or payload isn't Base64 JSON.") }
        var text = "Header\n\(header)\n\nPayload\n\(payload)"
        if let data = base64Data(parts[1]), let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["iat", "nbf", "exp"] {
                if let t = (claims[key] as? NSNumber)?.doubleValue {
                    text += "\n\(key): \(Date(timeIntervalSince1970: t).formatted(date: .abbreviated, time: .standard))"
                }
            }
        }
        return .text(text + "\n\nSignature not verified.")
    }

    static func timestamp(_ input: String, now: Date) -> Output {
        let t = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let iso = ISO8601DateFormatter()
        let date: Date
        if t.isEmpty {
            date = now
        } else if let n = Double(t) {
            date = Date(timeIntervalSince1970: n > 1e11 ? n / 1000 : n)   // milliseconds if very large
        } else if let d = iso.date(from: t) {
            date = d
        } else {
            return .error("Enter Unix seconds, milliseconds or an ISO 8601 date.")
        }
        let secs = date.timeIntervalSince1970
        return .text("""
        Unix      \(Int64(secs.rounded(.down)))
        Millis    \(Int64((secs * 1000).rounded(.down)))
        ISO 8601  \(iso.string(from: date))
        Local     \(date.formatted(date: .complete, time: .standard))
        """)
    }

    static func color(_ input: String) -> Output {
        let t = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var r = 0.0, g = 0.0, b = 0.0
        let nums = t.components(separatedBy: CharacterSet(charactersIn: "0123456789.").inverted).compactMap(Double.init)
        if t.hasPrefix("rgb"), nums.count >= 3 {
            (r, g, b) = (nums[0] / 255, nums[1] / 255, nums[2] / 255)
        } else if t.hasPrefix("hsl"), nums.count >= 3 {
            (r, g, b) = hslToRGB(nums[0] / 360, nums[1] / 100, nums[2] / 100)
        } else {
            var hex = t.replacingOccurrences(of: "#", with: "")
            if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
            guard hex.count == 6, let v = UInt32(hex, radix: 16) else { return .error("Use #RRGGBB, rgb(r,g,b) or hsl(h,s%,l%).") }
            (r, g, b) = (Double((v >> 16) & 0xff) / 255, Double((v >> 8) & 0xff) / 255, Double(v & 0xff) / 255)
        }
        guard [r, g, b].allSatisfy({ (0...1).contains($0) }) else { return .error("Values out of range.") }
        let (h, s, l) = rgbToHSL(r, g, b)
        let R = Int((r * 255).rounded()), G = Int((g * 255).rounded()), B = Int((b * 255).rounded())
        return .text("""
        HEX  #\(String(format: "%02X%02X%02X", R, G, B))
        RGB  rgb(\(R), \(G), \(B))
        HSL  hsl(\(Int((h * 360).rounded())), \(Int((s * 100).rounded()))%, \(Int((l * 100).rounded()))%)
        """)
    }

    static func rgbToHSL(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
        let mx = max(r, g, b), mn = min(r, g, b), l = (mx + mn) / 2
        guard mx != mn else { return (0, 0, l) }
        let d = mx - mn
        let s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn)
        var h: Double
        switch mx {
        case r: h = (g - b) / d + (g < b ? 6 : 0)
        case g: h = (b - r) / d + 2
        default: h = (r - g) / d + 4
        }
        h /= 6
        return (h, s, l)
    }

    static func hslToRGB(_ h: Double, _ s: Double, _ l: Double) -> (Double, Double, Double) {
        guard s > 0 else { return (l, l, l) }
        let q = l < 0.5 ? l * (1 + s) : l + s - l * s, p = 2 * l - q
        func hue(_ t0: Double) -> Double {
            var t = t0
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1 / 6 { return p + (q - p) * 6 * t }
            if t < 1 / 2 { return q }
            if t < 2 / 3 { return p + (q - p) * (2 / 3 - t) * 6 }
            return p
        }
        return (hue(h + 1 / 3), hue(h), hue(h - 1 / 3))
    }

    static func qrImage(_ text: String, size: CGFloat = 132) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: size / output.extent.width, y: size / output.extent.height))
        guard let cg = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: size, height: size))
    }
}
