import Foundation

/// What the words on screen would do, read on the phone as you type. It only
/// previews: the AIRKEY server reads the command again (server/src/parse.ts,
/// same patterns) and the leash decides.
struct Intent: Equatable {
    enum Kind { case pay, swap }

    let kind: Kind
    /// "Pay 0.5 NEAR to harshal.near", "Swap 20 USDC to SOL"
    let title: String
    /// "for dinner"
    let detail: String?

    var icon: String { kind == .pay ? "arrow.up.right" : "arrow.left.arrow.right" }

    static func read(_ text: String) -> Intent? {
        // The last line is the message being written.
        guard let line = text.split(whereSeparator: \.isNewline).last.map(String.init)?.trimmingCharacters(in: .whitespaces), line.count >= 6 else { return nil }

        if let m = match(swap, line) {
            return Intent(kind: .swap, title: "Swap \(m[1]) \(m[2].uppercased()) to \(m[3].uppercased())", detail: nil)
        }
        if let m = match(amountFirst, line), usable(m[2]) {
            return pay(to: m[2], amount: m[1], memo: m[3])
        }
        if let m = match(receiverFirst, line), usable(m[1]) {
            return pay(to: m[1], amount: m[2], memo: m[3])
        }
        return nil
    }

    private static func pay(to receiver: String, amount: String, memo: String) -> Intent {
        let name = receiver.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".,;:"))
        let note = memo.trimmingCharacters(in: CharacterSet(charactersIn: " .!?"))
        return Intent(kind: .pay, title: "Pay \(amount) NEAR to \(name)", detail: note.isEmpty ? nil : "for \(note)")
    }

    /// A receiver is a name, not a number and not one of the command's own words.
    private static func usable(_ receiver: String) -> Bool {
        let r = receiver.lowercased()
        return !r.isEmpty && r.first?.isNumber == false && !["near", "to", "for"].contains(r)
    }

    private static let verb = "(?:pay|send|give|transfer|tip)"
    private static let amount = #"(\d+(?:\.\d+)?)"#
    private static let unit = #"(?:\s*(?:near|Ⓝ))?"#
    private static let account = #"([a-z0-9_-]+(?:\.[a-z0-9_-]+)*)"#
    private static let memo = #"(?:\s+(?:for|re|memo:?)\s+(.+?))?"#

    private static let swap = regex(#"\bswap\s+"# + amount + #"\s*([a-z][a-z0-9]{1,9})\s+(?:to|for|into)\s+([a-z][a-z0-9]{1,9})\b"#)
    private static let amountFirst = regex(#"\b"# + verb + #"\s+"# + amount + unit + #"\s+(?:to\s+)?"# + account + memo + #"\s*[.!?]*$"#)
    private static let receiverFirst = regex(#"\b"# + verb + #"\s+"# + account + #"\s+"# + amount + unit + memo + #"\s*[.!?]*$"#)

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // The patterns are constants; a typo here should fail loudly in development.
        try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    /// Capture groups as strings ("" for a group that didn't take part), or nil for no match.
    private static func match(_ re: NSRegularExpression, _ s: String) -> [String]? {
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (0..<m.numberOfRanges).map { i in
            let r = m.range(at: i)
            return r.location == NSNotFound ? "" : ns.substring(with: r)
        }
    }
}
