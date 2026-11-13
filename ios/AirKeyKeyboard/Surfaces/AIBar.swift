import NaturalLanguage
import UIKit

protocol AIBarDelegate: AnyObject {
    /// ✕: back to the keys.
    func aiBarClosed()
    /// The ask field takes the keys (an editor), or gives them back (nil).
    func aiBarAskActivated(_ editor: InlineEditor?)
    /// The bar moved between the strip (asking, keys live) and the panel.
    func aiBarLayoutChanged()
    /// Swap `source`, the text before the cursor the answer was made from,
    /// for the answer.
    func aiBarReplace(source: String, with text: String)
    /// Put the answer in at the cursor.
    func aiBarInsert(_ text: String)
    func aiBarCopy(_ text: String)
    /// Live translate: swap `source` for its translation; the strip stays.
    func aiBarSwap(source: String, with text: String)
    /// What was copied, read now (the tap on a Copied tile is the ask).
    func aiBarReadCopied() -> String?
    /// The copied text is a payment or a crypto call: it goes to Check
    /// copied, never to an AI action.
    func aiBarCheckCopied()
}

/// Hold space → AI on what you wrote. Everything Glyf's AI does, in
/// AIRKEY's look: one thing at a time, quiet tiles on the sheet, lime only
/// where it means "this one".
///
///  · actions   — tiles: Rewrite, Reply, Translate, Tone, Ask, Live
///                translate, Search, My glyfs (or, on a copy: Summarize,
///                Reply, Translate, Ask, Check copied…)
///  · tones     — Natural, Professional, Casual, Gen-Z
///  · prompting — one field in the strip, the keys live under it: a
///                question, a search, or what a new glyf should do
///  · live      — live translate in the strip while you type; a tap puts
///                the translation in
///  · working   — your text in the card; the answer writes itself over it
///  · versions  — a rewrite's versions, each as soon as it is written
///  · result    — the answer, who answered, and ↻ Copy Insert Replace
///  · cards     — search results; Insert puts the picked one in
///  · glyfs     — my glyfs, the ready-made ones, and Build your own
///  · draft     — a glyf the AI just built: Try it, Save it
///  · failed / locked
///
/// Nothing goes in until a button is tapped. The answers come from the
/// AIRKEY server: NEAR AI Cloud first, OpenAI only when that is allowed,
/// and every answer says which one gave it.
final class AIBar: UIView {

    weak var delegate: AIBarDelegate?

    enum Action: String { case rewrite, reply, translate, tone, ask, summarize, write, glyf, search, build }

    struct Request {
        var action: Action
        var text: String
        var tone: String?
        var toneLabel: String?
        var language: String?
        /// Ask: the text the question is about.
        var context: String?
        /// The text is someone else's (copied), not what you typed.
        var copied = false
        var glyfID: String?
        var glyfPrompt: String?
        var glyfName: String?
    }

    private enum Phase { case actions, tones, prompting, live, working, versions, result, cards, glyfs, draft, failed, locked }
    private var phase: Phase = .actions

    /// What the strip's field is for.
    private enum Prompt { case ask, search, build }
    private var prompt: Prompt = .ask

    /// Asking and live translate happen in the strip, with the keys under
    /// it; everything else covers the keys.
    var isStrip: Bool { phase == .prompting || phase == .live }

    /// What the field held before the cursor when the bar opened; empty
    /// when there was nothing to work on.
    private var source = ""
    /// Something was just copied, and the field is empty: the bar works on
    /// the copy. Its text is read only when a tile asks for it.
    private var onCopy = false
    private var copied: String?
    private var request: Request?
    private var answer: ActResult?
    private var options: [AIClient.Option] = []
    private var search: AIClient.Search?
    private var glyfList: AIClient.Glyfs?
    private var draft: AIClient.Built?
    private var task: Task<Void, Never>?
    private var runID = 0
    private var busy = false
    /// Whether the bar opened on the tiles (so the strip's field goes back to them).
    private var hasTiles = true

    /// The most text one act reads (the server's cap too): the end of
    /// what was written, nearest the cursor.
    static let maxSource = 2000

    /// (label, what the prompt says): Glyf's four tones.
    static let tones: [(label: String, value: String)] = [
        ("Natural", "natural, human"),
        ("Professional", "professional"),
        ("Casual", "casual"),
        ("Gen-Z", "gen-z playful"),
    ]

    // Header (the strip's row)
    private let closeButton = UIButton(type: .system)
    private let moreButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let directionButton = UIButton(type: .system)
    private let providerLabel = UILabel()
    private let progressTrack = UIView()
    private let progressBar = CAGradientLayer()

    // Prompting
    private let askEditor = InlineEditor(placeholder: "Ask anything", symbol: "sparkles")
    private let sendButton = UIButton(type: .system)

    // Live translate
    private let liveLabel = UILabel()
    private var liveWork: DispatchWorkItem?
    private var liveTask: Task<Void, Never>?
    private var liveTarget = "Spanish"
    private var liveSource = ""
    private var liveWindow = ""
    private var liveTranslation = ""
    private var liveProvider: (name: String, verified: Bool)?
    /// What a tap just put in: the draft is now a translation, not something to translate again.
    private var liveSwapped = ""

    // Tiles: actions and tones.
    private let tiles = (0..<8).map { _ in AITile() }
    private var tileCount = 4

    // Working, result, failed, locked
    private let card = UIView()
    private let textView = UITextView()
    private let statusLabel = UILabel()
    private let list = AIList()
    private let retryButton = UIButton(type: .system)
    private let copyButton = UIButton(type: .system)
    private let insertButton = UIButton(type: .system)
    private let replaceButton = UIButton(type: .system)

    init() {
        super.init(frame: .zero)
        // Never fully clear: a keyboard drops touches on clear pixels.
        backgroundColor = Glass.touchableGrid
        accessibilityIdentifier = "ai:bar"
        buildHeader()
        buildAsking()
        for tile in tiles { addSubview(tile) }
        buildCard()
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Closing lets go of everything: the request in flight too.
    override func willMove(toSuperview newSuperview: UIView?) {
        super.willMove(toSuperview: newSuperview)
        if newSuperview == nil {
            cancel()
            stopLive()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        runID += 1
        busy = false
        stopProgress()
    }

    // MARK: Build

    private func buildHeader() {
        // Exactly the strip's g pill: its place and shape.
        closeButton.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold), forImageIn: .normal)
        closeButton.tintColor = Glass.textPrimary
        closeButton.backgroundColor = Glass.fillSoft
        closeButton.layer.cornerRadius = 10
        closeButton.layer.cornerCurve = .continuous
        closeButton.accessibilityIdentifier = "ai:close"
        closeButton.addAction(UIAction { [weak self] _ in self?.closeTapped() }, for: .touchUpInside)
        addSubview(closeButton)

        // In the ask strip: everything else the AI does.
        moreButton.setImage(UIImage(systemName: "square.grid.2x2", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)), for: .normal)
        moreButton.tintColor = Glass.textPrimary
        moreButton.backgroundColor = Glass.fillSoft
        moreButton.layer.cornerRadius = 10
        moreButton.layer.cornerCurve = .continuous
        moreButton.accessibilityIdentifier = "ai:more"
        moreButton.accessibilityLabel = "More"
        moreButton.addAction(UIAction { [weak self] _ in self?.moreTapped() }, for: .touchUpInside)
        addSubview(moreButton)

        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = Glass.textPrimary
        titleLabel.accessibilityIdentifier = "ai:title"
        addSubview(titleLabel)

        directionButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        directionButton.setTitleColor(Glass.textPrimary, for: .normal)
        directionButton.tintColor = Glass.textSecondary
        directionButton.setImage(UIImage(systemName: "chevron.up.chevron.down",
                                         withConfiguration: UIImage.SymbolConfiguration(pointSize: 9, weight: .bold)),
                                 for: .normal)
        directionButton.semanticContentAttribute = .forceRightToLeft
        directionButton.imageEdgeInsets = UIEdgeInsets(top: 0, left: 5, bottom: 0, right: 0)
        directionButton.contentEdgeInsets = UIEdgeInsets(top: 0, left: 11, bottom: 0, right: 15)
        directionButton.backgroundColor = Glass.fillSoft
        directionButton.layer.cornerCurve = .continuous
        directionButton.accessibilityIdentifier = "ai:language"
        directionButton.accessibilityHint = "Translates into another language"
        directionButton.addAction(UIAction { [weak self] _ in self?.cycleLanguage() }, for: .touchUpInside)
        addSubview(directionButton)

        providerLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        providerLabel.textColor = Glass.textSecondary
        providerLabel.textAlignment = .right
        providerLabel.accessibilityIdentifier = "ai:provider"
        addSubview(providerLabel)

        // Live translate: the translation, in the strip. A tap puts it in.
        liveLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        liveLabel.textColor = Glass.textPrimary
        liveLabel.lineBreakMode = .byTruncatingHead
        liveLabel.adjustsFontSizeToFitWidth = true
        liveLabel.minimumScaleFactor = 0.8
        liveLabel.isUserInteractionEnabled = true
        liveLabel.accessibilityIdentifier = "ai:live"
        liveLabel.accessibilityTraits = .button
        liveLabel.accessibilityHint = "Puts the translation in"
        liveLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(liveTapped)))
        addSubview(liveLabel)

        // The one sign of work: a short lime line crossing under the header.
        progressTrack.isUserInteractionEnabled = false
        progressTrack.clipsToBounds = true
        let lime = Glass.chipAccent
        progressBar.colors = [lime.withAlphaComponent(0).cgColor, lime.cgColor, lime.withAlphaComponent(0).cgColor]
        progressBar.startPoint = CGPoint(x: 0, y: 0.5)
        progressBar.endPoint = CGPoint(x: 1, y: 0.5)
        progressTrack.layer.addSublayer(progressBar)
        addSubview(progressTrack)
    }

    private func buildAsking() {
        askEditor.showsEnd = true
        askEditor.accessibilityIdentifier = "ai:ask"
        askEditor.onChange = { [weak self] _ in self?.updateSend() }
        askEditor.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(askTapped)))
        addSubview(askEditor)

        sendButton.setImage(UIImage(systemName: "arrow.up"), for: .normal)
        sendButton.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 12, weight: .bold), forImageIn: .normal)
        sendButton.accessibilityIdentifier = "ai:send"
        sendButton.accessibilityLabel = "Ask"
        sendButton.addAction(UIAction { [weak self] _ in self?.submitAsk() }, for: .touchUpInside)
        addSubview(sendButton)
        updateSend()
    }

    private func buildCard() {
        card.backgroundColor = Glass.surfaceTile
        card.layer.cornerRadius = 16
        card.layer.cornerCurve = .continuous
        addSubview(card)

        textView.isEditable = false
        textView.isSelectable = false
        textView.backgroundColor = .clear
        textView.font = .systemFont(ofSize: 17)
        textView.textColor = Glass.textPrimary
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 9, bottom: 12, right: 9)
        textView.showsVerticalScrollIndicator = false
        textView.accessibilityIdentifier = "ai:text"
        textView.noEdgeEffects()
        card.addSubview(textView)

        statusLabel.font = .systemFont(ofSize: 15, weight: .medium)
        statusLabel.textColor = Glass.textSecondary
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.accessibilityIdentifier = "ai:status"
        card.addSubview(statusLabel)

        list.accessibilityIdentifier = "ai:list"
        list.onSelect = { [weak self] i in self?.rowTapped(i) }
        list.onRemove = { [weak self] i in self?.rowRemoved(i) }
        addSubview(list)

        retryButton.setImage(UIImage(systemName: "arrow.clockwise",
                                     withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)),
                             for: .normal)
        retryButton.accessibilityLabel = "Try again"
        retryButton.accessibilityIdentifier = "ai:retry"
        retryButton.addAction(UIAction { [weak self] _ in self?.retry() }, for: .touchUpInside)

        copyButton.setTitle("Copy", for: .normal)
        copyButton.accessibilityIdentifier = "ai:copy"
        copyButton.addAction(UIAction { [weak self] _ in
            guard let self, let text = self.actText else { return }
            Haptics.layer()
            self.delegate?.aiBarCopy(text)
        }, for: .touchUpInside)

        insertButton.accessibilityIdentifier = "ai:insert"
        insertButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            if self.phase == .draft { return self.tryDraft() }
            guard let text = self.actText else { return }
            self.delegate?.aiBarInsert(text)
        }, for: .touchUpInside)

        replaceButton.accessibilityIdentifier = "ai:replace"
        replaceButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            if self.phase == .draft || self.tryingDraft { return self.saveDraft() }
            guard let text = self.actText else { return }
            self.delegate?.aiBarReplace(source: self.source, with: text)
        }, for: .touchUpInside)

        for b in [retryButton, copyButton, insertButton, replaceButton] {
            b.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
            b.layer.cornerRadius = 20
            b.layer.cornerCurve = .continuous
            addSubview(b)
        }
    }

    /// One button lime (the thing to tap), the rest quiet on the sheet.
    private func style(_ b: UIButton, primary: Bool) {
        if primary {
            b.backgroundColor = Glass.accentPrimary
            b.setTitleColor(Glass.accentInk, for: .normal)
            b.tintColor = Glass.accentInk
            b.layer.borderWidth = 0
        } else {
            b.backgroundColor = Glass.surfaceTile
            b.setTitleColor(Glass.textPrimary, for: .normal)
            b.tintColor = Glass.textPrimary
            b.layer.borderWidth = Glass.hairlineWidth
            b.layer.borderColor = Glass.strokeHairline.cgColor
        }
    }

    /// The text the buttons act on: the answer, the picked version, or the
    /// picked result.
    private var actText: String? {
        switch phase {
        case .result: return answer?.text
        case .versions: return options.indices.contains(list.selected) ? options[list.selected].text : nil
        case .cards: return cardTexts.indices.contains(list.selected) ? cardTexts[list.selected] : nil
        default: return nil
        }
    }

    // MARK: Opening

    /// Called once when the bar opens. `before` is the text before the
    /// cursor (AIRKEY's own copy, which reaches past the sentence iOS shows).
    /// `hasCopy`: something was just copied (its text isn't read yet).
    /// `run`: an action to start at once (the strip's suggestion was tapped).
    func present(before: String, hasCopy: Bool = false, hasFullAccess: Bool, run action: String? = nil) {
        source = before
        guard hasFullAccess else { return show(.locked) }
        let empty = trimmedSource.isEmpty
        onCopy = empty && hasCopy
        liveTarget = Self.liveLanguage()
        if !empty, let action, let a = Action(rawValue: action), [.rewrite, .ask, .write, .reply].contains(a) {
            return run(Request(action: a, text: trimmedSource))
        }
        if empty && !hasCopy {
            // Nothing to work on: ask. The tiles are one tap away.
            hasTiles = false
            startPrompt(.ask)
        } else {
            show(.actions)
        }
    }

    // MARK: Prompting

    private func startPrompt(_ p: Prompt) {
        prompt = p
        askEditor.clear()
        switch p {
        case .ask: askEditor.placeholder = subjectText == nil ? "Ask anything" : (onCopy ? "Ask about what you copied" : "Ask about your text")
        case .search: askEditor.placeholder = "Search the web"
        case .build: askEditor.placeholder = "What should it do?"
        }
        sendButton.accessibilityLabel = p == .search ? "Search" : p == .build ? "Build" : "Ask"
        show(.prompting)
        askTapped()
    }

    @objc private func askTapped() {
        guard phase == .prompting else { return }
        askEditor.isActive = true
        delegate?.aiBarAskActivated(askEditor)
    }

    private func leavePrompt() {
        askEditor.isActive = false
        delegate?.aiBarAskActivated(nil)
    }

    /// The send arrow and return both ask.
    func submitAsk() {
        let q = askEditor.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard phase == .prompting, !q.isEmpty else { return }
        Haptics.layer()
        switch prompt {
        case .ask:
            // About your text, or about what you copied, when there is one.
            guard let subject = resolveSubject(allowEmpty: true) else { return }
            leavePrompt()
            run(Request(action: .ask, text: q, context: subject.isEmpty ? nil : subject, copied: onCopy))
        case .search:
            leavePrompt()
            run(Request(action: .search, text: q))
        case .build:
            leavePrompt()
            run(Request(action: .build, text: q))
        }
    }

    private func updateSend() {
        let ready = !askEditor.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        sendButton.backgroundColor = ready ? Glass.accentPrimary : Glass.fillField
        sendButton.tintColor = ready ? Glass.accentInk : Glass.textSecondary
    }

    private func moreTapped() {
        Haptics.layer()
        leavePrompt()
        hasTiles = true
        show(.actions)
    }

    // MARK: Tiles

    private typealias Item = (id: String, title: String, symbol: String, detail: String?, tap: () -> Void)

    private func configureActions() {
        let language = Self.translateTarget(for: onCopy ? "" : source)
        let act: (Action) -> () -> Void = { a in { [weak self] in self?.actionTapped(a) } }
        let ask: Item = ("ask", "Ask", "sparkles", nil, { [weak self] in self?.startPrompt(.ask) })
        let live: Item = ("live", "Live translate", "character.bubble", nil, { [weak self] in self?.startLive() })
        let find: Item = ("search", "Search", "magnifyingglass", nil, { [weak self] in self?.startPrompt(.search) })
        let mine: Item = ("glyfs", "My glyfs", "square.stack.3d.up", nil, { [weak self] in self?.openGlyfs() })
        var items: [Item]
        if onCopy {
            items = [
                ("summarize", "Summary", "text.alignleft", nil, act(.summarize)),
                ("reply", "Reply", "arrowshape.turn.up.left", nil, act(.reply)),
                ("translate", "Translate", "translate", nil, act(.translate)),
                ask,
                ("check", "Check copied", "checkmark.shield", nil, { [weak self] in self?.delegate?.aiBarCheckCopied() }),
                find, live, mine,
            ]
        } else if trimmedSource.isEmpty {
            items = [ask, find, live, mine]
        } else {
            items = [
                ("rewrite", "Rewrite", "pencil.line", nil, act(.rewrite)),
                ("reply", "Reply", "arrowshape.turn.up.left", nil, act(.reply)),
                ("translate", "Translate", "translate", "To \(language)", act(.translate)),
                ("tone", "Tone", "theatermasks", nil, act(.tone)),
                ask, live, find, mine,
            ]
        }
        tileCount = items.count
        for (tile, item) in zip(tiles, items) {
            tile.compact = items.count > 4
            tile.configure(title: item.title, symbol: item.symbol, detail: items.count > 4 ? nil : item.detail)
            tile.accessibilityIdentifier = "ai:\(item.id)"
            tile.onTap = { Haptics.layer(); item.tap() }
        }
    }

    private func configureTones() {
        tileCount = 4
        for (tile, tone) in zip(tiles, Self.tones) {
            tile.compact = false
            tile.configure(title: tone.label, symbol: nil, detail: nil)
            tile.accessibilityIdentifier = "ai:tone:\(tone.label.lowercased())"
            tile.onTap = { [weak self] in
                guard let self else { return }
                Haptics.layer()
                self.run(Request(action: .tone, text: self.trimmedSource, tone: tone.value, toneLabel: tone.label))
            }
        }
    }

    private func actionTapped(_ action: Action) {
        if action == .tone { return show(.tones) }
        guard let text = resolveSubject() else { return }
        var r = Request(action: action, text: text, copied: onCopy)
        if action == .translate { r.language = Self.translateTarget(for: text) }
        run(r)
    }

    /// What is sent: the text, without the space the cursor sits after.
    private var trimmedSource: String { source.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The text the bar is working on, if it has it in hand.
    private var subjectText: String? {
        if onCopy { return copied }
        return trimmedSource.isEmpty ? nil : trimmedSource
    }

    /// The text to act on: what you typed, or (on a copy) what you copied,
    /// read now. nil when there is nothing, and the bar has said so.
    private func resolveSubject(allowEmpty: Bool = false) -> String? {
        if onCopy {
            if copied == nil {
                copied = delegate?.aiBarReadCopied()?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let c = copied { copied = String(c.prefix(Self.maxSource)) }
            }
            guard let c = copied, !c.isEmpty else {
                copied = nil
                request = nil
                showFailure("AIRKEY couldn't read what you copied.\nSettings › Apps › AIRKEY › Paste from Other Apps › Allow.")
                return nil
            }
            return c
        }
        if trimmedSource.isEmpty && !allowEmpty {
            KeyboardToast.show(in: self, text: "Type something first")
            return nil
        }
        return trimmedSource
    }

    // MARK: Running

    private func run(_ r: Request) {
        task?.cancel()
        request = r
        answer = nil
        options = []
        search = nil
        runID += 1
        let id = runID
        busy = true
        textView.text = r.context ?? r.text
        textView.textColor = Glass.textSecondary
        textView.setContentOffset(.zero, animated: false)
        streamed = ""
        if r.action == .rewrite {
            list.picks = true
            list.set([])
        }
        show(.working)
        switch r.action {
        case .search: runSearch(r, id)
        case .build: runBuild(r, id)
        default: runStream(r, id)
        }
    }

    private var streamed = ""

    private func runStream(_ r: Request, _ id: Int) {
        let client = AIClient()
        let events = r.action == .glyf
            ? client.runGlyf(id: r.glyfID, prompt: r.glyfPrompt, text: r.text, copied: r.copied)
            : client.act(text: r.text, action: r.action.rawValue, tone: r.tone, language: r.language,
                         context: r.context, copied: r.copied)
        task = Task { [weak self] in
            do {
                for try await event in events {
                    guard let bar = self, bar.runID == id else { return }
                    switch event {
                    case .option(let o): bar.addOption(o)
                    case .text(let t): bar.addText(t)
                    case .reset: bar.resetStream()
                    case .done(let d): bar.finish(d)
                    }
                }
                // The stream ended without a result.
                if let bar = self, bar.runID == id, bar.busy { bar.showFailure("The AI didn't answer.") }
            } catch is AIClient.MoneyText {
                guard let bar = self, bar.runID == id else { return }
                // A payment or a crypto call: AIRKEY's own check, never an AI action.
                bar.delegate?.aiBarCheckCopied()
            } catch {
                guard let bar = self, bar.runID == id, !(error is CancellationError) else { return }
                bar.showFailure((error as? LocalizedError)?.errorDescription ?? "The AI didn't answer.")
            }
        }
    }

    /// A rewrite version, the moment it is written.
    private func addOption(_ o: AIClient.Option) {
        options.append(o)
        if phase != .versions {
            list.set([])
            show(.versions)
        }
        if options.count == 1 { Haptics.space() }
        list.append(.init(caption: o.label, text: o.text))
        updateRow()
    }

    /// The next words of the answer.
    private func addText(_ t: String) {
        streamed += t
        textView.text = streamed
        textView.textColor = Glass.textPrimary
        // Keep the newest line in view while it writes.
        let bottom = textView.contentSize.height - textView.bounds.height
        if bottom > 0 { textView.setContentOffset(CGPoint(x: 0, y: bottom), animated: false) }
    }

    /// The AI that was writing stopped: the next one starts over.
    private func resetStream() {
        streamed = ""
        options = []
        list.set([])
        if phase == .versions { show(.working) }
        textView.text = request?.context ?? request?.text
        textView.textColor = Glass.textSecondary
    }

    private func finish(_ d: AIClient.Done) {
        busy = false
        answer = d.result
        if request?.action == .rewrite, let final = d.options, final.count > 1 {
            // What the server kept, in its order; the picked row stays picked.
            if final != options {
                let picked = options.indices.contains(list.selected) ? options[list.selected].id : nil
                options = final
                list.set(final.map { .init(caption: $0.label, text: $0.text) },
                         selected: final.firstIndex { $0.id == picked } ?? 0)
            }
            Haptics.success()
            return show(.versions)
        }
        showAnswer(d.result)
    }

    private func runSearch(_ r: Request, _ id: Int) {
        task = Task { [weak self] in
            do {
                let found = try await AIClient().search(query: r.text)
                guard let self, self.runID == id else { return }
                self.busy = false
                self.search = found
                guard found.answer != nil || !found.cards.isEmpty else { return self.showFailure("Nothing found.") }
                var rows: [AIList.Row] = []
                if let a = found.answer { rows.append(.init(caption: a.source, text: a.value)) }
                rows += found.cards.map { .init(caption: $0.domain, text: $0.title, detail: $0.snippet) }
                self.list.picks = true
                self.list.set(rows)
                Haptics.space()
                self.show(.cards)
            } catch {
                guard let self, self.runID == id, !(error is CancellationError) else { return }
                self.showFailure((error as? LocalizedError)?.errorDescription ?? "Search isn't working right now.")
            }
        }
    }

    /// What Insert puts in for each search row: the answer, or the result's link.
    private var cardTexts: [String] {
        guard let s = search else { return [] }
        return (s.answer.map { [$0.value] } ?? []) + s.cards.map { "\($0.title) \($0.url)" }
    }

    private func retry() {
        Haptics.layer()
        // Nothing ran (the copy couldn't be read): back to the choices.
        guard let request else { return show(.actions) }
        run(request)
    }

    private func showAnswer(_ result: ActResult) {
        answer = result
        Haptics.space()
        let wasStreamed = !streamed.isEmpty
        let settle = { [self] in
            textView.text = result.text
            textView.textColor = Glass.textPrimary
            if !wasStreamed { textView.setContentOffset(.zero, animated: false) }
        }
        if Glass.reduceMotion || wasStreamed {
            settle()
        } else {
            UIView.transition(with: textView, duration: 0.22, options: .transitionCrossDissolve, animations: settle)
        }
        show(.result)
    }

    private func showFailure(_ message: String) {
        busy = false
        Haptics.warning()
        failure = message
        show(.failed)
    }

    private var failure = "The AI didn't answer."

    // MARK: Rows

    private func rowTapped(_ i: Int) {
        Haptics.layer()
        switch phase {
        case .glyfs: glyfTapped(i)
        default: updateRow()
        }
    }

    /// The picked row changed: nothing to redraw but the buttons' target.
    private func updateRow() { setNeedsLayout() }

    // MARK: My glyfs

    /// What each row of the glyfs list is: Build your own first, then mine, then the ready-made ones.
    private var glyfRows: [AIClient.Glyf?] {
        guard let g = glyfList else { return [nil] }
        return [nil] + g.glyfs + g.starters.filter { s in !g.glyfs.contains { $0.name.lowercased() == s.name.lowercased() } }
    }

    private func openGlyfs() {
        list.picks = false
        renderGlyfs()
        show(.glyfs)
        runID += 1
        let id = runID
        busy = true
        startProgress()
        task = Task { [weak self] in
            let loaded = try? await AIClient().glyfs()
            guard let self, self.runID == id else { return }
            self.busy = false
            self.stopProgress()
            guard let loaded else {
                if self.glyfList == nil { self.showFailure("Can't reach the AIRKEY server.") }
                return
            }
            self.glyfList = loaded
            if self.phase == .glyfs { self.renderGlyfs() }
        }
    }

    private func renderGlyfs() {
        let mine = Set((glyfList?.glyfs ?? []).map(\.id))
        list.set(glyfRows.map { g in
            guard let g else {
                return .init(text: "Build your own", detail: "Say what it should do. The AI writes it.", symbol: "plus")
            }
            return .init(caption: mine.contains(g.id) ? "Mine" : "Ready-made", text: g.name, detail: g.prompt,
                         removable: mine.contains(g.id))
        })
    }

    private func glyfTapped(_ i: Int) {
        let rows = glyfRows
        guard rows.indices.contains(i) else { return }
        guard let g = rows[i] else { return startPrompt(.build) }
        guard let text = resolveSubject() else { return }
        tryingDraft = false
        run(Request(action: .glyf, text: text, copied: onCopy, glyfID: g.id, glyfName: g.name))
    }

    private func rowRemoved(_ i: Int) {
        let rows = glyfRows
        guard phase == .glyfs, rows.indices.contains(i), let g = rows[i] else { return }
        Haptics.layer()
        glyfList = glyfList.map { .init(glyfs: $0.glyfs.filter { $0.id != g.id }, starters: $0.starters) }
        renderGlyfs()
        Task { try? await AIClient().removeGlyf(id: g.id) }
    }

    // MARK: Build your own

    /// A draft's try-out is on screen: its result offers Save.
    private var tryingDraft = false

    private func runBuild(_ r: Request, _ id: Int) {
        task = Task { [weak self] in
            do {
                let built = try await AIClient().buildGlyf(description: r.text)
                guard let self, self.runID == id else { return }
                self.busy = false
                self.draft = built
                self.answer = ActResult(text: built.prompt, provider: built.provider, model: "", signature: built.signature)
                Haptics.space()
                self.textView.attributedText = Self.draftText(built)
                self.textView.setContentOffset(.zero, animated: false)
                self.show(.draft)
            } catch {
                guard let self, self.runID == id, !(error is CancellationError) else { return }
                self.showFailure((error as? LocalizedError)?.errorDescription ?? "Couldn't make that glyf.")
            }
        }
    }

    private static func draftText(_ d: AIClient.Built) -> NSAttributedString {
        let out = NSMutableAttributedString(string: d.name + "\n", attributes: [
            .font: UIFont.systemFont(ofSize: 18, weight: .semibold), .foregroundColor: Glass.textPrimary,
        ])
        out.append(NSAttributedString(string: d.prompt, attributes: [
            .font: UIFont.systemFont(ofSize: 15), .foregroundColor: Glass.textSecondary,
        ]))
        return out
    }

    /// Run the draft on the text, before saving it.
    private func tryDraft() {
        guard let d = draft, let text = resolveSubject() else { return }
        Haptics.layer()
        tryingDraft = true
        run(Request(action: .glyf, text: text, copied: onCopy, glyfPrompt: d.prompt, glyfName: d.name))
    }

    private func saveDraft() {
        guard let d = draft else { return }
        Haptics.layer()
        replaceButton.isEnabled = false
        Task { [weak self] in
            let saved = try? await AIClient().saveGlyf(name: d.name, prompt: d.prompt)
            guard let self else { return }
            self.replaceButton.isEnabled = true
            guard saved != nil else { return KeyboardToast.show(in: self, text: "Couldn't save") }
            Haptics.success()
            self.draft = nil
            self.tryingDraft = false
            self.openGlyfs()
            KeyboardToast.show(in: self, text: "Saved")
        }
    }

    // MARK: Live translate

    private func startLive() {
        liveSource = ""
        liveTranslation = ""
        liveSwapped = ""
        liveProvider = nil
        show(.live)
        renderLive()
        draftChanged(source)
    }

    private func stopLive() {
        liveWork?.cancel()
        liveWork = nil
        liveTask?.cancel()
        liveTask = nil
    }

    /// What of a draft gets translated: all of it up to 280 characters, else
    /// its end from the start of a sentence (or at least of a word), so no
    /// word is cut in half and the tap swaps only what was translated.
    static func window(of draft: String) -> String {
        guard draft.count > 280 else { return draft }
        let tail = String(draft.suffix(280))
        if let r = tail.range(of: #"[.!?\n]\s+"#, options: .regularExpression), r.upperBound < tail.endIndex {
            return String(tail[r.upperBound...])
        }
        if let space = tail.firstIndex(of: " ") { return String(tail[tail.index(after: space)...]) }
        return tail
    }

    /// The keyboard says what is before the cursor each time typing settles.
    /// Only live translate listens.
    func draftChanged(_ draft: String) {
        guard phase == .live else { return }
        source = draft
        let window = Self.window(of: draft)
        let text = window.trimmingCharacters(in: .whitespacesAndNewlines)
        liveWindow = window
        if text.isEmpty {
            stopLive()
            liveSource = ""
            liveTranslation = ""
            liveSwapped = ""
            return renderLive()
        }
        guard text != liveSource, liveSwapped.isEmpty || !text.hasSuffix(liveSwapped) else { return }
        liveSwapped = ""
        liveSource = text
        // The draft moved on: the old translation dims until the new one lands.
        if liveTranslation.isEmpty { renderLive() }
        liveLabel.alpha = 0.45
        liveWork?.cancel()
        let target = liveTarget
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.liveTask?.cancel()
            self.startProgress()
            self.liveTask = Task { [weak self] in
                let result = try? await AIClient().translate(text: text, target: target)
                guard let self, self.phase == .live, self.liveSource == text, self.liveTarget == target else { return }
                self.stopProgress()
                guard let result else {
                    self.liveTranslation = ""
                    self.liveLabel.alpha = 1
                    self.liveLabel.text = "Couldn't translate"
                    self.liveLabel.textColor = Glass.textSecondary
                    return
                }
                self.liveTranslation = result.translation
                self.liveProvider = (result.provider == "near-ai-cloud" ? "NEAR AI" : result.provider == "openai" ? "OpenAI" : result.provider,
                                     result.signature == "verified")
                self.renderLive()
            }
        }
        liveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private func renderLive() {
        liveLabel.alpha = 1
        if liveTranslation.isEmpty {
            liveLabel.text = liveSource.isEmpty ? "Type to translate" : "…"
            liveLabel.textColor = Glass.textSecondary
        } else {
            liveLabel.text = liveTranslation
            liveLabel.textColor = Glass.textPrimary
        }
        directionButton.setTitle(liveTarget, for: .normal)
        providerLabel.attributedText = liveTranslation.isEmpty ? nil : liveProvider.map { Self.providerLine($0.name, verified: $0.verified, size: 11) }
        providerLabel.accessibilityLabel = liveProvider.map { "Translated by \($0.name)" }
        setNeedsLayout()
    }

    /// A tap on the translation swaps it in for what was typed.
    @objc private func liveTapped() {
        guard phase == .live, !liveTranslation.isEmpty else { return }
        let put = liveTranslation
        // The spaces around the draft stay around the translation.
        let leading = String(liveWindow.prefix(while: { $0.isWhitespace }))
        let trailing = String(liveWindow.reversed().prefix(while: { $0.isWhitespace }).reversed())
        liveSwapped = put.trimmingCharacters(in: .whitespacesAndNewlines)
        liveSource = ""
        liveTranslation = ""
        Haptics.success()
        delegate?.aiBarSwap(source: liveWindow, with: leading + put + trailing)
        liveLabel.text = "Replaced"
        liveLabel.textColor = Glass.chipAccent
        providerLabel.attributedText = nil
        setNeedsLayout()
    }

    private static let liveLanguages = ["Spanish", "Hindi", "French", "German", "Portuguese", "Japanese", "Chinese", "Arabic", "English"]

    /// Where live translate goes: the language last picked, else the phone's
    /// second language, else Spanish.
    static func liveLanguage() -> String {
        UserDefaults.standard.string(forKey: savedTargetKey) ?? translateTarget(for: "")
    }

    // MARK: Translate's direction

    /// Where a translation goes: English for anything that isn't, and the
    /// person's other language (the last one they picked, else their phone's
    /// second language) for English.
    static func translateTarget(for text: String) -> String {
        if sourceLanguage(of: text) != "English" { return "English" }
        if let saved = UserDefaults.standard.string(forKey: savedTargetKey), saved != "English" { return saved }
        let english = Locale(identifier: "en_US")
        for id in Locale.preferredLanguages {
            guard let code = Locale(identifier: id).language.languageCode?.identifier, code != "en",
                  let name = english.localizedString(forLanguageCode: code) else { continue }
            return name
        }
        return "Spanish"
    }

    /// The language the text is written in, by its English name; English
    /// when it can't tell (a word or two).
    static func sourceLanguage(of text: String) -> String {
        guard let lang = NLLanguageRecognizer.dominantLanguage(for: text), lang != .undetermined,
              let name = Locale(identifier: "en_US").localizedString(forLanguageCode: lang.rawValue)
        else { return "English" }
        return name
    }

    private static let savedTargetKey = "ai.translateTo"
    private static let commonLanguages = ["English", "Spanish", "Hindi", "French", "German",
                                          "Portuguese", "Japanese", "Chinese", "Arabic"]

    /// A tap on the language translates into the next one instead.
    private func cycleLanguage() {
        if phase == .live {
            let all = Self.liveLanguages
            liveTarget = all[((all.firstIndex(of: liveTarget) ?? -1) + 1) % all.count]
            UserDefaults.standard.set(liveTarget, forKey: Self.savedTargetKey)
            Haptics.layer()
            liveSource = ""
            liveTranslation = ""
            renderLive()
            return draftChanged(source)
        }
        guard var r = request, r.action == .translate, phase == .result || phase == .failed else { return }
        let current = r.language ?? "English"
        // Never into the language it is already in.
        var seen: Set<String> = [Self.sourceLanguage(of: r.text)]
        let options = ([Self.translateTarget(for: r.text)] + Self.commonLanguages).filter { seen.insert($0).inserted }
        guard !options.isEmpty else { return }
        let next = options[((options.firstIndex(of: current) ?? -1) + 1) % options.count]
        r.language = next
        if next != "English" { UserDefaults.standard.set(next, forKey: Self.savedTargetKey) }
        Haptics.layer()
        run(r)
    }

    // MARK: Phases

    /// Where the header's button goes back to; nil means it closes the bar.
    private var backTarget: Phase? {
        switch phase {
        case .tones: return .actions
        case .glyfs: return .actions
        case .draft: return .glyfs
        case .prompting: return prompt == .build ? .glyfs : (hasTiles ? .actions : nil)
        case .live: return nil
        case .working, .versions, .result, .cards, .failed:
            if tryingDraft, draft != nil { return .draft }
            if request?.action == .glyf || request?.action == .build { return .glyfs }
            return hasTiles ? .actions : nil
        case .actions, .locked: return nil
        }
    }

    private func closeTapped() {
        guard let back = backTarget else {
            delegate?.aiBarClosed()
            return
        }
        Haptics.layer()
        cancel()
        if phase == .prompting { leavePrompt() }
        switch back {
        case .glyfs: tryingDraft = false; openGlyfs()
        case .draft:
            tryingDraft = false
            if let d = draft { textView.attributedText = Self.draftText(d) }
            show(.draft)
        default: show(back)
        }
    }

    /// What fades in when a phase shows it.
    private var bodyViews: [UIView] { [card, list, retryButton, copyButton, insertButton, replaceButton] + tiles }

    private func show(_ p: Phase) {
        let wasStrip = isStrip
        let old = phase
        let wasHidden = bodyViews.map(\.isHidden)
        if old == .live && p != .live { stopLive() }
        phase = p
        let picking = p == .actions || p == .tones
        let carded = p == .working || p == .result || p == .failed || p == .locked || p == .draft
        let listed = p == .versions || p == .cards || p == .glyfs

        if p == .actions { configureActions() }
        if p == .tones { configureTones() }

        // Header
        let back = backTarget != nil
        closeButton.setImage(UIImage(systemName: back ? "chevron.left" : "xmark"), for: .normal)
        closeButton.accessibilityLabel = back ? "Back" : "Close"
        moreButton.isHidden = !(p == .prompting && prompt == .ask && !hasTiles)
        titleLabel.text = title(for: p)
        let quoting = p == .actions && !onCopy && !trimmedSource.isEmpty
        titleLabel.font = quoting ? .systemFont(ofSize: 14) : .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = quoting ? Glass.textSecondary : Glass.textPrimary
        titleLabel.lineBreakMode = quoting ? .byTruncatingHead : .byTruncatingTail
        titleLabel.isHidden = isStrip
        let translating = request?.action == .translate && (p == .working || p == .result || p == .failed)
        directionButton.isHidden = !(translating || p == .live)
        if translating { directionButton.setTitle(request?.language ?? "English", for: .normal) }
        if p == .live { directionButton.setTitle(liveTarget, for: .normal) }
        directionButton.isEnabled = p != .working
        directionButton.alpha = p == .working ? 0.5 : 1
        liveLabel.isHidden = p != .live
        let answered = p == .result || p == .draft || (p == .versions && !busy) || p == .cards
        providerLabel.attributedText = answered ? providerText() : nil
        providerLabel.accessibilityLabel = answered ? providerSpoken() : nil
        if busy && !isStrip { startProgress() } else { stopProgress() }

        // Prompting
        askEditor.isHidden = p != .prompting
        sendButton.isHidden = p != .prompting

        // Body
        for (i, tile) in tiles.enumerated() { tile.isHidden = !picking || i >= tileCount }
        card.isHidden = !carded
        list.isHidden = !listed
        textView.isHidden = !(p == .working || p == .result || p == .draft)
        statusLabel.isHidden = !(p == .failed || p == .locked)
        if p == .locked {
            statusLabel.attributedText = Self.lockedText()
        } else if p == .failed {
            statusLabel.attributedText = NSAttributedString(string: failure, attributes: [
                .font: UIFont.systemFont(ofSize: 15, weight: .medium),
                .foregroundColor: Glass.textSecondary,
            ])
        }

        // The row under the card: ↻ Copy Insert Replace. Replace only swaps
        // what you typed; an answer to a question, a search result, or
        // anything made from a copy only goes in. A draft glyf: ↻ Try Save.
        let acting = p == .result || (p == .versions && !options.isEmpty) || p == .cards
        let saving = p == .draft || (p == .result && tryingDraft)
        let canReplace = acting && p != .cards && !onCopy && !trimmedSource.isEmpty
            && request?.action != .ask && !tryingDraft
        retryButton.isHidden = !(acting || p == .failed || p == .draft) || (p == .versions && busy)
        copyButton.isHidden = !acting || tryingDraft
        insertButton.isHidden = !(acting || p == .draft)
        replaceButton.isHidden = !(canReplace || saving)
        insertButton.setTitle(p == .draft ? "Try" : "Insert", for: .normal)
        replaceButton.setTitle(saving ? "Save" : "Replace", for: .normal)
        style(retryButton, primary: p == .failed)
        style(copyButton, primary: false)
        style(insertButton, primary: replaceButton.isHidden && p != .draft)
        style(replaceButton, primary: true)
        retryButton.setTitle(p == .failed ? "  Try again" : nil, for: .normal)

        setNeedsLayout()
        if wasStrip != isStrip { delegate?.aiBarLayoutChanged() }
        // What just came into view rises in on the surfaces' one soft
        // spring; what stays (the card under a new answer) stays put. The
        // tiles turning from actions into tones count as new.
        guard old != p, !Glass.reduceMotion else { return }
        layoutIfNeeded()
        let fresh = zip(bodyViews, wasHidden).filter { v, hidden in
            !v.isHidden && (hidden || (picking && v is AITile))
        }.map(\.0)
        guard !fresh.isEmpty else { return }
        for v in fresh {
            v.alpha = 0
            v.transform = CGAffineTransform(translationX: 0, y: 6)
        }
        UIViewPropertyAnimator(duration: 0.3, dampingRatio: 0.9) {
            for v in fresh {
                v.alpha = 1
                v.transform = .identity
            }
        }.startAnimation()
    }

    private func title(for p: Phase) -> String? {
        switch p {
        case .prompting, .live: return nil
        case .actions:
            if onCopy { return "Copied text" }
            if trimmedSource.isEmpty { return "AI" }
            let flat = trimmedSource.split(whereSeparator: \.isNewline).joined(separator: " ")
            return "“\(flat)”"
        case .tones: return "Tone"
        case .locked: return "AI"
        case .glyfs: return "My glyfs"
        case .draft: return "New glyf"
        case .cards: return request?.text
        case .working, .versions, .result, .failed:
            guard let r = request else { return "AI" }
            switch r.action {
            case .rewrite: return "Rewrite"
            case .reply: return "Reply"
            case .translate: return "Translate"
            case .tone: return r.toneLabel ?? "Tone"
            case .ask: return p == .result ? "Answer" : "Ask"
            case .summarize: return "Summary"
            case .write: return "Write"
            case .glyf: return r.glyfName ?? "Glyf"
            case .search: return "Search"
            case .build: return "New glyf"
            }
        }
    }

    /// "NEAR AI" or "OpenAI", the one that answered; a seal when NEAR AI's
    /// signature over this very answer checked out. A search says which
    /// search engine.
    private func providerText() -> NSAttributedString? {
        if phase == .cards {
            guard let s = search else { return nil }
            return Self.providerLine(s.provider == "brave" ? "Brave" : "Google", verified: false, size: 12)
        }
        guard let answer else { return nil }
        return Self.providerLine(answer.providerName, verified: answer.signature == "verified", size: 12)
    }

    private static func providerLine(_ name: String, verified: Bool, size: CGFloat) -> NSAttributedString {
        let out = NSMutableAttributedString()
        if verified,
           let seal = UIImage(systemName: "checkmark.seal.fill",
                              withConfiguration: UIImage.SymbolConfiguration(pointSize: size - 1, weight: .semibold))?
            .withTintColor(Glass.chipAccent, renderingMode: .alwaysOriginal) {
            let a = NSTextAttachment(image: seal)
            a.bounds = CGRect(x: 0, y: -2, width: seal.size.width, height: seal.size.height)
            out.append(NSAttributedString(attachment: a))
            out.append(NSAttributedString(string: " "))
        }
        out.append(NSAttributedString(string: name, attributes: [
            .font: UIFont.systemFont(ofSize: size, weight: .semibold),
            .foregroundColor: Glass.textSecondary,
        ]))
        return out
    }

    private func providerSpoken() -> String? {
        if phase == .cards { return search.map { "Results from \($0.provider == "brave" ? "Brave" : "Google")" } }
        guard let answer else { return nil }
        return "Answered by \(answer.providerName)" + (answer.signature == "verified" ? ", signature verified" : "")
    }

    private static func lockedText() -> NSAttributedString {
        let p = NSMutableParagraphStyle()
        p.alignment = .center
        p.lineSpacing = 3
        let out = NSMutableAttributedString(string: "Turn on Allow Full Access to use AI\n", attributes: [
            .font: UIFont.systemFont(ofSize: 16, weight: .semibold),
            .foregroundColor: Glass.textPrimary,
            .paragraphStyle: p,
        ])
        out.append(NSAttributedString(string: "Settings › General › Keyboard › Keyboards › AIRKEY", attributes: [
            .font: UIFont.systemFont(ofSize: 13),
            .foregroundColor: Glass.textSecondary,
            .paragraphStyle: p,
        ]))
        return out
    }

    // MARK: Progress line

    private func startProgress() {
        progressTrack.isHidden = false
        guard progressBar.animation(forKey: "sweep") == nil else { return }
        guard !Glass.reduceMotion else {
            progressBar.opacity = 0.6
            return
        }
        let width = max(progressTrack.bounds.width, bounds.width)
        let sweep = CABasicAnimation(keyPath: "position.x")
        sweep.fromValue = -width * 0.2
        sweep.toValue = width * 1.2
        sweep.duration = 1.2
        sweep.repeatCount = .infinity
        sweep.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        progressBar.add(sweep, forKey: "sweep")
    }

    private func stopProgress() {
        progressBar.removeAllAnimations()
        progressTrack.isHidden = true
    }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width, h = bounds.height
        // The strip's own measures (Toolbar): the close sits where the brand
        // pill does.
        let strip = Glass.toolbarHeight
        let mid = Glass.stripBand + Glass.stripContent / 2 - Glass.stripLift
        let pillW = (Glass.stripContent * 1.18).rounded()
        let pill = Glass.stripBox(height: (Glass.stripContent * 0.78).rounded(), mid: mid)
        closeButton.frame = CGRect(x: 5, y: pill.y, width: pillW, height: pill.height)

        // Prompting: the field across the rest of the strip, the arrow
        // inside it; More, when it shows, between the close and the field.
        var left = pillW + 11
        if !moreButton.isHidden {
            moreButton.frame = CGRect(x: left, y: pill.y, width: pillW, height: pill.height)
            left += pillW + 6
        }
        let field = CGRect(x: left, y: pill.y, width: max(0, w - left - 6), height: pill.height)
        askEditor.frame = field
        askEditor.layer.cornerRadius = pill.height / 2
        let sendD = pill.height - 6
        sendButton.frame = CGRect(x: field.maxX - sendD - 3, y: field.midY - sendD / 2, width: sendD, height: sendD)
        sendButton.layer.cornerRadius = sendD / 2
        askEditor.trailingInset = sendD + 10

        // Header: title, then the language, then who answered on the right.
        let providerW = min(providerLabel.intrinsicContentSize.width, 110)
        providerLabel.frame = CGRect(x: w - 12 - providerW, y: mid - 10, width: providerW, height: 20)
        let chipH: CGFloat = 28
        let titleX = 5 + pillW + 12
        if phase == .live {
            // Close, the language, the translation, who translated.
            let chipW = min(directionButton.intrinsicContentSize.width, 130)
            directionButton.frame = CGRect(x: pillW + 11, y: mid - chipH / 2, width: chipW, height: chipH)
            directionButton.layer.cornerRadius = chipH / 2
            let x = directionButton.frame.maxX + 10
            let end = providerLabel.attributedText == nil ? w - 12 : providerLabel.frame.minX - 8
            liveLabel.frame = CGRect(x: x, y: 0, width: max(0, end - x), height: strip)
        } else {
            var titleEnd = (providerLabel.attributedText == nil ? w - 14 : providerLabel.frame.minX - 10)
            if !directionButton.isHidden {
                let chipW = min(directionButton.intrinsicContentSize.width, 150)
                titleEnd -= chipW + 8
                directionButton.frame = CGRect(x: 0, y: mid - chipH / 2, width: chipW, height: chipH)
                directionButton.layer.cornerRadius = chipH / 2
            }
            let titleW = min(titleLabel.intrinsicContentSize.width, max(0, titleEnd - titleX))
            titleLabel.frame = CGRect(x: titleX, y: mid - 11, width: titleW, height: 22)
            directionButton.frame.origin.x = titleLabel.frame.maxX + 8
        }

        progressTrack.frame = CGRect(x: 0, y: strip - 2, width: w, height: 2)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        progressBar.frame = CGRect(x: 0, y: 0, width: w * 0.4, height: 2)
        progressBar.position = CGPoint(x: w / 2, y: 1)
        CATransaction.commit()

        // Body, in the keys' place.
        let side: CGFloat = 8, gap: CGFloat = 8
        let top = strip + 4, bottom = h - 8
        let columns: CGFloat = tileCount > 4 ? 4 : 2
        let tileW = (w - side * 2 - gap * (columns - 1)) / columns
        let tileH = max(0, (bottom - top - gap) / 2)
        for (i, tile) in tiles.enumerated() {
            tile.frame = CGRect(x: side + CGFloat(i % Int(columns)) * (tileW + gap),
                                y: top + CGFloat(i / Int(columns)) * (tileH + gap), width: tileW, height: tileH)
        }

        let rowH: CGFloat = 40
        let rowY = bottom - rowH
        let showsRow = !retryButton.isHidden || !insertButton.isHidden
        let bodyRect = CGRect(x: side, y: top, width: w - side * 2,
                              height: max(0, (showsRow ? rowY - gap : bottom) - top))
        card.frame = bodyRect
        list.frame = bodyRect
        textView.frame = card.bounds
        statusLabel.frame = card.bounds.insetBy(dx: 20, dy: 12)

        if phase == .failed {
            let tryW: CGFloat = 150
            retryButton.frame = CGRect(x: (w - tryW) / 2, y: rowY, width: tryW, height: rowH)
        } else {
            retryButton.frame = CGRect(x: side, y: rowY, width: rowH + 4, height: rowH)
            let x0 = retryButton.frame.maxX + gap
            let shown = [copyButton, insertButton, replaceButton].filter { !$0.isHidden }
            let rest = w - side - x0
            if shown.count == 3 {
                // The primary, Replace, a little wider and nearest the thumb.
                let each = (rest - gap * 2) / 3.3
                copyButton.frame = CGRect(x: x0, y: rowY, width: each, height: rowH)
                insertButton.frame = CGRect(x: x0 + each + gap, y: rowY, width: each, height: rowH)
                replaceButton.frame = CGRect(x: insertButton.frame.maxX + gap, y: rowY,
                                             width: w - side - insertButton.frame.maxX - gap, height: rowH)
            } else if !shown.isEmpty {
                let each = (rest - gap * CGFloat(shown.count - 1)) / CGFloat(shown.count)
                for (i, b) in shown.enumerated() {
                    b.frame = CGRect(x: x0 + CGFloat(i) * (each + gap), y: rowY, width: each, height: rowH)
                }
            }
        }
    }
}

/// One choice in the bar: an icon over its name, the way Control Center's
/// tiles read. Presses sink a little; the haptic does the rest.
final class AITile: UIControl {
    private let icon = UIImageView()
    private let title = UILabel()
    private let detail = UILabel()
    var onTap: (() -> Void)?
    /// Eight to a panel instead of four: a smaller name, on two lines if it needs them.
    var compact = false

    init() {
        super.init(frame: .zero)
        backgroundColor = Glass.surfaceTile
        layer.cornerRadius = 16
        layer.cornerCurve = .continuous
        icon.tintColor = Glass.chipAccent
        icon.contentMode = .left
        icon.preferredSymbolConfiguration = .init(pointSize: 19, weight: .medium)
        title.font = .systemFont(ofSize: 16, weight: .semibold)
        title.textColor = Glass.textPrimary
        detail.font = .systemFont(ofSize: 13)
        detail.textColor = Glass.textSecondary
        for v in [icon, title, detail] as [UIView] {
            v.isUserInteractionEnabled = false
            addSubview(v)
        }
        isAccessibilityElement = true
        accessibilityTraits = .button
        addAction(UIAction { [weak self] _ in self?.onTap?() }, for: .touchUpInside)
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(title text: String, symbol: String?, detail sub: String?) {
        title.text = text
        title.font = .systemFont(ofSize: compact ? 13.5 : 16, weight: .semibold)
        title.numberOfLines = compact ? 2 : 1
        icon.image = symbol.flatMap { UIImage(systemName: $0) }
        icon.preferredSymbolConfiguration = .init(pointSize: compact ? 17 : 19, weight: .medium)
        icon.isHidden = symbol == nil
        detail.text = sub
        detail.isHidden = sub == nil
        accessibilityLabel = [text, sub].compactMap { $0 }.joined(separator: ", ")
        setNeedsLayout()
    }

    override var isHighlighted: Bool {
        didSet {
            guard oldValue != isHighlighted else { return }
            let down = isHighlighted
            UIViewPropertyAnimator(duration: down ? 0.12 : 0.3, dampingRatio: down ? 1 : 0.7) { [self] in
                transform = down && !Glass.reduceMotion ? CGAffineTransform(scaleX: Glass.pressScale, y: Glass.pressScale) : .identity
                backgroundColor = down ? Glass.surfaceTile.withAlphaComponent(0.6) : Glass.surfaceTile
            }.startAnimation()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width, h = bounds.height
        let pad: CGFloat = compact ? 10 : 14
        if icon.isHidden {
            // A tone: just its name, in the middle.
            title.textAlignment = .center
            title.frame = CGRect(x: pad, y: (h - 22) / 2, width: w - pad * 2, height: 22)
        } else if compact {
            title.textAlignment = .natural
            icon.frame = CGRect(x: pad, y: pad, width: 26, height: 22)
            let th = ceil(title.sizeThatFits(CGSize(width: w - pad * 2, height: .greatestFiniteMagnitude)).height)
            title.frame = CGRect(x: pad, y: h - pad - th, width: w - pad * 2, height: th)
        } else {
            title.textAlignment = .natural
            icon.frame = CGRect(x: pad, y: pad - 1, width: 28, height: 24)
            let titleY = detail.isHidden ? h - pad - 21 : h - pad - 38
            title.frame = CGRect(x: pad, y: titleY, width: w - pad * 2, height: 21)
            detail.frame = CGRect(x: pad, y: h - pad - 17, width: w - pad * 2, height: 17)
        }
    }
}
