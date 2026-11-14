import Foundation

/// What the Assist panel can do with a piece of text. The raw value is the
/// server's name for it (POST /v1/assist).
enum AssistTask: String, CaseIterable, Identifiable {
    case fix, shorter, warmer, formal, reply, translate, ask, search

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fix: "Fix"
        case .shorter: "Shorter"
        case .warmer: "Warmer"
        case .formal: "Formal"
        case .reply: "Reply"
        case .translate: "Translate"
        case .ask: "Ask"
        case .search: "Search"
        }
    }

    /// Ask and Search need words of their own, typed on the keys.
    var takesQuestion: Bool { self == .ask || self == .search }
}

/// One reply the server suggests ("Yes", "Not now", "Ask back").
struct AssistOption: Identifiable, Equatable {
    let id: String
    let label: String
    let text: String
}

/// One web result for Search.
struct AssistLink: Identifiable, Equatable {
    let id: String
    let title: String
    let url: String
    let site: String
    let snippet: String
}

/// Who answered and what was proven about it.
struct AssistReceipt: Equatable {
    /// "near-ai-cloud" or "openai".
    let provider: String
    let model: String
    /// "verified", "mismatch" or "unavailable".
    let signature: String
    /// "verified", "partial", "failed" or "not checked".
    let attestation: String
    /// tdxQuote, nvidia, nonce, signerMatch, composeHash: passed, failed or
    /// unavailable (a missing key is unavailable too).
    let checks: [String: CheckState]

    enum CheckState: Equatable { case passed, failed, unavailable }

    func state(_ key: String) -> CheckState { checks[key] ?? .unavailable }
    let ms: Int?

    var isNear: Bool { provider == "near-ai-cloud" }
    /// The badge's check: a NEAR AI answer whose signature and hardware both checked out.
    var isPrivate: Bool { isNear && signature == "verified" && attestation == "verified" }
}

/// What a finished answer carries.
struct AssistFinish: Equatable {
    let text: String
    let options: [AssistOption]
    let links: [AssistLink]
    let receipt: AssistReceipt?
    let note: String?
}

/// One thing the stream said.
enum AssistEvent {
    case words(String)
    case option(AssistOption)
    case link(AssistLink)
    case finished(AssistFinish)
    /// The server would not do it (plain words).
    case refused(String)
    /// The text reads as a payment: AIRKEY's agents handle that, not the AI.
    case money(String)
}

struct AssistRequest {
    var task: AssistTask
    var text: String
    var language: String?
    var question: String?
    /// "typed" (the draft) or "copied" (the clipboard).
    var source: String
}

/// Talks to the AIRKEY server's /v1/assist over server-sent events. The
/// address and token are the ones the rest of AIRKEY uses (Shared/API.swift).
/// Every field is read loosely: a missing or renamed one is skipped, never fatal.
struct AssistClient {
    var base: String = Settings.serverURL
    var token: String = Settings.token
    static let timeout: TimeInterval = 40

    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = timeout
        c.timeoutIntervalForResource = timeout
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }()

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// The events, in order. Cancelling the consuming task cancels the request.
    func stream(_ req: AssistRequest) -> AsyncThrowingStream<AssistEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await run(req, continuation)
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch let e as URLError where e.code == .cancelled {
                    continuation.finish()
                } catch let e as URLError where e.code == .timedOut {
                    continuation.finish(throwing: Failure(message: "The AI took too long. Try again."))
                } catch let e as URLError {
                    _ = e
                    continuation.finish(throwing: Failure(message: "Can't reach the Keybots server."))
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(_ req: AssistRequest, _ out: AsyncThrowingStream<AssistEvent, Error>.Continuation) async throws {
        guard let url = URL(string: base.trimmingCharacters(in: .whitespaces) + "/v1/assist") else {
            throw Failure(message: "The server address in Settings isn't a URL.")
        }
        var r = URLRequest(url: url, timeoutInterval: Self.timeout)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "content-type")
        r.setValue("text/event-stream", forHTTPHeaderField: "accept")
        r.setValue("keyboard", forHTTPHeaderField: "x-airkey-client")
        if !token.isEmpty { r.setValue("Bearer \(token)", forHTTPHeaderField: "authorization") }
        var body: [String: Any] = ["task": req.task.rawValue, "text": req.text, "source": req.source]
        if let l = req.language { body["language"] = l }
        if let q = req.question { body["question"] = q }
        r.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await Self.session.bytes(for: r)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            var raw = Data()
            for try await b in bytes { raw.append(b); if raw.count > 16_384 { break } }
            let json = (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any]
            let said = Self.string(json?["error"])
            if status == 409 || (json?["money"] as? Bool) == true {
                out.yield(.money(said ?? ""))
                return
            }
            if status == 401 || status == 403 { throw Failure(message: "The server didn't accept this keyboard's token.") }
            throw Failure(message: said.map(Plain.scrub) ?? "The AI isn't answering right now (\(status)).")
        }

        // `lines` skips blank lines, so each data line is handled as it comes,
        // under the last event name seen (JSON never spans lines here).
        var name: String?
        for try await line in bytes.lines {
            try Task.checkCancellation()
            if line.hasPrefix("event:") {
                name = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
                continue
            }
            guard line.hasPrefix("data:") else { continue }
            let data = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            defer { name = nil }
            guard data != "[DONE]", let json = (try? JSONSerialization.jsonObject(with: Data(data.utf8))) as? [String: Any] else { continue }
            let kind = name ?? Self.string(json["type"]) ?? Self.string(json["event"]) ?? ""
            if let event = Self.event(kind, json) {
                out.yield(event)
                if case .finished = event { return }
                if case .refused = event { return }
            }
        }
    }

    // MARK: Reading the events

    static func event(_ kind: String, _ j: [String: Any]) -> AssistEvent? {
        switch kind {
        case "chunk":
            guard let t = string(j["t"]) ?? string(j["text"]), !t.isEmpty else { return nil }
            return .words(t)
        case "option":
            return option(j).map(AssistEvent.option)
        case "result":
            return link(j).map(AssistEvent.link)
        case "done":
            let receipt = (j["receipt"] as? [String: Any]).map(receipt)
            return .finished(AssistFinish(
                text: string(j["text"]) ?? "",
                options: (j["options"] as? [[String: Any]] ?? []).compactMap(option),
                links: (j["results"] as? [[String: Any]] ?? []).compactMap(link),
                receipt: receipt,
                note: string(j["note"])))
        case "error":
            if (j["money"] as? Bool) == true { return .money(string(j["error"]) ?? "") }
            return .refused(string(j["error"]).map(Plain.scrub) ?? "Something went wrong.")
        default:
            return nil
        }
    }

    private static func option(_ j: [String: Any]) -> AssistOption? {
        guard let text = string(j["text"]), !text.isEmpty else { return nil }
        let label = string(j["label"]) ?? ""
        return AssistOption(id: string(j["id"]) ?? label + text, label: label, text: text)
    }

    private static func link(_ j: [String: Any]) -> AssistLink? {
        guard let url = string(j["url"]), !url.isEmpty else { return nil }
        let site = string(j["site"]) ?? URL(string: url)?.host ?? ""
        return AssistLink(id: string(j["id"]) ?? url, title: string(j["title"]) ?? site,
                          url: url, site: site, snippet: string(j["snippet"]) ?? "")
    }

    private static func receipt(_ j: [String: Any]) -> AssistReceipt {
        var checks: [String: AssistReceipt.CheckState] = [:]
        for (k, v) in j["checks"] as? [String: Any] ?? [:] {
            if let b = v as? Bool {
                checks[k] = b ? .passed : .failed
            } else if let s = (v as? String)?.lowercased() {
                checks[k] = ["verified", "ok", "pass", "passed", "true", "match"].contains(s) ? .passed
                    : ["failed", "fail", "false", "mismatch", "invalid"].contains(s) ? .failed : .unavailable
            } else {
                checks[k] = .unavailable
            }
        }
        let ms = (j["ms"] as? NSNumber)?.intValue ?? string(j["ms"]).flatMap { Int($0) }
        return AssistReceipt(provider: string(j["provider"]) ?? "", model: string(j["model"]) ?? "",
                             signature: string(j["signature"]) ?? "unavailable",
                             attestation: string(j["attestation"]) ?? "not checked",
                             checks: checks, ms: ms)
    }

    private static func string(_ v: Any?) -> String? {
        switch v {
        case let s as String: s
        case let n as NSNumber: n.stringValue
        default: nil
        }
    }
}
