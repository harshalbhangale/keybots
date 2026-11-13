import Foundation

enum Fmt {
    /// yoctoNEAR (decimal string) -> "0.5 NEAR", exact, trimmed to 4 decimals.
    static func near(_ yocto: String, unit: Bool = true) -> String {
        let digits = yocto.filter(\.isNumber)
        let padded = String(repeating: "0", count: max(0, 25 - digits.count)) + digits
        let whole = String(padded.dropLast(24)).drop(while: { $0 == "0" })
        var frac = String(padded.suffix(24).prefix(4))
        while frac.hasSuffix("0") { frac.removeLast() }
        let n = (whole.isEmpty ? "0" : String(whole)) + (frac.isEmpty ? "" : "." + frac)
        return unit ? "\(n) NEAR" : n
    }

    /// 0...1 share of `part` in `whole`, both yoctoNEAR strings.
    static func share(_ part: String, of whole: String) -> Double {
        let p = Double(near(part, unit: false)) ?? 0
        let w = Double(near(whole, unit: false)) ?? 0
        return w > 0 ? min(1, p / w) : 0
    }

    /// "pay.airkey-harshal.testnet" -> "pay"
    static func short(_ account: String) -> String {
        account.split(separator: ".").first.map(String.init) ?? account
    }

    static func agentName(_ tier: String) -> String {
        tier == "trusted" ? "Payment Agent" : "Inbox Agent"
    }

    /// Named by the account's first part: pay.<you> is the Payment Agent.
    static func agentName(account: String) -> String {
        switch short(account) {
        case "pay": "Payment Agent"
        case "inbox": "Inbox Agent"
        case "trade", "trader": "Trading Agent"
        case "copy": "Copy Agent"
        case let other: other.prefix(1).uppercased() + other.dropFirst() + " Agent"
        }
    }

    static func agentPurpose(account: String, tier: String) -> String {
        switch short(account) {
        case "pay": "Pays for what you type, within its caps."
        case "inbox": "Reads messages other people send you. It can pay your allowlist; anyone else waits for you."
        case "trade", "trader": "Swaps tokens you ask for, within its caps."
        default: tier == "trusted" ? "Acts on what you type, within its caps." : "Acts on other people's words. Anyone off your allowlist waits for you."
        }
    }

    /// "Today", "Yesterday", or "12 Nov".
    static func day(_ date: Date?) -> String {
        guard let date else { return "Earlier" }
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }

    /// "$2.41", "$81,250.00", "$0.0042": two decimals, more for tiny prices.
    static func usd(_ v: Double) -> String {
        v.formatted(.currency(code: "USD").precision(.fractionLength(v > 0 && v < 1 ? 2...4 : 2...2)))
    }

    /// "₹8,870.50": an amount in its own currency.
    static func money(_ v: Double, _ code: String) -> String {
        v.formatted(.currency(code: code).precision(.fractionLength(0...2)))
    }

    static func time(_ date: Date?) -> String {
        guard let date else { return "" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: .now)
    }

    static func greeting(_ now: Date = .now) -> String {
        switch Calendar.current.component(.hour, from: now) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
    }
}
