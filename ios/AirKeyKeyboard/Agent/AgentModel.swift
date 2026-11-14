import Observation
import UIKit

/// What the agent strip needs from the keyboard: the text in the field and
/// a way to change it. The keyboard's view controller is the host.
@MainActor
protocol AgentHost: AnyObject {
    /// What was typed before the caret (the keyboard's own copy, which iOS
    /// cuts short at sentence breaks), plus whatever follows the caret.
    var agentFieldText: String { get }
    var agentHasFullAccess: Bool { get }
    /// Types `text` at the caret, with a space before it when it needs one.
    func agentInsert(_ text: String, spaced: Bool)
    /// Swaps the last thing typed (`tail`, plus any spaces after it) for `new`.
    func agentReplaceTail(_ tail: String, with new: String)
    /// Takes `text` out of the message box when the box holds exactly it.
    func agentClear(_ text: String)
}

/// AIRKEY's agents in the keyboard. The keys and the strip are the
/// keyboard's; this is what rides on top of them: what the words in the
/// field would do (a payment, a swap, a trade), a price or a conversion
/// looked up as you type, and what came back from the server.
///
/// The keyboard never holds a key and never signs: a command goes to the
/// AIRKEY server, whose agents ask the leash on NEAR. A tap never runs a
/// command; only the press-and-hold button in the strip does.
@Observable
@MainActor
final class AgentModel {
    /// A command ready to run, as the strip shows it: what it would do and
    /// the word on its hold button. `command` is what goes to the server
    /// when it is not the field's own text (a reading of loose wording).
    struct Ready: Equatable {
        let kind: Intent.Kind
        let title: String
        let detail: String?
        let verb: String
        var command: String? = nil
        /// Short lines the strip turns through under the title, one at a
        /// time (a copied call's checks), in place of `detail`.
        var lines: [String] = []
        /// CALLS HOOK: the copied call's record in the calls book, so its hold is kept with it.
        var callId: String? = nil
        /// A copied call's own words: its chip opens the review card, never a trade.
        var callText: String? = nil

        var icon: String { kind == .pay ? "arrow.up.right" : "arrow.left.arrow.right" }
        var holdLabel: String { "Hold to \(verb)" }
    }

    /// What the words in the field would do, read as you type.
    var intent: Intent?
    /// A reading of wording the phone's own patterns don't know, from the
    /// AIRKEY server, for the text it was asked about.
    var readIntent: Ready?

    /// The command the strip offers to run, if any.
    var ready: Ready? {
        if let intent { return Ready(kind: intent.kind, title: intent.title, detail: intent.detail, verb: intent.verb) }
        return readIntent ?? callIntent
    }
    /// A sum, a percentage or a bill split worked out on the phone, when the
    /// keyboard's own answers had nothing for the text.
    var instant: Instant?
    /// A price or a currency conversion that came back from the server.
    var answer: Answer?
    /// The kind of command that is running, for the wording while it waits.
    var runningKind: Intent.Kind?
    /// "typed" or "pasted" while waiting on the server.
    var running: String?
    var result: Receipt?
    var notice: String?
    /// The vault row is open in the strip, with what it offers.
    var vaultOpen = false
    var vaultItems: [Vault.Item] = []
    /// The trade a copied crypto call could be, ready to hold (POST /v1/call).
    var callIntent: Ready?
    /// The message text when the call chip came up: typing anything new
    /// means you moved on, and the chip goes.
    @ObservationIgnored private var callFor: String?
    /// The paste guard: an address that arrived whole and isn't one you know.
    var pasteWarning: String?

    /// True while the strip is the agent's (the toolbar's otherwise).
    var isShowing: Bool {
        result != nil || notice != nil || running != nil || vaultOpen
            || ready != nil || answer != nil || instant != nil || pasteWarning != nil
    }

    @ObservationIgnored weak var host: AgentHost?

    /// How the AIRKEY server read wording the phone's patterns don't know:
    /// what the strip shows, and the exact command a hold sends.
    struct Reading: Equatable {
        let kind: Intent.Kind
        let title: String
        let verb: String
        let command: String
        /// The model that read it ("NEAR AI", "OpenAI"), or nil when the server's rules did.
        let readBy: String?
    }
    /// Asks the server to read a line; nil when it isn't a command.
    @ObservationIgnored var reader: ((String) async -> Reading?)?
    /// What the keyboard is looking up, so a late reply for old text is dropped.
    @ObservationIgnored private var asking: Ask?
    /// The field's text at the last read, and the text a sum or an answer
    /// was put away for: it stays away until the text changes.
    @ObservationIgnored private var lastText = ""
    @ObservationIgnored private var putAwayFor: String?
    /// What the agents just put in the message themselves (a receipt, an
    /// address from the vault), so the paste guard lets it be.
    @ObservationIgnored private var ownInsert: String?
    /// False until the first read after the keyboard opens: a draft that's
    /// already in the field was not pasted just now.
    @ObservationIgnored private var primed = false
    @ObservationIgnored private var warnedAddress: String?

    // MARK: Reading the field

    /// Called whenever the text settles. `answered` is true when the
    /// keyboard's own strip already has an answer for it (a sum, a unit).
    func read(_ text: String, answered: Bool) {
        guardPaste(old: lastText, new: text)
        if callIntent != nil, let callFor, text != callFor {
            callIntent = nil
            self.callFor = nil
        }
        lastText = text
        let next = Intent.read(text)
        if next != intent { intent = next }
        askServer(text)
        if let putAwayFor, putAwayFor == text { return }
        putAwayFor = nil
        // One thing at a time: a command first, then a lookup, then a sum.
        // A conversion the keyboard already worked out ("50 usd in inr") is
        // not asked of the server again: its chip is up, with no flip.
        look(up: ready == nil && !answered ? Ask.read(text) : nil)
        let sum = ready == nil && asking == nil && !answered ? Instant.read(text) : nil
        if sum != instant { instant = sum }
    }

    // MARK: Loose wording

    /// Words a command starts with, when the phone's patterns don't read it.
    private static let commandStarts: Set<String> = [
        "pay", "send", "give", "tip", "transfer", "swap", "buy", "sell", "convert", "exchange", "trade",
    ]
    @ObservationIgnored private var readFor: String?
    @ObservationIgnored private var readTask: Task<Void, Never>?

    /// "swap 5 bucks of near into usdc": the phone's patterns miss it, but it
    /// starts like a command, so the AIRKEY server reads it (its rules, or a
    /// model) a moment after typing stops. Only with Full Access; a reply for
    /// text that has moved on is dropped. The hold then sends the server's
    /// exact command, never the loose words.
    private func askServer(_ text: String) {
        let line = text.split(whereSeparator: \.isNewline).last.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        let first = line.split(separator: " ").first.map { $0.lowercased() } ?? ""
        guard intent == nil, line.count >= 8, Self.commandStarts.contains(first),
              host?.agentHasFullAccess == true, let reader else {
            readTask?.cancel()
            readTask = nil
            readFor = nil
            if readIntent != nil { readIntent = nil }
            return
        }
        guard line != readFor else { return }
        readFor = line
        if readIntent != nil { readIntent = nil }
        readTask?.cancel()
        readTask = Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled, readFor == line else { return }
            let reading = await reader(line)
            guard !Task.isCancelled, readFor == line, let reading else { return }
            readIntent = Ready(kind: reading.kind, title: reading.title, detail: reading.readBy.map { "Read by \($0)" },
                               verb: reading.verb, command: reading.command)
        }
    }

    /// Ask the server for a price or a conversion, a moment after typing stops.
    private func look(up ask: Ask?) {
        guard ask != asking else { return }
        asking = ask
        if answer != nil { answer = nil }
        guard let ask, host?.agentHasFullAccess == true else { return }
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
            return Answer(ask: ask, title: "\(p.symbol) \(Fmt.usd(p.usd))", detail: "Live price from NEAR Intents",
                          insert: "\(p.symbol) is \(Fmt.usd(p.usd))", buy: "buy $2 of \(p.symbol.lowercased())")
        case .fx(let amount, let from, let to):
            guard let c = try? await API().fx(amount: amount, from: from, to: to) else { return nil }
            return Answer(ask: ask, title: Fmt.money(c.value, c.to), detail: "\(amount) \(c.from) at today's rate",
                          insert: " = \(Fmt.money(c.value, c.to))", buy: nil)
        }
    }

    /// Keep the list of real token symbols fresh (NEAR Intents' list, by way
    /// of the server), the names in your contacts and your NEAR account.
    func refreshTokens() {
        primed = false
        guard host?.agentHasFullAccess == true else { return }
        if Tokens.stale { Task { if let symbols = try? await API().tokens() { Tokens.save(symbols) } } }
        Task { await Vault.pull() }
        if Contacts.stale || Contacts.accounts.isEmpty || Vault.owner == nil {
            Task {
                guard let s = try? await API().state() else { return }
                Contacts.save(s.contacts)
                Vault.saveOwner(s.owner)
            }
        }
    }

    // MARK: Answers

    /// Tap on a sum: add the answer to the message.
    func insertInstant() {
        guard let i = instant else { return }
        host?.agentInsert(i.insert, spaced: false)
        instant = nil
    }

    /// Tap on a price or a conversion: put it in the message. A price
    /// replaces "$near".
    func insertAnswer() {
        guard let a = answer else { return }
        if case .price(_, let typed) = a.ask { host?.agentReplaceTail(typed, with: a.insert) } else { host?.agentInsert(a.insert, spaced: false) }
        answer = nil
    }

    /// Buy on a price: "$near" becomes "buy $2 of near", which the strip then
    /// offers to run. A small amount on purpose: the number is there to be edited.
    func buyAnswer() {
        guard let a = answer, let command = a.buy, case .price(_, let typed) = a.ask else { return }
        host?.agentReplaceTail(typed, with: command)
        answer = nil
    }

    // MARK: Agents

    /// The hold on the strip's button: the command it shows.
    func runReady() {
        // The hold button has already played its rising ticks and its thud (HoldFeel).
        // Trade panel hook: a swap, a buy or a sell opens the swap screen, filled in; it runs from there.
        if reviewCall() { return }
        if reviewReady() { return }
        if intent == nil, readIntent == nil, callIntent != nil {
            // A copied call only ever trades from its review card.
            return
        } else if let command = ready?.command { runCommand(command) } else { runTyped() }
    }

    // MARK: A copied call's review

    /// Opens Calls on the copied call's review card (keyboard's hook).
    @ObservationIgnored var openCallReview: ((_ text: String) -> Void)?

    /// The chip of a copied call opens its review: pay, get, limits, then the hold.
    @discardableResult
    func reviewCall() -> Bool {
        guard intent == nil, readIntent == nil, let call = callIntent, let text = call.callText, let openCallReview else { return false }
        callIntent = nil
        openCallReview(text)
        return true
    }

    // MARK: Trade panel (hook)

    /// Opens the keyboard's swap screen on a command; false when it can't read it as a trade.
    @ObservationIgnored var openTrade: ((_ command: String, _ origin: String?) -> Bool)?

    /// The chip's trade goes to the swap screen instead of running: every
    /// number is on screen before the hold. False for a payment.
    @discardableResult
    func reviewReady() -> Bool {
        guard let ready, ready.kind == .swap, let openTrade else { return false }
        let typed = (host?.agentFieldText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let fromCall = intent == nil && readIntent == nil && callIntent != nil
        let line = typed.split(whereSeparator: \.isNewline).last.map(String.init) ?? typed
        guard openTrade(ready.command ?? line, fromCall ? nil : typed) else { return false }
        if fromCall { callIntent = nil }
        return true
    }

    /// The swap screen's hold: its quote's own command, sent as typed, so the
    /// receipt, Share and the haptics are the strip's as ever.
    func runTrade(_ command: String, clearing: String?) {
        send(command, source: "typed", clearing: clearing)
        if running != nil { runningKind = .swap }
    }

    /// A command the server read out of what was typed: it runs, and what
    /// was typed is taken out of the message box as a typed command is.
    func runCommand(_ command: String) {
        let typed = (host?.agentFieldText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        send(command, source: "typed", clearing: typed)
    }

    /// The text in the field: what you typed. Goes to the trusted Payment Agent.
    func runTyped() {
        let text = (host?.agentFieldText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { notice = "Type something first, like “pay harshal 0.2 for dinner”."; return }
        send(text, source: "typed")
    }

    /// What's on the clipboard: someone else's words. Goes to the untrusted Inbox Agent.
    func runPasted() {
        guard host?.agentHasFullAccess == true else { notice = "Turn on Allow Full Access for AIRKEY to check what you copied."; return }
        guard let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            // A keyboard can't show iOS's "Allow Paste" prompt, so a refused read looks like an empty clipboard.
            notice = UIPasteboard.general.hasStrings
                ? "To check copied text: Settings › Apps › AIRKEY › Paste from Other Apps › Allow."
                : "Copy a message first, then tap Check."
            return
        }
        checkCall(text)
    }

    /// A copied message. A crypto call becomes a trade chip to hold, its
    /// token checked on NEAR Intents and its size under the leash's caps (or
    /// one line saying why not); anything else goes to the untrusted Inbox Agent.
    private func checkCall(_ text: String) {
        notice = nil
        result = nil
        callIntent = nil
        running = "pasted"
        Task {
            let check = try? await API().call(text)
            running = nil
            guard let check, check.call.isCall else { send(text, source: "pasted"); return }
            let r = check.route
            guard r.status == "available", let command = r.command, let title = r.title else {
                notice = Plain.scrub(r.reason ?? check.call.summary)
                Haptics.warning()
                return
            }
            callIntent = Ready(kind: .swap, title: title, detail: nil, verb: r.side == "sell" ? "sell" : "buy",
                               command: command, lines: Self.callLines(check), callId: check.id, callText: text)
            callFor = lastText
            Haptics.chip()
        }
    }

    private static func callLines(_ c: CallCheck) -> [String] {
        let r = c.route
        var caps = "your limits apply"
        if let k = r.caps {
            caps = k.paused ? "Stop everything is on"
                : (k.within ?? true) ? "within your limits" : "over today's limit (\(k.leftToday) NEAR left)"
        }
        var lines = ["\(c.call.asset ?? "Token") is a real token · \(caps)"]
        if let q = r.quote {
            lines.append("Live price: \(q.amountIn) NEAR gets about \(Plain.tidy(q.amountOut)) \(q.symbolOut)")
        }
        if let s = r.standIn { lines.append(Plain.scrub(s)) }
        return lines
    }

    /// The paste guard (Protections.swift): warn about an address that
    /// arrived whole and isn't yours, your vault's or a contact's.
    private func guardPaste(old: String, new: String) {
        defer { if new != old { ownInsert = nil } }
        if let warned = warnedAddress, !new.contains(warned) {
            warnedAddress = nil
            pasteWarning = nil
        }
        guard primed else { primed = true; return }
        guard new != old, let a = PasteGuard.stranger(old: old, new: new, known: PasteGuard.known),
              !(ownInsert?.contains(a) ?? false) else { return }
        warnedAddress = a
        pasteWarning = "\(PasteGuard.short(a)) isn't yours or a contact's. Check every character before you pay it."
        Haptics.warning()
    }

    private func send(_ text: String, source: String, clearing: String? = nil, callId: String? = nil) {
        guard host?.agentHasFullAccess == true else { notice = "Turn on Allow Full Access for AIRKEY so it can pay and swap for you."; return }
        notice = nil
        result = nil
        vaultOpen = false
        runningKind = source == "typed" ? ready?.kind : nil
        running = source
        Task {
            do {
                // CALLS HOOK: a copied call's hold carries the call's id.
                let r = if let callId { try await API().command(text, callId: callId) } else { try await API().command(text, source: source) }
                result = r
                feedback(for: r.signal)
                if source == "typed", r.signal != .block, r.signal != .neutral { host?.agentClear(clearing ?? text) }
            } catch {
                notice = error.localizedDescription
            }
            running = nil
        }
    }

    /// Put the receipt into the chat, so the other person sees it too.
    func insertReceipt() {
        guard let r = result else { return }
        // The plain line says what happened ("Paid 0.2 NEAR to harshal", "Blocked: …").
        var line = "AIRKEY · \(Plain.line(r))"
        if let tx = r.tx { line += " \(tx.url)" }
        result = nil
        ownInsert = line
        host?.agentInsert(line, spaced: true)
    }

    /// WALLET/CALLS HOOK: words the Wallet or Calls panel puts in the message
    /// (a receipt, an address, "pay vendor 0.2"), marked as the keyboard's
    /// own so the paste guard lets them be.
    func insertOwn(_ text: String) {
        ownInsert = text
        host?.agentInsert(text, spaced: true)
    }

    func dismiss() {
        callIntent = nil
        pasteWarning = nil
        result = nil
        notice = nil
        vaultOpen = false
        // A sum or an answer put away stays away until the text changes.
        if instant != nil || answer != nil { putAwayFor = lastText }
        instant = nil
        answer = nil
    }

    // MARK: Vault

    /// Show your NEAR account and saved addresses in the strip.
    func openVault() {
        vaultItems = Vault.all
        if host?.agentHasFullAccess == true {
            Task { @MainActor in
                await Vault.pull()
                vaultItems = Vault.all
                if !vaultItems.isEmpty { notice = nil }
            }
        }
        guard !vaultItems.isEmpty else {
            notice = "Add addresses in the AIRKEY app, in Settings › Vault."
            return
        }
        notice = nil
        result = nil
        vaultOpen = true
    }

    /// Put an address in the message, with a space before it if it needs one.
    func insertVault(_ item: Vault.Item) {
        vaultOpen = false
        ownInsert = item.value
        host?.agentInsert(item.value, spaced: true)
        if SettingsStore.current.keyClicks { UIDevice.current.playInputClick() }
        Haptics.letter()
    }

    private func feedback(for signal: Signal) {
        switch signal {
        case .allow: Haptics.success()
        case .warn: Haptics.warning()
        case .block: Haptics.error()
        case .quote, .watch: Haptics.chip()
        case .neutral: break
        }
    }
}
