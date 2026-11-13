import Foundation

/// Where the app and the keyboard find the AIRKEY server. Shared through the
/// App Group so the keyboard uses what you set in the app.
enum Settings {
    static let group = "group.tech.airkey.shared"
    static var store: UserDefaults { UserDefaults(suiteName: group) ?? .standard }

    static var serverURL: String {
        get { store.string(forKey: "serverURL") ?? (Bundle.main.object(forInfoDictionaryKey: "AirkeyServer") as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "http://127.0.0.1:8787" }
        set { store.set(newValue, forKey: "serverURL") }
    }
    static var token: String {
        get { store.string(forKey: "token") ?? "" }
        set { store.set(newValue, forKey: "token") }
    }
    static var name: String {
        get { store.string(forKey: "name") ?? "Harshal" }
        set { store.set(newValue, forKey: "name") }
    }
}

struct APIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// The AIRKEY server's API (server/src/app.ts).
struct API {
    var base: String = Settings.serverURL
    var token: String = Settings.token

    func state() async throws -> LeashState { try await get("/v1/state") }
    func receipts(limit: Int = 50) async throws -> [Receipt] { try await (get("/v1/receipts?limit=\(limit)") as ReceiptList).receipts }

    /// source: "typed" (you wrote it) or "pasted" (someone else did).
    func command(_ text: String, source: String) async throws -> Receipt {
        try await post("/v1/command", ["text": text, "source": source])
    }

    /// Read a command without running it (rules first, an AI for loose wording).
    func read(_ text: String) async throws -> ReadResult {
        try await post("/v1/read", ["text": text])
    }

    /// What swapping `amount` NEAR into `to` gets on Rhea right now.
    func swapQuote(amount: String, to: String) async throws -> SwapQuote {
        try await get("/v1/swap/quote?amount=\(amount)&to=\(to)")
    }

    /// A token's live price in dollars, from NEAR Intents' list.
    func price(_ symbol: String) async throws -> Price { try await get("/v1/price/\(symbol)") }

    func fx(amount: String, from: String, to: String) async throws -> Conversion {
        try await get("/v1/fx?amount=\(amount)&from=\(from)&to=\(to)")
    }

    /// Trades waiting for a price, newest first.
    func orders() async throws -> [Order] { try await (get("/v1/orders") as OrderList).orders }

    func cancelOrder(_ id: String) async throws {
        var r = try request("/v1/orders/\(id)")
        r.httpMethod = "DELETE"
        let _: Order = try await send(r)
    }

    /// Every symbol NEAR Intents lists.
    func tokens() async throws -> [String] { try await (get("/v1/tokens") as TokenSymbols).symbols }

    func prepare(method: String, args: [String: any Sendable], publicKey: String) async throws -> Prepared {
        try await post("/v1/owner/prepare", ["method": method, "args": args, "publicKey": publicKey])
    }

    func submit(tx: String, signature: String) async throws -> Submitted {
        try await post("/v1/owner/submit", ["tx": tx, "signature": signature])
    }

    /// The keyboard's AI bar: "rewrite", "reply", "translate", "tone" or
    /// "ask" on `text`. Only the answer comes back; nothing is put anywhere.
    func act(text: String, action: String, tone: String? = nil, language: String? = nil) async throws -> ActResult {
        var body: [String: any Sendable] = ["text": text, "action": action]
        if let tone { body["tone"] = tone }
        if let language { body["language"] = language }
        return try await post("/v1/act", body)
    }

    /// A copied crypto call: what it says and the one small trade it could
    /// be. Runs nothing.
    func call(_ text: String) async throws -> CallCheck { try await post("/v1/call", ["text": text]) }

    // MARK: The calls book (keyboard › Calls)

    /// Every copied call that was checked, newest first, with the trade its hold ran.
    func calls(limit: Int = 50) async throws -> [CallRecord] { try await (get("/v1/calls?limit=\(limit)") as CallList).calls }

    /// The hold on a call's chip: its command, as typed, tied to the call so the book keeps the outcome.
    func command(_ text: String, callId: String) async throws -> Receipt {
        try await post("/v1/command", ["text": text, "source": "typed", "callId": callId])
    }

    /// Put a call away without trading it.
    func dismissCall(_ id: String) async throws {
        let _: CallRecord = try await post("/v1/calls/\(id)/dismiss", [:])
    }

    /// The vault as the server keeps it (the app saves it there; free signing has no App Group).
    func vault() async throws -> [Vault.Item] { try await (get("/v1/vault") as VaultList).items }

    func saveVault(_ items: [Vault.Item]) async throws {
        var r = try request("/v1/vault")
        r.httpMethod = "PUT"
        r.setValue("application/json", forHTTPHeaderField: "content-type")
        r.httpBody = try JSONEncoder().encode(VaultList(items: items))
        let _: VaultList = try await send(r)
    }

    private func request(_ path: String) throws -> URLRequest {
        guard let url = URL(string: base.trimmingCharacters(in: .whitespaces) + path) else {
            throw APIError(message: "The server address in Settings isn't a URL.")
        }
        var r = URLRequest(url: url, timeoutInterval: 30)
        if !token.isEmpty { r.setValue("Bearer \(token)", forHTTPHeaderField: "authorization") }
        // Which side sent it, so the server log can tell keyboard runs from app runs.
        r.setValue(Bundle.main.bundleIdentifier?.hasSuffix(".keyboard") == true ? "keyboard" : "app", forHTTPHeaderField: "x-airkey-client")
        return r
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        try await send(request(path))
    }

    private func post<T: Decodable>(_ path: String, _ body: [String: any Sendable]) async throws -> T {
        var r = try request(path)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "content-type")
        r.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await send(r)
    }

    private func send<T: Decodable>(_ r: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: r)
        } catch {
            throw APIError(message: "Can't reach the AIRKEY server at \(base).")
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw APIError(message: msg ?? "The server answered \(status).")
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError(message: "The server's answer didn't make sense (\(error.localizedDescription)).")
        }
    }
}

// MARK: - Trade panel

extension API {
    /// What a swap pays, gets and costs right now, and the command a hold
    /// sends. `order` ("limit", "stop", "take") with `trigger` asks for a
    /// price-triggered order instead. Sends nothing.
    func quote(from: String, to: String, amount: String, order: String? = nil, trigger: String? = nil) async throws -> TradeQuote {
        var path = "/v1/quote?from=\(from)&to=\(to)&amount=\(amount)"
        if let order, let trigger { path += "&order=\(order)&trigger=\(trigger)" }
        return try await get(path)
    }

    /// The token picker: what trades here first, with prices and the leash's balances.
    func tokenList() async throws -> [PickerToken] { try await (get("/v1/tokens/list") as PickerTokenList).tokens }
}

struct VaultList: Codable { let items: [Vault.Item] }
