import Observation
import UIKit

@Observable
@MainActor
final class KeyboardModel {
    enum Layer { case letters, numbers, symbols }

    var layer: Layer = .letters
    var shift = false
    var capsLock = false
    var needsGlobe = true
    var returnLabel = "return"
    /// What the words in the field would do, read as you type.
    var intent: Intent?
    /// A sum, a percentage or a bill split worked out on the phone.
    var instant: Instant?
    /// A price or a currency conversion that came back from the server.
    var answer: Answer?
    /// What the keyboard is looking up, so a late reply for old text is dropped.
    @ObservationIgnored private var asking: Ask?
    /// The kind of command that is running, for the wording while it waits.
    var runningKind: Intent.Kind?
    var running: String?  // "typed" or "pasted" while waiting
    var result: Receipt?
    var notice: String?

    /// What was typed through this keyboard. iOS only hands a keyboard the
    /// text back to the last sentence break ("pay harshal 0.1" arrives as "1"),
    /// so the keyboard keeps its own copy and checks it against what iOS shows.
    @ObservationIgnored private var typed = ""

    @ObservationIgnored var proxy: () -> UITextDocumentProxy? = { nil }
    @ObservationIgnored var advance: () -> Void = {}
    @ObservationIgnored var hasFullAccess: () -> Bool = { false }

    // MARK: typing

    func type(_ s: String) {
        let out = shift || capsLock ? s.uppercased() : s
        insert(out)
        if shift && !capsLock { shift = false }
        UIDevice.current.playInputClick()
        refreshContext()
    }

    func delete() {
        proxy()?.deleteBackward()
        if !typed.isEmpty { typed.removeLast() }
        UIDevice.current.playInputClick()
        refreshContext()
    }

    private func insert(_ s: String) {
        proxy()?.insertText(s)
        typed += s
    }

    func space() {
        // Double space after a word: ". " like the system keyboard.
        if let before = proxy()?.documentContextBeforeInput, before.hasSuffix(" "), let last = before.dropLast().last, last.isLetter || last.isNumber {
            proxy()?.deleteBackward()
            if !typed.isEmpty { typed.removeLast() }
            insert(". ")
        } else {
            insert(" ")
        }
        UIDevice.current.playInputClick()
        refreshContext()
    }

    func returnKey() {
        insert("\n")
        refreshContext()
    }

    func toggleShift() {
        if shift { capsLock.toggle(); shift = capsLock } else { shift = true }
    }

    /// The whole message being written: our own copy before the cursor, plus
    /// whatever iOS shows after it.
    private var fieldText: String {
        typed + (proxy()?.documentContextAfterInput ?? "")
    }

    /// Called after every keystroke and whenever the host app changes the text.
    func refreshContext() {
        let p = proxy()
        let before = p?.documentContextBeforeInput ?? ""
        // Keep our copy honest: empty when the field is (sent or cleared), and
        // replaced by what iOS shows when the two disagree (pasted, cursor moved).
        if before.isEmpty { typed = "" } else if !typed.hasSuffix(before) { typed = before }

        if layer == .letters, !capsLock {
            let sentences = (p?.autocapitalizationType ?? .sentences) == .sentences
            shift = sentences && (before.isEmpty || before.hasSuffix(". ") || before.hasSuffix("? ") || before.hasSuffix("! ") || before.hasSuffix("\n"))
        }
        let text = fieldText
        intent = Intent.read(text)
        // One thing at a time: a command first, then a lookup, then a sum.
        look(up: intent == nil ? Ask.read(text) : nil)
        instant = intent == nil && asking == nil ? Instant.read(text) : nil
        returnLabel = switch proxy()?.returnKeyType {
        case .send: "send"
        case .go: "go"
        case .search, .google, .yahoo: "search"
        case .done: "done"
        case .next: "next"
        case .join: "join"
        default: "return"
        }
    }

    // MARK: answers

    /// Ask the server for a price or a conversion, a moment after typing stops.
    private func look(up ask: Ask?) {
        guard ask != asking else { return }
        asking = ask
        answer = nil
        guard let ask, hasFullAccess() else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard asking == ask else { return }
            let found = await Self.fetch(ask)
            guard asking == ask else { return }
            answer = found
        }
    }

    private static func fetch(_ ask: Ask) async -> Answer? {
        switch ask {
        case .price(let symbol, _):
            guard let p = try? await API().price(symbol) else { return nil }
            return Answer(ask: ask, title: "\(p.symbol) \(Fmt.usd(p.usd))", detail: "Live price from NEAR Intents", insert: "\(p.symbol) is \(Fmt.usd(p.usd))", buy: "buy $2 of \(p.symbol.lowercased())")
        case .fx(let amount, let from, let to):
            guard let c = try? await API().fx(amount: amount, from: from, to: to) else { return nil }
            return Answer(ask: ask, title: Fmt.money(c.value, c.to), detail: "\(amount) \(c.from) at today's rate", insert: " = \(Fmt.money(c.value, c.to))", buy: nil)
        }
    }

    /// Tap on a sum: add the answer to the message.
    func insertInstant() {
        guard let i = instant else { return }
        insert(i.insert)
        refreshContext()
    }

    /// Tap on a price or a conversion: put it in the message. A price replaces "$near".
    func insertAnswer() {
        guard let a = answer else { return }
        if case .price(_, let typed) = a.ask { replaceTail(typed, with: a.insert) } else { insert(a.insert) }
        refreshContext()
    }

    /// Buy on a price: "$near" becomes "buy $2 of near", which the bar then offers to run.
    /// A small amount on purpose: the number is there to be edited.
    func buyAnswer() {
        guard let a = answer, let command = a.buy, case .price(_, let typed) = a.ask else { return }
        replaceTail(typed, with: command)
        refreshContext()
    }

    /// Swap the last thing typed (plus any spaces after it) for something else.
    private func replaceTail(_ tail: String, with new: String) {
        var count = 0
        var rest = Substring(typed)
        while let last = rest.last, last.isWhitespace { rest = rest.dropLast(); count += 1 }
        guard rest.lowercased().hasSuffix(tail.lowercased()) else { insert(" " + new); return }
        count += tail.count
        for _ in 0..<count { proxy()?.deleteBackward() }
        typed.removeLast(min(count, typed.count))
        insert(new)
    }

    /// Keep the list of real token symbols fresh (NEAR Intents' list, by way of
    /// the server), and the names in your contacts.
    func refreshTokens() {
        guard hasFullAccess() else { return }
        if Tokens.stale { Task { if let symbols = try? await API().tokens() { Tokens.save(symbols) } } }
        if Contacts.stale { Task { if let s = try? await API().state() { Contacts.save(s.contacts) } } }
    }

    // MARK: agents

    /// The text in the field: what you typed. Goes to the trusted Payment Agent.
    func runTyped() {
        let text = fieldText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { notice = "Type something first, like “pay harshal 0.2 for dinner”."; return }
        send(text, source: "typed")
    }

    /// What's on the clipboard: someone else's words. Goes to the untrusted Inbox Agent.
    func runPasted() {
        guard hasFullAccess() else { notice = "Turn on Allow Full Access for AIRKEY to check what you copied."; return }
        guard let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            notice = "Copy a message first, then tap Check."
            return
        }
        send(text, source: "pasted")
    }

    private func send(_ text: String, source: String) {
        guard hasFullAccess() else { notice = "Turn on Allow Full Access for AIRKEY so your agents can reach the server."; return }
        notice = nil
        result = nil
        runningKind = source == "typed" ? intent?.kind : nil
        running = source
        Task {
            do {
                let r = try await API().command(text, source: source)
                result = r
                feedback(for: r.signal)
                if source == "typed", r.signal != .block, r.signal != .neutral { clearCommand(text) }
            } catch {
                notice = error.localizedDescription
            }
            running = nil
        }
    }

    /// The command was for the agent, not for the person in the chat: once it
    /// has run, take it out of the message box so it can't be sent by mistake.
    /// Only when the box still holds exactly what was run; a blocked command
    /// stays so it can be fixed.
    private func clearCommand(_ text: String) {
        let p = proxy()
        guard typed.trimmingCharacters(in: .whitespacesAndNewlines) == text, (p?.documentContextAfterInput ?? "").isEmpty else { return }
        for _ in 0..<typed.count { p?.deleteBackward() }
        typed = ""
        refreshContext()
    }

    /// Put the receipt into the chat, so the other person sees it too.
    func insertReceipt() {
        guard let r = result else { return }
        var line = "AIRKEY · \(r.signal.word.capitalized): \(r.message)"
        if let tx = r.tx { line += " \(tx.url)" }
        insert(line)
        result = nil
        refreshContext()
    }

    func dismissResult() { result = nil; notice = nil }

    private func feedback(for signal: Signal) {
        let gen = UINotificationFeedbackGenerator()
        switch signal {
        case .allow: gen.notificationOccurred(.success)
        case .warn: gen.notificationOccurred(.warning)
        case .block: gen.notificationOccurred(.error)
        case .quote, .watch: UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .neutral: break
        }
    }
}
