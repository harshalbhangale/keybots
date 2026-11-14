import Observation
import UIKit

/// The Assist panel's state: which text it works on, the task, what came
/// back so far, and who answered. It never types anything itself: Replace,
/// Insert, Copy and "Use the agent" are handed to the keyboard.
@Observable
@MainActor
final class AssistModel {

    enum Source { case draft, copied }

    enum Phase: Equatable {
        /// Nothing asked yet (Ask or Search waiting for words).
        case waiting
        case working
        case finished
        case failed(String)
        /// Reads as a payment: AIRKEY's agents, not the AI.
        case money
        /// There is nothing to work on.
        case empty
    }

    // What it works on
    let draft: String
    private(set) var copied: String?
    let canCopy: Bool
    private(set) var source: Source

    // What is asked
    private(set) var task: AssistTask = .fix
    private(set) var languages: [String]
    var language: String { languages.first ?? "English" }
    /// Ask or Search: the words typed on the keys.
    private(set) var question = ""
    /// The keys are typing the question (the panel is a strip over them).
    private(set) var typing = false

    // What came back
    private(set) var phase: Phase = .waiting
    /// The answer as shown, which runs a few words behind the stream.
    private(set) var shown = ""
    private(set) var options: [AssistOption] = []
    var picked = 0
    private(set) var links: [AssistLink] = []
    private(set) var receipt: AssistReceipt?
    private(set) var note: String?
    var receiptOpen = false
    /// "Copied" on the button, briefly.
    private(set) var copiedFlash = false

    // Wiring
    @ObservationIgnored var isMoney: (String) -> Bool = { _ in false }
    @ObservationIgnored var onTyping: ((Bool) -> Void)?
    @ObservationIgnored var onClose: (() -> Void)?
    @ObservationIgnored var onReplace: ((_ source: String, _ with: String) -> Void)?
    @ObservationIgnored var onInsert: ((String) -> Void)?
    @ObservationIgnored var onCopy: ((String) -> Void)?
    @ObservationIgnored var onAgent: ((_ text: String, _ copied: Bool) -> Void)?
    @ObservationIgnored var readCopied: (() -> String?)?

    @ObservationIgnored private var job: Task<Void, Never>?
    @ObservationIgnored private var watchdog: Task<Void, Never>?
    @ObservationIgnored private var reveal: Task<Void, Never>?
    /// Words that arrived and are not on screen yet.
    @ObservationIgnored private var backlog = ""
    @ObservationIgnored private var final: String?
    /// Bumped on every run, so a late event from an old one is dropped.
    @ObservationIgnored private var run = 0

    static let allLanguages = ["English", "Hindi", "Spanish", "French", "Arabic", "Japanese",
                               "German", "Portuguese", "Chinese", "Korean"]
    private static let languagesKey = "assistLanguages"

    /// `copied` is the clipboard when the field is empty (read already), or
    /// nil; `canCopy` says whether there is a clipboard to switch to.
    init(draft: String, copied: String?, canCopy: Bool) {
        self.draft = draft
        self.copied = copied
        self.canCopy = canCopy || copied != nil
        source = draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && copied != nil ? .copied : .draft
        let saved = Settings.store.stringArray(forKey: Self.languagesKey) ?? []
        languages = saved.filter(Self.allLanguages.contains)
            + Self.allLanguages.filter { !saved.contains($0) }
    }

    /// The text the task works on.
    var text: String { source == .draft ? draft : (copied ?? "") }
    private var hasText: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Opens on Fix at once when there is text; on Ask otherwise.
    func open(on first: AssistTask = .fix) {
        if hasText || first.takesQuestion { select(first, tick: false) } else { select(.ask, tick: false) }
    }

    // MARK: Choosing

    func select(_ t: AssistTask, tick: Bool = true) {
        if tick { Haptics.layer() }
        task = t
        receiptOpen = false
        if t.takesQuestion {
            stop()
            clear()
            phase = .waiting
            question = ""
            setTyping(true)
            return
        }
        setTyping(false)
        go()
    }

    func pick(language: String) {
        guard language != self.language else { return }
        Haptics.layer()
        languages.removeAll { $0 == language }
        languages.insert(language, at: 0)
        Settings.store.set(languages, forKey: Self.languagesKey)
        go()
    }

    func pick(source s: Source) {
        guard s != source else { return }
        if s == .copied, copied == nil { copied = readCopied?() }
        if s == .copied, (copied ?? "").isEmpty { return }
        if s == .draft, draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }
        Haptics.layer()
        source = s
        if task.takesQuestion { if !question.isEmpty { go() } } else { go() }
    }

    /// Back to the keys to change the question.
    func editQuestion() {
        guard task.takesQuestion else { return }
        stop()
        setTyping(true)
    }

    /// The question as typed on the keys.
    func typed(_ q: String) { question = q }

    /// Return, or the arrow: ask.
    func submit() {
        guard task.takesQuestion else { return }
        guard !question.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        setTyping(false)
        go()
    }

    private func setTyping(_ on: Bool) {
        guard typing != on else { return }
        typing = on
        onTyping?(on)
    }

    // MARK: Running

    func again() {
        Haptics.layer()
        go()
    }

    private func go() {
        stop()
        clear()
        let words = task.takesQuestion ? question : text
        if !task.takesQuestion, !hasText { phase = .empty; return }
        if hasText && isMoney(text) || isMoney(words) {
            phase = .money
            Haptics.warning()
            return
        }
        phase = .working
        run += 1
        let mine = run
        let req = AssistRequest(task: task, text: text,
                                language: task == .translate ? language : nil,
                                question: task.takesQuestion ? question : nil,
                                source: source == .draft ? "typed" : "copied")
        job = Task { [weak self] in
            do {
                for try await event in AssistClient().stream(req) {
                    guard let self, self.run == mine else { return }
                    self.take(event)
                }
                guard let self, self.run == mine else { return }
                if self.phase == .working { self.finish(nil) }
            } catch {
                guard let self, self.run == mine else { return }
                self.fail(error.localizedDescription)
            }
        }
        watchdog = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(AssistClient.timeout * 1_000_000_000))
            guard !Task.isCancelled, let self, self.run == mine, self.phase == .working else { return }
            self.stop()
            self.fail("The AI took too long. Try again.")
        }
    }

    private func take(_ e: AssistEvent) {
        switch e {
        case .words(let t): add(t)
        case .option(let o): if !options.contains(where: { $0.id == o.id }) { options.append(o) }
        case .link(let l): if !links.contains(where: { $0.id == l.id }) { links.append(l) }
        case .finished(let f): finish(f)
        case .refused(let why): fail(why)
        case .money:
            stop()
            clear()
            phase = .money
            Haptics.warning()
        }
    }

    private func finish(_ f: AssistFinish?) {
        watchdog?.cancel()
        if let f {
            if options.isEmpty { options = f.options }
            if links.isEmpty { links = f.links }
            receipt = f.receipt
            note = f.note
            if !f.text.isEmpty { final = f.text }
        }
        if picked >= options.count { picked = 0 }
        phase = .finished
        if reveal == nil { settle() }
    }

    private func fail(_ why: String) {
        watchdog?.cancel()
        reveal?.cancel(); reveal = nil
        phase = .failed(why)
        Haptics.error()
    }

    /// Cancels whatever is in flight (the panel closing, a new task).
    func stop() {
        run += 1
        job?.cancel(); job = nil
        watchdog?.cancel(); watchdog = nil
        reveal?.cancel(); reveal = nil
    }

    private func clear() {
        shown = ""
        backlog = ""
        final = nil
        options = []
        picked = 0
        links = []
        receipt = nil
        note = nil
        receiptOpen = false
    }

    // MARK: Word by word

    /// Streamed text goes on screen a word at a time, a beat apart, so a
    /// burst from the network reads as writing rather than a jump.
    private func add(_ t: String) {
        if Glass.reduceMotion { shown += t; return }
        backlog += t
        guard reveal == nil else { return }
        reveal = Task { [weak self] in
            while let self, !Task.isCancelled, !self.backlog.isEmpty {
                self.shown += self.nextWords()
                try? await Task.sleep(nanoseconds: 32_000_000)
            }
            guard let self, !Task.isCancelled else { return }
            self.reveal = nil
            if self.phase == .finished { self.settle() }
        }
    }

    /// The next word and the space after it; more than one when far behind.
    private func nextWords() -> String {
        let take = backlog.count > 160 ? 3 : 1
        var out = ""
        for _ in 0..<take {
            guard !backlog.isEmpty else { break }
            var i = backlog.startIndex
            while i < backlog.endIndex, backlog[i].isWhitespace { i = backlog.index(after: i) }
            while i < backlog.endIndex, !backlog[i].isWhitespace { i = backlog.index(after: i) }
            out += backlog[..<i]
            backlog = String(backlog[i...])
        }
        return out
    }

    /// The stream is over: the server's final text is the answer.
    private func settle() {
        if let final { shown = final }
        shown = shown.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The caret shows while words are still coming.
    var writing: Bool { phase == .working || (phase == .finished && reveal != nil) }

    // MARK: The answer and what to do with it

    /// What Replace, Insert and Copy use: the picked reply, or the text.
    var answer: String {
        if task == .reply, options.indices.contains(picked) { return options[picked].text }
        return shown
    }

    var canAct: Bool { phase == .finished && !answer.isEmpty && reveal == nil }

    /// Replace swaps the draft; it has no place for copied text or a search.
    var canReplace: Bool {
        source == .draft && !draft.isEmpty && ![.ask, .search].contains(task)
    }

    func replace() {
        guard canAct, canReplace else { return }
        onReplace?(draft, answer)
    }

    func insert() {
        guard canAct else { return }
        onInsert?(answer)
    }

    func insert(link: AssistLink) {
        Haptics.chip()
        onInsert?(link.url)
    }

    func copy() {
        guard canAct else { return }
        onCopy?(answer)
        copiedFlash = true
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            self?.copiedFlash = false
        }
    }

    func useAgent() {
        stop()
        onAgent?(source == .copied ? (copied ?? "") : draft, source == .copied)
    }

    func close() {
        stop()
        onClose?()
    }

    func toggleReceipt() {
        guard receipt != nil else { return }
        Haptics.layer()
        receiptOpen.toggle()
    }

    // MARK: The strip's "Fix this"

    /// Shorthand that reads as rushed.
    private static let shorthand: Set<String> = [
        "u", "ur", "pls", "plz", "tmrw", "tmr", "thx", "thnx", "ty", "r", "y", "b4", "gonna",
        "wanna", "dont", "cant", "wont", "im", "ive", "idk", "rn", "msg", "abt", "bc", "cuz", "sry",
    ]

    /// Local rules, no network: a draft of three words or more that looks
    /// rough (no capital at the start, shorthand, no end mark, double spaces).
    /// Never for a payment; the caller checks that too.
    static func looksRough(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = t.split(whereSeparator: { $0.isWhitespace })
        guard words.count >= 3, t.count <= 600, Intent.read(t) == nil else { return false }
        // Links, handles and code are written that way on purpose.
        if t.contains("://") || t.contains("@") || t.contains("`") { return false }
        var signs = 0
        if let first = t.first, first.isLetter, first.isLowercase { signs += 1 }
        let lower = words.map { $0.lowercased().trimmingCharacters(in: .punctuationCharacters) }
        if lower.contains(where: shorthand.contains) { signs += 2 }
        if lower.contains("i") { signs += 1 }
        if let last = t.last, !".!?…)\"'".contains(last), words.count >= 5 { signs += 1 }
        if text.contains("  ") { signs += 1 }
        return signs >= 2
    }
}
