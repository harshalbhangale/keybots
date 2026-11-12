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

    static func agentPurpose(_ tier: String) -> String {
        tier == "trusted"
            ? "Pays for what you type. Trusted: it can pay anyone within its caps."
            : "Acts on messages from other people. Untrusted: it pays only your allowlist on its own; everyone else waits for you."
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
