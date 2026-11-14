import Observation
import UIKit

/// The trade panel's state: what you pay, what you get, and the server's
/// quote for it. Nothing here invents a number: the cards and the details
/// show only what GET /v1/quote answered for exactly the trade on screen,
/// and the hold sends that quote's own `command`.
@Observable
@MainActor
final class TradeModel {
    /// What the hold does: swap now, or leave an order waiting for a price.
    enum Kind: String, CaseIterable, Identifiable {
        case swap, limit, stop, take
        var id: String { rawValue }
        var title: String {
            switch self {
            case .swap: "Swap"
            case .limit: "Limit"
            case .stop: "Stop-loss"
            case .take: "Take profit"
            }
        }
        var hold: String { self == .swap ? "Hold to swap" : "Hold to place order" }
    }
    enum Side: Equatable { case pay, get }
    enum Field: Equatable { case amount, trigger }
    /// The whole panel, a value being typed on the keys, or the token list.
    enum Mode: Equatable {
        case panel
        case number(Field)
        case tokens(Side)
        case search(Side)
    }

    /// A trade to open the panel on, read from a command ("swap 0.5 near to usdc").
    struct Seed: Equatable {
        var kind = Kind.swap
        var from = "NEAR"
        var to = "USDC"
        var amount = ""
        /// The amount is dollars' worth of `from`, turned into tokens at the list price.
        var dollars = false
        var trigger = ""
    }

    var kind = Kind.swap
    var from = "NEAR"
    var to = "USDC"
    var amount = ""
    var trigger = ""
    private(set) var mode = Mode.panel

    /// The server's answer for the trade on screen (nil until one lands, or after an edit that has no answer yet).
    private(set) var quote: TradeQuote?
    private(set) var asking = false
    /// Why there is no quote, in the server's words.
    private(set) var failure: String?
    private(set) var tokens: [PickerToken] = []
    private(set) var tokensFailed = false
    var query = ""

    @ObservationIgnored var hasFullAccess = true
    /// Dollars waiting for a price, from a seed like "swap $1 of near to usdc".
    @ObservationIgnored private var seedDollars: Double?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var asked = ""
    /// The mode changed: the keyboard lays the panel out again and points its keys at it (or back).
    @ObservationIgnored var onMode: (() -> Void)?
    /// What the keys have typed should now read `text` (after digits-only tidying).
    @ObservationIgnored var onTyped: ((String) -> Void)?
    @ObservationIgnored var onRun: ((String) -> Void)?
    @ObservationIgnored var onClose: (() -> Void)?

    init(seed: Seed = Seed()) {
        kind = seed.kind
        from = seed.from
        to = seed.to
        trigger = seed.trigger
        if seed.dollars { seedDollars = Double(seed.amount) } else { amount = seed.amount }
    }

    // MARK: What the panel shows

    var amountValue: Double? { Double(amount).flatMap { $0 > 0 ? $0 : nil } }
    var triggerValue: Double? { Double(trigger).flatMap { $0 > 0 ? $0 : nil } }
    var isOrder: Bool { kind != .swap }

    /// The quote, only while it is for exactly what's on screen.
    var live: TradeQuote? { quote.flatMap { asked == key ? $0 : nil } }

    func token(_ symbol: String) -> PickerToken? { tokens.first { $0.symbol == symbol } }

    /// "≈ $1.76" for a side, from NEAR Intents' price.
    func dollars(_ side: Side) -> String? {
        if side == .pay {
            if let v = live?.valueUsd { return "≈ $\(v)" }
            guard let a = amountValue, let p = token(from)?.price else { return nil }
            return "≈ \(Fmt.usd(a * p))"
        }
        guard let q = live, let out = Double(q.amountOut), let p = q.to.price else { return nil }
        return "≈ \(Fmt.usd(out * p))"
    }

    /// "Spend Limits: 0.61 NEAR" for a side.
    func held(_ side: Side) -> String? {
        let symbol = side == .pay ? from : to
        if side == .pay, let b = live?.balance { return "Spend Limits: \(b.amount) \(b.symbol)" }
        guard let t = token(symbol) else { return nil }
        return "Spend Limits: \(t.balance ?? "0") \(symbol)"
    }

    /// The token an order watches, as the server would pick it.
    var watched: String {
        if let o = live?.order { return o.symbol }
        let dollarsIn = ["USDC", "USDT", "DAI"].contains(from)
        return dollarsIn ? to : from
    }
    var watchedPrice: Double? {
        if let now = live?.order?.now { return now }
        if let q = live { return watched == q.from.symbol ? q.from.price : q.to.price }
        return token(watched)?.price
    }
    /// "below" or "above": which way the price has to go.
    var direction: String {
        if let o = live?.order { return o.direction }
        switch kind {
        case .stop: return "below"
        case .take: return "above"
        default: return ["USDC", "USDT", "DAI"].contains(from) ? "below" : "above"
        }
    }

    /// Why the hold is off, as the few words on the button; nil when it may run.
    /// Errors show nowhere else: the button says what is wrong.
    var blocked: String? {
        guard hasFullAccess else { return "Turn on Allow Full Access" }
        guard amountValue != nil else { return "Enter an amount" }
        if isOrder, triggerValue == nil { return "Set a trigger price" }
        guard let q = live else {
            if asking { return "Getting the price…" }
            return failure.map(Self.short) ?? "Getting the price…"
        }
        if q.ready { return nil }
        if !q.executable { return q.reason.map(Self.short) ?? "Quote only" }
        if q.caps?.paused == true { return "The kill switch is on" }
        if let c = q.caps, !c.within {
            let over = (Double(c.valueNear ?? "") ?? 0) > (Double(c.perTrade) ?? .infinity)
            if over { return "Over your \(c.perTrade) NEAR per-trade limit" }
            if !isOrder { return "Only \(c.leftToday) NEAR left today" }
        }
        if let b = q.balance, !b.enough, !isOrder { return "Not enough \(b.symbol)" }
        if let o = q.order, let now = o.now { return "\(o.symbol) is already \(o.direction) $\(o.trigger) (\(Fmt.usd(now)))" }
        return q.problem.map(Self.short) ?? (isOrder ? "Can't place this" : "Can't swap this")
    }

    /// The first sentence of a server message, to fit a button: "Testnet has no SOL".
    private static func short(_ message: String) -> String {
        if message.hasPrefix("Can't reach") { return "Can't reach your Keybots server" }
        let first = message.split(separator: ".", maxSplits: 1).first.map(String.init) ?? message
        let colon = first.split(separator: ":", maxSplits: 1).first.map(String.init) ?? first
        return String((first.count <= 34 ? first : colon).prefix(40))
    }

    /// The words on the hold: "Hold to swap ≈ $1.76".
    var holdLabel: String {
        guard !isOrder, let usd = live?.valueUsd else { return kind.hold }
        return "\(kind.hold) ≈ $\(usd)"
    }

    /// What an order will do, in one plain line under the details.
    var orderLine: String? { blocked == nil ? live?.order?.line : nil }

    // MARK: Edits

    func open() {
        loadTokens()
        requote(now: true)
    }

    func set(kind next: Kind) {
        guard next != kind else { return }
        kind = next
        Haptics.layer()
        requote(now: true)
    }

    func flip() {
        swap(&from, &to)
        // What you were getting is now what you pay: carry the quoted figure across.
        if let out = live?.amountOut { amount = out }
        Haptics.modifier()
        requote(now: true)
    }

    /// All of what the leash holds of the token being paid.
    func useMax() {
        guard let held = live?.balance?.amount ?? token(from)?.balance, (Double(held) ?? 0) > 0 else { return }
        amount = held
        Haptics.layer()
        requote(now: true)
    }

    func pick(_ token: PickerToken, for side: Side) {
        let other = side == .pay ? to : from
        if token.symbol == other {
            swap(&from, &to)
        } else if side == .pay {
            from = token.symbol
        } else {
            to = token.symbol
        }
        Haptics.layer()
        query = ""
        show(.panel)
        requote(now: true)
    }

    func show(_ next: Mode) {
        guard next != mode else { return }
        mode = next
        if case .search = next {} else { query = "" }
        onMode?()
    }

    /// What the keys type into right now, if anything.
    var typing: String? {
        switch mode {
        case .number(.amount): amount
        case .number(.trigger): trigger
        case .search: query
        default: nil
        }
    }

    /// The keys typed: `text` is everything in the field now.
    func typed(_ text: String) {
        switch mode {
        case .number(let field):
            let clean = Self.number(text)
            if clean != text { onTyped?(clean) }
            if field == .amount {
                guard clean != amount else { return }
                amount = clean
            } else {
                guard clean != trigger else { return }
                trigger = clean
            }
            requote(now: false)
        case .search:
            let clean = String(text.filter { $0.isLetter || $0.isNumber }.prefix(12))
            if clean != text { onTyped?(clean) }
            query = clean
        default:
            break
        }
    }

    /// Digits and one point, as an amount is written: "007" is "7", "." is "0.".
    static func number(_ text: String) -> String {
        var out = ""
        var point = false
        for c in text {
            if c.isASCII, c.isNumber {
                out.append(c)
            } else if c == "." || c == ",", !point {
                point = true
                out.append(".")
            }
        }
        if out.hasPrefix(".") { out = "0" + out }
        while out.count > 1, out.hasPrefix("0"), !out.hasPrefix("0.") { out.removeFirst() }
        return String(out.prefix(12))
    }

    var matches: [PickerToken] {
        let q = query.uppercased()
        guard !q.isEmpty else { return tokens }
        return tokens.filter { $0.symbol.hasPrefix(q) } + tokens.filter { !$0.symbol.hasPrefix(q) && $0.symbol.contains(q) }
    }

    // MARK: The server

    private var key: String { "\(kind.rawValue)|\(from)|\(to)|\(amount)|\(isOrder ? trigger : "")" }

    /// Ask again for what's on screen: at once after a tap, 0.3 s after the last key.
    func requote(now: Bool) {
        task?.cancel()
        failure = nil
        guard hasFullAccess, amountValue != nil else {
            asking = false
            quote = nil
            asked = ""
            return
        }
        let want = key
        guard want != asked || quote == nil else { asking = false; return }
        asking = true
        let (from, to, amount) = (from, to, amount.hasSuffix(".") ? String(amount.dropLast()) : amount)
        let order = isOrder && triggerValue != nil ? kind.rawValue : nil
        let trigger = trigger.hasSuffix(".") ? String(trigger.dropLast()) : trigger
        task = Task {
            if !now { try? await Task.sleep(for: .milliseconds(300)) }
            guard !Task.isCancelled else { return }
            do {
                let q = try await API().quote(from: from, to: to, amount: amount, order: order, trigger: order == nil ? nil : trigger)
                guard !Task.isCancelled, want == key else { return }
                quote = q
                asked = want
                failure = nil
            } catch {
                guard !Task.isCancelled, want == key else { return }
                quote = nil
                asked = ""
                failure = error.localizedDescription
            }
            asking = false
        }
    }

    /// The token list, once per panel: prices and the leash's balances.
    func loadTokens() {
        guard hasFullAccess, tokens.isEmpty else { return }
        tokensFailed = false
        Task {
            guard let list = try? await API().tokenList() else { tokensFailed = true; return }
            tokens = list
            // "swap $1 of near to usdc": the dollars become NEAR at the list's price, as the server does it.
            if let usd = seedDollars, let price = token(from)?.price, price > 0 {
                seedDollars = nil
                amount = Self.number(String(format: "%.4f", usd / price)).trimmingZeros
                requote(now: true)
            }
        }
    }

    /// The hold: send the quote's own command, exactly as shown.
    func run() {
        guard blocked == nil, let q = live else { return }
        Haptics.hold()
        onRun?(q.command)
    }

    // MARK: Reading a command

    /// "swap 0.5 near to usdc", "buy $2 of near", "sell 1 near if it drops below 2": the panel opens on it.
    static func seed(from command: String) -> Seed? {
        var text = command.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        var seed = Seed()
        var condition: (below: Bool, price: String)?
        if let m = match(#"^(.+?)\s+(?:if|when|once|whenever)\s+.*?(below|under|above|over|past)\s+\$?(\d+(?:\.\d+)?)\s*[.!?]*$"#, text) {
            text = m[1]
            condition = (["below", "under"].contains(m[2]), m[3])
        }
        if let m = match(#"\b(?:swap|convert|exchange|trade)\s+(?:\$\s*(\d+(?:\.\d+)?)|(\d+(?:\.\d+)?)\s*(?:\$|usd|dollars?|bucks))\s+(?:worth\s+)?(?:of\s+)?\$?([a-z][a-z0-9]{1,9})\s+(?:to|for|into)\s+\$?([a-z][a-z0-9]{1,9})\b"#, text) {
            seed.amount = m[1].isEmpty ? m[2] : m[1]
            seed.dollars = true
            seed.from = m[3].uppercased()
            seed.to = m[4].uppercased()
        } else if let m = match(#"\bswap\s+(\d+(?:\.\d+)?)\s*([a-z][a-z0-9]{1,9})\s+(?:to|for|into)\s+([a-z][a-z0-9]{1,9})\b"#, text) {
            seed.amount = m[1]
            seed.from = m[2].uppercased()
            seed.to = m[3].uppercased()
        } else if let m = match(#"\bbuy\s+(?:\$\s*(\d+(?:\.\d+)?)|(\d+(?:\.\d+)?)\s*(?:usdc?|dollars?|bucks))\s+(?:worth\s+)?(?:of\s+)?\$?([a-z][a-z0-9]{1,9})\b"#, text) {
            seed.amount = m[1].isEmpty ? m[2] : m[1]
            seed.from = "USDC"
            seed.to = m[3].uppercased()
        } else if let m = match(#"\bsell\s+(\d+(?:\.\d+)?)\s*\$?([a-z][a-z0-9]{1,9})(?:\s+(?:for|to|into)\s+\$?([a-z][a-z0-9]{1,9}))?\b"#, text) {
            seed.amount = m[1]
            seed.from = m[2].uppercased()
            seed.to = m[3].isEmpty ? "USDC" : m[3].uppercased()
        } else {
            return nil
        }
        if seed.from == "WNEAR" { seed.from = "NEAR" }
        if seed.to == "WNEAR" { seed.to = "NEAR" }
        guard seed.from != seed.to else { return nil }
        if let condition {
            seed.trigger = condition.price
            let dollarsIn = ["USDC", "USDT", "DAI"].contains(seed.from)
            seed.kind = dollarsIn || !condition.below ? (dollarsIn ? .limit : .take) : .stop
        }
        return seed
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

private extension String {
    /// "0.2850" -> "0.285", "1.0000" -> "1".
    var trimmingZeros: String {
        guard contains(".") else { return self }
        var s = self
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }
}
