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
    struct SwapLeash: Decodable { let agent: String; let valueNear: String; let perPaymentCap: String; let leftToday: String; let within: Bool }

    var signal: Signal { Signal(outcome: outcome) }
    var date: Date? { ISO8601DateFormatter.withFraction.date(from: at) ?? ISO8601DateFormatter().date(from: at) }
}

struct ReceiptList: Decodable { let receipts: [Receipt] }

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
