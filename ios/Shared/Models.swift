import Foundation

// Mirrors of the AIRKEY server's JSON (server/src). Optional where the server may omit.

struct LeashState: Decodable {
    let owner: String
    let leash: String
    let paused: Bool
    let available: String
    let agents: [AgentEntry]
    let allowlist: [String]
    let blocklist: [Blocked]
    let pending: [Pending]
    let explorer: String
    let contacts: [String: String]
    /// Tokens the leash holds (swaps land back in it). Missing on older servers.
    let holdings: [Holding]?
    /// The agent accounts this server signs for, by role. Missing on older servers.
    let active: Roles?

    struct Roles: Decodable {
        let trusted: String
        let untrusted: String
        let trade: String
    }

    /// The agents this server uses: the leash may list more (the named set
    /// and OutLayer's), and only the active three are shown.
    var shownAgents: [AgentEntry] {
        guard let active else { return agents }
        let mine = [active.trusted, active.untrusted, active.trade]
        let shown = agents.filter { mine.contains($0.account) }
        return shown.isEmpty ? agents : shown
    }

    /// Account → role name, for agents whose account name says nothing (OutLayer's hex accounts).
    var roleNames: [String: String] {
        guard let active else { return [:] }
        return [active.trusted: Plain.agent(role: "pay"), active.untrusted: Plain.agent(role: "inbox"), active.trade: Plain.trades]
    }

    struct Holding: Decodable, Identifiable {
        let symbol: String
        let token: String
        let amount: String
        var id: String { token }
    }

    struct AgentEntry: Decodable, Identifiable {
        let account: String
        let agent: Agent
        var id: String { account }
    }

    struct Agent: Decodable {
        let tier: String
        let per_payment_cap: String
        let daily_cap: String
        let spent_today: String
    }

    struct Blocked: Decodable, Identifiable {
        let account: String
        let reason: String
        var id: String { account }
    }

    struct Pending: Decodable, Identifiable {
        let id: Int
        let agent: String
        let receiver: String
        let amount: String
        let memo: String?
        let rule: String
        let reason: String
        /// When the agent asked, in nanoseconds (the contract's block time). Older servers leave it out.
        let created_at_ns: Double?

        var createdAt: Date? { created_at_ns.map { Date(timeIntervalSince1970: $0 / 1e9) } }
    }
}

struct Receipt: Decodable, Identifiable {
    let id: String
    let at: String
    let input: Input
    let interpretation: Interpretation
    let agent: AgentRef?
    let receiver: ReceiverRef?
    let checks: Checks?
    let decision: Decision?
    let swap: Swap?
    let order: OrderRef?
    let outcome: String
    let message: String
    /// The server's plain line for it. Missing on older servers and older receipts: Plain works it out.
    let summary: String?
    let tx: Tx?

    struct Input: Decodable {
        let text: String
        let source: String
        /// The caller behind a reviewed or followed call, and its post when it has one.
        var handle: String? = nil
        var postUrl: String? = nil
        /// Another app that sent it, e.g. "claude-code" (an agent using Keybots' MCP server).
        var client: String? = nil
    }
    struct Interpretation: Decodable {
        let action: Action
        let reader: String
        let ai: AIEvidence?
    }
    struct Action: Decodable {
        let kind: String
        let receiver: String?
        let amountNear: String?
        let memo: String?
        let amount: String?
        let from: String?
        let to: String?
        let reason: String?
        let command: String?
    }
    struct AIEvidence: Decodable {
        let provider: String
        let model: String
        let chatId: String?
        let signature: Sig
        let attestation: String
        struct Sig: Decodable { let status: String; let kind: String?; let signingAddress: String? }
    }
    struct AgentRef: Decodable { let account: String; let tier: String }
    struct ReceiverRef: Decodable { let asked: String; let account: String; let via: String }
    struct Checks: Decodable {
        let verdict: String
        let reasons: [String]
        let facts: Facts?
        struct Facts: Decodable { let isContract: Bool?; let paidBefore: Bool?; let ageDays: Int? }
    }
    struct Decision: Decodable { let status: String; let rule: String?; let reason: String; let pending_id: Int? }
    struct Tx: Decodable { let hash: String; let url: String }
    struct Swap: Decodable {
        let from: TokenCheck
        let to: TokenCheck
        let quote: Quote?
        let leash: SwapLeash?
        /// Set when the swap really ran: on Rhea, from the leash.
        let executed: Executed?
    }
    struct Executed: Decodable {
        let venue: String
        let exchange: String
        let amountIn: String
        let symbolIn: String?
        let amountOut: String?
        let symbolOut: String
        let ok: Bool
    }
    struct TokenCheck: Decodable {
        let asked: String
        let verified: Bool
        let reason: String
        let alsoOn: [String]
        let token: Token?
        struct Token: Decodable { let assetId: String; let symbol: String; let blockchain: String }
    }
    struct Quote: Decodable {
        let amountInFormatted: String
        let amountInUsd: String?
        let amountOutFormatted: String
        let amountOutUsd: String?
        let minAmountOut: String?
        let timeEstimate: Double?
    }
    struct OrderRef: Decodable { let id: String; let symbol: String; let direction: String; let price: Double; let priceThen: Double; let command: String }
    struct SwapLeash: Decodable { let agent: String; let valueNear: String; let perPaymentCap: String; let leftToday: String; let within: Bool }

    var signal: Signal { Signal(outcome: outcome) }
    var date: Date? { ISO8601DateFormatter.withFraction.date(from: at) ?? ISO8601DateFormatter().date(from: at) }
}

struct ReceiptList: Decodable { let receipts: [Receipt] }

/// A command the server read without running it: what it is, and the exact
/// command to send when you hold. `reader` is "rules", "openai" or "near-ai-cloud".
struct ReadResult: Decodable {
    let kind: String
    let title: String?
    let verb: String?
    let command: String?
    let reader: String
}

/// What a NEAR swap would get on Rhea right now.
struct SwapQuote: Decodable {
    let venue: String
    let pool: Int
    let to: String
    let amountIn: String
    let amountOut: String
    let minAmountOut: String
}

/// A trade waiting for a price: "sell 1 near" when NEAR is below $2.
struct Order: Decodable, Identifiable {
    let id: String
    let command: String
    let symbol: String
    let direction: String
    let price: Double
    let priceThen: Double
    let status: String

    /// "when NEAR is below $2"
    var condition: String { "when \(symbol) is \(direction) \(Fmt.usd(price))" }
}

struct OrderList: Decodable { let orders: [Order] }

struct Price: Decodable { let symbol: String; let usd: Double; let blockchain: String }

struct Conversion: Decodable { let amount: Double; let from: String; let to: String; let value: Double; let rate: Double }

struct TokenSymbols: Decodable { let symbols: [String] }

struct Prepared: Decodable { let tx: String; let hash: String; let summary: String }

struct Submitted: Decodable {
    let method: String
    let txHash: String
    let url: String
    let ok: Bool
}

extension ISO8601DateFormatter {
    nonisolated(unsafe) static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}

/// What the keyboard's AI bar got back (POST /v1/act): only the text, and
/// which AI answered. `provider` is "near-ai-cloud" or "openai"; `signature`
/// is "verified", "mismatch" or "unavailable" (only NEAR AI Cloud signs).
struct ActResult: Decodable, Sendable {
    let text: String
    let provider: String
    let model: String
    let signature: String

    /// Who answered, in the words the keyboard shows.
    var providerName: String {
        switch provider {
        case "near-ai-cloud": "NEAR AI"
        case "openai": "OpenAI"
        default: provider
        }
    }
}

/// A copied crypto call, read by the server's rules (POST /v1/call).
struct CallCheck: Decodable {
    struct Call: Decodable {
        let isCall: Bool
        let confidence: String
        let asset: String?
        let direction: String?
        let summary: String
    }
    struct Caps: Decodable {
        let agent: String
        let perTrade: String
        let leftToday: String
        let paused: Bool
        let within: Bool?
    }
    /// NEAR Intents' dry quote for the token the call names.
    struct Quote: Decodable {
        let amountIn: String
        let amountOut: String
        let symbolOut: String
    }
    /// "available" with the command a hold would send, or "unavailable" with why not.
    struct Route: Decodable {
        let status: String
        let side: String?
        let command: String?
        let title: String?
        let caps: Caps?
        let quote: Quote?
        /// What the hold runs instead of the title, when it does (testnet has no SOL).
        let standIn: String?
        let note: String?
        let reason: String?
    }
    let call: Call
    let route: Route
    /// Its record in the calls book (GET /v1/calls). Missing on older servers, and for text that isn't a call.
    let id: String?
}

/// One call in the calls book: what was copied, how it was read, the trade a
/// hold would send, and what came back if one did.
struct CallRecord: Decodable, Identifiable {
    let id: String
    let at: String
    let text: String
    let asset: String?
    /// "bullish" or "bearish".
    let direction: String?
    let confidence: String
    /// "available" with `command`, or "unavailable" with `reason`.
    let status: String
    let reason: String?
    let command: String?
    let title: String?
    let side: String?
    let standIn: String?
    /// The token passed NEAR Intents' check.
    let verified: Bool?
    /// The token's dollar price when the call was checked, and now.
    let priceThen: Double?
    let priceNow: Double?
    let trade: Trade?
    let dismissed: Bool?

    struct Trade: Decodable {
        let at: String
        let outcome: String
        let message: String
        let tx: Receipt.Tx?
        var signal: Signal { Signal(outcome: outcome) }
    }

    var date: Date? { ISO8601DateFormatter.withFraction.date(from: at) ?? ISO8601DateFormatter().date(from: at) }
    var bearish: Bool { direction == "bearish" }
    /// Still to act on: a trade is on offer and nothing has been done with it.
    var open: Bool { status == "available" && trade == nil && dismissed != true }

    /// The move since the call, in the called direction, in percent.
    var move: Double? {
        guard let then = priceThen, then > 0, let now = priceNow else { return nil }
        let m = (now - then) / then * 100
        return bearish ? -m : m
    }
}

struct CallList: Decodable { let calls: [CallRecord] }

// MARK: - Trade panel (GET /v1/quote, GET /v1/tokens/list)

/// Everything the keyboard's trade panel shows for one swap, before the
/// hold. Every number is the server's: Rhea's pool, NEAR Intents' list and
/// quote, and the leash's state on chain.
struct TradeQuote: Decodable, Equatable {
    struct Token: Decodable, Equatable {
        let symbol: String
        let assetId: String?
        let price: Double?
        let verified: Bool
    }
    /// "Rhea" with its pools, or "NEAR Intents" with how long it takes.
    struct Route: Decodable, Equatable {
        let venue: String
        let pool: Int?
        let pools: [Int]?
        let seconds: Double?
    }
    struct Fee: Decodable, Equatable {
        let amount: String
        let symbol: String
        let usd: String?
    }
    /// The Trading Agent's caps on chain, in NEAR.
    struct Caps: Decodable, Equatable {
        let agent: String
        let perTrade: String
        let leftToday: String
        let paused: Bool
        let valueNear: String?
        let within: Bool
    }
    struct Balance: Decodable, Equatable {
        let symbol: String
        let amount: String
        let enough: Bool
    }
    /// A price-triggered order: which token is watched, and for what price.
    struct Order: Decodable, Equatable {
        let kind: String
        let symbol: String
        let direction: String
        let trigger: String
        let now: Double?
        let line: String
    }

    let from: Token
    let to: Token
    let amountIn: String
    let amountOut: String
    /// "1 NEAR = 2.10 USDC"
    let rate: String
    let minReceived: String
    let slippagePct: Double
    let route: Route
    /// A hold would really swap on this network.
    let executable: Bool
    let reason: String?
    let networkFee: Fee
    /// Percent lost to the size of the trade.
    let priceImpact: Double?
    /// Percent above or below NEAR Intents' dollar prices.
    let vsMarket: Double?
    let valueUsd: String?
    let caps: Caps?
    let balance: Balance?
    /// The exact text a hold sends to /v1/command.
    let command: String
    /// One plain line when the hold is off.
    let problem: String?
    let ready: Bool
    let order: Order?
}

/// A row in the trade panel's token picker.
struct PickerToken: Decodable, Identifiable, Equatable {
    let symbol: String
    let chain: String
    let price: Double?
    /// What the leash holds of it, when it holds any.
    let balance: String?
    /// A hold can really swap it on this network.
    let tradable: Bool
    var id: String { symbol }
}

struct PickerTokenList: Decodable { let tokens: [PickerToken] }

// MARK: - People you follow (GET/POST/DELETE /v1/follows, GET /v1/kols)
//
// Decoded loosely: every field but the handle (and a trade's id) has a
// default, and unknown keys are ignored, so a small server difference
// leaves the list on screen instead of an error.

private extension KeyedDecodingContainer {
    func loose<T: Decodable>(_ key: Key, _ fallback: T) -> T {
        ((try? decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
    }
}

/// A list that drops the items it can't read instead of failing whole.
struct LooseList<T: Decodable>: Decodable {
    let items: [T]
    init(from decoder: Swift.Decoder) throws {
        var c = try decoder.unkeyedContainer()
        var out: [T] = []
        while !c.isAtEnd {
            // A failed decode doesn't move the cursor; Skip does.
            if let item = try? c.decode(T.self) { out.append(item) } else if (try? c.decode(Skip.self)) == nil { break }
        }
        items = out
    }
    /// Reads any value and keeps nothing, so the list moves past a bad item.
    private struct Skip: Decodable { init(from decoder: Swift.Decoder) throws {} }
}

/// A caller's record on X: calls that hit, missed, are still open, and the average return.
struct CallerRecord: Decodable, Equatable, Sendable {
    var hits: Int
    var misses: Int
    var open: Int
    /// nil when Keybots has no return for them yet.
    var avgReturnBps: Double?

    enum CodingKeys: String, CodingKey { case hits, misses, open, avgReturnBps }
    init(from decoder: Swift.Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hits = c.loose(.hits, 0)
        misses = c.loose(.misses, 0)
        open = c.loose(.open, 0)
        avgReturnBps = c.loose(.avgReturnBps, nil as Double?)
    }

    /// "7 of 10 calls up · avg +1.2%" (no average when Keybots has none)
    var line: String {
        var parts = ["\(hits) of \(hits + misses) calls up"]
        if let bps = avgReturnBps {
            let avg = bps / 100
            parts.append("avg " + (abs(avg) < 0.05 ? "0%" : String(format: "%+.1f%%", avg)))
        }
        return parts.joined(separator: " · ")
    }
}

/// Someone you follow, with the rules their calls trade under.
struct Follow: Decodable, Identifiable, Equatable, Sendable {
    let handle: String
    var auto: Bool
    var perCallUsd: Double
    var perDayUsd: Double
    /// "buy" or "both".
    var sides: String
    var highOnly: Bool
    var stopAfterMisses: Int
    let addedAt: String?
    var spentTodayUsd: Double
    let lastCallAt: String?
    var pausedReason: String?
    let record: CallerRecord?
    /// Misses since their last hit.
    let missesInRow: Int

    var id: String { handle.lowercased() }

    enum CodingKeys: String, CodingKey {
        case handle, auto, perCallUsd, perDayUsd, sides, highOnly, stopAfterMisses, addedAt, spentTodayUsd, lastCallAt, pausedReason, record, missesInRow
    }
    init(from decoder: Swift.Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        handle = Follow.clean(try c.decode(String.self, forKey: .handle))
        auto = c.loose(.auto, false)
        perCallUsd = c.loose(.perCallUsd, 1)
        perDayUsd = c.loose(.perDayUsd, 3)
        sides = c.loose(.sides, "buy")
        highOnly = c.loose(.highOnly, true)
        stopAfterMisses = c.loose(.stopAfterMisses, 3)
        addedAt = c.loose(.addedAt, nil as String?)
        spentTodayUsd = c.loose(.spentTodayUsd, 0)
        lastCallAt = c.loose(.lastCallAt, nil as String?)
        pausedReason = c.loose(.pausedReason, nil as String?)
        missesInRow = c.loose(.missesInRow, 0)
        record = c.loose(.record, nil as CallerRecord?)
    }

    /// "@CryptoKaleo", "x.com/CryptoKaleo" or "CryptoKaleo" → "CryptoKaleo".
    static func clean(_ handle: String) -> String {
        var h = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        if let q = h.firstIndex(of: "?") { h = String(h[..<q]) }
        while h.hasSuffix("/") { h.removeLast() }
        if let slash = h.lastIndex(of: "/") { h = String(h[h.index(after: slash)...]) }
        while h.hasPrefix("@") { h.removeFirst() }
        return h
    }

    /// A handle X would accept: 1 to 15 letters, digits or underscores.
    static func valid(_ handle: String) -> Bool {
        !handle.isEmpty && handle.count <= 15 && handle.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }
    }

    /// The record line, or a quiet stand-in while the X feed is slow.
    var recordLine: String { record?.line ?? "Record loading" }
    /// Auto was turned off for them (three misses in a row, say).
    var paused: Bool { !(pausedReason ?? "").isEmpty }

    /// "$1 of $3 used"
    var usedLine: String { "\(Dollars.text(spentTodayUsd)) of \(Dollars.text(perDayUsd)) used" }
    var buyOnly: Bool { sides != "both" }

    var rules: FollowRules {
        FollowRules(auto: auto, perCallUsd: perCallUsd, perDayUsd: perDayUsd, sides: sides, highOnly: highOnly, stopAfterMisses: stopAfterMisses)
    }

    mutating func apply(_ r: FollowRules) {
        auto = r.auto
        perCallUsd = r.perCallUsd
        perDayUsd = r.perDayUsd
        sides = r.sides
        highOnly = r.highOnly
        stopAfterMisses = r.stopAfterMisses
    }
}

/// What you set for one person: sent as POST /v1/follows.
struct FollowRules: Equatable, Sendable {
    var auto: Bool = false
    var perCallUsd: Double = 1
    var perDayUsd: Double = 3
    var sides: String = "buy"
    var highOnly: Bool = true
    var stopAfterMisses: Int = 3
}

/// A trade made (or not) for you because someone you follow posted a call.
struct AutoTrade: Decodable, Identifiable, Equatable, Sendable {
    let id: String
    let handle: String
    let postId: String?
    let postUrl: String?
    let asset: String?
    let side: String
    let at: String
    /// "traded", "skipped" or "failed".
    let status: String
    let reason: String?
    let message: String
    let usd: Double?
    let receiptId: String?
    let txUrl: String?
    let onRequest: Bool

    enum CodingKeys: String, CodingKey {
        case id, handle, postId, postUrl, asset, side, at, status, reason, message, usd, receiptId, txUrl, onRequest
    }
    init(from decoder: Swift.Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let postId = c.loose(.postId, nil as String?)
        let at = c.loose(.at, "")
        let id = c.loose(.id, nil as String?) ?? postId ?? at
        guard !id.isEmpty else { throw DecodingError.dataCorruptedError(forKey: .id, in: c, debugDescription: "A trade without an id.") }
        self.id = id
        handle = Follow.clean(c.loose(.handle, ""))
        self.postId = postId
        postUrl = c.loose(.postUrl, nil as String?)
        asset = c.loose(.asset, nil as String?)
        side = c.loose(.side, "buy")
        self.at = at
        status = c.loose(.status, "skipped")
        let reason = c.loose(.reason, nil as String?)
        self.reason = reason
        let message = c.loose(.message, "")
        self.message = message.isEmpty ? (reason ?? "No trade.") : message
        usd = c.loose(.usd, nil as Double?)
        receiptId = c.loose(.receiptId, nil as String?)
        txUrl = c.loose(.txUrl, nil as String?)
        onRequest = c.loose(.onRequest, false)
    }

    var traded: Bool { status == "traded" }
    var failed: Bool { status == "failed" }
    /// The mark a row gets: a check when it traded, a warning when it failed, a dash when skipped.
    var icon: String {
        switch status {
        case "traded": "checkmark"
        case "failed": "exclamationmark"
        default: "minus"
        }
    }
    /// traded: lime, failed: amber, skipped: quiet.
    var signal: Signal {
        switch status {
        case "traded": .allow
        case "failed": .warn
        default: .neutral
        }
    }
    var date: Date? { ISO8601DateFormatter.withFraction.date(from: at) ?? ISO8601DateFormatter().date(from: at) }
    /// "just now" for the last minute (or a server clock a little ahead), else "4 min. ago".
    var ago: String {
        guard let date else { return "" }
        return date.timeIntervalSinceNow > -60 ? "just now" : Fmt.time(date)
    }
}

struct FollowsList: Decodable {
    let follows: [Follow]
    let trades: [AutoTrade]
    enum CodingKeys: String, CodingKey { case follows, trades }
    init(from decoder: Swift.Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        follows = c.loose(.follows, nil as LooseList<Follow>?)?.items ?? []
        trades = c.loose(.trades, nil as LooseList<AutoTrade>?)?.items ?? []
    }
}

/// A caller Keybots tracks, to suggest when you add someone.
struct Caller: Decodable, Identifiable, Equatable, Sendable {
    let handle: String
    let name: String?
    /// What they mostly call: "majors", "SOL memes". Missing for some.
    let focus: String?
    let record: CallerRecord
    var id: String { handle.lowercased() }

    enum CodingKeys: String, CodingKey { case handle, name, focus }
    init(from decoder: Swift.Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        handle = Follow.clean(try c.decode(String.self, forKey: .handle))
        name = c.loose(.name, nil as String?)
        focus = c.loose(.focus, nil as String?).flatMap { $0.isEmpty ? nil : $0 }
        record = try CallerRecord(from: decoder)
    }
}

struct CallerList: Decodable {
    let callers: [Caller]
    enum CodingKeys: String, CodingKey { case callers }
    init(from decoder: Swift.Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        callers = c.loose(.callers, nil as LooseList<Caller>?)?.items ?? []
    }
}

struct FollowCheck: Decodable {
    let trades: [AutoTrade]
    enum CodingKeys: String, CodingKey { case trades }
    init(from decoder: Swift.Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        trades = c.loose(.trades, nil as LooseList<AutoTrade>?)?.items ?? []
    }
}

enum Dollars {
    /// "$1", "$2.50": whole dollars without the cents.
    static func text(_ v: Double) -> String {
        v.rounded() == v && abs(v) < 1e9 ? "$\(Int(v))" : Fmt.usd(v)
    }
}

/// What Keybots is connected to, each service checked live by the server.
struct Connected: Decodable {
    let checkedAt: String
    let network: String
    let services: [Service]

    struct Service: Decodable, Identifiable {
        let id: String
        let name: String
        let role: String
        /// live | down | off
        let status: String
        let detail: String
    }
}
