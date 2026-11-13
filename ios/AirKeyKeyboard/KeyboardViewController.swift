import SwiftUI
import UIKit
import os.log

/// iOS grants keyboard extensions arbitrary (often cached, oversized) heights
/// and ignores height constraints — an Apple-acknowledged issue with no
/// sanctioned fix. This root makes the granted size irrelevant: the real
/// keyboard is BOTTOM-ANCHORED at exactly its designed height, everything
/// above is transparent, and touches up there fall through to the host app.
/// Keystroke timing, for the latency work. A keyboard has to answer a key
/// inside a frame or it reads as lag — Fleksy measures ~19ms a key, the next
/// one out ~31ms, so anything over ~16ms of our own work is a problem.
/// Numbers go to the console: `log stream --predicate 'category == "perf"'`.
enum Perf {
    /// Flip off before shipping; the reads themselves are nearly free but
    /// the log line is not worth paying for in someone's pocket.
    static let on = false
    private static let log = Logger(subsystem: "tech.airkey.keyboard", category: "perf")

    @inline(__always) static func mark() -> CFAbsoluteTime {
        on ? CFAbsoluteTimeGetCurrent() : 0
    }

    /// Milliseconds since `start`, to one decimal.
    @inline(__always) static func ms(_ start: CFAbsoluteTime) -> Double {
        ((CFAbsoluteTimeGetCurrent() - start) * 1000 * 10).rounded() / 10
    }

    static func say(_ what: String) {
        guard on else { return }
        log.log("PERF \(what, privacy: .public)")
    }

    /// How many times this event reached across into the host app. Free on
    /// the simulator, the dominant cost on a phone — so it is counted rather
    /// than timed, and the count is what to keep down.
    nonisolated(unsafe) private static var hostReads = 0

    @inline(__always) static func countHostRead() {
        if on { hostReads += 1 }
    }

    static func reportHostReads() {
        guard on else { return }
        log.log("PERF hostReads=\(hostReads, privacy: .public)")
        hostReads = 0
    }
}

final class PassThroughRoot: UIView {
    var contentHeight: CGFloat = 260

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if point.y < bounds.height - contentHeight { return nil }
        return super.hitTest(point, with: event)
    }
}

/// The AIRKEY keyboard: the keys, the strip above them and the panels that
/// open over the keys, with AIRKEY's agents in the strip. The keyboard never
/// holds a key and never signs: a command goes to the AIRKEY server, whose
/// agents ask the leash on NEAR, and only a press and hold sends one.
final class KeyboardViewController: UIInputViewController {

    private let log = Logger(subsystem: "tech.airkey.keyboard", category: "lifecycle")
    private static var appearances = 0

    // Surfaces
    /// Autolayout content root: iOS derives the keyboard's height from what
    /// it can MEASURE. Manual-frame children give it nothing, so this view is
    /// pinned to all edges and carries the required height constraint — the
    /// system then adopts exactly totalHeight. (Manual frames continue inside.)
    private let content = UIView()
    private var backdrop: UIView!
    private let toolbar = KeyToolbar()
    private let keyboardView = KeyboardView()
    private var shell: MenuShell?
    private var emoji: EmojiBoard?
    /// The clipboard: its own header, pinned and recent as card columns.
    private var clipboardPanel: ClipboardPanel?
    /// Menu → Games: Snake and Chomp over the key area.
    private var games: GamesSurface?
    /// WALLET/CALLS HOOK: the Wallet or the Calls panel (Surfaces/WalletModel.swift),
    /// built when it opens and let go when it closes.
    private var money: MoneyPanel?
    /// Hold space: AI on what you wrote (rewrite, reply, translate, tone,
    /// or ask). Built when it opens and let go when it closes.
    private var aiBar: AIBar?
    private var noteEdit: NoteEditSurface?
    /// What the editor strip opens on (set right before setSurface(.noteEdit)).
    private var pendingEdit: NoteEditSurface.Edit?
    /// Text around the cursor, mirrored for the length of a space-bar glide.
    private var cursorMirror: CursorMirror?
    private var lastCursorAdjust: CFTimeInterval = 0

    /// AIRKEY's agents: what the words would do, and what came back. They
    /// take the strip's place while they have something to say.
    private let agent: AgentModel = {
        let agent = AgentModel()
        // Wording the phone's patterns miss goes to the AIRKEY server to read;
        // the hold then sends the server's exact command.
        agent.reader = { text in
            guard let r = try? await API().read(text), r.kind == "pay" || r.kind == "swap",
                  let title = r.title, let verb = r.verb, let command = r.command else { return nil }
            let by: String? = switch r.reader {
            case "near-ai-cloud": "NEAR AI"
            case "openai": "OpenAI"
            default: nil
            }
            return .init(kind: r.kind == "pay" ? .pay : .swap, title: title, verb: verb, command: command, readBy: by)
        }
        return agent
    }()
    private var agentHost: UIHostingController<AgentStrip>?

    private enum Surface: Equatable { case none, shell, emoji, noteEdit, clipboard, games, ai, wallet, calls }
    private var surface: Surface = .none

    /// When set, key input routes into an inline editor (note editor, emoji search).
    private weak var inlineTarget: InlineEditor?

    // Typing: suggestions, autocorrect, next word, learning (Engine/Typing)
    private var typing: TypingEngine? { TypingStore.shared.engine }
    private struct Correction {
        let original: String
        let replacement: String
        /// Engine corrections teach on undo; shorthand expansions don't.
        let fromEngine: Bool
        /// What came before the caret right after the correction and its
        /// space went in. Undo works from exactly there: anything written,
        /// deleted or moved to since leaves the correction behind.
        var anchor: String? = nil
        /// What came after the fix at the anchor: its space, or the
        /// punctuation that made the fix and then a space (WordTracker.undoTail).
        var tail = ""
    }
    private var lastCorrection: Correction?

    /// Engine corrections of the last few minutes. Going back into one and
    /// typing the original again is a "no": the word stays as typed and is
    /// learned (user, 2026-09-29: "cutee" became "cute", was deleted and
    /// typed again, and became "cute" every time). A typo typed twice
    /// ("teh") is still fixed: its correction was never gone back into.
    private struct RecentFix {
        let original: String
        let replacement: String
        let at: Date
        var touched = false
    }
    private var recentFixes: [RecentFix] = []

    /// The last correction, while the caret is still right after it and its
    /// space. Otherwise a backspace that later reaches the same word in other
    /// text ("free" in a pasted line) would swap it back.
    private func undoableCorrection(before: String?) -> Correction? {
        guard let corr = lastCorrection, let anchor = corr.anchor, let before,
              before == anchor, !corr.tail.isEmpty, before.hasSuffix(corr.replacement + corr.tail) else { return nil }
        return corr
    }
    /// Where each letter of the word being typed was touched.
    private var wordTouches: [(Float, Float)?] = []
    private var wordTouchesFor = ""
    private var lastSpaceTap: Date = .distantPast
    /// Glide typing: the decoder over the base
    /// dictionary, the word a glide just put in (one backspace takes it all
    /// back, a tap swaps it), and the guesses the strip shows for it while
    /// the caret stays put.
    private var glideDecoder: GlideDecoder?
    private var glide: GlideState?
    private var glideStrip: (anchor: String, words: [String])?

    private var heightConstraint: NSLayoutConstraint?
    private var viewHeightConstraint: NSLayoutConstraint?
    private var didBuild = false

    // MARK: Heights

    private var keysHeight: CGFloat {
        // An iPhone on its side gets the shorter rows Apple's keyboard has
        // there: portrait's rows left the app about 100 of its 402pt.
        if traitCollection.verticalSizeClass == .compact {
            let numberRow = SettingsStore.current.numberRow && !keyboardView.context.isPad
            return Glass.sidewaysKeysHeight + (numberRow ? Glass.sidewaysNumberRowExtra : 0)
        }
        // The key region is the system keyboard's own, which is taller on
        // Plus/Max-class phones — never a number baked in for one device.
        let w = view.bounds.width > 0 ? view.bounds.width
                                      : UIScreen.main.bounds.width
        let base = Glass.keysHeight(width: w)
        // A digit pad is Apple's four rows whatever the number-row setting.
        let numberRow = SettingsStore.current.numberRow && !keyboardView.context.isPad
        return numberRow ? base + Glass.numberRowExtra(width: w) : base
    }

    private var totalHeight: CGFloat {
        let base = Glass.toolbarHeight + keysHeight
        switch surface {
        case .emoji:
            // Apple's emoji keyboard stands a little taller than its letters.
            return base + EmojiBoard.extraHeight
        // The note's strip takes the toolbar's place (it is hidden), so
        // the keys keep their own height instead of stretching.
        case .noteEdit: return base + NoteEditSurface.stripHeight - Glass.toolbarHeight
        // Panels take the key area instead of growing the keyboard: the keys
        // never move, so muscle memory holds.
        case .none, .shell, .clipboard, .games, .ai, .wallet, .calls: return base
        }
    }

    // MARK: Lifecycle

    override func loadView() {
        view = PassThroughRoot()
        view.backgroundColor = .clear
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        log.log("KB viewDidLoad")
        // The settings file changed under us (our own Settings screen, the
        // app): the keyboard that is up takes the new look and bindings.
        // Deferred a turn so a rebuild never lands inside the caller.
        NotificationCenter.default.addObserver(
            forName: SettingsStore.changedNote, object: nil, queue: nil) { [weak self] _ in
            DispatchQueue.main.async { self?.settingsChanged() }
        }
        // What a UIPasteControl is allowed to hand us. Without this the
        // control stays disabled however much is on the clipboard.
        let paste = UIPasteConfiguration(forAccepting: NSString.self)
        paste.addTypeIdentifiers(forAccepting: UIImage.self)
        pasteConfiguration = paste
        agent.host = self
        refreshHaptics()
    }

    /// Haptics need Full Access, and the person may have turned them off.
    /// The generators are warmed up so the first key is not late.
    private func refreshHaptics() {
        Haptics.allowed = hasFullAccess && SettingsStore.current.haptics
        Haptics.warmUp()
    }

    /// Where every system paste button in the keyboard lands.
    override func paste(itemProviders: [NSItemProvider]) {
        acceptPasted(itemProviders)
    }

    /// The keyboard type the traits were last read for, so a focus moving
    /// between fields (Safari's next arrow) is noticed without resetting the
    /// page on every keystroke.
    private var lastKeyboardType: UIKeyboardType?

    /// What the field says about its keys: a return key that names its
    /// action, and WebKit's number fields (numbers-and-punctuation), which
    /// Apple's keyboard opens on the 123 page. A new field starts on the
    /// letters, the way the system keyboard does.
    private func adoptFieldTraits(fresh: Bool) {
        let type = textDocumentProxy.keyboardType
        keyboardView.returnFace = Self.returnFace(for: textDocumentProxy.returnKeyType)
        // Apple greys the key while a field that enables it automatically is
        // empty. Drawn only: the proxy's view of the text can lag, and a
        // return that does nothing would be worse than one drawn a shade off.
        keyboardView.returnEnabled = textDocumentProxy.enablesReturnKeyAutomatically != true
            || textDocumentProxy.hasText
        guard fresh || type != lastKeyboardType else { return }
        lastKeyboardType = type
        keyboardView.setMode(type == .numbersAndPunctuation ? .symbols1 : .letters)
    }

    /// Apple's return key for each action, measured on the iOS 26.5
    /// simulator (web fields with each enterkeyhint, Safari's address bar)
    /// and on an iPhone 16 Pro: go, search, send and done are blue with a
    /// white glyph, next is a chevron, plain return is the ⏎ glyph. Symbol
    /// sizes are matched to Apple's ink (go 17.3 x 14pt, search 18 x 18.3,
    /// send 14 x 17.3, done 16 x 15.7, next 6.7 x 16). The rest were not
    /// measured and keep their word.
    static func returnFace(for type: UIReturnKeyType?) -> ReturnFace {
        switch type {
        case .go:
            return ReturnFace(symbol: "arrow.right", pointSize: 18.5, weight: .medium, primary: true)
        case .search, .google, .yahoo:
            return ReturnFace(symbol: "magnifyingglass", pointSize: 19, weight: .light, primary: true)
        case .send:
            return ReturnFace(symbol: "arrow.up", pointSize: 18.5, weight: .medium, primary: true)
        case .done:
            return ReturnFace(symbol: "checkmark", pointSize: 18.5, weight: .medium, primary: true)
        case .next:
            return ReturnFace(symbol: "chevron.right", pointSize: 19, weight: .light)
        case .join: return ReturnFace(text: "join")
        case .route: return ReturnFace(text: "route")
        case .continue: return ReturnFace(text: "continue")
        case .emergencyCall: return ReturnFace(text: "call")
        default: return .plain
        }
    }

    /// Apple behavior: the keyboard follows the HOST (field appearance /
    /// system style). A forced light or dark is not offered on the iPhone
    /// any more: iOS draws the band above the keyboard and the globe bar
    /// below it in the host's colour, so a board forced the other way looked
    /// cut off between them (user, 2026-09-27). A choice saved before is
    /// ignored.
    private func resolveAppearance() {
        let pref = "auto"
        // The host's keyboardAppearance is resolved once, when the field
        // takes focus: Messages opened in dark mode keeps reporting .dark
        // after the phone switches to light. The trait (which the system
        // sheet follows) does change, so after a live flip it wins.
        // The host's appearance is the trait ABOVE our view: our own
        // override (set a few lines down) reaches our view and everything
        // in it, and reading it back here would make a forced dark look
        // like a dark host, dropping the sheet we paint for the difference.
        if let above = view.superview?.traitCollection {
            hostTraitDark = above.userInterfaceStyle == .dark
        } else if overrideUserInterfaceStyle == .unspecified {
            hostTraitDark = traitCollection.userInterfaceStyle == .dark
        }
        let traitDark = hostTraitDark
        // The sheet iOS draws behind the keys follows the host's trait. The
        // field's keyboardAppearance can be stale: Messages focused in dark
        // keeps reporting .dark after the phone turns light, even when the
        // keyboard comes back later, which drew dark keys on a light sheet
        // and the strip's words white on white (user, 2026-10-01: "not
        // visible"). So once the host's trait can be read it decides; the
        // field's word counts only before then.
        let hostDark = view.superview != nil || appearanceFlipped
            ? traitDark
            : textDocumentProxy.keyboardAppearance == .dark || traitDark
        let dark = pref == "dark" || (pref == "auto" && hostDark)
        let theme = SettingsStore.current.keyTheme ?? "glass"
        // Painted boards (the colour and gradient themes) are retired for
        // now: iOS draws its own band above every keyboard that nothing can
        // paint, so a coloured board looked cut off under it. One picked
        // before stays in settings and is ignored (user, 2026-09-27).
        let bg = ""
        let borders = SettingsStore.current.keyBorders ?? false
        let dim = SettingsStore.current.themeBrightness ?? 0
        // A keyboard theme (docs/THEMES.md): keys, glyphs, popup, chip, dot,
        // shadows, borders, face and sound; never a board, never a size.
        // Its font and sounds load only while it is the one picked.
        let skin = KeyboardTheme.named(SettingsStore.current.skin)
        ThemeSound.shared.allowed = (SettingsStore.current.skinSound ?? true) && hasFullAccess
        overrideUserInterfaceStyle =
            pref == "light" ? .light : pref == "dark" ? .dark : .unspecified
        // iOS draws the sheet for the HOST's appearance whatever we say, so a
        // forced light or dark that disagrees with it paints its own sheet;
        // in auto the host's sheet is right and nothing is painted.
        forcedSheet = (pref != "auto" && dark != hostDark) ? Glass.sheetPaint(dark: dark) : nil
        backdrop?.backgroundColor = forcedSheet ?? .clear
        if Glass.isDark != dark || Glass.keyTheme != theme
            || Glass.themeBg != bg || Glass.keyBorders != borders
            || Glass.themeDim != dim || Glass.skin?.id != skin?.id {
            Glass.isDark = dark
            Glass.keyTheme = theme
            Glass.themeBg = bg
            Glass.keyBorders = borders
            Glass.themeDim = dim
            if Glass.skin?.id != skin?.id {
                Glass.skin = skin
                ThemeFonts.activate(skin?.font)
                ThemeSound.shared.load(skin?.sound.roles.isEmpty == false ? skin?.sound : nil)
                if skin?.keyTexture == nil { ThemeTextures.release() }
                // The last theme's faces and texture tiles go with it.
                KeyFaces.release()
            }
            refreshPalette()
        }
    }

    /// A look, appearance or binding changed on disk: apply what differs
    /// (both calls are no-ops when nothing did).
    private func settingsChanged() {
        refreshHaptics()
        guard didBuild else { return }
        keyboardView.refreshBindings()
        resolveAppearance()
    }

    /// Re-skins the long-lived chrome after an appearance flip; transient
    /// surfaces pick the palette up on their next open.
    private func refreshPalette() {
        guard didBuild else { return }
        toolbar.applyPalette()
        keyboardView.rebuild()
        applyBoardPaint()
        emoji?.applyPalette()
    }

    /// The painted board of a colour or gradient theme.
    private var boardLayer: CAGradientLayer?

    /// A colour or gradient theme paints the board the tiles in the app
    /// promise (Gboard's themes do the same); with none, the system's own
    /// sheet shows through, or the forced one when the person overrode the
    /// host's appearance.
    private func applyBoardPaint() {
        guard let backdrop else { return }
        let colors = Glass.boardColors
        guard !colors.isEmpty else {
            boardLayer?.removeFromSuperlayer()
            boardLayer = nil
            backdrop.backgroundColor = forcedSheet ?? .clear
            return
        }
        let layer = boardLayer ?? CAGradientLayer()
        layer.frame = backdrop.bounds
        layer.colors = (colors.count == 1 ? [colors[0], colors[0]] : colors).map(\.cgColor)
        layer.startPoint = CGPoint(x: 0, y: 0)
        layer.endPoint = CGPoint(x: 1, y: 1)
        if boardLayer == nil { backdrop.layer.insertSublayer(layer, at: 0) }
        boardLayer = layer
        backdrop.backgroundColor = .clear
    }

    /// Set once light/dark changes while the keyboard is up; cleared when it
    /// goes away, so the next field's own appearance is read fresh.
    private var appearanceFlipped = false

    /// The last appearance the host handed down (see resolveAppearance).
    private var hostTraitDark = false

    /// The sheet we paint when the person forces an appearance the host does
    /// not have; nil (transparent) whenever the host's own sheet is right.
    private var forcedSheet: UIColor?

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        // Turned on its side, or back: the rows change height with it.
        if didBuild, previous?.verticalSizeClass != traitCollection.verticalSizeClass {
            applySurfaceLayout(animated: false)
        }
        guard let before = previous?.userInterfaceStyle,
              before != traitCollection.userInterfaceStyle else { return }
        if before != .unspecified { appearanceFlipped = true }
        resolveAppearance()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        SettingsStore.invalidate()
        recentFixes = []   // another field: its corrections are not these
        emojiSeen = ""     // a draft the keyboard opens on teaches nothing
        emojiAnchor = nil
        typed = ""         // another field: our copy of its text starts over
        forgetBefore()
        VaultStore.shared.invalidate() // the app may have edited the vault
        refreshHaptics()
        seedOwnNames()
        resolveAppearance() // BEFORE building — tokens feed every surface
        if !didBuild {
            didBuild = true
            build()
            toolbar.applyPalette()
        }
        if heightConstraint == nil {
            let c = content.heightAnchor.constraint(equalToConstant: totalHeight)
            c.priority = .required
            c.isActive = true
            heightConstraint = c
        }
        // Best-effort: ask nicely for the exact height too (999 — if iOS
        // adopts it there is zero dead zone; if not, bottom-anchoring wins).
        if viewHeightConstraint == nil {
            let v = view.heightAnchor.constraint(equalToConstant: totalHeight)
            v.priority = UILayoutPriority(999)
            v.isActive = true
            viewHeightConstraint = v
        }
        keyboardView.needsGlobe = needsInputModeSwitchKey
        // A keyboard coming back for a field starts on the letters: a menu,
        // clipboard or emoji panel left open last time would greet the next
        // field with something it never asked for.
        if didBuild, surface != .none { setSurface(.none, animated: false) }
        agent.dismiss()
        keyboardView.context = fieldContext
        adoptFieldTraits(fresh: true)
        keyboardView.rebuild()
        keyboardView.refreshBindings()
        toolbar.reloadItems()
        applySurfaceLayout(animated: false)
        syncAutoShift()
        wordTouches = []
        wordTouchesFor = ""
        TypingStore.shared.letterRows = LetterLayout(id: SettingsStore.current.keyLayout).rows
        TypingStore.shared.prepare(
            hasFullAccess: hasFullAccess,
            // iOS answers on a background queue: the engine is the main
            // queue's, so the words are handed over there.
            lexicon: { [weak self] done in
                self?.requestSupplementaryLexicon { @Sendable lexicon in
                    DispatchQueue.main.async { done(lexicon) }
                }
            },
            ready: { [weak self] _ in
                // The engine may load after viewWillAppear's seeding ran.
                self?.seedOwnNames()
                self?.updateCandidates()
                self?.glideDecoderReady()?.warm()
            })
        // Token symbols, contacts and your NEAR account, from the server.
        agent.refreshTokens()
        updateCandidates()
        watch()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        appearanceFlipped = false
        // A chip's colours stop turning with the keyboard away.
        toolbar.setMagicRunning(false)
        TypingStore.shared.saveNow()
        watcher?.cancel()
        watcher = nil
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // On screen now: the host's trait can be read, and it may overrule
        // the guess made before the view had a superview.
        resolveAppearance()
        toolbar.setMagicRunning(true)
        Self.appearances += 1
        log.log("KB height=\(self.view.bounds.height) target=\(self.totalHeight)")
        _ = MemoryLogger.logAppearance(Self.appearances)
        ClipboardStore.fullAccessHint = hasFullAccess && !isSecureField
        watch()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        layoutSurfaces()
        if let boardLayer, boardLayer.frame != backdrop.bounds {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            boardLayer.frame = backdrop.bounds
            CATransaction.commit()
        }
    }

    private func build() {
        content.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(content)
        NSLayoutConstraint.activate([
            // Within the safe area: on its side an iPhone's corners and
            // Dynamic Island would cover the outermost keys (Apple's keys
            // stop short of them too). Portrait has no side insets.
            content.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            // Bottom-anchored; the top edge floats — dead space stays clear.
            content.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        // No board of our own: iOS draws the keyboard sheet behind every
        // third-party keyboard and its margins cannot be painted, so a board
        // inside it only shows up as a second, mismatched band. The keys sit
        // on the system's sheet, in every theme.
        backdrop = UIView()
        backdrop.backgroundColor = forcedSheet ?? .clear
        backdrop.isUserInteractionEnabled = false
        backdrop.frame = content.bounds
        backdrop.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        content.addSubview(backdrop)

        toolbar.delegate = self
        content.addSubview(toolbar)

        keyboardView.delegate = self
        keyboardView.clipsToBounds = false
        content.addSubview(keyboardView)

        // AIRKEY's agents ride over the toolbar, in SwiftUI (the hold to
        // confirm and Liquid Glass are SwiftUI's).
        let host = UIHostingController(rootView: AgentStrip(model: agent))
        host.view.backgroundColor = .clear
        host.sizingOptions = []
        host.safeAreaRegions = []
        addChild(host)
        content.addSubview(host.view)
        host.didMove(toParent: self)
        host.view.isHidden = true
        agentHost = host
        observeAgent()
        applyBoardPaint()
    }

    /// The agent strip comes and goes with what it has to say: watched, so
    /// a receipt that lands while the fingers are still takes the strip.
    private func observeAgent() {
        withObservationTracking {
            _ = agent.isShowing
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.layoutAgent(animated: true)
                self.observeAgent()
            }
        }
    }

    /// AIRKEY's strip takes the toolbar's place while it has something to
    /// say; the toolbar (words, chips, tools) is back the moment it is done.
    private func layoutAgent(animated: Bool = false) {
        guard let host = agentHost else { return }
        let show = surface == .none && agent.isShowing && !isSecureField
        host.view.frame = CGRect(x: 0, y: 0, width: content.bounds.width, height: Glass.toolbarHeight)
        guard show == host.view.isHidden else { return }
        if show {
            content.bringSubviewToFront(host.view)
            host.view.isHidden = false
            toolbar.isHidden = true
            guard animated, !Glass.reduceMotion else { host.view.alpha = 1; return }
            // The same soft spring every surface uses.
            host.view.alpha = 0
            UIViewPropertyAnimator(duration: 0.3, dampingRatio: 0.9) {
                host.view.alpha = 1
            }.startAnimation()
        } else {
            host.view.isHidden = true
            toolbar.isHidden = toolbarHiddenBySurface
        }
    }

    /// Panels that stand in for the toolbar (the clipboard, emoji, the note
    /// editor) hide it whatever the agent strip says.
    private var toolbarHiddenBySurface = false

    // MARK: Surface layout

    /// Panels sit in the key area: the strip stays put and the keys are
    /// covered, so the keyboard never changes height.
    private func panelRect(_ w: CGFloat, _ h: CGFloat) -> CGRect {
        CGRect(x: 0, y: Glass.toolbarHeight, width: w,
               height: max(0, h - Glass.toolbarHeight))
    }

    /// Strip contents while a panel is open: icon + name, close on the left.
    private func panelHeader() -> (String?, String?) {
        switch surface {
        case .shell:
            let title = shell?.headerTitle ?? MenuShell.rootTitle
            return (title == MenuShell.rootTitle ? "square.grid.2x2" : nil, title)
        case .emoji where emoji?.searchActive != true: return ("face.smiling", "Emoji")
        case .games: return ("gamecontroller", "Games")
        case .wallet: return (KeyToolbar.icons["wallet"], "Wallet") // WALLET/CALLS HOOK
        case .calls: return (KeyToolbar.icons["calls"], "Calls")
        default: return (nil, nil)
        }
    }


    /// Suggestions and the smart strip are recomputed once typing settles,
    /// never inside the keystroke itself. At speed the old way put the
    /// engine, two dozen regexes and a strip rebuild between one finger
    /// going down and the next — long enough to lose the tap. Every key
    /// schedules this instead, so a burst collapses into a single pass.
    private var candidatesWork: DispatchWorkItem?
    /// When the settings file was last stat'ed (textDidChange throttles it).
    private var lastSettingsCheck: CFTimeInterval = 0
    /// Slices of the last suggestion pass, for Perf.
    private var tChip: Double = 0
    private var tEngine: Double = 0
    private var tStrip: Double = 0
    /// The clipboard offer, and when it was last worked out.
    private var lastClipProbe: CFTimeInterval = 0
    private var cachedPaste: String?

    /// Whether to offer what was copied. Measured at 14-20ms a call: the
    /// probe is a cross-process read of UIPasteboard plus two App Group
    /// files, and it used to run on every keystroke with an empty field.
    /// Nobody's clipboard changes while they are typing, so it is worked
    /// out once a second and remembered in between.
    private func pasteOffer(tailEmpty: Bool) -> String? {
        guard hasFullAccess, tailEmpty else { return nil }
        let now = CACurrentMediaTime()
        guard now - lastClipProbe > 1.0 else { return cachedPaste }
        lastClipProbe = now
        // History only knows a copy once it has been read; a newer one shows
        // as an offer instead of the older text.
        // Until the new copy is in history, history's first is the copy
        // before it: offering that pasted stale text ("Your code is…" when
        // "See you at noon." was on the clipboard, 2026-10-14).
        let unread = ClipboardStore.pasteboardHasNewContent()
        if unread { nameTheCopy() }
        cachedPaste = ClipContext.isFresh(within: StripPolicy.pasteFresh)
            // A sensitive copy isn't shown in the strip: the placeholder pastes it.
            ? ((unread ? nil : ClipboardStore.load().first.flatMap { $0.sensitive == true ? nil : $0.text })
                ?? ClipboardStore.pastePlaceholder)
            : nil
        return cachedPaste
    }

    /// Which copy we have already asked iOS to name, so a chip that cannot be
    /// named is not re-asked on every probe.
    private var namedCopy = -1

    /// Puts the new copy into history so the chip can show the WORDS rather
    /// than an offer to paste something unnamed.
    ///
    /// Does nothing at all unless "Capture everything you copy" is on. There
    /// is no quiet way in: `detectValues` names a link or a number, but
    /// handing over the value IS a read and iOS raises "Allow Paste?" for it
    /// exactly as it does for the whole string. Only `detectPatterns`, which
    /// answers with types and no values, stays silent, and a type is not
    /// something a chip can show. So the offer to Paste is the default route
    /// — the tap is the permission — and this is the opt-in one.
    private func nameTheCopy() {
        let cc = UIPasteboard.general.changeCount
        guard namedCopy != cc else { return }
        namedCopy = cc
        ClipboardStore.captureNewCopy { [weak self] added in
            guard added, let self else { return }
            self.cachedPaste = nil
            self.lastClipProbe = 0
            self.updateCandidates()
        }
    }

    private func scheduleCandidates() {
        lastEditAt = CACurrentMediaTime()
        chipRecheck?.cancel()
        chipRecheck = nil
        candidatesWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.candidatesWork = nil
            if self.showGlideStrip() { return }
            self.updateCandidates()
        }
        candidatesWork = work
        // Short enough to feel immediate when the fingers stop, long enough
        // that a fast run of keys only pays for it once.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03, execute: work)
    }
    /// Which chip may show and when, and what a ✕ or typing past one means
    /// for the next (StripPolicy): useful, never nagging.
    private var stripPolicy = StripPolicy()
    /// When the text last changed (a key, a commit, the host).
    private var lastEditAt: CFTimeInterval = 0
    /// A chip waiting for the fingers to stop.
    private var chipRecheck: DispatchWorkItem?

    /// The tool being dragged onto or around the strip, and its ghost.
    private var draggingToolId: String?
    private var dragGhost: UIImageView?

    /// The g menu itself is open (its root grid), so the strip keeps showing
    /// the tools — that is the thing a tile gets dragged onto.
    private var shellAtMenu: Bool {
        surface == .shell && shell?.canGoBack == false
    }

    private var lastPanelTitle: String??

    private func layoutSurfaces() {
        let w = content.bounds.width
        let h = content.bounds.height
        let header = panelHeader()
        if lastPanelTitle != .some(header.1) {
            lastPanelTitle = .some(header.1)
            toolbar.showPanelHeader(icon: header.0, title: header.1,
                                    canGoBack: shell?.canGoBack == true,
                                    keepTools: shellAtMenu)
        }
        toolbarHiddenBySurface = false
        switch surface {
        case .none:
            toolbar.frame = CGRect(x: 0, y: 0, width: w, height: Glass.toolbarHeight)
            keyboardView.isHidden = false
            keyboardView.frame = CGRect(x: 0, y: Glass.toolbarHeight, width: w,
                                        height: max(0, h - Glass.toolbarHeight))
        case .emoji:
            toolbar.frame = CGRect(x: 0, y: 0, width: w, height: Glass.toolbarHeight)
            toolbarHiddenBySurface = true
            if emoji?.searchActive == true {
                // Strip + letter keys (Apple's emoji-search behaviour). The
                // strip stands in for the toolbar, as on Apple's.
                keyboardView.isHidden = false
                emoji?.frame = CGRect(x: 0, y: 0, width: w,
                                      height: EmojiBoard.searchStripHeight)
                let keysY = EmojiBoard.searchStripHeight
                keyboardView.frame = CGRect(x: 0, y: keysY, width: w,
                                            height: max(0, h - keysY))
            } else {
                // The board is the whole keyboard, search field where the
                // strip was, the way Apple's emoji keyboard is.
                keyboardView.isHidden = true
                emoji?.frame = CGRect(x: 0, y: 0, width: w, height: h)
            }
        case .shell:
            toolbar.frame = CGRect(x: 0, y: 0, width: w, height: Glass.toolbarHeight)
            keyboardView.isHidden = true
            shell?.frame = panelRect(w, h)
        case .noteEdit:
            toolbarHiddenBySurface = true
            keyboardView.isHidden = false
            noteEdit?.frame = CGRect(x: 0, y: 0, width: w,
                                     height: NoteEditSurface.stripHeight)
            keyboardView.frame = CGRect(x: 0, y: NoteEditSurface.stripHeight,
                                        width: w,
                                        height: max(0, h - NoteEditSurface.stripHeight))
        case .games:
            toolbar.frame = CGRect(x: 0, y: 0, width: w, height: Glass.toolbarHeight)
            keyboardView.isHidden = true
            games?.frame = panelRect(w, h)
        case .wallet, .calls: // WALLET/CALLS HOOK: over the keys, under the strip's title.
            toolbar.frame = CGRect(x: 0, y: 0, width: w, height: Glass.toolbarHeight)
            keyboardView.isHidden = true
            money?.frame = panelRect(w, h)
        case .clipboard:
            // The clipboard owns the whole keyboard, strip included.
            toolbarHiddenBySurface = true
            keyboardView.isHidden = true
            clipboardPanel?.frame = CGRect(x: 0, y: 0, width: w, height: h)
        case .ai:
            // Asking takes the strip and types with the keys under it; the
            // rest of the AI bar owns the whole keyboard, as the clipboard does.
            toolbarHiddenBySurface = true
            if aiBar?.isStrip == true {
                keyboardView.isHidden = false
                aiBar?.frame = CGRect(x: 0, y: 0, width: w, height: Glass.toolbarHeight)
                keyboardView.frame = CGRect(x: 0, y: Glass.toolbarHeight, width: w,
                                            height: max(0, h - Glass.toolbarHeight))
            } else {
                keyboardView.isHidden = true
                aiBar?.frame = CGRect(x: 0, y: 0, width: w, height: h)
            }
        }
        let agentUp = surface == .none && agent.isShowing && !isSecureField
        toolbar.isHidden = toolbarHiddenBySurface || agentUp
        if let host = agentHost {
            host.view.frame = CGRect(x: 0, y: 0, width: w, height: Glass.toolbarHeight)
            host.view.isHidden = !agentUp
            if agentUp { content.bringSubviewToFront(host.view) }
        }
    }

    private func applySurfaceLayout(animated: Bool) {
        heightConstraint?.constant = totalHeight
        viewHeightConstraint?.constant = totalHeight
        (view as? PassThroughRoot)?.contentHeight = totalHeight
        let work = {
            self.layoutSurfaces()
            // Entrances fade in inside the same spring; the growing height
            // provides the rise itself.
            for overlay in [self.shell, self.emoji, self.noteEdit,
                            self.clipboardPanel, self.games, self.aiBar, self.money] as [UIView?] {
                overlay?.alpha = 1
            }
            self.view.layoutIfNeeded()
        }
        if animated && !Glass.reduceMotion {
            // One soft spring for every surface change — nothing snaps, but
            // quick: Apple's surface moves land in ~0.3s.
            let spring = UIViewPropertyAnimator(duration: 0.30, dampingRatio: 0.9,
                                                animations: work)
            spring.startAnimation()
        } else {
            work()
        }
    }

    /// Prepares a freshly-added overlay to rise into place: the spring fades
    /// it in while the keyboard height grows underneath it.
    private func prepareEntrance(_ v: UIView, animated: Bool) {
        guard animated, !Glass.reduceMotion else { return }
        v.alpha = 0
    }

    private func setSurface(_ new: Surface, animated: Bool = true) {
        guard surface != new else { return }
        // Tear down the old overlay.
        switch surface {
        case .shell: shell?.removeFromSuperview(); shell = nil
        case .emoji: emoji?.removeFromSuperview(); emoji = nil
        case .noteEdit:
            // A phone number was typed on the digits: the letters come back.
            if noteEdit?.wantsDigits == true { keyboardView.setMode(.letters) }
            // An email or a link had its own keys: the field's come back.
            if noteEdit?.keysContext != nil { keyboardView.context = KeyboardContext(keyboardType: textDocumentProxy.keyboardType) }
            noteEdit?.removeFromSuperview(); noteEdit = nil
        case .clipboard: clipboardPanel?.removeFromSuperview(); clipboardPanel = nil
        case .games: games?.stop(); games?.removeFromSuperview(); games = nil
        case .wallet, .calls: money?.close(); money = nil // WALLET/CALLS HOOK: timers stop, the panel is let go.
        case .ai: aiBar?.removeFromSuperview(); aiBar = nil
        case .none: break
        }
        inlineTarget = nil
        surface = new
        // A suggestion is about the sentence in the field; once a panel is
        // open it is about something else, so it leaves the strip.
        if new != .none { toolbar.showSmart(nil) }
        switch new {
        case .shell:
            let s = MenuShell()
            s.delegate = self
            content.addSubview(s)
            prepareEntrance(s, animated: animated)
            shell = s
        case .emoji:
            let e = EmojiBoard()
            e.delegate = self
            content.addSubview(e)
            prepareEntrance(e, animated: animated)
            emoji = e
            MemoryLogger.logSurface("emoji")
        case .clipboard:
            let c = ClipboardPanel()
            c.delegate = self
            c.pasteTarget = self
            content.addSubview(c)
            prepareEntrance(c, animated: animated)
            clipboardPanel = c
            MemoryLogger.logSurface("clipboard")
        case .noteEdit:
            let n = NoteEditSurface(edit: pendingEdit ?? .note(id: nil, text: ""))
            pendingEdit = nil
            n.delegate = self
            content.addSubview(n)
            prepareEntrance(n, animated: animated)
            noteEdit = n
            if n.wantsDigits { keyboardView.setMode(.symbols1) }
            if let keys = n.keysContext { keyboardView.context = keys }
            n.activate(n.activeEditor)
        case .games:
            let g = GamesSurface()
            content.addSubview(g)
            prepareEntrance(g, animated: animated)
            games = g
            MemoryLogger.logSurface("games")
        case .wallet, .calls: // WALLET/CALLS HOOK
            let m = MoneyPanel(kind: new == .wallet ? .wallet : .calls, actions: moneyActions, dark: Glass.chromeDark)
            content.addSubview(m)
            m.attach(to: self)
            prepareEntrance(m, animated: animated)
            money = m
            MemoryLogger.logSurface(new == .wallet ? "wallet" : "calls")
        case .ai:
            let b = AIBar()
            b.delegate = self
            content.addSubview(b)
            prepareEntrance(b, animated: animated)
            aiBar = b
            MemoryLogger.logSurface("ai")
        case .none:
            break
        }
        applySurfaceLayout(animated: animated)
        // Back on the keys: the strip is about the field again (a glide's
        // other guesses while the caret is still after it).
        if new == .none { scheduleCandidates() }
    }

    // MARK: Text context

    private var isSecureField: Bool {
        textDocumentProxy.isSecureTextEntry ?? false
    }

    // MARK: The host round trip

    /// `documentContextBeforeInput` reaches across into the host app. On a
    /// phone that crossing is the most expensive thing a keystroke does, and
    /// within one event the answer cannot change, so it is read once and kept
    /// until the document actually moves. Every edit we make goes through
    /// `hostInsert`/`hostDelete`/`hostAdjust`, and anything the HOST changes
    /// arrives as textDidChange or selectionDidChange — all of which drop it.
    private var cachedBefore: String??

    /// What was typed through this keyboard, up to the caret. iOS only hands
    /// a keyboard the text back to the last sentence break ("pay harshal
    /// 0.1" arrives as "1", "harshal.near" as "near"), so the keyboard keeps
    /// its own copy and checks it against what iOS shows: emptied when the
    /// field is (sent or cleared), and replaced by what iOS shows when the
    /// two disagree (pasted, cursor moved).
    private var typed = ""

    /// The text before the caret: our own copy where iOS cut it short.
    var beforeContext: String? {
        if let cachedBefore { return cachedBefore }
        let host = textDocumentProxy.documentContextBeforeInput
        Perf.countHostRead()
        let value: String?
        if let host, !host.isEmpty {
            if !typed.hasSuffix(host) { typed = host }
            value = typed
        } else {
            typed = ""
            value = host
        }
        cachedBefore = .some(value)
        return value
    }

    /// Forgets the cached context. Cheap, and the safe thing to do whenever
    /// there is any doubt — a stale answer here edits the wrong text.
    func forgetBefore() { cachedBefore = nil }

    func hostInsert(_ text: String) {
        _ = beforeContext   // our copy agrees with the field before it grows
        textDocumentProxy.insertText(text)
        typed += text
        forgetBefore()
    }

    /// Deletes `count` characters before the caret.
    func hostDelete(_ count: Int = 1) {
        guard count > 0 else { return }
        _ = beforeContext
        for _ in 0..<count { textDocumentProxy.deleteBackward() }
        typed.removeLast(min(count, typed.count))
        forgetBefore()
    }

    func hostAdjust(byCharacterOffset offset: Int) {
        textDocumentProxy.adjustTextPosition(byCharacterOffset: offset)
        // The caret moved inside the text: iOS's view of it is the one to trust.
        typed = ""
        forgetBefore()
    }

    override func selectionDidChange(_ textInput: UITextInput?) {
        super.selectionDidChange(textInput)
        forgetBefore()
    }

    override func selectionWillChange(_ textInput: UITextInput?) {
        super.selectionWillChange(textInput)
        forgetBefore()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        let t0 = Perf.mark()
        forgetBefore() // the document moved — whoever moved it
        Perf.reportHostReads()
        if CACurrentMediaTime() - lastSettingsCheck > 0.5 {
            lastSettingsCheck = CACurrentMediaTime()
            SettingsStore.reloadIfChanged() // settingsChanged() does the rest
        }
        // Field flavour can change per focus (email → number pad → text).
        keyboardView.context = fieldContext
        adoptFieldTraits(fresh: false)
        syncAutoShift()
        // Scheduled, not immediate: this fires after our own insert too.
        scheduleCandidates()
        Perf.say("textDidChange=\(Perf.ms(t0))ms")
    }

    // Some apps change the text without telling the keyboard (a paste from
    // the menu, a message sent). Look again a few times a second while the
    // keyboard is on screen.
    private var watcher: Task<Void, Never>?
    /// The field as the strip last read it, so the watcher only acts on a change.
    private var lastSeenField = ""

    private func watch() {
        guard watcher == nil else { return }
        watcher = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(400))
                guard let self else { return }
                guard self.view.window != nil, self.surface == .none, self.inlineTarget == nil else { continue }
                self.forgetBefore()
                if self.fieldSignature != self.lastSeenField {
                    self.syncAutoShift()
                    self.updateCandidates()
                }
            }
        }
    }

    /// The text on both sides of the caret, as one string to compare.
    private var fieldSignature: String {
        (beforeContext ?? "") + "\u{1}" + (textDocumentProxy.documentContextAfterInput ?? "")
    }

    /// `knownBefore` is the text before the cursor when the caller already
    /// knows it. Reading it from the proxy is a round trip to the HOST app —
    /// the most expensive thing a keyboard does per key — so a caller that
    /// just inserted something passes what the field now holds instead of
    /// asking across the process a second time.
    private func syncAutoShift(knownBefore: String? = nil) {
        // Respect the FIELD's capitalization type like the system keyboard:
        // .none fields (usernames, searches) never auto-shift.
        let wants: Bool
        switch textDocumentProxy.autocapitalizationType ?? .sentences {
        case .none: wants = false
        case .allCharacters: wants = true
        case .words:
            let before = knownBefore ?? beforeContext
            wants = before?.isEmpty != false || before?.hasSuffix(" ") == true
        default:
            wants = WordTracker.wantsCapital(
                beforeContext: knownBefore ?? beforeContext)
        }
        keyboardView.syncAutoShift(wantsCapital: wants)
    }

    /// What this field allows (when the keyboard autocorrects): nothing
    /// in secure, email, URL, username, code and number fields; no
    /// autocorrect where the field or the user turned it off; no learning in
    /// fields that hold names or when learning is paused.
    private var typingPolicy: TypingEngine.Policy {
        let proxy = textDocumentProxy
        if isSecureField { return [] }
        switch proxy.keyboardType ?? .default {
        case .URL, .emailAddress, .numberPad, .phonePad, .decimalPad, .asciiCapableNumberPad, .namePhonePad:
            return []
        default: break
        }
        let quiet: [UITextContentType] = [.URL, .emailAddress, .username, .password, .newPassword, .oneTimeCode,
                                          .creditCardNumber, .telephoneNumber]
        // The type kept for this field: iOS can answer nil on a later read.
        let contentType = fieldContentType
        if let type = contentType, quiet.contains(type) { return [] }
        let s = SettingsStore.current
        var policy: TypingEngine.Policy = .all
        if !s.autocorrect || proxy.autocorrectionType == .no || proxy.keyboardType == .twitter
            || proxy.keyboardType == .webSearch {
            policy.remove(.autocorrect)
        }
        // A field that turns autocorrect off (search bars) teaches nothing:
        // "teh" typed twice into Safari's search bar was never fixed in
        // Messages again (RESEARCH-IMPROVEMENTS-APP 12).
        if proxy.autocorrectionType == .no || proxy.keyboardType == .webSearch {
            policy.remove(.learning)
        }
        if let type = contentType, [.name, .givenName, .familyName, .nickname].contains(type) {
            policy.remove(.autocorrect)
        }
        if s.vocabLearning == false { policy.remove(.learning) }
        return policy
    }

    /// Where autocorrect is off but learning is on (the "Autocorrect"
    /// setting off, X's composer), only words autocorrect would have left
    /// alone are learned. A name field learns what it's given.
    private var learnsOnlyWordsItWouldKeep: Bool {
        !SettingsStore.current.autocorrect || textDocumentProxy.keyboardType == .twitter
    }


    /// The person's own names are words to the engine, whatever the
    /// dictionary makes of them: each word of a name saved in the notes'
    /// details, and every name in AIRKEY's contacts, is kept and never
    /// autocorrected.
    private var seededNames: Set<String> = []
    /// The text before the caret at the last strip update (PhraseMemory).
    private var phraseSeen = ""
    /// The text before the caret at the last look for emoji runs, and the
    /// last run learned (its text up to the run), so one is learned once.
    private var emojiSeen = ""
    private var emojiAnchor: String?
    private func seedOwnNames() {
        guard let engine = typing else { return }
        let fields = VaultStore.shared.load().fields
        func words(_ values: [String]) -> Set<String> {
            Set(values.flatMap { $0.split(whereSeparator: { !$0.isLetter && $0 != "'" && $0 != "-" }).map(String.init) }
                .filter { $0.count >= 2 })
        }
        let names = words(fields.filter { $0.kind == "name" }.map(\.value))
            .union(words(Array(Contacts.names)))
        let details = words(["givenName", "familyName", "company", "city", "state"]
            .flatMap { Smart.detailsFor(kind: $0, fields: fields).map(\.value) })
        engine.setOwnNames(names.union(details).sorted())
        guard names != seededNames else { return }
        for name in names.subtracting(seededNames) { engine.keep(name) }
        seededNames = names
        TypingStore.shared.scheduleSave()
    }

    /// Whether the keyboard's own answers had something for the text at the
    /// last look (a sum, a unit, a date), whatever the strip policy let show.
    private var smartFound = false

    /// The smart strip: a sum you just typed, a conversion, the saved detail
    /// the sentence is asking for, or what was just copied, as one chip.
    private func updateSmartChip() -> Bool {
        smartFound = false
        guard surface == .none, !isSecureField else {
            toolbar.showSmart(nil)
            return false
        }
        let before = beforeContext ?? ""
        // The chip that was up: typed past it? (StripPolicy)
        if let doc = documentID { stripPolicy.enter(field: doc.uuidString) }
        switch stripPolicy.observe(before: before, now: Date().timeIntervalSince1970) {
        case .nothing, .ignored: break
        case .pasteIgnored:
            // A copy shows once: typed past, it is done.
            ClipContext.markDone()
            cachedPaste = nil
            lastClipProbe = 0
        }
        let tail = String(before.suffix(120))
        notePhrases(before)
        // Something just copied rides in the strip as one chip, never as a
        // second row: history's copy when we already have it, otherwise the
        // offer itself (tapping reads, which is the moment iOS asks).
        var paste = pasteOffer(tailEmpty: tail.isEmpty)
        // A digit pad can only take digits: a copied link is no offer there.
        if keyboardView.context.isPad, let p = paste,
           !p.allSatisfy({ $0.isNumber || "+-() .".contains($0) }) {
            paste = nil
        }
        let rates = RatesStore.shared.snapshot()
        let region = SettingsStore.current.region ?? Locale.current.region?.identifier
        let vault = VaultStore.shared.load()
        var chip = Smart.chip(for: tail, fields: vault.fields,
                              paste: paste, field: fieldHint(emptyField: before.isEmpty),
                              rates: rates,
                              indianGrouping: (region ?? "") == "IN",
                              region: region,
                              linkContext: String(before.suffix(2048)))
        // The person's own shorthand of the same name wins over ";date".
        if case .convert(let c)? = chip, Smart.builtInShortcuts.contains(c.source),
           Shorthand.expansion(for: c.source, in: vault) != nil {
            chip = nil
        }
        // An amount with no rate yet: ask for the day's rates; the strip is
        // arranged again when they land. A character test first: the
        // patterns can't match without a digit.
        if chip == nil, hasFullAccess, tail.contains(where: \.isNumber),
           Smart.looksLikeMoney(tail) || Smart.currencyPair(in: tail) != nil {
            RatesStore.shared.ensureFiat { [weak self] in self?.updateCandidates() }
        }
        if let c = chip, c.copiedText == nil { smartFound = true }
        return present(chip)
    }

    // MARK: Strip policy

    /// Shows the chip if the policy lets it come now; otherwise the word
    /// slots keep the strip (and a pause brings the chip back for another look).
    private func present(_ chip: Smart.Chip?) -> Bool {
        guard let chip else {
            toolbar.showSmart(nil)
            return false
        }
        let kind = Self.policyKind(chip)
        let id = Self.policyID(chip)
        let now = Date().timeIntervalSince1970
        guard StripPolicy.allowed(kind, in: policyField),
              stripPolicy.allows(kind, id: id, now: now) else {
            toolbar.showSmart(nil)
            return false
        }
        let before = beforeContext
        let word = WordTracker.currentWord(beforeContext: before)
        let policy = typingPolicy
        let midWord = !word.isEmpty && (word.first?.isLetter ?? false)
            && SettingsStore.current.candidates && policy.contains(.suggestions)
            && !WordTracker.insideLinkOrAddress(beforeContext: before)
        let typing = StripPolicy.Typing(
            sinceEdit: CACurrentMediaTime() - lastEditAt,
            midWord: midWord,
            undoOnOffer: word.isEmpty && undoableCorrection(before: before) != nil,
            fixPending: { [weak self] in
                self?.suggestions(for: word, before: before, policy: policy)?.autocorrect != nil
            })
        switch stripPolicy.timing(kind, id: id, typing: typing) {
        case .now:
            toolbar.showSmart(chip)
            stripPolicy.shown(kind, id: id, before: before ?? "", now: now)
            return true
        case .wait(let seconds):
            toolbar.showSmart(nil)
            recheckChip(after: seconds)
            return false
        case .words:
            toolbar.showSmart(nil)
            return false
        }
    }

    private func recheckChip(after seconds: TimeInterval) {
        chipRecheck?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.chipRecheck = nil
            self?.updateCandidates()
        }
        chipRecheck = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds + 0.02, execute: work)
    }

    /// A chip tapped: wanted.
    private func noteChipUsed(_ chip: Smart.Chip) {
        stripPolicy.used()
    }

    /// Passwords get nothing; codes, cards and digit pads only what they
    /// are for (a saved detail, a copy).
    private var policyField: StripPolicy.Field {
        if isSecureField { return .secret }
        if let type = fieldContentType {
            if [.password, .newPassword].contains(type) { return .secret }
            if [.oneTimeCode, .creditCardNumber].contains(type) { return .code }
        }
        if keyboardView.context.isPad { return .code }
        switch textDocumentProxy.keyboardType {
        case .numberPad?, .decimalPad?, .phonePad?, .asciiCapableNumberPad?: return .code
        default: return .normal
        }
    }

    static func policyKind(_ chip: Smart.Chip) -> StripPolicy.Kind {
        if chip.copiedText != nil { return .paste }
        switch chip {
        case .calc, .money, .convert: return .answer
        case .vault, .details: return .fill
        case .paste, .action: return .paste
        }
    }

    /// The same chip for the same text: its kind and what it offers.
    static func policyID(_ chip: Smart.Chip) -> String {
        "\(chipKind(chip))|\(chip.value)"
    }

    private static func chipKind(_ chip: Smart.Chip) -> String {
        switch chip {
        case .calc: return "calc"
        case .money: return "money"
        case .vault(let f): return "vault:\(f.kind)"
        case .details(let fields, _): return "vault:\(fields.first?.kind ?? "")"
        case .convert: return "convert"
        case .paste: return "paste"
        case .action: return "action"
        }
    }

    /// What the focused field is asking for. iOS tells a keyboard extension
    /// nothing about labels, so this reads the signals it does give: the
    /// keyboard type, and for names the pairing of word-capitalisation with a
    /// Next key. (Android reads the real hint — see Autofill.kt.)
    private func fieldHint(emptyField: Bool) -> Smart.FieldHint {
        guard !isSecureField else { return .none }
        let proxy = textDocumentProxy
        var kind: String?
        // What the field says it holds, when the app or the website declares
        // it (autocomplete="email", "postal-code", "given-name"): iOS shares
        // that much with a keyboard, never a field's label or placeholder
        // (measured 2026-10-02 on iOS 26.5; user: "if field says email, we
        // can suggest"). Phone fields never come: iOS shows its own pad there.
        switch fieldContentType {
        case .emailAddress?, .username?: kind = "email"
        case .telephoneNumber?: kind = "phone"
        // A card box offers the saved card (shown as its last four).
        case .creditCardNumber?: kind = "card"
        case .fullStreetAddress?, .streetAddressLine1?: kind = "address"
        case .postalCode?: kind = "postcode"
        // City and state come out of the saved address (research 2026-10-07:
        // forms ask for them one box at a time).
        case .addressCity?: kind = "city"
        case .addressState?: kind = "state"
        case .addressCityAndState?: kind = "cityState"
        case .name?, .nickname?: kind = "name"
        case .givenName?: kind = "givenName"
        case .familyName?: kind = "familyName"
        // A search box (Safari's address bar) is asking what to look for,
        // not for your link, whatever it declares.
        case .URL?: kind = proxy.keyboardType == .webSearch ? nil : "link"
        case .organizationName?: kind = "company"
        default: break
        }
        if kind == nil {
            switch proxy.keyboardType {
            case .emailAddress: kind = "email"
            case .phonePad, .namePhonePad: kind = "phone"
            // A web address field may want your site; a search box (Safari's
            // address bar) is asking what to look for, not for your link.
            case .URL: kind = "link"
            default: break
            }
        }
        if kind == nil, proxy.autocapitalizationType == .words,
           proxy.returnKeyType == .next {
            kind = "name"
        }
        return Smart.FieldHint(kind: kind, empty: emptyField)
    }

    /// The field's declared content type, kept for the field: iOS can say it
    /// once and nil on a later read of the same field.
    private var contentTypeSeen: (doc: UUID, type: UITextContentType)?
    private var fieldContentType: UITextContentType? {
        let proxy = textDocumentProxy
        guard let doc = documentID else { return proxy.textContentType ?? nil }
        if let type = proxy.textContentType ?? nil {
            contentTypeSeen = (doc, type)
            return type
        }
        if let seen = contentTypeSeen, seen.doc == doc { return seen.type }
        return nil
    }

    /// The field's document, or nil between fields. Swift reads the proxy's
    /// documentIdentifier as a UUID that is always there, and the nil iOS
    /// hands back while moving between web form fields crashed the keyboard
    /// (2026-10-02), so it is asked for without bridging.
    private var documentID: UUID? {
        let proxy = textDocumentProxy as AnyObject
        let getter = NSSelectorFromString("documentIdentifier")
        guard proxy.responds(to: getter),
              let id = proxy.perform(getter)?.takeUnretainedValue() as? NSUUID else { return nil }
        return id as UUID
    }

    private func updateCandidates() {
        // A scheduled pass is now redundant, whoever asked for this one.
        candidatesWork?.cancel()
        candidatesWork = nil
        let tC = Perf.mark()
        defer {
            Perf.say("candidates=\(Perf.ms(tC))ms chip=\(self.tChip)ms engine=\(self.tEngine)ms strip=\(self.tStrip)ms")
            Perf.reportHostReads() // end of the cycle: the whole keystroke's crossings
        }
        lastSeenField = fieldSignature
        noteEmojiRuns(beforeContext ?? "")
        let tCh = Perf.mark()
        let chipOwns = updateSmartChip()
        tChip = Perf.ms(tCh)
        // AIRKEY's agents read the whole field: a command, a price, a sum.
        refreshAgent()
        if chipOwns { return }            // one chip owns the strip
        let policy = typingPolicy
        guard SettingsStore.current.candidates, policy.contains(.suggestions), surface == .none else {
            toolbar.showSuggestions([])
            return
        }
        let before = beforeContext
        let word = WordTracker.currentWord(beforeContext: before)
        if word.isEmpty {
            if let corr = undoableCorrection(before: before) {
                // Apple's way: what was typed, in quotes, in the first slot; a
                // tap puts it back and teaches the engine. The next words
                // keep the other two slots once the space is in.
                var items: [KeyToolbar.Suggestion] = [.init(text: corr.original, kind: .undo)]
                if let engine = typing, corr.tail == " ",
                   let previous = WordTracker.previousWord(beforeContext: before) {
                    items += engine.predictions(
                        previous: previous, beforePrevious: WordTracker.wordBeforePrevious(beforeContext: before),
                        policy: policy).prefix(2).map { KeyToolbar.Suggestion(text: $0, kind: .word) }
                }
                toolbar.showSuggestions(items)
            } else if let engine = typing, before?.hasSuffix(" ") == true,
                      let previous = WordTracker.previousWord(beforeContext: before) {
                // After "pay", "send" or "to": who to, from your contacts.
                let people = Protections.contacts(typed: "", after: previous)
                if !people.isEmpty {
                    toolbar.showSuggestions(people.prefix(3).map { .init(text: $0, kind: .contact) })
                    return
                }
                let beforePrevious = WordTracker.wordBeforePrevious(beforeContext: before)
                var words = engine.predictions(previous: previous, beforePrevious: beforePrevious, policy: policy)
                // A sentence the person keeps sending offers its next word
                // first: a word at a time, never the rest as a phrase.
                if policy.contains(.learning), let next = PhraseMemoryStore.shared.memory.nextWord(
                    after: String((before ?? "").suffix(120)), today: TypingText.day()) {
                    words = [next] + words.filter { $0.lowercased() != next.lowercased() }
                }
                var items = words.map { KeyToolbar.Suggestion(text: $0, kind: .word) }
                // The word just finished brings its emoji to the last slot:
                // the run this person puts there before the table's guess.
                if let e = engine.emojiRun(after: previous, previous: beforePrevious, policy: policy)
                    ?? EmojiWords.emoji(for: previous) {
                    items = Array(items.prefix(2)) + [.init(text: e, kind: .emoji)]
                }
                toolbar.showSuggestions(items)
            } else {
                toolbar.showSuggestions([])
            }
            return
        }
        lastCorrection = nil
        // Inside a link, an email, a handle, a NEAR account or an amount the
        // letters are no word: "com" of alex@example.com, "near" of harshal.near.
        if WordTracker.insideLinkOrAddress(beforeContext: before) {
            toolbar.showSuggestions([])
            return
        }
        // "pay har": the contacts it could be, never a dictionary word.
        // "to har": the contact first, words beside it ("to have").
        let previousWord = WordTracker.previousWord(beforeContext: before)
        let people = Protections.contacts(typed: word, after: previousWord)
        let payee = previousWord.map { Protections.payVerbs.contains($0.lowercased()) } ?? false
        if !people.isEmpty, payee {
            toolbar.showSuggestions(people.prefix(3).map { .init(text: $0, kind: .contact) })
            return
        }
        let tE = Perf.mark()
        let sMaybe = suggestions(for: word, before: before, policy: policy)
        tEngine = Perf.ms(tE)
        guard let s = sMaybe else {
            toolbar.showSuggestions([])
            return
        }
        let tSt = Perf.mark()
        defer { tStrip = Perf.ms(tSt) }
        // The word being typed is never one of the three: the fix in bold,
        // then other words, all of them somewhere to go. Keeping a word the
        // space bar would fix is a backspace right after it (the undo chip),
        // which also teaches it.
        let others = s.alternatives.map { KeyToolbar.Suggestion(text: $0, kind: .word) }
        var items: [KeyToolbar.Suggestion]
        if let fix = s.autocorrect {
            // With "Correct automatically" off the space keeps the word, so
            // the fix is offered as a plain word rather than promised in bold.
            let fixKind: KeyToolbar.Suggestion.Kind =
                SettingsStore.current.autocorrectApply == false ? .word : .correction
            items = [.init(text: fix, kind: fixKind)] + others.prefix(2)
        } else {
            items = Array(others.prefix(3))
            // A word typed in full brings its emoji ("pizza" → 🍕) to the
            // last slot, the way Apple's bar does.
            if let e = typing?.emojiRun(after: word, previous: WordTracker.previousWord(beforeContext: before), policy: policy)
                ?? EmojiWords.emoji(for: word) {
                items = Array(items.prefix(2)) + [.init(text: e, kind: .emoji)]
            }
        }
        if let person = people.first {
            items = [.init(text: person, kind: .contact)] + items.filter { $0.text.lowercased() != person }.prefix(2)
        }
        toolbar.showSuggestions(items)
    }

    /// What the agents make of the whole field, and whether their strip is up.
    private func refreshAgent() {
        guard surface == .none, !isSecureField else { return }
        agent.read(agentFieldText, answered: smartFound)
        layoutAgent()
    }

    private func suggestions(for word: String, before: String?, policy: TypingEngine.Policy) -> TypingEngine.Suggestions? {
        guard let engine = typing else { return nil }
        // A number is not a misspelt word, and a ;trigger is on its way to
        // becoming shorthand: neither wants the dictionary's guesses.
        guard let first = word.first, !first.isNumber, first != ";" else { return nil }
        // "$near", "a_b", "#tag": not words either.
        guard !word.contains(where: { !$0.isLetter && $0 != "'" && $0 != "’" && $0 != "-" }) else { return nil }
        let head = String((before ?? "").dropLast(word.count))
        // ";" splits words, so a trigger reaches here as "otw" with the
        // semicolon just before it.
        if head.last == ";" { return nil }
        let previous = WordTracker.previousWord(beforeContext: before)
        var policy = policy
        // Money and names are left exactly as typed: contacts, accounts,
        // token symbols, command words and words taught by an undo.
        if Protections.isProtected(word, after: previous) { policy.remove(.autocorrect) }
        return engine.suggestions(
            typed: word,
            touches: wordTouchesFor == word ? wordTouches : nil,
            previous: previous,
            beforePrevious: WordTracker.wordBeforePrevious(beforeContext: before),
            sentenceStart: WordTracker.wantsCapital(beforeContext: head),
            policy: policy)
    }

    /// A word just ended (space, punctuation, return): expand a text
    /// replacement, or autocorrect it when the engine is sure, then learn
    /// what was actually kept.
    private func commitCurrentWord() {
        let before = beforeContext
        let word = WordTracker.currentWord(beforeContext: before)
        defer {
            wordTouches = []
            wordTouchesFor = ""
        }
        guard !word.isEmpty else { return }
        // A link, an email or a handle: its parts are not words to fix or learn.
        if WordTracker.insideLinkOrAddress(beforeContext: before) { return }
        let policy = typingPolicy
        let previous = WordTracker.previousWord(beforeContext: before)
        let head = String((before ?? "").dropLast(word.count))
        let sentenceStart = WordTracker.wantsCapital(beforeContext: head)

        if !policy.isEmpty, let phrase = TypingStore.shared.replacements[word.lowercased()] {
            replaceCurrentWord(with: phrase)
            lastCorrection = Correction(original: word, replacement: phrase, fromEngine: false)
            return
        }
        guard let engine = typing else { return }
        var kept = word
        // What this word may teach: a typo left standing teaches nothing.
        var learn = policy
        recentFixes.removeAll { Date().timeIntervalSince($0.at) > 300 }
        if let i = recentFixes.firstIndex(where: { $0.touched && $0.original.lowercased() == word.lowercased() }) {
            // Corrected, gone back into, and typed the same again: keep it.
            let refused = recentFixes.remove(at: i)
            if policy.contains(.learning) { engine.revert(typed: word, correction: refused.replacement) }
        } else if policy.contains(.autocorrect),
           let fix = suggestions(for: word, before: before, policy: policy)?.autocorrect, fix != word {
            // "Correct automatically" off: the word stands exactly as typed.
            // The strip is already offering the fix, so a tap still takes it
            // — nothing is changed behind the writer's back.
            if SettingsStore.current.autocorrectApply != false {
                replaceCurrentWord(with: fix)
                lastCorrection = Correction(original: word, replacement: fix, fromEngine: true)
                recentFixes.append(RecentFix(original: word, replacement: fix, at: Date()))
                if recentFixes.count > 8 { recentFixes.removeFirst(recentFixes.count - 8) }
                kept = fix
                // A capital typed mid-sentence was meant: twice, and it's a name.
                engine.noteCorrected(typed: word, fix: fix, sentenceStart: sentenceStart, policy: policy)
            } else {
                // Left standing but not chosen: typed twice it would become a
                // word and never be fixed again (RESEARCH-IMPROVEMENTS-APP 12).
                learn.remove(.learning)
            }
        } else if !policy.contains(.autocorrect), policy.contains(.learning), learnsOnlyWordsItWouldKeep,
                  engine.wouldFix(word, previous: previous,
                                  beforePrevious: WordTracker.wordBeforePrevious(beforeContext: before),
                                  sentenceStart: sentenceStart) {
            // Autocorrect switched off: what it would have fixed is a typo,
            // not a word to learn.
            learn.remove(.learning)
        }
        let autoCapitalized = sentenceStart && SettingsStore.current.autocapitalize
            && textDocumentProxy.autocapitalizationType != UITextAutocapitalizationType.none
        engine.commit(word: kept, previous: previous, autoCapitalized: autoCapitalized, policy: learn)
        TypingStore.shared.scheduleSave()
    }

    /// Replace the word being typed (suggestions, autocorrect, replacements).
    private func replaceCurrentWord(with replacement: String) {
        let word = WordTracker.currentWord(
            beforeContext: beforeContext)
        hostDelete(word.count)
        hostInsert(replacement)
    }

    // MARK: Why there is no underline under a flagged word
    //
    // `UITextDocumentProxy` does carry `setMarkedText` — the provisional run
    // an IME composes in — and it works: marking a word and reading back
    // `documentContextBeforeInput` returns the text WITHOUT it, which is
    // exactly what a composing run should do.
    //
    // That is also why it cannot be used here. Everything this keyboard
    // knows about what you are writing comes from that context: the word
    // being typed, the previous word, whether a sentence is starting. Mark
    // the current word and the keyboard stops being able to see it.
    //
    // And it buys nothing: Messages draws no underline under marked text, so
    // the flag is invisible in the very place it was meant for. The honest
    // version of "don't change my words" is the one that ships — with
    // "Correct automatically" off the word stands exactly as typed and the
    // strip offers the fix for a tap.

    /// Put back what was typed before the last correction; an engine
    /// correction is never offered for that word again.
    @discardableResult
    private func undoLastCorrection() -> Bool {
        guard let corr = undoableCorrection(before: beforeContext), let before = beforeContext,
              let undo = WordTracker.undo(before: before, original: corr.original,
                                          replacement: corr.replacement, tail: corr.tail) else { return false }
        hostDelete(undo.delete)
        hostInsert(undo.insert)
        lastCorrection = nil
        teachUndo(corr)
        return true
    }

    /// `ch` just went in after a word: a correction it made is undoable from
    /// here, and one it follows (`extending`, undoable just before it) moves
    /// its anchor here while what came after the fix is only marks and one
    /// space. Reads the host only when there is a correction to anchor.
    private func anchorCorrection(after ch: Character, extending: Correction?) {
        guard let corr = lastCorrection else { return }
        if corr.anchor == nil {
            lastCorrection?.anchor = beforeContext
            lastCorrection?.tail = String(ch)
        } else if let extending, let tail = WordTracker.undoTail(extending.tail, adding: ch) {
            lastCorrection?.anchor = beforeContext
            lastCorrection?.tail = tail
        }
    }

    /// An undone engine correction is never offered for that word again,
    /// and the word is kept (the "retype teaches" logic, PersonalLexicon.revert).
    private func teachUndo(_ corr: Correction) {
        guard corr.fromEngine, typingPolicy.contains(.learning) else { return }
        typing?.revert(typed: corr.original, correction: corr.replacement)
        Protections.learn(corr.original)
        TypingStore.shared.scheduleSave()
    }
}

// MARK: - KeyboardViewDelegate

extension KeyboardViewController: KeyboardViewDelegate {

    func kbInsert(_ text: String) {
        if let editor = inlineTarget {
            editor.append(text)
            return
        }
        // The host round trip below is the costliest part of a keystroke, so
        // it happens at most once: what the field will hold afterwards is
        // just what it held plus this character.
        let t0 = Perf.mark()
        var tHost: Double = 0
        var before: String?
        var readBefore = false
        /// A fix this punctuation makes, or one whose punctuation it follows
        /// ("teh!?"), stays undoable with the marks after it.
        var punctuation: Character?
        var extending: Correction?
        if text.count == 1, let ch = text.first {
            if WordTracker.correctionBoundaries.contains(ch) {
                punctuation = ch
                if lastCorrection?.anchor != nil { extending = undoableCorrection(before: beforeContext) }
                // Punctuation ends the word: correct it before the mark lands.
                commitCurrentWord()
            } else if !WordTracker.boundaries.contains(ch) || ch == "'" || ch == "’" {
                let th = Perf.mark()
                before = beforeContext
                tHost = Perf.ms(th)
                readBefore = true
                let current = WordTracker.currentWord(beforeContext: before)
                if current != wordTouchesFor {
                    wordTouches = Array(repeating: nil, count: current.unicodeScalars.count)
                }
                wordTouches.append(keyboardView.lastTapOffset)
                wordTouchesFor = current + text
            }
        }
        let tI = Perf.mark()
        hostInsert(text)
        let tInsert = Perf.ms(tI)
        if let ch = punctuation { anchorCorrection(after: ch, extending: extending) }
        let tS = Perf.mark()
        syncAutoShift(knownBefore: readBefore ? (before ?? "") + text : nil)
        let tShift = Perf.ms(tS)
        scheduleCandidates()
        Perf.say("key total=\(Perf.ms(t0))ms host=\(tHost)ms insert=\(tInsert)ms shift=\(tShift)ms")
    }

    func kbDeleteBackward() {
        if let editor = inlineTarget {
            editor.deleteBackward()
            return
        }
        // Right after a glide, one backspace takes the whole word (iOS's way).
        if glideBackspace() { return }
        // Backspace right after a correction puts back what was typed (and
        // teaches the engine to leave that word alone).
        // After a fix made by punctuation ("the,") backspace deletes as usual.
        if let corr = undoableCorrection(before: beforeContext), corr.tail == " " {
            hostDelete(corr.replacement.count + 1)
            hostInsert(corr.original)
            lastCorrection = nil
            teachUndo(corr)
        } else {
            lastCorrection = nil
            hostDelete()
        }
        // One read of the host's text, reused below: the delete has already
        // happened, so this IS what the field holds now.
        let before = beforeContext
        let current = WordTracker.currentWord(beforeContext: before)
        // Backing into a word the engine corrected ("cute" → "cut"): if the
        // original comes back, that correction was a mistake.
        if current.count >= 2 {
            let lower = current.lowercased()
            for i in recentFixes.indices where recentFixes[i].replacement.lowercased().hasPrefix(lower) {
                recentFixes[i].touched = true
            }
        }
        if wordTouches.count > current.unicodeScalars.count {
            wordTouches.removeLast(wordTouches.count - current.unicodeScalars.count)
        }
        wordTouchesFor = current
        syncAutoShift(knownBefore: before)
        scheduleCandidates()
    }

    func kbSpaceTapped() {
        if let editor = inlineTarget {
            editor.append(" ")
            return
        }
        // A glide already put its space in after the word: a space tapped
        // right after it is taken as "yes, that word", never a second space
        // ("Swap  1 near"), the way iOS absorbs it.
        if let g = glide {
            glide = nil
            glideStrip = nil
            if g.isCurrent(before: beforeContext), (beforeContext ?? "").hasSuffix(g.word + " ") {
                scheduleCandidates()
                return
            }
        }
        let s = SettingsStore.current
        let now = Date()
        // Double-space → ". " (§6.1)
        if s.periodShortcut, now.timeIntervalSince(lastSpaceTap) < 0.45,
           WordTracker.canPeriodShortcut(beforeContext: beforeContext) {
            hostDelete()
            hostInsert(". ")
            lastSpaceTap = .distantPast
            syncAutoShift()
            scheduleCandidates()
            return
        }
        lastSpaceTap = now

        // §6.7 shorthand: ;sig-style triggers expand on the space commit,
        // before autocorrect gets a look. Undo works like autocorrect undo.
        if !isSecureField,
           let token = Shorthand.pendingToken(
               beforeContext: beforeContext),
           let expansion = Shorthand.expansion(for: token, in: VaultStore.shared.load()) {
            let filled = fillShorthand(expansion)
            hostDelete(token.count)
            hostInsert(filled.text)
            if filled.back > 0 {
                // {cursor}: typing goes on inside what was typed out.
                textDocumentProxy.adjustTextPosition(byCharacterOffset: -filled.back)
            } else {
                lastCorrection = Correction(original: token, replacement: filled.text, fromEngine: false)
                hostInsert(" ")
                lastCorrection?.anchor = beforeContext
                lastCorrection?.tail = " "
            }
            syncAutoShift()
            scheduleCandidates()
            return
        }

        // A full stop doesn't end a word as it is typed (it is part of NEAR
        // accounts like harshal.near), so the last word of a sentence is
        // fixed on the space after it: "teh." then space is "the. ".
        if WordTracker.endsOnFullStop(beforeContext: beforeContext) {
            hostDelete(1)
            commitCurrentWord()
            hostInsert(".")
            anchorCorrection(after: ".", extending: nil)
            let extending = lastCorrection?.anchor != nil ? undoableCorrection(before: beforeContext) : nil
            hostInsert(" ")
            anchorCorrection(after: " ", extending: extending)
            syncAutoShift()
            scheduleCandidates()
            return
        }

        // Autocorrect + learning on commit (§6.1, Engine/Typing) — the
        // policy keeps secure fields untouched (§11.9).
        // "teh," then space: the fix stays undoable with its comma and space.
        let extending = lastCorrection?.anchor != nil ? undoableCorrection(before: beforeContext) : nil
        commitCurrentWord()
        hostInsert(" ")
        // A correction this space just made is undoable from here only.
        anchorCorrection(after: " ", extending: extending)
        syncAutoShift()
        scheduleCandidates()
    }

    func kbReturnTapped() {
        if inlineTarget != nil, surface == .emoji {
            // Return = done searching: emoji go back to the full grid, a
            emoji?.returnPressed()
            return
        }
        if inlineTarget != nil, surface == .noteEdit {
            // A new line in a note, on from a shortcut, Save for a detail.
            noteEdit?.returnPressed()
            return
        }
        if inlineTarget != nil, surface == .ai {
            // Return asks, as the arrow does.
            aiBar?.submitAsk()
            return
        }
        if let editor = inlineTarget {
            editor.isActive = false
            inlineTarget = nil
            return
        }
        commitCurrentWord()
        // Return may send the message: what it said is the sentence to
        // remember, whatever the strip last saw (PhraseMemory).
        if let said = beforeContext, !said.isEmpty { phraseSeen = said }
        hostInsert("\n")
        syncAutoShift()
        updateCandidates()
    }

    func kbReturnHeld() {
        // In the keyboard's own editors, a hold is a tap.
        guard inlineTarget == nil else { return kbReturnTapped() }
        commitCurrentWord()
        // A "send" field sends on any "\n" it's given; a line separator
        // still breaks the line and isn't caught as Return.
        hostInsert(textDocumentProxy.returnKeyType == .send ? "\u{2028}" : "\n")
        syncAutoShift()
        updateCandidates()
    }

    func kbGlobe(event: UIEvent?, key: KeyView, longPress: Bool) {
        if longPress, let event {
            handleInputModeList(from: key, with: event)
        } else {
            advanceToNextInputMode()
        }
    }

    func kbOpenEmoji() {
        setSurface(.emoji)
    }

    // MARK: Cursor glide (space-bar trackpad)

    func kbCursorGlideBegan() {
        cursorMirror = currentCursorMirror()
    }

    func kbMoveCursor(graphemes: Int) {
        // The proxy's context lags a move by a frame or two, so it's only
        // re-read once the mirror has run out AND the host has had time.
        if cursorMirror?.isStale ?? true,
           CACurrentMediaTime() - lastCursorAdjust > 0.15 {
            cursorMirror = currentCursorMirror()
        }
        let offset = cursorMirror?.offset(forGraphemes: graphemes) ?? graphemes
        guard offset != 0 else { return }
        hostAdjust(byCharacterOffset: offset)
        lastCursorAdjust = CACurrentMediaTime()
    }

    func kbSpaceGestures() -> (glide: Bool, bar: Bool) {
        (glide: inlineTarget == nil, bar: inlineTarget == nil && !isSecureField)
    }

    func kbBindingsLive() -> Bool {
        inlineTarget == nil && !isSecureField
    }

    func kbCursorGlideEnded() {
        cursorMirror = nil
        // Keyboard-driven moves don't come back as textDidChange, so caps
        // and candidates re-read the new position once the host settles.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.syncAutoShift()
            self?.updateCandidates()
        }
    }

    private func currentCursorMirror() -> CursorMirror {
        CursorMirror(before: beforeContext ?? "",
                     after: textDocumentProxy.documentContextAfterInput ?? "")
    }

    // MARK: Glide typing

    func kbGlideAllowed() -> Bool {
        inlineTarget == nil && !isSecureField && typingPolicy.contains(.suggestions)
    }

    func kbGlideMoved(_ points: [GlidePoint], layout: GlideDecoder.Layout) -> String? {
        glideDecode(points, layout: layout, limit: 1).first?.word
    }

    /// The lift: the best guess goes in with a space after it, as a tapped
    /// suggestion does, and the other guesses wait in the strip. A word
    /// being typed is finished first, the way the space bar would.
    func kbGlideEnded(_ points: [GlidePoint], layout: GlideDecoder.Layout) {
        let guesses = glideDecode(points, layout: layout, limit: 4).map(\.word)
        guard let word = guesses.first else { return }
        let before = beforeContext
        let typing = WordTracker.currentWord(beforeContext: before)
        if !typing.isEmpty {
            commitCurrentWord()
            hostInsert(" ")
        }
        let previous = typing.isEmpty ? WordTracker.previousWord(beforeContext: before) : typing
        let capitalized = keyboardView.shift == .on
        hostInsert(word + " ")
        lastCorrection = nil
        wordTouches = []
        wordTouchesFor = ""
        let anchor = beforeContext ?? ""
        glide = GlideState(word: word, alternatives: Array(guesses.dropFirst()), anchor: anchor)
        glideStrip = (anchor, Array(guesses.dropFirst()))
        self.typing?.commit(word: word, previous: previous, autoCapitalized: capitalized, policy: typingPolicy)
        TypingStore.shared.scheduleSave()
        syncAutoShift(knownBefore: anchor)
        scheduleCandidates()
    }

    /// The decoder over the base dictionary, once the engine has loaded it.
    private func glideDecoderReady() -> GlideDecoder? {
        if glideDecoder == nil, let base = typing?.base { glideDecoder = GlideDecoder(trie: base) }
        return glideDecoder
    }

    /// The words before the caret, the capitals the board shows, and this
    /// person's own words, for the decoder's language side.
    private func glideDecode(_ points: [GlidePoint], layout: GlideDecoder.Layout, limit: Int) -> [GlideDecoder.Candidate] {
        guard let engine = typing, let decoder = glideDecoderReady() else { return [] }
        let before = beforeContext
        let current = WordTracker.currentWord(beforeContext: before)
        var context = GlideDecoder.Context()
        if current.isEmpty {
            context.previous = WordTracker.previousWord(beforeContext: before)
            context.beforePrevious = WordTracker.wordBeforePrevious(beforeContext: before)
        } else {
            // The glide finishes that word first, so it becomes the previous one.
            context.previous = current
            context.beforePrevious = WordTracker.previousWord(beforeContext: before)
        }
        switch keyboardView.shift {
        case .capsLock: context.capitals = .all
        case .on: context.capitals = .first
        case .off: break
        }
        context.personal = engine.personal
        return decoder.decode(points, layout: layout, context: context, limit: limit)
    }

    /// The glide's other guesses, while the caret is still right after it;
    /// false once anything else happened, and the usual strip takes over.
    private func showGlideStrip() -> Bool {
        guard let strip = glideStrip else { return false }
        guard surface == .none, beforeContext == strip.anchor, !strip.words.isEmpty else {
            glideStrip = nil
            return false
        }
        toolbar.showSuggestions(strip.words.prefix(3).map { .init(text: $0, kind: .word) })
        return true
    }

    /// One backspace right after a glide removes the word and its space and
    /// offers it and the other guesses back; the next backspace is ordinary.
    private func glideBackspace() -> Bool {
        guard let g = glide else { return false }
        glide = nil
        guard g.isCurrent(before: beforeContext) else { return false }
        hostDelete(g.deleteCount)
        let anchor = beforeContext ?? ""
        glideStrip = (anchor, [g.word] + g.alternatives)
        syncAutoShift(knownBefore: anchor)
        scheduleCandidates()
        return true
    }

    /// A tap on another guess swaps the glided word for it.
    private func glideSwap(_ suggestion: KeyToolbar.Suggestion) -> Bool {
        // Only one of the glide's own guesses: a next-word prediction shown
        // in the same slots (after a panel closed, say) is a new word.
        guard suggestion.kind == .word, let g = glide, g.isCurrent(before: beforeContext),
              g.alternatives.contains(suggestion.text) else { return false }
        hostDelete(g.deleteCount)
        hostInsert(suggestion.text + " ")
        let anchor = beforeContext ?? ""
        let others = g.others(after: suggestion.text)
        glide = GlideState(word: suggestion.text, alternatives: others, anchor: anchor)
        glideStrip = (anchor, others)
        typing?.commit(word: suggestion.text, previous: g.previousWord, autoCapitalized: false, policy: typingPolicy)
        TypingStore.shared.scheduleSave()
        syncAutoShift(knownBefore: anchor)
        scheduleCandidates()
        return true
    }

    func kbSpaceHoldIgnited(origin: KeyView) {
        // Holding space opens the AI bar once the ripple has had its beat,
        // the way a held key opens its surface.
        let delay = Glass.reduceMotion ? Glass.Ripple.reducedMotionFlash
                                       : Glass.Ripple.surfaceRiseDelay
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.openAI()
        }
    }

    /// The AI bar on the text before the cursor: our own copy, which reaches
    /// past the sentence iOS shows a keyboard. Never in a password field.
    private func openAI() {
        guard !isSecureField, surface == .none else { return }
        let before = String((beforeContext ?? "").suffix(AIBar.maxSource))
        setSurface(.ai)
        aiBar?.present(before: before, hasFullAccess: hasFullAccess)
        applySurfaceLayout(animated: true)
    }

    func kbBoundKeyIgnited(keyId: String, target: String, origin: KeyView) {
        let delay = Glass.reduceMotion ? Glass.Ripple.reducedMotionFlash
                                       : Glass.Ripple.surfaceRiseDelay
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.runBinding(target)
        }
    }

    /// What a held key opens: a menu screen ("surface:notes").
    private func runBinding(_ target: String) {
        // Glyf Keys (Engine/KeyBindings): a strip tool, or words typed ("pay ").
        if let tool = KeyBindings.tool(in: target) { return openTool(tool) }
        if let words = KeyBindings.words(in: target) { return agentInsert(words, spaced: true) }
        guard target.hasPrefix("surface:") else { return }
        if surface != .shell { setSurface(.shell) }
        shell?.push(String(target.dropFirst("surface:".count)))
    }

    /// Remembers each sentence the person finishes or sends, for
    /// PhraseMemory: a sentence ending in . ! ? and a space, or the field
    /// emptied after a message (sent). Never where learning is off.
    private func notePhrases(_ before: String) {
        defer { phraseSeen = before }
        guard before != phraseSeen, typingPolicy.contains(.learning) else { return }
        if let ended = PhraseMemory.endedSentence(in: before), !phraseSeen.hasSuffix(ended + " "), before.count > phraseSeen.count {
            PhraseMemoryStore.shared.record(ended)
        } else if before.isEmpty, phraseSeen.count >= 15,
                  (textDocumentProxy.documentContextAfterInput ?? "").isEmpty,
                  !phraseSeen.hasSuffix(" ") || PhraseMemory.endedSentence(in: phraseSeen) == nil {
            PhraseMemoryStore.shared.record(PhraseMemory.lastSentence(of: phraseSeen))
        }
    }

    /// The emoji run the person just finished after their words ("love you
    /// ❤️❤️❤️ ", or sent): one more use of that habit (EmojiRuns). Never
    /// where learning is off, so never in a password, code or search field.
    private func noteEmojiRuns(_ before: String) {
        defer {
            emojiSeen = before
            if before.isEmpty { emojiAnchor = nil } // the next message is a new one
        }
        guard before != emojiSeen, let engine = typing else { return }
        if before.isEmpty, !(textDocumentProxy.documentContextAfterInput ?? "").isEmpty { return }
        let policy = typingPolicy
        guard policy.contains(.learning), let run = EmojiRuns.finished(seen: emojiSeen, now: before),
              run.anchor != emojiAnchor else { return }
        emojiAnchor = run.anchor
        if engine.noteEmoji(run, policy: policy) { TypingStore.shared.scheduleSave() }
    }

    func kbTextInteraction() {}

    func kbLettersShown() { syncAutoShift() }
}

// MARK: - AgentHost (AIRKEY's agents)

// MARK: - WALLET/CALLS HOOK: what the Wallet and Calls panels may ask for

extension KeyboardViewController {

    /// The panels never type or send by themselves: words go in the message
    /// (where the strip reads them and offers its hold), a receipt goes in
    /// the chat, a link opens in Safari.
    fileprivate var moneyActions: MoneyActions {
        MoneyActions(
            fullAccess: { [weak self] in self?.hasFullAccess ?? false },
            insert: { [weak self] text in
                guard let self else { return }
                self.setSurface(.none)
                self.agent.insertOwn(text)
            },
            share: { [weak self] line in
                guard let self else { return }
                self.setSurface(.none)
                self.agent.insertOwn(line)
            },
            open: { [weak self] url, done in
                // A keyboard has no UIApplication of its own; with Full Access
                // the host app's is on the responder chain.
                var responder: UIResponder? = self
                while let r = responder {
                    if let app = r as? UIApplication {
                        app.open(url, options: [:]) { ok in DispatchQueue.main.async { done(ok) } }
                        return
                    }
                    responder = r.next
                }
                done(false)
            }
        )
    }
}

extension KeyboardViewController: AgentHost {

    /// The whole message being written: our own copy before the caret, plus
    /// whatever iOS shows after it.
    var agentFieldText: String {
        (beforeContext ?? "") + (textDocumentProxy.documentContextAfterInput ?? "")
    }

    var agentHasFullAccess: Bool { hasFullAccess }

    func agentInsert(_ text: String, spaced: Bool) {
        hostInsert(spaced ? Self.spaced(text, after: beforeContext) : text)
        lastCorrection = nil
        syncAutoShift()
        updateCandidates()
    }

    func agentReplaceTail(_ tail: String, with new: String) {
        let before = beforeContext ?? ""
        var count = 0
        var rest = Substring(before)
        while let last = rest.last, last.isWhitespace { rest = rest.dropLast(); count += 1 }
        guard rest.lowercased().hasSuffix(tail.lowercased()) else {
            agentInsert(new, spaced: true)
            return
        }
        hostDelete(count + tail.count)
        hostInsert(new)
        lastCorrection = nil
        syncAutoShift()
        updateCandidates()
    }

    /// The command was for the agent, not for the person in the chat: once
    /// it has run, take it out of the message box so it can't be sent by
    /// mistake. Only when the box still holds exactly what was run; a
    /// blocked command stays so it can be fixed.
    func agentClear(_ text: String) {
        let before = beforeContext ?? ""
        guard before.trimmingCharacters(in: .whitespacesAndNewlines) == text,
              (textDocumentProxy.documentContextAfterInput ?? "").isEmpty else { return }
        hostDelete(before.count)
        lastCorrection = nil
        syncAutoShift()
        updateCandidates()
    }
}

// MARK: - AIBarDelegate (hold space)

extension KeyboardViewController: AIBarDelegate {

    func aiBarClosed() {
        setSurface(.none)
        syncAutoShift()
    }

    func aiBarAskActivated(_ editor: InlineEditor?) {
        inlineTarget = editor
        // A question starts with a capital.
        if editor != nil { keyboardView.syncAutoShift(wantsCapital: true) }
    }

    func aiBarLayoutChanged() {
        applySurfaceLayout(animated: true)
    }

    /// Swaps exactly the text the answer was made from. If the field moved
    /// on since (it no longer ends with it), nothing is deleted: the answer
    /// goes in at the cursor instead.
    func aiBarReplace(source: String, with text: String) {
        let before = beforeContext ?? ""
        setSurface(.none)
        if !source.isEmpty, before.hasSuffix(source) {
            hostDelete(source.count)
            hostInsert(text)
        } else {
            hostInsert(Self.spaced(text, after: before))
        }
        aiWrote()
    }

    func aiBarInsert(_ text: String) {
        setSurface(.none)
        hostInsert(Self.spaced(text, after: beforeContext))
        aiWrote()
    }

    func aiBarCopy(_ text: String) {
        guard hasFullAccess else { return }
        UIPasteboard.general.string = text
        remember(copied: text)
        if let aiBar { KeyboardToast.show(in: aiBar, text: "Copied") }
    }

    private func aiWrote() {
        Haptics.success()
        lastCorrection = nil
        glide = nil
        syncAutoShift()
        updateCandidates()
    }
}

// MARK: - ClipboardPanelDelegate

extension KeyboardViewController: ClipboardPanelDelegate {
    func clipboardPanelClosed() { setSurface(.none) }

    func clipboardPanelPaste(_ text: String) {
        setSurface(.none)
        // A copy is its own piece of text: it never glues onto the word
        // before it ("10.8QvS…").
        hostInsert(Self.spaced(text, after: beforeContext))
        updateCandidates()
    }

    /// The system paste button handed content over. Reaching the clipboard
    /// this way is the ONE route iOS does not put a banner in front of: the
    /// tap IS the permission, so there is nothing to approve afterwards.
    func acceptPasted(_ providers: [NSItemProvider]) {
        guard let provider = providers.first else { return }
        if provider.canLoadObject(ofClass: String.self) {
            _ = provider.loadObject(ofClass: String.self) { [weak self] value, _ in
                guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else { return }
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.setSurface(.none)
                    ClipContext.markDone()
                    self.remember(copied: value)
                    self.hostInsert(Self.spaced(value, after: self.beforeContext))
                    self.updateCandidates()
                }
            }
            return
        }
        // An image cannot go into a host text box from any keyboard (the proxy
        // types text and nothing else), so it goes where it CAN be used again:
        // the notes, which are ours to draw.
        if provider.canLoadObject(ofClass: UIImage.self) {
            _ = provider.loadObject(ofClass: UIImage.self) { [weak self] value, _ in
                guard let image = value as? UIImage else { return }
                DispatchQueue.main.async { self?.keepImage(image) }
            }
        }
    }

    /// Saves a pasted or picked image into the notes and says where it went.
    func keepImage(_ image: UIImage, label: String = "Image") {
        // JPEG at 0.85: a screenshot keeps its text crisp and a photo lands
        // well under the cap, where the original PNG often would not.
        guard let data = image.jpegData(compressionQuality: 0.85) else {
            KeyboardToast.show(in: content, text: "Could not read that image")
            return
        }
        if let why = VaultStore.shared.addImage(data: data, label: label) {
            KeyboardToast.show(in: content, text: why)
            return
        }
        KeyboardToast.show(in: content, text: "Saved to Notes")
        shell?.render()
    }

    func clipboardPanelSavedToVault(refusal: String?) {
        KeyboardToast.show(in: content, text: refusal ?? "Saved to Notes")
    }

    func clipboardPanelCopiedImage() {
        // iOS lets no keyboard put an image in a text box: it is on the
        // clipboard, one hold of the box away.
        setSurface(.none)
    }

    /// Everything that arrives from the pasteboard lands in history first, so
    /// "what I copied earlier" is there even after the copy itself is gone.
    private func remember(copied text: String) {
        _ = ClipboardStore.inserting(text, into: ClipboardStore.load(), now: Date())
            .map(ClipboardStore.save)
    }
}

// MARK: - ToolbarDelegate

extension KeyboardViewController: ToolbarDelegate {

    func toolbarBrandTapped() {
        Haptics.layer()
        setSurface(surface == .shell ? .none : .shell)
    }

    func toolbarItemTapped(_ id: String) {
        Haptics.layer()
        openTool(id)
    }

    /// Every tool opens the same way from the strip and from the menu.
    private func openTool(_ requested: String) {
        let id = KeyboardSettings.Toolbar.canonical(requested)
        switch id {
        // AIRKEY: your NEAR account and saved addresses, in the strip.
        // WALLET/CALLS HOOK: the Wallet panel (the saved addresses are inside it, under Addresses).
        case "wallet": setSurface(.wallet)
        // The calls book: copied calls, open and done.
        case "calls": setSurface(.calls)
        // AIRKEY: what you copied, to the Inbox Agent.
        case "check": setSurface(.none); agent.runPasted()
        case "clipboard": setSurface(.clipboard)
        case "emoji": setSurface(.emoji)
        case "games": setSurface(.games)
        case "notes", "settings", "style":
            if id == "style" {
                let picked = textDocumentProxy.selectedText ?? ""
                MenuShell.styleSample = picked.isEmpty ? (beforeContext ?? "") : picked
            }
            if surface != .shell { setSurface(.shell) }
            shell?.push(id)
        default: break
        }
    }

    func toolbarItemLongPressed(_ id: String) {
        // A plain hold with no drag opens the place where the strip is
        // edited by hand.
        setSurface(.shell)
        shell?.push(id == "settings" ? "settings" : "toolbar")
    }

    // MARK: Strip customising (hold a tool, drag it)

    func toolbarItemDragBegan(_ id: String, at windowPoint: CGPoint) {
        beginToolDrag(id: id, icon: KeyToolbar.icons[id] ?? "square", at: windowPoint)
    }

    func toolbarItemDragMoved(to windowPoint: CGPoint) {
        moveToolDrag(to: windowPoint)
        // Over the menu's grid, the tiles open a slot where it would land.
        if let id = draggingToolId, shellAtMenu {
            shell?.stripToolHovered(id, at: toolbarContains(windowPoint) ? nil : windowPoint)
        }
    }

    func toolbarItemDragEnded(_ id: String, at windowPoint: CGPoint) {
        if toolbarContains(windowPoint) {
            shell?.stripToolHovered(id, at: nil)
            endToolDrag()
            SettingsStore.update { s in
                s.toolbarOrder.removeAll { $0 == id }
                let idx = min(max(0, toolbar.dropIndex(for: toolbar.convert(windowPoint, from: nil))),
                              s.toolbarOrder.count)
                s.toolbarOrder.insert(id, at: idx)
                s.toolbarHidden.removeAll { $0 == id }
            }
            toolbar.reloadItems()
            return
        }
        // Let go over the menu's grid, it lands in the slot it opened there
        // and the strip closes behind it; anywhere else it goes back.
        if shellAtMenu, let shell, let slot = shell.landStripTool(id, at: windowPoint) {
            SettingsStore.update { s in
                if !s.toolbarHidden.contains(id) { s.toolbarHidden.append(id) }
                s.toolbarOrder.removeAll { $0 == id }
                s.toolbarOrder.append(id)
            }
            toolbar.removeItem(id)
            shell.revealTile(id)
            settleToolDrag(into: slot)
        } else {
            shell?.stripToolHovered(id, at: nil)
            toolbar.settleItem(id)
            settleToolDrag(into: toolbar.itemFrame(id).map {
                CGRect(x: $0.midX - 22, y: $0.midY - 22, width: 44, height: 44)
            })
        }
    }

    func shellTileDragBegan(_ id: String, icon: String, at windowPoint: CGPoint) {
        beginToolDrag(id: id, icon: KeyToolbar.icons[id] ?? icon, at: windowPoint)
    }

    func shellTileDragMoved(to windowPoint: CGPoint) { moveToolDrag(to: windowPoint) }

    func shellTileDragEnded(at windowPoint: CGPoint) {
        guard let id = draggingToolId else { return }
        let inStrip = toolbarContains(windowPoint)
        endToolDrag()
        guard inStrip else { return }
        SettingsStore.update { s in
            s.toolbarHidden.removeAll { $0 == id }
            s.toolbarOrder.removeAll { $0 == id }
            let idx = min(max(0, toolbar.dropIndex(for: toolbar.convert(windowPoint, from: nil))),
                          s.toolbarOrder.count)
            s.toolbarOrder.insert(id, at: idx)
        }
        toolbar.reloadItems()
        setSurface(.none)
        KeyboardToast.show(in: content, text: "Added to the strip")
    }

    private func beginToolDrag(id: String, icon: String, at windowPoint: CGPoint) {
        draggingToolId = id
        let ghost = UIImageView(image: UIImage(systemName: icon))
        ghost.preferredSymbolConfiguration = .init(pointSize: 22, weight: .regular)
        ghost.tintColor = Glass.textPrimary
        ghost.contentMode = .center
        ghost.backgroundColor = Glass.surfaceCard
        ghost.layer.cornerRadius = 12
        ghost.layer.cornerCurve = .continuous
        ghost.layer.shadowColor = UIColor.black.cgColor
        ghost.layer.shadowOpacity = 0.18
        ghost.layer.shadowRadius = 8
        ghost.layer.shadowOffset = CGSize(width: 0, height: 3)
        ghost.bounds = CGRect(x: 0, y: 0, width: 44, height: 44)
        ghost.center = content.convert(windowPoint, from: nil)
        content.addSubview(ghost)
        dragGhost = ghost
        moveToolDrag(to: windowPoint)
    }

    private func moveToolDrag(to windowPoint: CGPoint) {
        dragGhost?.center = content.convert(windowPoint, from: nil)
        toolbar.showDropMarker(at: toolbarContains(windowPoint)
                               ? toolbar.convert(windowPoint, from: nil) : nil)
    }

    private func endToolDrag() {
        dragGhost?.removeFromSuperview()
        dragGhost = nil
        draggingToolId = nil
        toolbar.showDropMarker(at: nil)
    }

    /// The ghost settles on where the tool now lives (`target`, in window
    /// coordinates), fading into it; with nowhere to go it just goes.
    private func settleToolDrag(into target: CGRect?) {
        let ghost = dragGhost
        dragGhost = nil
        endToolDrag()
        guard let ghost else { return }
        guard let target, !Glass.reduceMotion else { return ghost.removeFromSuperview() }
        let to = content.convert(target, from: nil)
        UIView.animate(withDuration: 0.24, delay: 0, options: [.curveEaseInOut]) {
            ghost.bounds.size = to.size
            ghost.center = CGPoint(x: to.midX, y: to.midY)
            ghost.alpha = 0
        } completion: { _ in
            ghost.removeFromSuperview()
        }
    }

    private func toolbarContains(_ windowPoint: CGPoint) -> Bool {
        let p = toolbar.convert(windowPoint, from: nil)
        return toolbar.bounds.insetBy(dx: -8, dy: -10).contains(p)
    }

    func toolbarBackTapped() {
        shell?.back()
    }

    /// The strip's close button: whatever panel is open goes away.
    func toolbarCloseTapped() {
        setSurface(.none)
    }

    /// The ✕ on a chip. A copy is marked done and never offered again (it is
    /// still in the clipboard panel); anything else rests for a while.
    func toolbarSmartDismissed() {
        if let chip = toolbar.smartChip {
            stripPolicy.dismissed(Self.policyKind(chip), id: Self.policyID(chip),
                                  now: Date().timeIntervalSince1970)
        }
        if toolbar.smartIsPaste {
            ClipContext.markDone()
            // The paste probe keeps its copy for a second: forget it too, or
            // the chip comes straight back until the next key.
            cachedPaste = nil
            lastClipProbe = 0
        }
        toolbar.showSmart(nil)
        updateCandidates()
    }

    func toolbarSmartTapped(_ chip: Smart.Chip) {
        noteChipUsed(chip)
        switch chip {
        case .details, .convert:
            // Its parts are the actions (toolbarSmartChoiceTapped).
            return
        case .action:
            toolbar.showSmart(nil)
            return
        case .paste(let text):
            // History's copy types straight out; the placeholder means we do
            // not have the text yet, so the tap is the intent that reads it.
            ClipContext.markDone()
            if text == ClipboardStore.pastePlaceholder {
                ClipboardStore.readCopy { [weak self] read in
                    guard let self else { return }
                    guard let read, !read.isEmpty else {
                        self.toolbar.showSmart(nil)
                        return
                    }
                    self.remember(copied: read)
                    self.hostInsert(Self.spaced(read, after: self.beforeContext))
                    self.toolbar.showSmart(nil)
                    self.syncAutoShift()
                    self.updateCandidates()
                }
                return
            }
            hostInsert(Self.spaced(text, after: beforeContext))
        case .vault(let f):
            // After "email" or "my number is", with a space between.
            hostInsert(Self.spaced(f.value, after: beforeContext))
        case .calc, .money:
            hostInsert(chip.insert)
        }
        toolbar.showSmart(nil)
        syncAutoShift()
        updateCandidates()
    }

    func toolbarSuggestionTapped(_ suggestion: KeyToolbar.Suggestion) {
        Haptics.letter()
        // Another guess for the word a glide just put in replaces it.
        if glideSwap(suggestion) { return }
        let before = beforeContext
        let word = WordTracker.currentWord(beforeContext: before)
        let previous = WordTracker.previousWord(beforeContext: before)
        let policy = typingPolicy
        switch suggestion.kind {
        case .undo:
            undoLastCorrection()
        case .literal:
            // Exactly what they typed, on purpose: keep it and never fix it.
            typing?.keep(word)
            typing?.commit(word: word, previous: previous, autoCapitalized: false, policy: policy)
            hostInsert(" ")
        case .correction, .word, .contact:
            if !word.isEmpty { replaceCurrentWord(with: suggestion.text) }
            hostInsert(word.isEmpty ? suggestion.text + " " : " ")
            typing?.commit(word: suggestion.text, previous: previous, autoCapitalized: false, policy: policy)
        case .emoji:
            // After the word, with a space on each side: "happy birthday 🎂 ".
            if !word.isEmpty { typing?.commit(word: word, previous: previous, autoCapitalized: false, policy: policy) }
            hostInsert((word.isEmpty ? "" : " ") + suggestion.text + " ")
        }
        TypingStore.shared.scheduleSave()
        wordTouches = []
        wordTouchesFor = ""
        syncAutoShift()
        updateCandidates()
    }

    func toolbarSmartExtraTapped(_ chip: Smart.Chip) {
        noteChipUsed(chip)
        guard case .paste(let text) = chip, TextPDF.offers(text) else { return }
        // A long copy as a PDF on the clipboard: the person pastes it in the
        // message box (a keyboard can't insert a file).
        ClipContext.markDone()
        cachedPaste = nil
        let ok = TextPDF.copy(text)
        toolbar.showSmart(ok ? .action(label: "PDF ready to paste") : nil)
    }

    /// One part of a row chip: a saved detail types itself, as its own chip
    /// would; a conversion's result goes in where it belongs.
    func toolbarSmartChoiceTapped(_ chip: Smart.Chip, index: Int) {
        noteChipUsed(chip)
        if case .convert(let c) = chip {
            guard index < c.results.count else { return }
            let text = c.insert(index)
            switch c.how(index) {
            case .bracket:
                // "10 inch" → "10 inch (25.4 cm)": the answer after what was typed.
                hostInsert(Smart.conversionInsert(text, before: beforeContext))
            case .after:
                // A link after the number, or a piece of what was copied (the
                // copy is then used, as a paste uses it).
                hostInsert(Self.spaced(text, after: beforeContext))
                if c.source.isEmpty {
                    ClipContext.markDone()
                    cachedPaste = nil
                    lastClipProbe = 0
                }
            case .replace:
                // ";date" → the date: what was typed goes, the answer stays.
                let before = beforeContext ?? ""
                let space = before.hasSuffix(" ") ? " " : ""
                if !c.source.isEmpty, (before.hasSuffix(c.source) || before.hasSuffix(c.source + " ")) {
                    hostDelete(c.source.count + space.count)
                    hostInsert(text + space)
                } else {
                    hostInsert(Self.spaced(text, after: beforeContext))
                }
            }
            // A coin, a die or a pick that was used: the next one is a new draw.
            Smart.luck = UInt64.random(in: 1...UInt64.max)
            toolbar.showSmart(nil)
            updateCandidates()
            return
        }
        guard case .details(let fields, let typed) = chip, index < fields.count else { return }
        if !typed.isEmpty {
            // Its start is typed already: the whole detail takes its place.
            hostDelete(typed.count)
            hostInsert(fields[index].value)
            toolbar.showSmart(nil)
            updateCandidates()
        } else {
            toolbarSmartTapped(.vault(field: fields[index]))
        }
    }
}

// MARK: - MenuShellDelegate

extension KeyboardViewController: MenuShellDelegate {

    func shellClosed() {
        setSurface(.none)
        keyboardView.rebuild()
        toolbar.reloadItems()
    }

    func shellInsertText(_ text: String) {
        setSurface(.none)
        hostInsert(text)
    }

    func shellInsertShorthand(_ text: String) {
        setSurface(.none)
        let filled = fillShorthand(text)
        hostInsert(filled.text)
        if filled.back > 0 { hostAdjust(byCharacterOffset: -filled.back) }
    }

    /// A shorthand's blanks filled where the phone is ({date}, {clipboard}…).
    private func fillShorthand(_ template: String) -> (text: String, back: Int) {
        Smart.fillIn(template, region: SettingsStore.current.region ?? Locale.current.region?.identifier,
                     clipboard: { [weak self] in self?.copiedForShorthand() })
    }

    /// What was copied, for {clipboard}: the keyboard's own copy of it when
    /// it has the latest, or iOS's (which asks "Allow Paste?" for a copy it
    /// hasn't seen: the person asked for it by typing the shorthand).
    private func copiedForShorthand() -> String? {
        guard hasFullAccess else { return nil }
        if !ClipboardStore.pasteboardHasNewContent(), let kept = ClipboardStore.load().first?.text, !kept.isEmpty {
            return kept
        }
        return UIPasteboard.general.string
    }

    func shellStateChanged() {
        // A setting changed under the menu: appearance and one-handed re-skin
        // the keys, the number row changes the height. All of it lands now,
        // not the next time the keyboard comes up.
        resolveAppearance()
        keyboardView.rebuild()
        keyboardView.refreshBindings()
        if heightConstraint?.constant != totalHeight { applySurfaceLayout(animated: true) }
        toolbar.reloadItems()
        // The strip shows which panel screen is open.
        let header = panelHeader()
        lastPanelTitle = .some(header.1)
        toolbar.showPanelHeader(icon: header.0, title: header.1,
                                canGoBack: shell?.canGoBack == true,
                                keepTools: shellAtMenu)
    }

    func shellOpenTool(_ id: String) {
        openTool(id)
    }

    func shellEditNote(id: String?, text: String) {
        pendingEdit = .note(id: id, text: text)
        setSurface(.noteEdit)
    }

    func shellAddDetail(_ kind: DetailKind) {
        pendingEdit = .detail(kind)
        setSurface(.noteEdit)
    }

    func shellAddShorthand() {
        pendingEdit = .shorthand
        setSurface(.noteEdit)
    }

    func shellCopyImage(id: String) {
        guard let data = VaultStore.shared.imageData(id: id),
              let image = UIImage(data: data) else {
            KeyboardToast.show(in: content, text: "That image could not be opened")
            return
        }
        UIPasteboard.general.image = image
        setSurface(.none)
    }

    /// Style: the words picked out are replaced by their styled form; with
    /// none, the message so far is.
    func shellApplyStyle(_ id: String) {
        guard let style = Smart.TextStyle(rawValue: id) else { return }
        if let picked = textDocumentProxy.selectedText, !picked.isEmpty {
            hostInsert(Smart.styled(picked, style))
        } else {
            let before = beforeContext ?? ""
            guard !before.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                KeyboardToast.show(in: content, text: "Type something first")
                return
            }
            hostDelete(before.count)
            hostInsert(Smart.styled(before, style))
        }
        setSurface(.none)
        KeyboardToast.show(in: content, text: style.title)
        updateCandidates()
    }
}

// MARK: - NoteEditSurfaceDelegate

extension KeyboardViewController: NoteEditSurfaceDelegate {

    func noteEditActivated(_ editor: InlineEditor) {
        inlineTarget = editor
        // A shortcut or an email starts in lowercase, whatever capital the
        // message field was about to get; a note or a name starts with one.
        keyboardView.syncAutoShift(wantsCapital: noteEdit?.startsWithCapital ?? false)
    }

    /// Saved or not, back to the notes it was opened from, where what was
    /// just added shows.
    func noteEditSaved() {
        inlineTarget = nil
        setSurface(.shell)
        shell?.push("notes")
    }

    func noteEditClosed() {
        inlineTarget = nil
        setSurface(.shell)
        shell?.push("notes")
    }
}

// MARK: - EmojiBoardDelegate

extension KeyboardViewController: EmojiBoardDelegate {

    func emojiPicked(_ emoji: String) {
        hostInsert(emoji)
    }

    func emojiBackToLetters() {
        setSurface(.none)
    }

    func emojiDeleteBackward() {
        hostDelete()
        syncAutoShift()
        updateCandidates()
    }

    func emojiBoardClosed() {
        inlineTarget = nil
        setSurface(.none)
    }

    func emojiLayoutChanged() {
        applySurfaceLayout(animated: true)
    }

    func emojiSearchDismissed() {
        inlineTarget = nil
    }

    func emojiSearchActivated(_ editor: InlineEditor) {
        inlineTarget = editor
        // Apple's emoji search starts in lowercase, whatever capital the
        // message field was about to get.
        keyboardView.syncAutoShift(wantsCapital: false)
    }

    func emojiBoardType(_ text: String) {
        // ":-)" is a word of its own: glued to the one before it reads as
        // "later:-)". Emoji need no space; emoticons do.
        hostInsert(Self.spaced(text, after: beforeContext))
        syncAutoShift()
        updateCandidates()
    }
}

extension KeyboardViewController {

    /// The keys the field asks for, or the note editor's own.
    private var fieldContext: KeyboardContext {
        if surface == .noteEdit, let keys = noteEdit?.keysContext { return keys }
        return KeyboardContext(keyboardType: textDocumentProxy.keyboardType)
    }

    /// A pasted card or contact must not weld itself onto the word before
    /// the caret.
    static func spaced(_ text: String, after before: String?) -> String {
        guard let last = before?.last, !last.isWhitespace, !last.isNewline else { return text }
        return " " + text
    }
}
