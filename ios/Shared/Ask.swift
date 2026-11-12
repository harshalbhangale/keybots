import Foundation

/// Something the keyboard has to look up as you type: a token's price
/// ("$near") or a currency conversion ("100 usd to inr").
enum Ask: Equatable {
    /// `typed` is the text as written ("$near"), so a tap can replace it.
    case price(symbol: String, typed: String)
    case fx(amount: String, from: String, to: String)

    static func read(_ text: String) -> Ask? {
        guard let line = text.split(whereSeparator: \.isNewline).last.map(String.init)?.trimmingCharacters(in: .whitespaces), line.count >= 3 else { return nil }

        if let m = match(#"(?:^|\s)(\$([A-Za-z][A-Za-z0-9]{1,9}))$"#, line) {
            return .price(symbol: m[2].uppercased(), typed: m[1])
        }
        if let m = match(#"(?:^|\s)(\d+(?:\.\d+)?)\s*([A-Za-z]{3})\s+(?:to|in)\s+([A-Za-z]{3})$"#, line) {
            let from = m[2].uppercased(), to = m[3].uppercased()
            if fiat.contains(from), fiat.contains(to), from != to { return .fx(amount: m[1], from: from, to: to) }
        }
        if let m = match(#"(?:^|\s)([$₹€£])\s*(\d+(?:\.\d+)?)\s+(?:to|in)\s+([A-Za-z]{3})$"#, line), let from = signs[m[1]] {
            let to = m[3].uppercased()
            if fiat.contains(to), from != to { return .fx(amount: m[2], from: from, to: to) }
        }
        return nil
    }

    private static let signs = ["$": "USD", "₹": "INR", "€": "EUR", "£": "GBP"]
    private static let fiat: Set<String> = [
        "USD", "INR", "EUR", "GBP", "AED", "JPY", "CNY", "CAD", "AUD", "SGD", "CHF", "HKD", "NZD", "SEK", "NOK", "DKK",
        "ZAR", "BRL", "MXN", "IDR", "THB", "MYR", "PHP", "VND", "KRW", "TRY", "SAR", "QAR", "KWD", "PKR", "BDT", "LKR", "NPR",
    ]

    private static func match(_ pattern: String, _ s: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (0..<m.numberOfRanges).map { i in
            let r = m.range(at: i)
            return r.location == NSNotFound ? "" : ns.substring(with: r)
        }
    }
}

/// What came back for an `Ask`, ready to show above the keys.
struct Answer: Equatable {
    let ask: Ask
    /// "NEAR $2.41", "₹8,870.50"
    let title: String
    /// "Price from NEAR Intents", "100 USD at today's rate"
    let detail: String
    /// What a tap on the answer puts in the message.
    let insert: String
    /// For a price: the command a tap on Buy types, "buy $2 of near".
    let buy: String?
}
