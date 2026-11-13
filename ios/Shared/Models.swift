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

    struct Input: Decodable { let text: String; let source: String }
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
