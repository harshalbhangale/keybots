import Foundation

/// The KOL call journey's side of the AIRKEY server:
///   GET  /v1/kol/feed        the callers' posts, read by rules
///   POST /v1/trade/review    one trade, priced and checked, with an id that expires
///   POST /v1/trade/confirm   the review, sent to the leash contract once
/// Every field is read loosely: a missing or renamed one falls back, never fails the card.

struct KolCall: Identifiable, Equatable {
    let id: String
    let handle: String
    let name: String?
    let postedAt: Date?
    let url: String?
    let text: String?
    let asset: String
    let direction: String
    let hits: Int?
    let misses: Int?
    /// "kall" (an X post, via Kall), "telegram" (a group the bot is in) or "sample". A server that doesn't say is Kall.
    var source: String = "kall"

    var sell: Bool { direction == "sell" }
    var telegram: Bool { source == "telegram" }
}

struct KolFeed: Equatable {
    /// "kall", "telegram", "mixed" or "sample".
    let source: String
    let note: String?
    let calls: [KolCall]
    var sample: Bool { source == "sample" }
}

struct Amount: Equatable {
    let amount: String
    let symbol: String
    var line: String { "\(amount) \(symbol)" }
}

struct TradeReview: Equatable {
    struct Call: Equatable {
        let handle: String?
        let name: String?
        let postedAt: Date?
        let url: String?
        let text: String
        let asset: String
        let direction: String
    }
    struct Limits: Equatable {
        let agentName: String
        let perTrade: String
        let daily: String
        let spentToday: String
        let stopped: Bool
        let within: Bool
        let sentence: String
        let willRefuse: String?
        /// "contract" (a limit, refused on chain) or "server" (Stop everything: nothing is sent).
        let refusedBy: String?
    }
    struct Mainnet: Equatable {
        let label: String
        let payAmount: String
        let receiveAmount: String
        let symbol: String
    }

    let reviewId: String
    let expiresAt: Date
    let call: Call
    let reading: String
    let network: String
    let venue: String
    let pay: Amount
    let receive: Amount
    let receiveMin: String
    let slippagePct: String
    let fundsSit: String
    let standIn: String?
    let mainnet: Mainnet?
    let limits: Limits
}

struct TradeReceipt: Equatable {
    /// "swapped", "blocked" or "failed".
    let status: String
    let repeated: Bool
    let id: String
    let summary: String
    let at: Date?
    /// "contract" or "server".
    let by: String
    let rule: String?
    let reason: String?
    let agent: String
    let pay: Amount?
    let receive: Amount?
    let venue: String?
    let standIn: String?
    let txHash: String?
    let txURL: String?
    let postURL: String?
    let postAuthor: String?
    /// "kall" or "telegram"; for Telegram, `postAuthor` is the group.
    var postSource: String? = nil

    var swapped: Bool { status == "swapped" }
    var blocked: Bool { status == "blocked" }
    /// NEAR didn't answer: whether it went through isn't known.
    var unknown: Bool { status == "unknown" }
    var byContract: Bool { by == "contract" }
}

enum ConfirmAnswer: Equatable {
    case receipt(TradeReceipt)
    /// The quote is older than 30 seconds: review again.
    case expired(String)
    /// The same review is already on its way.
    case busy(String)
    /// The server doesn't know this review (it restarted): review again.
    case gone(String)
}

struct JourneyAPI {
    var base: String = Settings.serverURL
    var token: String = Settings.token

    func feed() async throws -> KolFeed {
        let j = try await send("GET", "/v1/kol/feed", nil).json
        return KolFeed(source: J.str(j["source"]) ?? "kall", note: J.str(j["note"]),
                       calls: J.arr(j["calls"]).compactMap(Self.kolCall))
    }

    func review(callId: String?, text: String?, usd: Int?) async throws -> TradeReview {
        var body: [String: Any] = [:]
        if let callId { body["callId"] = callId }
        if let text { body["text"] = text }
        if let usd { body["usd"] = usd }
        let (status, j) = try await send("POST", "/v1/trade/review", body)
        guard (200..<300).contains(status) else { throw APIError(message: Self.said(j, status)) }
        guard let r = Self.review(j) else { throw APIError(message: "The server's review was missing its numbers.") }
        return r
    }

    func confirm(reviewId: String) async throws -> ConfirmAnswer {
        // A swap waits on NEAR's receipts: give it longer than a review.
        let (status, j) = try await send("POST", "/v1/trade/confirm", ["reviewId": reviewId], timeout: 90)
        if status == 409 {
            let msg = Self.said(j, status)
            return J.bool(j["expired"]) == true ? .expired(msg) : .busy(msg)
        }
        if status == 404 { return .gone(J.str(j["error"]) ?? "No such review. Review the trade again.") }
        guard (200..<300).contains(status) else { throw APIError(message: Self.said(j, status)) }
        let r = J.dict(j["receipt"])
        return .receipt(TradeReceipt(
            status: J.str(j["status"]) ?? "failed",
            repeated: J.bool(j["repeat"]) ?? false,
            id: J.str(r["id"]) ?? reviewId,
            summary: J.str(r["summary"]) ?? "",
            at: J.date(r["at"]),
            by: J.str(r["by"]) ?? "server",
            rule: J.str(r["rule"]),
            reason: J.str(r["reason"]),
            agent: J.str(r["agent"]) ?? "Trading Agent",
            pay: Self.amount(r["pay"]),
            receive: Self.amount(r["receive"]),
            venue: J.str(r["venue"]),
            standIn: J.str(r["standIn"]),
            txHash: J.str(J.dict(r["tx"])["hash"]),
            txURL: J.str(J.dict(r["tx"])["url"]),
            postURL: J.str(J.dict(r["post"])["url"]),
            postAuthor: J.str(J.dict(r["post"])["author"]),
            postSource: J.str(J.dict(r["post"])["source"])))
    }

    // MARK: Reading

    private static func said(_ j: [String: Any], _ status: Int) -> String {
        J.str(j["error"]).map(Plain.scrub) ?? "The server answered \(status)."
    }

    private static func amount(_ v: Any?) -> Amount? {
        let d = J.dict(v)
        guard let a = J.str(d["amount"]), let s = J.str(d["symbol"]) else { return nil }
        return Amount(amount: a, symbol: s)
    }

    static func kolCall(_ v: Any) -> KolCall? {
        let d = J.dict(v)
        guard let id = J.str(d["id"]), let asset = J.str(d["asset"]) else { return nil }
        let author = J.dict(d["author"])
        let record = J.dict(d["record"])
        return KolCall(id: id, handle: (J.str(author["handle"]) ?? "unknown").replacingOccurrences(of: "@", with: ""),
                       name: J.str(author["name"]), postedAt: J.date(d["postedAt"]), url: J.str(d["url"]),
                       text: J.str(d["text"]), asset: asset, direction: J.str(d["direction"]) ?? "buy",
                       hits: J.int(record["hits"]), misses: J.int(record["misses"]),
                       source: ["kall", "telegram", "sample"].contains(J.str(d["source"]) ?? "") ? J.str(d["source"])! : "kall")
    }

    static func review(_ j: [String: Any]) -> TradeReview? {
        guard let id = J.str(j["reviewId"]) else { return nil }
        let c = J.dict(j["call"]), author = J.dict(c["author"])
        let t = J.dict(j["trade"]), l = J.dict(j["limits"]), m = J.dict(j["mainnetQuote"])
        guard let pay = amount(t["pay"]) else { return nil }
        let recv = J.dict(t["receive"])
        let receive = Amount(amount: J.str(recv["amount"]) ?? "?", symbol: J.str(recv["symbol"]) ?? "")
        let mainnet: TradeReview.Mainnet? = m.isEmpty ? nil : TradeReview.Mainnet(
            label: J.str(m["label"]) ?? "Mainnet price", payAmount: J.str(m["payAmount"]) ?? "?",
            receiveAmount: J.str(m["receiveAmount"]) ?? "?", symbol: J.str(m["symbol"]) ?? "")
        return TradeReview(
            reviewId: id,
            // Count down from when the quote arrived, not the server's clock: the phone's clock may differ.
            expiresAt: Date().addingTimeInterval((j["ttlSeconds"] as? NSNumber)?.doubleValue ?? 30),
            call: .init(handle: J.str(author["handle"])?.replacingOccurrences(of: "@", with: ""), name: J.str(author["name"]),
                        postedAt: J.date(c["postedAt"]), url: J.str(c["url"]), text: J.str(c["text"]) ?? "",
                        asset: J.str(c["asset"]) ?? receive.symbol, direction: J.str(c["direction"]) ?? "buy"),
            reading: J.str(J.dict(j["reading"])["detail"]) ?? "",
            network: J.str(t["network"]) ?? "NEAR testnet",
            venue: J.str(t["venue"]) ?? "",
            pay: pay, receive: receive,
            receiveMin: J.str(recv["min"]) ?? receive.amount,
            slippagePct: J.str(t["slippagePct"]) ?? "1",
            fundsSit: J.str(t["fundsSit"]) ?? "",
            standIn: J.str(t["standIn"]),
            mainnet: mainnet,
            limits: .init(agentName: J.str(l["agentName"]) ?? "Trading Agent", perTrade: J.str(l["perTrade"]) ?? "?",
                          daily: J.str(l["daily"]) ?? "?", spentToday: J.str(l["spentToday"]) ?? "0",
                          stopped: J.bool(l["stopped"]) ?? false, within: J.bool(l["within"]) ?? true,
                          sentence: J.str(l["sentence"]) ?? "", willRefuse: J.str(l["willRefuse"]), refusedBy: J.str(l["refusedBy"])))
    }

    // MARK: Sending

    private func send(_ method: String, _ path: String, _ body: [String: Any]?, timeout: TimeInterval = 30) async throws -> (status: Int, json: [String: Any]) {
        guard let url = URL(string: base.trimmingCharacters(in: .whitespaces) + path) else {
            throw APIError(message: "The server address in Settings isn't a URL.")
        }
        var r = URLRequest(url: url, timeoutInterval: timeout)
        r.httpMethod = method
        if !token.isEmpty { r.setValue("Bearer \(token)", forHTTPHeaderField: "authorization") }
        r.setValue("keyboard", forHTTPHeaderField: "x-airkey-client")
        if let body {
            r.setValue("application/json", forHTTPHeaderField: "content-type")
            r.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let data: Data, response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: r)
        } catch {
            throw APIError(message: "Can't reach the Keybots server.")
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if method == "GET", !(200..<300).contains(status) { throw APIError(message: Self.said(json, status)) }
        return (status, json)
    }
}

/// Loose JSON reading: numbers and strings are interchangeable, nulls are nil.
enum J {
    static func dict(_ v: Any?) -> [String: Any] { v as? [String: Any] ?? [:] }
    static func arr(_ v: Any?) -> [Any] { v as? [Any] ?? [] }
    static func str(_ v: Any?) -> String? {
        switch v {
        case let s as String: s.isEmpty ? nil : s
        case let n as NSNumber where CFGetTypeID(n) != CFBooleanGetTypeID(): n.stringValue
        default: nil
        }
    }
    static func int(_ v: Any?) -> Int? { (v as? NSNumber)?.intValue ?? str(v).flatMap { Int($0) } }
    static func bool(_ v: Any?) -> Bool? {
        if let n = v as? NSNumber { return n.boolValue }
        if let s = v as? String { return ["true", "yes", "1"].contains(s.lowercased()) }
        return nil
    }
    static func date(_ v: Any?) -> Date? {
        if let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() {
            let x = n.doubleValue
            return Date(timeIntervalSince1970: x > 10_000_000_000 ? x / 1000 : x)
        }
        guard let s = v as? String else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    /// "just now", "12 min ago", "3 h ago", "2 days ago".
    static func ago(_ d: Date?, now: Date = .now) -> String? {
        guard let d else { return nil }
        let s = max(0, now.timeIntervalSince(d))
        if s < 60 { return "just now" }
        if s < 3600 { return "\(Int(s / 60)) min ago" }
        if s < 86400 { return "\(Int(s / 3600)) h ago" }
        let days = Int(s / 86400)
        return days == 1 ? "1 day ago" : "\(days) days ago"
    }
}
