import Foundation

/// The keyboard's side of the AIRKEY server's AI routes (server/src/
/// ai-routes.ts): answers that arrive as they are written, live translate,
/// the smart chip, search, and my glyfs. Text only, and nothing is kept:
/// what streams in goes straight to the bar.
struct AIClient {
    var base: String = Settings.serverURL
    var token: String = Settings.token

    /// One version of a rewrite ("Clean", "Work", "Polite"…).
    struct Option: Decodable, Equatable {
        let id: String
        let label: String
        let text: String
    }

    /// The end of a streamed answer: the whole text and who gave it.
    struct Done: Decodable {
        let text: String
        let options: [Option]?
        let provider: String
        let model: String
        let signature: String

        var result: ActResult { ActResult(text: text, provider: provider, model: model, signature: signature) }
    }

    enum Event {
        /// A rewrite version, finished.
        case option(Option)
        /// The next piece of the answer.
        case text(String)
        /// The AI that was writing stopped; the next starts the answer over.
        case reset
        case done(Done)
    }

    /// Copied text that reads as a payment or a trade: it belongs to Check
    /// copied, never to an AI action.
    struct MoneyText: Error {}

    struct Translation: Decodable {
        let detected: String
        let target: String
        let translation: String
        let provider: String
        let signature: String
    }

    struct Suggestion: Decodable, Equatable {
        let label: String
        /// "rewrite", "ask", "write" or "reply".
        let action: String
    }

    struct Card: Decodable {
        let id: String
        let title: String
        let url: String
        let domain: String
        let snippet: String?
    }

    struct Answer: Decodable {
        let title: String
        let value: String
        let source: String
        let url: String
    }

    struct Search: Decodable {
        let provider: String
        let answer: Answer?
        let cards: [Card]
    }

    struct Glyf: Decodable {
        let id: String
        let name: String
        let prompt: String
    }

    struct Glyfs: Decodable {
        let glyfs: [Glyf]
        let starters: [Glyf]
    }

    struct Built: Decodable {
        let name: String
        let prompt: String
        let provider: String
        let signature: String
    }

    // MARK: Streams

    /// The AI bar's acts, streamed. `source: "copied"` marks someone else's
    /// words: the server refuses money text there (MoneyText).
    func act(text: String, action: String, tone: String? = nil, language: String? = nil,
             context: String? = nil, copied: Bool = false) -> AsyncThrowingStream<Event, Error> {
        var body: [String: Any] = ["text": text, "action": action]
        if let tone { body["tone"] = tone }
        if let language { body["language"] = language }
        if let context, !context.isEmpty { body["context"] = context }
        if copied { body["source"] = "copied" }
        return stream("/v1/act/stream", body)
    }

    /// Run one of my glyfs (by id), or a draft's prompt, on `text`.
    func runGlyf(id: String?, prompt: String?, text: String, copied: Bool = false) -> AsyncThrowingStream<Event, Error> {
        var body: [String: Any] = ["text": text]
        if let id { body["id"] = id }
        if let prompt { body["prompt"] = prompt }
        if copied { body["source"] = "copied" }
        return stream("/v1/glyfs/run", body)
    }

    private func stream(_ path: String, _ body: [String: Any]) -> AsyncThrowingStream<Event, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let r = try request(path, body: body)
                    let (bytes, response): (URLSession.AsyncBytes, URLResponse)
                    do {
                        (bytes, response) = try await URLSession.shared.bytes(for: r)
                    } catch {
                        throw APIError(message: "Can't reach the AIRKEY server.")
                    }
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    guard (200..<300).contains(status) else {
                        var data = Data()
                        for try await b in bytes { data.append(b); if data.count > 4000 { break } }
                        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                        if status == 409, json?["money"] as? Bool == true { throw MoneyText() }
                        throw APIError(message: (json?["error"] as? String) ?? "The server answered \(status).")
                    }
                    var event = ""
                    let decoder = JSONDecoder()
                    for try await line in bytes.lines {
                        if line.hasPrefix("event:") {
                            event = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
                        } else if line.hasPrefix("data:") {
                            let data = Data(line.dropFirst(5).utf8)
                            switch event {
                            case "option":
                                if let o = try? decoder.decode(Option.self, from: data) { continuation.yield(.option(o)) }
                            case "text":
                                if let t = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["t"] as? String {
                                    continuation.yield(.text(t))
                                }
                            case "reset":
                                continuation.yield(.reset)
                            case "done":
                                continuation.yield(.done(try decoder.decode(Done.self, from: data)))
                            case "error":
                                let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
                                throw APIError(message: msg ?? "The AI didn't answer.")
                            default: break
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: Whole answers

    func translate(text: String, target: String) async throws -> Translation {
        try await send(request("/v1/translate", body: ["text": text, "target": target]))
    }

    /// The one thing the AI could do with what's typed, or nil.
    func suggest(text: String) async throws -> Suggestion? {
        struct Reply: Decodable { let suggestion: Suggestion? }
        let r: Reply = try await send(request("/v1/suggest", body: ["text": text]))
        return r.suggestion
    }

    func search(query: String) async throws -> Search {
        try await send(request("/v1/search", body: ["query": query]))
    }

    func glyfs() async throws -> Glyfs { try await send(request("/v1/glyfs")) }

    func saveGlyf(name: String, prompt: String) async throws -> Glyf {
        try await send(request("/v1/glyfs", body: ["name": name, "prompt": prompt]))
    }

    func removeGlyf(id: String) async throws {
        struct OK: Decodable { let ok: Bool }
        var r = try request("/v1/glyfs/\(id)")
        r.httpMethod = "DELETE"
        let _: OK = try await send(r)
    }

    func buildGlyf(description: String) async throws -> Built {
        try await send(request("/v1/glyfs/build", body: ["description": description]))
    }

    // MARK: Plumbing

    private func request(_ path: String, body: [String: Any]? = nil) throws -> URLRequest {
        guard let url = URL(string: base.trimmingCharacters(in: .whitespaces) + path) else {
            throw APIError(message: "The server address in Settings isn't a URL.")
        }
        var r = URLRequest(url: url, timeoutInterval: 40)
        if !token.isEmpty { r.setValue("Bearer \(token)", forHTTPHeaderField: "authorization") }
        r.setValue("keyboard", forHTTPHeaderField: "x-airkey-client")
        if let body {
            r.httpMethod = "POST"
            r.setValue("application/json", forHTTPHeaderField: "content-type")
            r.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return r
    }

    private func send<T: Decodable>(_ r: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: r)
        } catch {
            throw APIError(message: "Can't reach the AIRKEY server.")
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw APIError(message: msg ?? "The server answered \(status).")
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError(message: "The server's answer didn't make sense.")
        }
    }
}
