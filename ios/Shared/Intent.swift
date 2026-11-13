import Foundation

/// What the words on screen would do, read on the phone as you type. It only
/// previews: the AIRKEY server reads the command again (server/src/parse.ts,
/// same patterns) and the leash decides.
struct Intent: Equatable {
    enum Kind { case pay, swap }

    let kind: Kind
    /// "Pay 0.5 NEAR to harshal.near", "Swap 20 USDC to SOL"
    let title: String
    /// "for dinner", or which agent handles it
    let detail: String?
    /// The word on the hold button: "Hold to pay", "Hold to buy".
    var verb = "pay"

    var icon: String { kind == .pay ? "arrow.up.right" : "arrow.left.arrow.right" }
    var holdLabel: String { "Hold to \(verb)" }

    static func read(_ text: String) -> Intent? {
        // The last line is the message being written.
        guard let line = text.split(whereSeparator: \.isNewline).last.map(String.init)?.trimmingCharacters(in: .whitespaces), line.count >= 6 else { return nil }

        // "<a trade> if it drops below 2": an order for the Trading Agent to wait on.
        if let m = match(when, line), let trade = read(m[1]), trade.kind == .swap {
            let below = ["below", "under"].contains(m[2].lowercased())
            return Intent(kind: .swap, title: trade.title, detail: "Runs when the price is \(below ? "below" : "above") $\(m[3])", verb: "place")
        }
        if let m = match(swap, line) {
            return Intent(kind: .swap, title: "Swap \(m[1]) \(m[2].uppercased()) to \(m[3].uppercased())", detail: nil, verb: "swap")
        }
        // Buying and selling only light up for tokens NEAR Intents lists, so
        // "buy 2 tickets" or "sell 3 chairs" stays an ordinary message.
        if let m = match(buyDollar, line) ?? match(buyWords, line), Tokens.known.contains(m[2].uppercased()), m[2].uppercased() != "USDC" {
            return Intent(kind: .swap, title: "Buy $\(m[1]) of \(m[2].uppercased())", detail: "Trading Agent gets a quote first", verb: "buy")
        }
        if let m = match(sell, line), Tokens.known.contains(m[2].uppercased()) {
            let to = m[3].isEmpty ? "USDC" : m[3].uppercased()
            if to != m[2].uppercased(), Tokens.known.contains(to) {
                return Intent(kind: .swap, title: "Sell \(m[1]) \(m[2].uppercased()) for \(to)", detail: "Trading Agent gets a quote first", verb: "sell")
            }
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

    private static let symbol = #"\$?([a-z][a-z0-9]{1,9})"#
    private static let buyDollar = regex(#"\bbuy\s+\$\s*"# + amount + #"\s+(?:worth\s+)?(?:of\s+)?"# + symbol + #"\b"#)
    private static let buyWords = regex(#"\bbuy\s+"# + amount + #"\s*(?:usdc?|dollars?|bucks)\s+(?:worth\s+)?(?:of\s+)?"# + symbol + #"\b"#)
    private static let sell = regex(#"\bsell\s+"# + amount + #"\s*"# + symbol + #"(?:\s+(?:for|to|into)\s+"# + symbol + #")?\b"#)

    private static let when = regex(#"^(.+?)\s+(?:if|when|once|whenever)\s+(?:it|the\s+price|\$?[a-z][a-z0-9]{1,9})?\s*(?:drops?|falls?|dips?|goes|is|gets|rises?|climbs?|hits)?\s*(?:to\s+)?(below|under|above|over|past)\s+\$?"# + amount + #"\s*[.!?]*$"#)
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

/// The token symbols the keyboard will offer trades in: NEAR Intents' own list,
/// fetched from the AIRKEY server and kept in the App Group, with the majors
/// built in for before the first fetch.
enum Tokens {
    private static let key = "tokenSymbols"
    private static let stamp = "tokenSymbolsAt"
    private static let majors: Set<String> = ["NEAR", "WNEAR", "SOL", "BTC", "ETH", "USDC", "USDT", "ZEC", "DOGE", "XRP", "BNB", "SUI", "TON", "TRX", "ADA", "APT", "ARB", "OP", "AURORA"]

    static var known: Set<String> {
        guard let saved = Settings.store.stringArray(forKey: key), !saved.isEmpty else { return majors }
        return Set(saved)
    }

    /// True when the saved list is missing or more than six hours old.
    static var stale: Bool {
        Date().timeIntervalSince1970 - Settings.store.double(forKey: stamp) > 6 * 3600
    }

    static func save(_ symbols: [String]) {
        guard !symbols.isEmpty else { return }
        Settings.store.set(symbols.map { $0.uppercased() }, forKey: key)
        Settings.store.set(Date().timeIntervalSince1970, forKey: stamp)
    }
}
