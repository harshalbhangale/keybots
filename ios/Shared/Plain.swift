import Foundation

/// AIRKEY in plain words. Every line a person reads about what happened to
/// their money comes from here, so the keyboard and the app say the same
/// thing, and none of it needs you to know NEAR: no rule codes, no contract
/// names, a contact's name instead of an account.
///
/// A line is worked out from the receipt's own fields (outcome, the rule
/// that decided, the receiver, the checks, the swap). The server's `summary`
/// is used when it sent one; its `message` is only ever reworded as a last
/// resort. The full technical message, with its rule code, stays one tap
/// away as `details`.
enum Plain {
    // MARK: A receipt

    /// What happened and why, in one line: "Blocked: drain.near is on your blocked list".
    static func line(_ r: Receipt) -> String {
        if let s = r.summary, !s.isEmpty { return s }
        return local(r) ?? scrub(r.message)
    }

    /// The line without its opening word, for under a title that already
    /// says it: "Blocked" over "drain.near is on your blocked list".
    static func body(_ r: Receipt) -> String {
        let full = line(r)
        for lead in ["Blocked: ", "Waiting for you: ", "Not sent: "] where full.hasPrefix(lead) {
            let rest = full.dropFirst(lead.count)
            // A name stays as it is written: "drain.near", "vendor".
            let first = rest.split(separator: " ").first.map(String.init) ?? ""
            if first.contains(".") || Contacts.names.contains(first) { return String(rest) }
            return rest.prefix(1).uppercased() + rest.dropFirst()
        }
        return full
    }

    /// The technical message as the server wrote it, with the rule code: for Details.
    static func details(_ r: Receipt) -> String {
        guard let rule = r.decision?.rule, !r.message.contains(rule) else { return r.message }
        return "\(r.message) (\(rule))"
    }

    /// The title over a receipt: what the outcome is called.
    static func title(_ r: Receipt) -> String {
        r.outcome == "swapped" ? "Swapped" : r.signal.title
    }

    /// What the strip says while it waits.
    static func working(pasted: Bool, swap: Bool) -> String {
        pasted ? "Checking this message…" : swap ? "Swapping…" : "Paying…"
    }

    private static func local(_ r: Receipt) -> String? {
        let a = r.interpretation.action
        let name = who(r)
        let rule = r.decision?.rule

        switch r.outcome {
        case "paid":
            guard a.kind == "pay", let amount = a.amountNear else { return nil }
            return "Paid \(amount) NEAR to \(name)"

        case "swapped":
            guard let x = r.swap?.executed else { return nil }
            let sold = x.symbolIn ?? "NEAR"
            guard let out = x.amountOut else { return "Swapping \(x.amountIn) \(sold) for \(x.symbolOut)" }
            return "Swapped \(x.amountIn) \(sold) for \(tidy(out)) \(x.symbolOut)"

        case "approval":
            if rule == "R6" { return "Waiting for you: \(name) isn't on your allowed list" }
            if let f = r.checks?.facts {
                let fresh = (f.ageDays ?? 99) < 7
                if f.isContract == true { return "Waiting for you: this account is an app, not a person" }
                if fresh, f.paidBefore == false { return "Waiting for you: a new account you've never paid" }
                if fresh { return "Waiting for you: this account is only a few days old" }
                if f.paidBefore == false { return "Waiting for you: you've never paid \(name)" }
            }
            return "Waiting for you to approve"

        case "blocked":
            switch rule {
            case "R1": return "Blocked: you turned on Stop everything"
            case "R3": return "Blocked: \(name) is on your blocked list"
            case "R4":
                let kind = a.kind == "swap" ? "per-trade" : "per-payment"
                return near(in: r.decision?.reason).map { "Blocked: over your \($0) NEAR \(kind) limit" } ?? "Blocked: over your \(kind) limit"
            case "R5":
                return near(in: r.decision?.reason).map { "Blocked: over your \($0) NEAR daily limit" } ?? "Blocked: over your daily limit"
            case "R6": return "Blocked: \(name) isn't on your allowed list"
            case "R0": return "Blocked: not enough NEAR in your AIRKEY balance"
            case .some: return nil
            case nil: break
            }
            // Stopped before the chain was asked.
            if r.input.source == "pasted", a.kind == "swap" || a.kind == "watch" {
                return "Blocked: trades only run from what you type, never from a copied message"
            }
            if let s = r.swap, !s.from.verified || !s.to.verified {
                let bad = s.from.verified ? s.to : s.from
                return "Blocked: \(bad.asked.uppercased()) isn't a token we could verify"
            }
            if let l = r.swap?.leash, !l.within {
                let cap = Fmt.near(l.perPaymentCap, unit: false)
                if let worth = Double(l.valueNear), let most = Double(cap), worth > most {
                    return "Blocked: over your \(cap) NEAR per-trade limit"
                }
                if Double(Fmt.near(l.leftToday, unit: false)) ?? 0 > 0 {
                    return "Blocked: only \(Fmt.near(l.leftToday, unit: false)) NEAR left of today's limit"
                }
            }
            return nil

        case "quoted":
            guard let q = r.swap?.quote, let amount = a.amount, let from = a.from, let to = a.to else { return nil }
            return "\(amount) \(from.uppercased()) gets about \(tidy(q.amountOutFormatted)) \(to.uppercased()). Nothing sent yet"

        case "watching":
            guard let o = r.order else { return nil }
            return "Watching \(o.symbol): will \(o.command) when it's \(o.direction) \(Fmt.usd(o.price))"

        default:
            if let x = r.swap?.executed, !x.ok { return "Not swapped: \(x.venue) couldn't fill it. Your NEAR is safe" }
            return nil
        }
    }

    // MARK: Names

    /// The name you know someone by: your contact's name when there is one, else the account.
    static func name(_ account: String) -> String {
        Contacts.name(for: account) ?? account
    }

    private static func who(_ r: Receipt) -> String {
        guard let rc = r.receiver else { return r.interpretation.action.receiver ?? "them" }
        return rc.via == "contacts" ? rc.asked.lowercased() : name(rc.account)
    }

    /// An agent by what it does. The server says which account plays which
    /// role; without that, the account's first part does ("pay.you.near").
    static func agent(role: String) -> String {
        switch role {
        case "pay", "trusted": "Payments"
        case "inbox", "untrusted": "Messages you copy"
        case "trade", "trader": "Trades"
        case "copy": "Copied trades"
        default: role.prefix(1).uppercased() + role.dropFirst()
        }
    }

    static let trades = agent(role: "trade")

    /// What an agent does, in a sentence.
    static func purpose(role: String, tier: String) -> String {
        switch role {
        case "pay": "Pays when you type a payment, up to these limits."
        case "inbox": "Reads messages you copy. It can pay people on your allowed list; anyone else waits for you."
        case "trade", "trader": "Swaps tokens when you ask, up to these limits."
        default: tier == "trusted" ? "Acts on what you type, up to these limits." : "Acts on other people's words. Anyone off your allowed list waits for you."
        }
    }

    /// Whose words an agent acts on, for the small tag on its card.
    static func tier(_ tier: String) -> String {
        tier == "trusted" ? "Your words" : "Others' words"
    }

    // MARK: Waiting and blocked

    /// Why a payment is waiting for you.
    static func pending(_ p: LeashState.Pending) -> String {
        switch p.rule {
        case "R6": "It came from a message you copied, and \(name(p.receiver)) isn't on your allowed list."
        case "R7": "AIRKEY doesn't know this account yet, so it asks you first."
        default: scrub(p.reason)
        }
    }

    /// Why an account is on your blocked list.
    static func blockedReason(_ reason: String) -> String {
        var s = reason
        if let r = s.range(of: #"^reported by [^:]+:\s*"#, options: [.regularExpression, .caseInsensitive]) {
            let why = s[r.upperBound...]
            s = "Reported as a scam: " + why
        }
        if s == "Blocked by the owner" { return "You blocked it" }
        return scrub(s)
    }

    /// A check on the receiver, reworded where it used a word from the contract.
    static func check(_ reason: String) -> String { scrub(reason) }

    /// The name of a change you signed ("set_paused"), in words.
    static func change(_ method: String) -> String {
        switch method {
        case "set_paused": "Stop everything"
        case "allow": "added to your allowed list"
        case "disallow": "removed from your allowed list"
        case "block": "added to your blocked list"
        case "unblock": "removed from your blocked list"
        case "approve": "approved a payment"
        case "reject": "rejected a payment"
        default: method.replacingOccurrences(of: "_", with: " ")
        }
    }

    // MARK: Old wording

    /// Rewords a message written for someone who knows the contract. Only
    /// for text that has no fields to work from: an older server's message,
    /// a reason stored on chain.
    static func scrub(_ text: String) -> String {
        var s = text
        for (pattern, plain) in rewrites {
            s = s.replacingOccurrences(of: pattern, with: plain, options: .regularExpression)
        }
        for (account, name) in Contacts.byAccount where s.contains(account) {
            s = s.replacingOccurrences(of: account, with: name)
        }
        return s
    }

    private static let rewrites: [(String, String)] = [
        (#"Blocked by the leash \(R\d\): "#, "Blocked by Spend Limits: "),
        (#"The leash would block this: "#, "Spend Limits would block this: "),
        (#"\s*\(R\d\)"#, ""),
        (#"The Inbox Agent can't (trade|set one)"#, "A copied message can't $1"),
        (#"(?i)the kill switch is on|kill switch is on"#, "Stop everything is on"),
        (#"(The|the) leash contract"#, "Spend Limits"),
        (#"(The|the) leash"#, "Spend Limits"),
        (#"(your|Your) leash"#, "Spend Limits"),
        (#"(The|the) (Inbox|Trading|Payment|Copy) Agent"#, "AIRKEY"),
        (#"(Inbox|Trading|Payment|Copy) Agent"#, "AIRKEY"),
        (#"The agent asked you to approve this one"#, "AIRKEY asks you first for this one"),
        (#"reported by [a-z0-9_-]+(\.[a-z0-9_-]+)+"#, "reported by AIRKEY"),
        (#"allowlist"#, "allowed list"),
        (#"blocklist"#, "blocked list"),
        (#"\bcaps\b"#, "limits"),
        (#"\bcap\b"#, "limit"),
        (#"\buntrusted\b"#, "someone else's"),
        (#"\bwNEAR\b"#, "NEAR"),
    ]

    // MARK: Numbers

    /// "0.5" out of "Over the per-payment cap of 0.5 NEAR".
    private static func near(in reason: String?) -> String? {
        guard let reason, let r = reason.range(of: #"\d+(?:\.\d+)?(?=\s*NEAR)"#, options: .regularExpression) else { return nil }
        return String(reason[r])
    }

    /// A number for a sentence: "0.124112944945" -> "0.1241".
    static func tidy(_ n: String) -> String {
        guard let v = Double(n) else { return n }
        return v.formatted(.number.precision(.significantDigits(1...4)).grouping(.never).locale(Locale(identifier: "en_US_POSIX")))
    }
}
