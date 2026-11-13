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
    struct Checks: Decodable { let verdict: String; let reasons: [String] }
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
