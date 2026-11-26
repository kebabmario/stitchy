// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// A small, safe expression evaluator (no NSExpression: it raises
/// Objective-C exceptions on bad input). Supports + − × ÷ % ^ !, parentheses,
/// constants (pi, e) and common functions. No implicit multiplication.
struct Calculator {
    enum Failure: Error, Equatable { case syntax, domain }

    var degrees = false

    func evaluate(_ input: String) throws -> Double {
        var p = Parser(tokens: try Self.tokenize(input), degrees: degrees)
        let value = try p.expression()
        guard p.atEnd else { throw Failure.syntax }
        guard value.isFinite else { throw Failure.domain }
        return value
    }

    /// "42", "0.333333333", "1.2e+20".
    static func format(_ v: Double) -> String {
        if v == v.rounded(), abs(v) < 1e15 { return String(Int64(v)) }
        let s = String(format: "%.10g", v)
        return s
    }

    enum Token: Equatable { case number(Double), ident(String), op(Character), lparen, rparen }

    static func tokenize(_ input: String) throws -> [Token] {
        let mapped = input.replacingOccurrences(of: "×", with: "*").replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "−", with: "-").replacingOccurrences(of: "π", with: "pi").replacingOccurrences(of: "√", with: "sqrt")
        var tokens: [Token] = []
        var i = mapped.startIndex
        while i < mapped.endIndex {
            let c = mapped[i]
            if c.isWhitespace { i = mapped.index(after: i); continue }
            if c.isNumber || c == "." {
                var j = i
                while j < mapped.endIndex, mapped[j].isNumber || mapped[j] == "." { j = mapped.index(after: j) }
                // Scientific notation: 1e5, 2.5E-3
                if j < mapped.endIndex, mapped[j] == "e" || mapped[j] == "E" {
                    var k = mapped.index(after: j)
                    if k < mapped.endIndex, mapped[k] == "-" || mapped[k] == "+" { k = mapped.index(after: k) }
                    if k < mapped.endIndex, mapped[k].isNumber {
                        j = k
                        while j < mapped.endIndex, mapped[j].isNumber { j = mapped.index(after: j) }
                    }
                }
                guard let v = Double(mapped[i..<j]) else { throw Failure.syntax }
                tokens.append(.number(v)); i = j; continue
            }
            if c.isLetter {
                var j = i
                while j < mapped.endIndex, mapped[j].isLetter || mapped[j].isNumber { j = mapped.index(after: j) }
                tokens.append(.ident(mapped[i..<j].lowercased())); i = j; continue
            }
            switch c {
            case "+", "-", "*", "/", "%", "^", "!": tokens.append(.op(c))
            case "(": tokens.append(.lparen)
            case ")": tokens.append(.rparen)
            default: throw Failure.syntax
            }
            i = mapped.index(after: i)
        }
        return tokens
    }

    private struct Parser {
        let tokens: [Token]
        let degrees: Bool
        var pos = 0
        var atEnd: Bool { pos == tokens.count }

        init(tokens: [Token], degrees: Bool) { self.tokens = tokens; self.degrees = degrees }

        mutating func peek() -> Token? { pos < tokens.count ? tokens[pos] : nil }
        mutating func next() -> Token? { defer { pos += 1 }; return peek() }

        mutating func expression() throws -> Double {
            var v = try term()
            while case .op(let o)? = peek(), o == "+" || o == "-" {
                pos += 1
                let r = try term()
                v = o == "+" ? v + r : v - r
            }
            return v
        }

        mutating func term() throws -> Double {
            var v = try unary()
            while case .op(let o)? = peek(), o == "*" || o == "/" || o == "%" {
                pos += 1
                let r = try unary()
                switch o {
                case "*": v *= r
                case "/": guard r != 0 else { throw Failure.domain }; v /= r
                default: guard r != 0 else { throw Failure.domain }; v = v.truncatingRemainder(dividingBy: r)
                }
            }
            return v
        }

        /// Unary minus binds looser than ^, so -2^2 = -4 (standard convention).
        mutating func unary() throws -> Double {
            if case .op(let o)? = peek(), o == "-" || o == "+" {
                pos += 1
                let v = try unary()
                return o == "-" ? -v : v
            }
            return try power()
        }

        mutating func power() throws -> Double {
            let base = try postfix()
            if case .op("^")? = peek() {
                pos += 1
                return Foundation.pow(base, try unary())   // right-associative; allows 2^-1
            }
            return base
        }

        mutating func postfix() throws -> Double {
            var v = try primary()
            while case .op("!")? = peek() {
                pos += 1
                guard v >= 0, v == v.rounded(), v <= 170 else { throw Failure.domain }
                v = (1...max(Int(v), 1)).reduce(1.0) { $0 * Double($1) }
            }
            return v
        }

        mutating func primary() throws -> Double {
            switch next() {
            case .number(let v)?: return v
            case .lparen?:
                let v = try expression()
                guard case .rparen? = next() else { throw Failure.syntax }
                return v
            case .ident(let name)?:
                if name == "pi" { return .pi }
                if name == "e" { return M_E }
                guard case .lparen? = peek() else { throw Failure.syntax }
                pos += 1
                let arg = try expression()
                guard case .rparen? = next() else { throw Failure.syntax }
                return try apply(name, arg)
            default: throw Failure.syntax
            }
        }

        func apply(_ name: String, _ x: Double) throws -> Double {
            let rad = degrees ? x * .pi / 180 : x
            func inv(_ v: Double) -> Double { degrees ? v * 180 / .pi : v }
            switch name {
            case "sin": return Foundation.sin(rad)
            case "cos": return Foundation.cos(rad)
            case "tan": return Foundation.tan(rad)
            case "asin": return inv(Foundation.asin(x))
            case "acos": return inv(Foundation.acos(x))
            case "atan": return inv(Foundation.atan(x))
            case "sqrt": guard x >= 0 else { throw Failure.domain }; return x.squareRoot()
            case "cbrt": return Foundation.cbrt(x)
            case "ln": guard x > 0 else { throw Failure.domain }; return Foundation.log(x)
            case "log": guard x > 0 else { throw Failure.domain }; return Foundation.log10(x)
            case "log2": guard x > 0 else { throw Failure.domain }; return Foundation.log2(x)
            case "abs": return Swift.abs(x)
            case "exp": return Foundation.exp(x)
            case "round": return x.rounded()
            case "floor": return Foundation.floor(x)
            case "ceil": return Foundation.ceil(x)
            default: throw Failure.syntax
            }
        }
    }
}
