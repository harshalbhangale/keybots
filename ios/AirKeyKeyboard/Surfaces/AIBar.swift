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
}

/// Hold space → AI on what you wrote. Glyf's bar, act panel and tones, in
/// AIRKEY's look: one thing at a time, quiet tiles on the sheet, lime only
/// where it means "this one".
///
///  · actions  — the field has text: Rewrite, Reply, Translate, Tone
///  · tones    — Natural, Professional, Casual, Gen-Z
///  · asking   — the field is empty: one Ask field in the strip, the keys
///               live underneath and typing into it
///  · working  — your text in the card, one thin line moving under the header
///  · result   — the answer in the card, who answered, and ↻ Copy Insert
///               Replace. Nothing goes in until one is tapped.
///  · failed   — what went wrong, and Try again
///  · locked   — no Full Access: how to turn it on
///
/// The answers come from the AIRKEY server (POST /v1/act): NEAR AI Cloud
/// first, OpenAI when NEAR AI isn't set up or doesn't answer.
final class AIBar: UIView {

    weak var delegate: AIBarDelegate?

    enum Action: String { case rewrite, reply, translate, tone, ask }

    struct Request: Equatable {
        var action: Action
        var text: String
        var tone: String?
        var toneLabel: String?
        var language: String?
    }

    private enum Phase { case asking, actions, tones, working, result, failed, locked }
    private var phase: Phase = .actions

    /// Asking happens in the strip, with the keys under it; everything else
    /// covers the keys.
    var isStrip: Bool { phase == .asking }

    /// What the field held before the cursor when the bar opened; empty
    /// when there was nothing to work on.
    private var source = ""
    private var request: Request?
    private var answer: ActResult?
    private var task: Task<Void, Never>?
    private var runID = 0

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
    private let titleLabel = UILabel()
    private let directionButton = UIButton(type: .system)
    private let providerLabel = UILabel()
    private let progressTrack = UIView()
    private let progressBar = CAGradientLayer()

    // Asking
    private let askEditor = InlineEditor(placeholder: "Ask anything", symbol: "sparkles")
    private let sendButton = UIButton(type: .system)

    // Actions and tones: the same four tiles, said differently.
    private let tiles = (0..<4).map { _ in AITile() }

    // Working, result, failed, locked
    private let card = UIView()
    private let textView = UITextView()
    private let statusLabel = UILabel()
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
        if newSuperview == nil { cancel() }
    }

    func cancel() {
        task?.cancel()
        task = nil
        runID += 1
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

        retryButton.setImage(UIImage(systemName: "arrow.clockwise",
                                     withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)),
                             for: .normal)
        retryButton.accessibilityLabel = "Try again"
        retryButton.accessibilityIdentifier = "ai:retry"
        retryButton.addAction(UIAction { [weak self] _ in self?.retry() }, for: .touchUpInside)

        copyButton.setTitle("Copy", for: .normal)
        copyButton.accessibilityIdentifier = "ai:copy"
        copyButton.addAction(UIAction { [weak self] _ in
            guard let self, let text = self.answer?.text else { return }
            Haptics.layer()
            self.delegate?.aiBarCopy(text)
        }, for: .touchUpInside)

        insertButton.setTitle("Insert", for: .normal)
        insertButton.accessibilityIdentifier = "ai:insert"
        insertButton.addAction(UIAction { [weak self] _ in
            guard let self, let text = self.answer?.text else { return }
            self.delegate?.aiBarInsert(text)
        }, for: .touchUpInside)

        replaceButton.setTitle("Replace", for: .normal)
        replaceButton.accessibilityIdentifier = "ai:replace"
        replaceButton.addAction(UIAction { [weak self] _ in
            guard let self, let text = self.answer?.text else { return }
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

    // MARK: Opening

    /// Called once when the bar opens. `before` is the text before the
    /// cursor (AIRKEY's own copy, which reaches past the sentence iOS shows).
    func present(before: String, hasFullAccess: Bool) {
        source = before
        guard hasFullAccess else { return show(.locked) }
        if before.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            show(.asking)
            askTapped()
        } else {
            show(.actions)
        }
    }

    // MARK: Asking

    @objc private func askTapped() {
        guard phase == .asking else { return }
        askEditor.isActive = true
        delegate?.aiBarAskActivated(askEditor)
    }

    /// The send arrow and return both ask.
    func submitAsk() {
        let q = askEditor.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard phase == .asking, !q.isEmpty else { return }
        askEditor.isActive = false
        delegate?.aiBarAskActivated(nil)
        Haptics.layer()
        run(Request(action: .ask, text: q))
    }

    private func updateSend() {
        let ready = !askEditor.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        sendButton.backgroundColor = ready ? Glass.accentPrimary : Glass.fillField
        sendButton.tintColor = ready ? Glass.accentInk : Glass.textSecondary
    }

    // MARK: Tiles

    private func configureActions() {
        let language = Self.translateTarget(for: source)
        let items: [(String, String, String?, Action)] = [
            ("Rewrite", "pencil.line", nil, .rewrite),
            ("Reply", "arrowshape.turn.up.left", nil, .reply),
            ("Translate", "translate", "To \(language)", .translate),
            ("Tone", "theatermasks", nil, .tone),
        ]
        for (tile, item) in zip(tiles, items) {
            tile.configure(title: item.0, symbol: item.1, detail: item.2)
            tile.accessibilityIdentifier = "ai:\(item.3.rawValue)"
            tile.onTap = { [weak self] in self?.actionTapped(item.3) }
        }
    }

    private func configureTones() {
        for (tile, tone) in zip(tiles, Self.tones) {
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
        Haptics.layer()
        switch action {
        case .tone:
            show(.tones)
        case .translate:
            run(Request(action: .translate, text: trimmedSource, language: Self.translateTarget(for: source)))
        default:
            run(Request(action: action, text: trimmedSource))
        }
    }

    /// What is sent: the text, without the space the cursor sits after.
    private var trimmedSource: String { source.trimmingCharacters(in: .whitespacesAndNewlines) }

    // MARK: Running

    private func run(_ r: Request) {
        task?.cancel()
        request = r
        answer = nil
        runID += 1
        let id = runID
        textView.text = r.text
        textView.textColor = Glass.textSecondary
        textView.setContentOffset(.zero, animated: false)
        show(.working)
        task = Task { [weak self] in
            do {
                let result = try await API().act(text: r.text, action: r.action.rawValue,
                                                 tone: r.tone, language: r.language)
                guard let self, self.runID == id else { return }
                self.showAnswer(result)
            } catch {
                guard let self, self.runID == id, !(error is CancellationError) else { return }
                self.showFailure((error as? LocalizedError)?.errorDescription ?? "The AI didn't answer.")
            }
        }
    }

    private func retry() {
        guard let request else { return }
        Haptics.layer()
        run(request)
    }

    private func showAnswer(_ result: ActResult) {
        answer = result
        Haptics.space()
        let crossfade = { [self] in
            textView.text = result.text
            textView.textColor = Glass.textPrimary
            textView.setContentOffset(.zero, animated: false)
        }
        if Glass.reduceMotion {
            crossfade()
        } else {
            UIView.transition(with: textView, duration: 0.22, options: .transitionCrossDissolve,
                              animations: crossfade)
        }
        show(.result)
    }

    private func showFailure(_ message: String) {
        Haptics.warning()
        failure = message
        show(.failed)
    }

    private var failure = "The AI didn't answer."

    // MARK: Translate's direction

    /// Where a translation goes: English for anything that isn't, and the
    /// person's other language (the last one they picked, else their phone's
    /// second language) for English.
    static func translateTarget(for text: String) -> String {
        if let lang = NLLanguageRecognizer.dominantLanguage(for: text), lang != .english, lang != .undetermined {
            return "English"
        }
        if let saved = UserDefaults.standard.string(forKey: savedTargetKey), saved != "English" { return saved }
        let english = Locale(identifier: "en_US")
        for id in Locale.preferredLanguages {
            guard let code = Locale(identifier: id).language.languageCode?.identifier, code != "en",
                  let name = english.localizedString(forLanguageCode: code) else { continue }
            return name
        }
        return "Spanish"
    }

    private static let savedTargetKey = "ai.translateTo"
    private static let commonLanguages = ["English", "Spanish", "Hindi", "French", "German",
                                          "Portuguese", "Japanese", "Chinese", "Arabic"]

    /// A tap on the language translates into the next one instead.
    private func cycleLanguage() {
        guard var r = request, r.action == .translate, phase == .result || phase == .failed else { return }
        let current = r.language ?? "English"
        var seen = Set<String>()
        let options = ([Self.translateTarget(for: source)] + Self.commonLanguages).filter { seen.insert($0).inserted }
        let next = options[((options.firstIndex(of: current) ?? -1) + 1) % options.count]
        r.language = next
        if next != "English" { UserDefaults.standard.set(next, forKey: Self.savedTargetKey) }
        Haptics.layer()
        run(r)
    }

    // MARK: Phases

    private func closeTapped() {
        if phase == .tones {
            Haptics.layer()
            return show(.actions)
        }
        delegate?.aiBarClosed()
    }

    /// What fades in when a phase shows it.
    private var bodyViews: [UIView] { [card, retryButton, copyButton, insertButton, replaceButton] + tiles }

    private func show(_ p: Phase) {
        let wasStrip = isStrip
        let old = phase
        let wasHidden = bodyViews.map(\.isHidden)
        phase = p
        let picking = p == .actions || p == .tones
        let carded = p == .working || p == .result || p == .failed || p == .locked

        if p == .actions { configureActions() }
        if p == .tones { configureTones() }

        // Header
        let back = p == .tones
        closeButton.setImage(UIImage(systemName: back ? "chevron.left" : "xmark"), for: .normal)
        closeButton.accessibilityLabel = back ? "Back" : "Close"
        titleLabel.text = title(for: p)
        titleLabel.font = p == .actions ? .systemFont(ofSize: 14) : .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = p == .actions ? Glass.textSecondary : Glass.textPrimary
        titleLabel.lineBreakMode = p == .actions ? .byTruncatingHead : .byTruncatingTail
        titleLabel.isHidden = p == .asking
        let translating = request?.action == .translate && (p == .working || p == .result || p == .failed)
        directionButton.isHidden = !translating
        if translating { directionButton.setTitle(request?.language ?? "English", for: .normal) }
        directionButton.isEnabled = p != .working
        directionButton.alpha = p == .working ? 0.5 : 1
        providerLabel.attributedText = p == .result ? providerText() : nil
        providerLabel.accessibilityLabel = p == .result ? providerSpoken() : nil
        if p == .working { startProgress() } else { stopProgress() }

        // Asking
        askEditor.isHidden = p != .asking
        sendButton.isHidden = p != .asking

        // Body
        for tile in tiles { tile.isHidden = !picking }
        card.isHidden = !carded
        textView.isHidden = !(p == .working || p == .result)
        statusLabel.isHidden = !(p == .failed || p == .locked)
        if p == .locked {
            statusLabel.attributedText = Self.lockedText()
        } else if p == .failed {
            statusLabel.attributedText = NSAttributedString(string: failure, attributes: [
                .font: UIFont.systemFont(ofSize: 15, weight: .medium),
                .foregroundColor: Glass.textSecondary,
            ])
        }

        // Actions: ↻ Copy Insert Replace. Replace only swaps what the field
        // held; an answer to a question only goes in.
        let canReplace = p == .result && !trimmedSource.isEmpty && request?.action != .ask
        retryButton.isHidden = !(p == .result || p == .failed)
        copyButton.isHidden = p != .result
        insertButton.isHidden = p != .result
        replaceButton.isHidden = !canReplace
        style(retryButton, primary: p == .failed)
        style(copyButton, primary: false)
        style(insertButton, primary: !canReplace)
        style(replaceButton, primary: true)
        if p == .failed {
            retryButton.setTitle("  Try again", for: .normal)
        } else {
            retryButton.setTitle(nil, for: .normal)
        }

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
        case .asking: return nil
        case .actions:
            let flat = trimmedSource.split(whereSeparator: \.isNewline).joined(separator: " ")
            return "“\(flat)”"
        case .tones: return "Tone"
        case .locked: return "AI"
        case .working, .result, .failed:
            guard let r = request else { return "AI" }
            switch r.action {
            case .rewrite: return "Rewrite"
            case .reply: return "Reply"
            case .translate: return "Translate"
            case .tone: return r.toneLabel ?? "Tone"
            case .ask: return p == .result ? "Answer" : "Ask"
            }
        }
    }

    /// "NEAR AI" or "OpenAI", the one that answered; a seal when NEAR AI's
    /// signature over this very answer checked out.
    private func providerText() -> NSAttributedString? {
        guard let answer else { return nil }
        let out = NSMutableAttributedString()
        if answer.signature == "verified",
           let seal = UIImage(systemName: "checkmark.seal.fill",
                              withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold))?
            .withTintColor(Glass.chipAccent, renderingMode: .alwaysOriginal) {
            let a = NSTextAttachment(image: seal)
            a.bounds = CGRect(x: 0, y: -2, width: seal.size.width, height: seal.size.height)
            out.append(NSAttributedString(attachment: a))
            out.append(NSAttributedString(string: " "))
        }
        out.append(NSAttributedString(string: answer.providerName, attributes: [
            .font: UIFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: Glass.textSecondary,
        ]))
        return out
    }

    private func providerSpoken() -> String? {
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
        progressBar.removeAllAnimations()
        guard !Glass.reduceMotion else {
            progressBar.opacity = 0.6
            return
        }
        let sweep = CABasicAnimation(keyPath: "position.x")
        sweep.fromValue = -progressTrack.bounds.width * 0.2
        sweep.toValue = progressTrack.bounds.width * 1.2
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

        // Asking: the field across the rest of the strip, the arrow inside it.
        let left = pillW + 11
        let field = CGRect(x: left, y: pill.y, width: max(0, w - left - 6), height: pill.height)
        askEditor.frame = field
        askEditor.layer.cornerRadius = pill.height / 2
        let sendD = pill.height - 6
        sendButton.frame = CGRect(x: field.maxX - sendD - 3, y: field.midY - sendD / 2, width: sendD, height: sendD)
        sendButton.layer.cornerRadius = sendD / 2
        askEditor.trailingInset = sendD + 10

        // Header: title, then the language, then who answered on the right.
        let providerW = min(providerLabel.intrinsicContentSize.width, 110)
        providerLabel.frame = CGRect(x: w - 14 - providerW, y: mid - 10, width: providerW, height: 20)
        let chipH: CGFloat = 28
        var titleEnd = (providerLabel.attributedText == nil ? w - 14 : providerLabel.frame.minX - 10)
        if !directionButton.isHidden {
            let chipW = min(directionButton.intrinsicContentSize.width, 150)
            titleEnd -= chipW + 8
            directionButton.frame = CGRect(x: 0, y: mid - chipH / 2, width: chipW, height: chipH)
            directionButton.layer.cornerRadius = chipH / 2
        }
        let titleX = 5 + pillW + 12
        let titleW = min(titleLabel.intrinsicContentSize.width, max(0, titleEnd - titleX))
        titleLabel.frame = CGRect(x: titleX, y: mid - 11, width: titleW, height: 22)
        directionButton.frame.origin.x = titleLabel.frame.maxX + 8

        progressTrack.frame = CGRect(x: 0, y: strip - 2, width: w, height: 2)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        progressBar.frame = CGRect(x: 0, y: 0, width: w * 0.4, height: 2)
        progressBar.position = CGPoint(x: w / 2, y: 1)
        CATransaction.commit()

        // Body, in the keys' place.
        let side: CGFloat = 8, gap: CGFloat = 8
        let top = strip + 4, bottom = h - 8
        let tileW = (w - side * 2 - gap) / 2
        let tileH = max(0, (bottom - top - gap) / 2)
        for (i, tile) in tiles.enumerated() {
            tile.frame = CGRect(x: side + CGFloat(i % 2) * (tileW + gap),
                                y: top + CGFloat(i / 2) * (tileH + gap), width: tileW, height: tileH)
        }

        let rowH: CGFloat = 40
        let rowY = bottom - rowH
        let showsRow = phase == .result || phase == .failed
        card.frame = CGRect(x: side, y: top, width: w - side * 2,
                            height: max(0, (showsRow ? rowY - gap : bottom) - top))
        textView.frame = card.bounds
        statusLabel.frame = card.bounds.insetBy(dx: 20, dy: 12)

        if phase == .failed {
            let tryW: CGFloat = 150
            retryButton.frame = CGRect(x: (w - tryW) / 2, y: rowY, width: tryW, height: rowH)
        } else {
            retryButton.frame = CGRect(x: side, y: rowY, width: rowH + 4, height: rowH)
            let x0 = retryButton.frame.maxX + gap
            let rest = w - side - x0
            if replaceButton.isHidden {
                let each = (rest - gap) / 2
                copyButton.frame = CGRect(x: x0, y: rowY, width: each, height: rowH)
                insertButton.frame = CGRect(x: x0 + each + gap, y: rowY, width: each, height: rowH)
            } else {
                // The primary, Replace, a little wider and nearest the thumb.
                let each = (rest - gap * 2) / 3.3
                copyButton.frame = CGRect(x: x0, y: rowY, width: each, height: rowH)
                insertButton.frame = CGRect(x: x0 + each + gap, y: rowY, width: each, height: rowH)
                replaceButton.frame = CGRect(x: insertButton.frame.maxX + gap, y: rowY,
                                             width: w - side - insertButton.frame.maxX - gap, height: rowH)
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
        icon.image = symbol.flatMap { UIImage(systemName: $0) }
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
        let pad: CGFloat = 14
        if icon.isHidden {
            // A tone: just its name, in the middle.
            title.textAlignment = .center
            title.frame = CGRect(x: pad, y: (h - 22) / 2, width: w - pad * 2, height: 22)
        } else {
            title.textAlignment = .natural
            icon.frame = CGRect(x: pad, y: pad - 1, width: 28, height: 24)
            let titleY = detail.isHidden ? h - pad - 21 : h - pad - 38
            title.frame = CGRect(x: pad, y: titleY, width: w - pad * 2, height: 21)
            detail.frame = CGRect(x: pad, y: h - pad - 17, width: w - pad * 2, height: 17)
        }
    }
}
