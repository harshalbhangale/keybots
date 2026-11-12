import Foundation

/// An answer the keyboard works out on the phone as you type: no AI, no
/// network. A sum, a percentage, or a bill split between people.
struct Instant: Equatable {
    /// "= 441", "59 each"
    let title: String
    /// "18% of 2450", "236 split 4 ways"
    let detail: String
    /// What a tap adds to the message: " = 441"
    let insert: String

    static func read(_ text: String) -> Instant? {
        guard let line = text.split(whereSeparator: \.isNewline).last.map(String.init)?.trimmingCharacters(in: .whitespaces), line.count >= 3 else { return nil }
        return split(line) ?? percent(line) ?? sum(line)
    }

    // MARK: a bill between people

    /// "236 for 4 of us", "split 236 by 4", "236 split 4 ways"
    private static func split(_ line: String) -> Instant? {
        let n = #"(\d+(?:\.\d+)?)"#
        let patterns = [
            #"\bsplit\s+\$?"# + n + #"\s+(?:by|between|among|with|for|in)\s+(\d+)\b"#,
            #"\$?"# + n + #"\s+(?:split\s+)?(?:by|between|among|for)\s+(\d+)\s+(?:of us|people|ppl|ways|friends)\b"#,
            #"\$?"# + n + #"\s+split\s+(\d+)(?:\s+ways)?\b"#,
        ]
        for p in patterns {
            guard let m = match(p, line), let total = Double(m[1]), let people = Double(m[2]), people >= 2, people <= 1000 else { continue }
            let each = format(total / people)
            return Instant(title: "\(each) each", detail: "\(m[1]) split \(m[2]) ways", insert: " = \(each) each")
        }
        return nil
    }

    // MARK: a percentage

    /// "18% of 2450"
    private static func percent(_ line: String) -> Instant? {
        guard let m = match(#"(\d+(?:\.\d+)?)\s*%\s*of\s*\$?(\d+(?:\.\d+)?)\s*=?\s*$"#, line), let pct = Double(m[1]), let of = Double(m[2]) else { return nil }
        let v = format(pct * of / 100)
        return Instant(title: "= \(v)", detail: "\(m[1])% of \(m[2])", insert: " = \(v)")
    }

    // MARK: a sum

    /// The sum the line ends with: "12*4+3", "(120 + 80) / 4 =".
    private static func sum(_ line: String) -> Instant? {
        guard let m = match(#"(\(?\d[\d.\s+\-*/×÷()]*[\d)])\s*(=?)\s*$"#, line) else { return nil }
        let raw = m[1].trimmingCharacters(in: .whitespaces)
        let compact = raw.filter { !$0.isWhitespace }
        // Needs an operator between numbers, and must not be a date, a phone number or "24/7".
        guard compact.contains(where: { "+-*/×÷".contains($0) }), compact.first != "-" else { return nil }
        if match(#"^\d{1,4}[-/.]\d{1,2}[-/.]\d{1,4}$"#, compact) != nil { return nil }  // 12/11/2026
        if match(#"^\d{1,2}/\d{1,2}$"#, compact) != nil { return nil }  // 12/11, 24/7, 1/2
        if match(#"^\d+(-\d+){1,}$"#, compact) != nil, compact.count >= 7 { return nil }  // 555-0100, 98765-43210
        // "4-2" with nothing around it is as likely a score or a room as a sum.
        if match(#"^\d+(-\d+)+$"#, compact) != nil, raw == compact, m[2].isEmpty { return nil }
        var parser = Parser(compact)
        guard let value = parser.parse(), value.isFinite else { return nil }
        let v = format(value)
        return Instant(title: "= \(v)", detail: raw, insert: m[2].isEmpty ? " = \(v)" : " \(v)")
    }

    /// + - × ÷ and brackets, the usual way round.
    private struct Parser {
        private let chars: [Character]
        private var i = 0
        init(_ s: String) { chars = Array(s) }

        mutating func parse() -> Double? {
            guard let v = expression(), i == chars.count else { return nil }
            return v
        }

        private mutating func expression() -> Double? {
            guard var v = term() else { return nil }
            while i < chars.count, chars[i] == "+" || chars[i] == "-" {
                let op = chars[i]; i += 1
                guard let r = term() else { return nil }
                v = op == "+" ? v + r : v - r
            }
            return v
        }

        private mutating func term() -> Double? {
            guard var v = factor() else { return nil }
            while i < chars.count, "*/×÷".contains(chars[i]) {
                let op = chars[i]; i += 1
                guard let r = factor() else { return nil }
                if op == "*" || op == "×" { v *= r } else { guard r != 0 else { return nil }; v /= r }
            }
            return v
        }

        private mutating func factor() -> Double? {
            guard i < chars.count else { return nil }
            if chars[i] == "(" {
                i += 1
                guard let v = expression(), i < chars.count, chars[i] == ")" else { return nil }
                i += 1
                return v
            }
            if chars[i] == "-" { i += 1; return factor().map { -$0 } }
            let start = i
            while i < chars.count, chars[i].isNumber || chars[i] == "." { i += 1 }
            return Double(String(chars[start..<i]))
        }
    }

    // MARK: helpers

    /// Whole numbers stay whole; the rest get up to two decimals (four if small).
    static func format(_ v: Double) -> String {
        if v == v.rounded(), abs(v) < 1e15 { return String(Int64(v)) }
        let s = String(format: abs(v) < 1 ? "%.4f" : "%.2f", v)
        return s.contains(".") ? s.replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression).replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression) : s
    }

    private static func match(_ pattern: String, _ s: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (0..<m.numberOfRanges).map { i in
            let r = m.range(at: i)
            return r.location == NSNotFound ? "" : ns.substring(with: r)
        }
    }
}
