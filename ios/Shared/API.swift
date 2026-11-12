import Foundation

/// Where the app and the keyboard find the AIRKEY server. Shared through the
/// App Group so the keyboard uses what you set in the app.
enum Settings {
    static let group = "group.tech.airkey.shared"
    static var store: UserDefaults { UserDefaults(suiteName: group) ?? .standard }

    static var serverURL: String {
        get { store.string(forKey: "serverURL") ?? "http://127.0.0.1:8787" }
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

    private func request(_ path: String) throws -> URLRequest {
        guard let url = URL(string: base.trimmingCharacters(in: .whitespaces) + path) else {
            throw APIError(message: "The server address in Settings isn't a URL.")
        }
        var r = URLRequest(url: url, timeoutInterval: 30)
        if !token.isEmpty { r.setValue("Bearer \(token)", forHTTPHeaderField: "authorization") }
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
