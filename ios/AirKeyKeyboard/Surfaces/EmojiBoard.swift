import UIKit

protocol EmojiBoardDelegate: AnyObject {
    func emojiPicked(_ emoji: String)
    func emojiBoardClosed()
    /// The ABC key: back to the letters, exactly like the system keyboard.
    func emojiBackToLetters()
    /// The backspace at the far end of the category row, also Apple's.
    func emojiDeleteBackward()
    func emojiSearchActivated(_ editor: InlineEditor)
    /// Search opened/closed — the board collapses to a strip so the LETTER
    /// KEYS can show underneath (Apple/Gboard behavior).
    func emojiLayoutChanged()
    func emojiSearchDismissed()
    /// An emoticon was tapped: type it, like a key.
    func emojiBoardType(_ text: String)
}

/// The emoji keyboard, laid out like Apple's: the search field on top, the
/// section's name under it, the grid, and ABC · categories · delete along
/// the bottom. Beside the search field, two glyphs switch what the board
/// holds: Emoji and Emoticons. Both keep Apple's shape: the same field, the
/// same small-capitals section name, the same bottom bar with ABC and
/// delete, the same grey circle behind whatever is chosen.
///
/// Emoji are text cells in one horizontally paging grid (no images, for
/// memory). Emoticons are text too and type straight into the field.
final class EmojiBoard: UIView, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

    weak var delegate: EmojiBoardDelegate?

    enum Mode: Int, CaseIterable {
        case emoji, emoticons, gifs

        var placeholder: String {
            switch self {
            case .emoji: return "Search Emoji"
            case .emoticons: return "Search Emoticons"
            case .gifs: return "GIFs"
            }
        }
        var name: String {
            switch self {
            case .emoji: return "emoji"
            case .emoticons: return "emoticons"
            case .gifs: return "gifs"
            }
        }
    }

    /// Always Emoji when the board opens: the key has a smiley on it, and
    /// Apple's opens on emoji every time. The other modes are one tap away
    /// and remember which chip was chosen for as long as the board is up.
    private(set) var mode: Mode = .emoji

    private let searchEditor = InlineEditor(placeholder: "Search Emoji", searchStyle: true)
    private let closeButton = UIButton(type: .system)
    private let abcButton = UIButton(type: .system)
    /// Apple's emoji keyboard keeps ABC bottom-left and ⌫ bottom-right, on
    /// either side of the category row. People reach for both without
    /// looking, so they are here too.
    private let lettersButton = UIButton(type: .system)
    private let deleteButton = UIButton(type: .system)
    /// While true the board is a strip (field + one result row) and the
    /// keyboard's letter keys are visible below it.
    private(set) var searchActive = false
    /// Strip height in search mode (field row + results row): the strip's
    /// place plus the board's extra, so searching never changes the
    /// keyboard's height and the keys sit where they always do (Apple's).
    static var searchStripHeight: CGFloat { EmojiMetrics.searchStripHeight() }
    /// How much taller than the letters the grid stands (Apple's does too).
    static let extraHeight: CGFloat = EmojiMetrics.extraHeight

    // Emoji
    private var collection: UICollectionView!
    private let tabs = UIStackView()
    private let tabThumb = UIView()
    private let sectionLabel = UILabel()
    /// Frequently used, then every category, as one horizontal run.
    private var sections: [(title: String, emoji: [String])] = []
    private var currentCategory = 0
    private var searchResults: [String]?
    private var tonePopup: UIView?
    /// The emoji face's point size: the grid's or the search row's.
    private var glyphSize: CGFloat = 39

    // The mode switch: two glyphs with Apple's grey circle behind one.
    private let modeBar = UIView()
    private var modeButtons: [UIButton] = []
    private let modeThumb = UIView()

    // Emoticons
    private var emoticonGrid: UICollectionView!
    private let chipBar = UIScrollView()
    /// Holds the chip bar and fades its ends, so a chip scrolled half out of
    /// sight dissolves instead of being cut at ABC or delete.
    private let chipFade = UIView()
    private let chipFadeMask = CAGradientLayer()
    private var chipButtons: [UIButton] = []
    private let chipThumb = UIView()
    private let suggestionBar = UIScrollView()
    private let statusLabel = UILabel()
    /// The line over an empty or failed grid. It lies over the grid, so it
    /// is only there (and only takes a tap, to retry) while it says
    /// something; an empty label on top would swallow every tap on the grid.
    private var statusText: String? {
        didSet {
            statusLabel.text = statusText
            statusLabel.isHidden = statusText == nil || mode == .emoji || searchActive
        }
    }
    private var selectedChip: [Mode: String] = [:]
    private var emoticonItems: [String] = []

    // GIFs, from KLIPY through our server. Loading them and handing one over
    // both need Full Access (network and pasteboard).
    var hasFullAccess = false
    private var gifGrid: UICollectionView!
    private var gifItems: [GifItem] = []
    private var gifQuery = ""
    private var gifNext: Int?
    private var gifLoading = false
    /// Bumped on every new feed, so a late answer for an old chip is dropped.
    private var gifGeneration = 0
    /// The line under the grid: "Copied. Paste it in the chat." for a moment.
    private let gifNote = UILabel()
    private let attributionLabel = UILabel()
    private var noteTimer: Timer?

    /// One entry on the bottom bar of a media or emoticon page.
    private struct Chip {
        let id: String
        /// Shown as text ("Haha"), as an emoji glyph ("😂"), or as an SF
        /// Symbol (the clock).
        var title: String?
        var glyph: String?
        var symbol: String?
        /// The category it shows; nil is the recents.
        var query: String?
        var label: String
    }

    private static let recentsChip = Chip(id: "recents", symbol: "clock", query: nil,
                                          label: "Recently used")

    private static let emoticonChips: [Chip] = [recentsChip] +
        EmoticonData.categories.map { Chip(id: $0.id, title: $0.title, query: $0.id, label: $0.title) }

    /// Searching needs the letter keys, which the board covers, so the GIF
    /// tab offers the feelings people reach for most, and trending.
    private static let gifChips: [Chip] =
        [Chip(id: "trending", title: "Trending", query: "", label: "Trending")] + [
            ("Haha", "haha"), ("Yes", "yes"), ("Thanks", "thank you"), ("Wow", "wow"),
            ("Sad", "sad"), ("Love", "love"), ("Party", "party"), ("No", "no"),
            ("Hi", "hello"), ("Congrats", "congratulations"), ("Good night", "good night"),
        ].map { Chip(id: $0.1, title: $0.0, query: $0.1, label: $0.0) }

    private func chips(for mode: Mode) -> [Chip] {
        switch mode {
        case .emoticons: return Self.emoticonChips
        case .gifs: return Self.gifChips
        case .emoji: return []
        }
    }

    private var placeholder: String { mode.placeholder }

    static let recentsKey = "emoji-recents.json"

    init() {
        super.init(frame: .zero)
        backgroundColor = Glass.touchableGrid

        searchEditor.onChange = { [weak self] q in self?.queryChanged(q) }
        // Apple's emoji search field is a rounded rectangle a shade lighter
        // than the sheet (#eff0f4 on #e2e4e8, measured on iOS 26), not a pill.
        searchEditor.layer.cornerRadius = 12
        searchEditor.backgroundColor = Glass.chromeDark
            ? UIColor.white.withAlphaComponent(0.10) : UIColor.white.withAlphaComponent(0.48)
        let tap = UITapGestureRecognizer(target: self, action: #selector(searchTapped))
        searchEditor.addGestureRecognizer(tap)
        searchEditor.isAccessibilityElement = true
        searchEditor.accessibilityIdentifier = "emoji:search"
        searchEditor.accessibilityLabel = "Search emoji"
        addSubview(searchEditor)

        closeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        closeButton.tintColor = Glass.textSecondary
        closeButton.accessibilityIdentifier = "emoji:close"
        closeButton.accessibilityLabel = "Close search"
        closeButton.addAction(UIAction { [weak self] _ in self?.exitSearch() },
                              for: .touchUpInside)
        addSubview(closeButton)

        abcButton.setTitle("ABC", for: .normal)
        abcButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        abcButton.setTitleColor(Glass.textPrimary, for: .normal)
        abcButton.accessibilityIdentifier = "emoji:abc"
        abcButton.isHidden = true
        abcButton.addAction(UIAction { [weak self] _ in self?.exitSearch() },
                            for: .touchUpInside)
        addSubview(abcButton)

        // Apple's grid: four rows of big emoji (iPhone, iOS 18.1 on), filled
        // top to bottom and scrolling sideways. Sizes in EmojiMetrics.
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = CGSize(width: 57, height: 47.5)
        layout.minimumInteritemSpacing = 0
        layout.minimumLineSpacing = 0
        layout.sectionInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 14)
        collection = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collection.noEdgeEffects()
        collection.backgroundColor = Glass.touchableGrid
        collection.dataSource = self
        collection.delegate = self
        collection.register(EmojiCell.self, forCellWithReuseIdentifier: "e")
        collection.showsHorizontalScrollIndicator = false
        collection.alwaysBounceHorizontal = true

        // Apple's section names are small capitals in a quiet grey.
        sectionLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        sectionLabel.textColor = Self.sectionGrey
        sectionLabel.accessibilityIdentifier = "emoji:section"
        addSubview(sectionLabel)
        let long = UILongPressGestureRecognizer(target: self, action: #selector(cellLong(_:)))
        long.minimumPressDuration = 0.35
        collection.addGestureRecognizer(long)
        addSubview(collection)

        let emoticonLayout = UICollectionViewFlowLayout()
        emoticonLayout.minimumInteritemSpacing = 0
        emoticonLayout.minimumLineSpacing = 2
        emoticonLayout.sectionInset = UIEdgeInsets(top: 0, left: 8, bottom: 10, right: 8)
        emoticonGrid = UICollectionView(frame: .zero, collectionViewLayout: emoticonLayout)
        emoticonGrid.noEdgeEffects()
        emoticonGrid.backgroundColor = Glass.touchableGrid
        emoticonGrid.dataSource = self
        emoticonGrid.delegate = self
        emoticonGrid.register(EmoticonCell.self, forCellWithReuseIdentifier: "t")
        emoticonGrid.showsVerticalScrollIndicator = false
        emoticonGrid.alwaysBounceVertical = true
        emoticonGrid.accessibilityIdentifier = "emoji:emoticons"
        addSubview(emoticonGrid)

        let gifLayout = UICollectionViewFlowLayout()
        gifLayout.minimumInteritemSpacing = 4
        gifLayout.minimumLineSpacing = 4
        gifLayout.sectionInset = UIEdgeInsets(top: 0, left: 8, bottom: 8, right: 8)
        gifGrid = UICollectionView(frame: .zero, collectionViewLayout: gifLayout)
        gifGrid.noEdgeEffects()
        gifGrid.backgroundColor = Glass.touchableGrid
        gifGrid.dataSource = self
        gifGrid.delegate = self
        gifGrid.register(GifCell.self, forCellWithReuseIdentifier: "g")
        gifGrid.showsVerticalScrollIndicator = false
        gifGrid.alwaysBounceVertical = true
        gifGrid.accessibilityIdentifier = "emoji:gifs"
        addSubview(gifGrid)

        gifNote.font = .systemFont(ofSize: 12, weight: .medium)
        gifNote.textColor = Glass.textPrimary
        gifNote.accessibilityIdentifier = "emoji:gif:note"
        gifNote.alpha = 0
        addSubview(gifNote)
        // KLIPY asks for its name beside its results.
        attributionLabel.font = .systemFont(ofSize: 11, weight: .medium)
        attributionLabel.textColor = Self.sectionGrey
        attributionLabel.textAlignment = .right
        attributionLabel.accessibilityIdentifier = "emoji:attribution"
        addSubview(attributionLabel)

        statusLabel.font = .systemFont(ofSize: 15)
        statusLabel.textColor = Glass.textSecondary
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.accessibilityIdentifier = "emoji:status"
        statusLabel.isUserInteractionEnabled = true
        statusLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(statusTapped)))
        addSubview(statusLabel)

        lettersButton.setTitle("ABC", for: .normal)
        lettersButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .regular)
        lettersButton.setTitleColor(Glass.textPrimary, for: .normal)
        lettersButton.accessibilityIdentifier = "emoji:letters"
        lettersButton.addAction(UIAction { [weak self] _ in
            self?.delegate?.emojiBackToLetters()
        }, for: .touchUpInside)
        addSubview(lettersButton)

        deleteButton.setImage(UIImage(systemName: "delete.left"), for: .normal)
        // Apple's: 21.3 x 17.7pt of ink, measured.
        deleteButton.setPreferredSymbolConfiguration(.init(pointSize: 20.5, weight: .regular),
                                                     forImageIn: .normal)
        deleteButton.tintColor = Glass.textPrimary
        deleteButton.accessibilityIdentifier = "emoji:delete"
        deleteButton.accessibilityLabel = "Delete"
        deleteButton.addAction(UIAction { [weak self] _ in
            self?.delegate?.emojiDeleteBackward()
        }, for: .touchUpInside)
        addSubview(deleteButton)

        tabThumb.backgroundColor = Self.thumbColor
        addSubview(tabThumb)
        tabs.axis = .horizontal
        tabs.distribution = .fillEqually
        addSubview(tabs)
        buildTabs()

        chipThumb.backgroundColor = Self.thumbColor
        chipBar.addSubview(chipThumb)
        chipBar.showsHorizontalScrollIndicator = false
        chipBar.accessibilityIdentifier = "emoji:chips"
        chipFade.addSubview(chipBar)
        chipBar.noEdgeEffects()
        chipFadeMask.startPoint = CGPoint(x: 0, y: 0.5)
        chipFadeMask.endPoint = CGPoint(x: 1, y: 0.5)
        chipFadeMask.colors = [UIColor.clear, .black, .black, .clear].map(\.cgColor)
        chipFade.layer.mask = chipFadeMask
        addSubview(chipFade)
        suggestionBar.showsHorizontalScrollIndicator = false
        suggestionBar.accessibilityIdentifier = "emoji:suggestions"
        addSubview(suggestionBar)
        suggestionBar.noEdgeEffects()

        modeThumb.backgroundColor = Self.thumbColor
        modeBar.addSubview(modeThumb)
        buildModeBar()
        addSubview(modeBar)

        reload()
        highlightTab(0)
        setMode(.emoji, animated: false)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Light and dark flipped while the board was up (the phone went dark
    /// at sunset, say): every colour it took from the palette is taken
    /// again, and the grids redraw with the new ink.
    func applyPalette() {
        backgroundColor = Glass.touchableGrid
        searchEditor.backgroundColor = Glass.chromeDark
            ? UIColor.white.withAlphaComponent(0.10) : UIColor.white.withAlphaComponent(0.48)
        searchEditor.placeholder = placeholder   // re-renders its text in the new ink
        closeButton.tintColor = Glass.textSecondary
        abcButton.setTitleColor(Glass.textPrimary, for: .normal)
        lettersButton.setTitleColor(Glass.textPrimary, for: .normal)
        deleteButton.tintColor = Glass.textPrimary
        for grid in [collection, emoticonGrid, gifGrid] as [UICollectionView] {
            grid.backgroundColor = Glass.touchableGrid
        }
        sectionLabel.textColor = Self.sectionGrey
        attributionLabel.textColor = Self.sectionGrey
        gifNote.textColor = Glass.textPrimary
        statusLabel.textColor = Glass.textSecondary
        for thumb in [tabThumb, modeThumb, chipThumb] { thumb.backgroundColor = Self.thumbColor }
        for (i, b) in modeButtons.enumerated() {
            b.tintColor = i == mode.rawValue ? Glass.textPrimary : Glass.textSecondary
        }
        highlightTab(currentCategory)
        placeChipThumb()
        collection.reloadData()
        emoticonGrid.reloadData()
        if !suggestionBar.isHidden { queryChanged(searchEditor.text) }
    }

    /// Apple's section names: small capitals, lighter than body text.
    private static var sectionGrey: UIColor {
        // Apple's grey is made for Apple's sheet. On a painted board it all
        // but vanishes, so there the board's own ink is softened instead.
        if Glass.themedBgActive { return Glass.textPrimary.withAlphaComponent(0.72) }
        // Light: Apple's (165,166,169), measured on the iOS 26.5 sheet.
        return Glass.chromeDark ? UIColor(white: 0.60, alpha: 1) : UIColor(red: 0.647, green: 0.651, blue: 0.663, alpha: 1)
    }
    /// The soft circle Apple puts behind the chosen category.
    private static var thumbColor: UIColor {
        Glass.textPrimary.withAlphaComponent(Glass.chromeDark ? 0.18 : 0.10)
    }

    private static let sectionTitles = [
        "smileys": "SMILEYS & PEOPLE", "animals": "ANIMALS & NATURE",
        "food": "FOOD & DRINK", "activity": "ACTIVITY", "travel": "TRAVEL & PLACES",
        "objects": "OBJECTS", "symbols": "SYMBOLS", "flags": "FLAGS",
    ]

    // MARK: Mode switch

    private func buildModeBar() {
        let glyphs: [(Mode, UIImage?, String)] = [
            (.emoji, UIImage(systemName: "face.smiling"), "Emoji"),
            (.emoticons, BoardGlyphs.text(":-)", size: 14, weight: .semibold), "Emoticons"),
            (.gifs, BoardGlyphs.text("GIF", size: 10.5, weight: .heavy, boxed: true), "GIFs"),
        ]
        for (mode, image, label) in glyphs {
            let b = UIButton(type: .system)
            b.setImage(image, for: .normal)
            if mode == .emoji {
                b.setPreferredSymbolConfiguration(.init(pointSize: 17, weight: .regular), forImageIn: .normal)
            }
            b.tintColor = Glass.textSecondary
            b.accessibilityLabel = label
            b.accessibilityIdentifier = "emoji:mode:\(mode.name)"
            b.addAction(UIAction { [weak self] _ in self?.setMode(mode, animated: true) },
                        for: .touchUpInside)
            modeBar.addSubview(b)
            modeButtons.append(b)
        }
    }

    /// Switches what the board holds. Search starts over in the new mode.
    func setMode(_ new: Mode, animated: Bool) {
        dismissTonePopup()
        let changed = new != mode
        mode = new
        searchEditor.placeholder = placeholder
        searchEditor.accessibilityLabel = placeholder
        for (i, b) in modeButtons.enumerated() {
            b.tintColor = i == new.rawValue ? Glass.textPrimary : Glass.textSecondary
            b.accessibilityTraits = i == new.rawValue ? [.button, .selected] : .button
        }
        buildChips()
        switch new {
        case .emoji:
            statusText = nil
            highlightTab(currentCategory)
        case .emoticons:
            selectChip(selectedChip[new] ?? (EmoticonRecents.load().isEmpty ? "classic" : "recents"))
        case .gifs:
            if !hasFullAccess {
                sectionLabel.text = "GIFS"
                statusText = "Turn on Allow Full Access to use GIFs\nSettings › Apps › AIRKEY › Keyboards"
            } else if changed || gifItems.isEmpty {
                selectChip(selectedChip[new] ?? "trending")
            }
        }
        if changed { MemoryLogger.logSurface("emoji:\(new.name)") }
        setNeedsLayout()
        if animated { UIView.animate(withDuration: Glass.motion) { self.layoutIfNeeded() } }
    }

    // MARK: Emoji tabs

    private func buildTabs() {
        let symbols = ["clock"] + EmojiData.categories.map(\.symbol)
        for (i, symbol) in symbols.enumerated() {
            let b = UIButton(type: .system)
            b.setImage(UIImage(systemName: symbol), for: .normal)
            b.setPreferredSymbolConfiguration(.init(pointSize: 16, weight: .light), forImageIn: .normal)
            b.tintColor = Glass.textSecondary
            b.accessibilityIdentifier = "emoji:tab:\(i)"
            b.addAction(UIAction { [weak self] _ in self?.jump(to: i) }, for: .touchUpInside)
            tabs.addArrangedSubview(b)
        }
    }

    /// A category button: straight to the start of its section.
    private func jump(to section: Int) {
        dismissTonePopup()
        guard section < sections.count, collection.numberOfItems(inSection: section) > 0 else { return }
        collection.scrollToItem(at: IndexPath(item: 0, section: section), at: .left, animated: false)
        highlightTab(section)
    }

    /// Apple rings the category you are in with a soft circle.
    private func highlightTab(_ section: Int) {
        currentCategory = section
        guard mode == .emoji else { return }
        let views = tabs.arrangedSubviews
        guard views.indices.contains(section) else { return }
        for (i, v) in views.enumerated() {
            (v as? UIButton)?.tintColor = i == section ? Glass.textPrimary : Glass.textSecondary
        }
        let frame = tabs.convert(views[section].frame, to: self)
        let d = min(frame.height, 29.5)
        tabThumb.frame = CGRect(x: frame.midX - d / 2, y: frame.midY - d / 2, width: d, height: d)
        tabThumb.layer.cornerRadius = d / 2
        if !searchActive {
            sectionLabel.text = sections.indices.contains(section) ? sections[section].title : nil
        }
    }

    // MARK: Emoticon chips

    private func buildChips() {
        chipButtons.forEach { $0.removeFromSuperview() }
        chipButtons = []
        for chip in chips(for: mode) {
            let b = UIButton(type: .system)
            if let symbol = chip.symbol {
                b.setImage(UIImage(systemName: symbol), for: .normal)
                b.setPreferredSymbolConfiguration(.init(pointSize: 16, weight: .light), forImageIn: .normal)
            } else if let glyph = chip.glyph {
                b.setTitle(glyph, for: .normal)
                b.titleLabel?.font = .systemFont(ofSize: 21)
            } else {
                b.setTitle(chip.title, for: .normal)
                b.titleLabel?.font = .systemFont(ofSize: 15)
            }
            b.tintColor = Glass.textSecondary
            b.setTitleColor(Glass.textSecondary, for: .normal)
            b.accessibilityLabel = chip.label
            b.accessibilityIdentifier = "emoji:chip:\(chip.id)"
            b.addAction(UIAction { [weak self] _ in self?.selectChip(chip.id) }, for: .touchUpInside)
            chipBar.addSubview(b)
            chipButtons.append(b)
        }
        layoutChips()
    }

    private func layoutChips() {
        let h = chipBar.bounds.height
        var x: CGFloat = 0
        for (b, chip) in zip(chipButtons, chips(for: mode)) {
            let w: CGFloat
            if chip.title != nil {
                w = ceil(b.intrinsicContentSize.width) + 20
            } else {
                w = 34
            }
            b.frame = CGRect(x: x, y: 0, width: w, height: h)
            x += w + (chip.title != nil ? 2 : 1)
        }
        chipBar.contentSize = CGSize(width: x, height: h)
        placeChipThumb()
    }

    private func placeChipThumb() {
        let list = chips(for: mode)
        let chosen = selectedChip[mode].flatMap { id in list.firstIndex { $0.id == id } }
        for (j, b) in chipButtons.enumerated() {
            let on = j == chosen
            b.tintColor = on ? Glass.textPrimary : Glass.textSecondary
            b.setTitleColor(on ? Glass.textPrimary : Glass.textSecondary, for: .normal)
            b.accessibilityTraits = on ? [.button, .selected] : .button
        }
        guard let i = chosen, chipButtons.indices.contains(i) else {
            chipThumb.isHidden = true
            return
        }
        chipThumb.isHidden = false
        let frame = chipButtons[i].frame
        let d = min(frame.height, 30)
        chipThumb.frame = list[i].title != nil
            ? CGRect(x: frame.minX, y: frame.midY - d / 2, width: frame.width, height: d)
            : CGRect(x: frame.midX - d / 2, y: frame.midY - d / 2, width: d, height: d)
        chipThumb.layer.cornerRadius = d / 2
        chipBar.scrollRectToVisible(frame.insetBy(dx: -40, dy: 0), animated: false)
    }

    /// A chip on the bottom bar: the recents, or a kind of emoticon.
    private func selectChip(_ id: String) {
        guard let chip = chips(for: mode).first(where: { $0.id == id }) else { return }
        selectedChip[mode] = id
        placeChipThumb()
        switch mode {
        case .emoticons:
            emoticonItems = id == "recents" ? EmoticonRecents.load() : EmoticonData.items(of: id)
            sectionLabel.text = chip.label.uppercased()
            statusText = emoticonItems.isEmpty ? "Emoticons you send show up here" : nil
            emoticonGrid.reloadData()
            emoticonGrid.setContentOffset(.zero, animated: false)
        case .gifs:
            sectionLabel.text = chip.label.uppercased()
            loadGifs(query: chip.query ?? "")
        case .emoji:
            break
        }
        setNeedsLayout()
    }

    // MARK: GIFs

    /// A new feed: trending ("") or a feeling's search, from the first page.
    private func loadGifs(query: String) {
        guard hasFullAccess else { return }
        gifGeneration += 1
        gifQuery = query
        gifItems = []
        gifNext = nil
        gifLoading = false
        gifGrid.reloadData()
        gifGrid.setContentOffset(.zero, animated: false)
        statusText = nil
        fetchGifs(page: 1)
    }

    private func fetchGifs(page: Int) {
        guard !gifLoading else { return }
        gifLoading = true
        let generation = gifGeneration, query = gifQuery
        Task { [weak self] in
            let result: Result<GifPage, Error>
            do { result = .success(try await API().gifs(q: query, page: page)) } catch { result = .failure(error) }
            guard let self, generation == self.gifGeneration else { return }
            self.gifLoading = false
            switch result {
            case .success(let found):
                let start = self.gifItems.count
                self.gifItems += found.items
                self.gifNext = found.next
                self.attributionLabel.text = found.attribution
                if start == 0 {
                    self.gifGrid.reloadData()
                } else {
                    self.gifGrid.insertItems(at: (start..<self.gifItems.count).map { IndexPath(item: $0, section: 0) })
                }
                if self.gifItems.isEmpty { self.statusText = "No GIFs for that" }
            case .failure(let error):
                // Only the first page says so; a later page just stops.
                if self.gifItems.isEmpty {
                    self.statusText = "\(error.localizedDescription)\nTap to try again"
                }
            }
        }
    }

    @objc private func statusTapped() {
        guard mode == .gifs, hasFullAccess, gifItems.isEmpty else { return }
        loadGifs(query: gifQuery)
    }

    /// A tapped GIF: download the medium one and put it on the pasteboard.
    private func sendGif(at ip: IndexPath) {
        guard gifItems.indices.contains(ip.item) else { return }
        let item = gifItems[ip.item]
        let cell = gifGrid.cellForItem(at: ip)
        cell?.contentView.alpha = 0.5
        GifLoader.shared.full(item.url) { [weak self, weak cell] data in
            cell?.contentView.alpha = 1
            guard let self else { return }
            if let data, GifLoader.copy(data) {
                Haptics.success()
                self.showGifNote("Copied. Paste it in the chat.")
            } else {
                Haptics.error()
                self.showGifNote("Couldn't get that GIF. Try again.")
            }
        }
    }

    private func showGifNote(_ text: String) {
        gifNote.text = text
        noteTimer?.invalidate()
        UIView.animate(withDuration: Glass.motion) { self.gifNote.alpha = 1 }
        noteTimer = Timer.scheduledTimer(withTimeInterval: 2.6, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                UIView.animate(withDuration: 0.4) { self.gifNote.alpha = 0 }
            }
        }
    }

    // MARK: Search

    private func queryChanged(_ q: String) {
        switch mode {
        case .emoji:
            if q.isEmpty {
                // In strip mode an empty query falls back to recents so the
                // row is never blank; in grid mode it clears the filter.
                searchResults = searchActive ? Self.loadRecents() : nil
            } else {
                searchResults = EmojiData.search(q)
            }
            reload()
        case .emoticons:
            let typed = q.trimmingCharacters(in: .whitespaces).lowercased()
            let hits = typed.isEmpty ? EmoticonRecents.load()
                : EmoticonData.categories.filter { $0.title.lowercased().hasPrefix(typed) }
                    .flatMap(\.items)
            showSuggestions(Array(hits.prefix(24)), emoticons: true)
        case .gifs:
            break   // no field on the GIF tab: its chips are the search
        }
    }

    /// The strip's second row outside emoji: the emoticons that match.
    private func showSuggestions(_ items: [String], emoticons: Bool = false) {
        suggestionBar.subviews.forEach { $0.removeFromSuperview() }
        var x: CGFloat = 8
        let h: CGFloat = 36
        for (i, text) in items.enumerated() {
            let b = UIButton(type: .system)
            b.setTitle(text, for: .normal)
            b.titleLabel?.font = .systemFont(ofSize: 16, weight: .regular)
            b.setTitleColor(Glass.textPrimary, for: .normal)
            b.backgroundColor = Glass.surfaceCard
            b.layer.cornerRadius = h / 2
            b.layer.cornerCurve = .continuous
            b.accessibilityIdentifier = "emoji:suggestion:\(i)"
            b.addAction(UIAction { [weak self] _ in
                self?.typeEmoticon(text)
            }, for: .touchUpInside)
            let w = ceil(b.intrinsicContentSize.width) + 26
            b.frame = CGRect(x: x, y: 0, width: w, height: h)
            suggestionBar.addSubview(b)
            x += w + 6
        }
        suggestionBar.contentSize = CGSize(width: x + 2, height: h)
        suggestionBar.setContentOffset(.zero, animated: false)
    }

    /// The return key while the strip is up.
    func returnPressed() {
        exitSearch()
    }

    @objc private func searchTapped() {
        guard mode != .gifs else { return }
        searchEditor.isActive = true
        if !searchActive {
            searchActive = true
            switch mode {
            case .emoji:
                // Empty query shows recents in the strip right away.
                if searchResults == nil { searchResults = Self.loadRecents() }
                reload()
            case .emoticons, .gifs:
                queryChanged(searchEditor.text)
            }
            abcButton.isHidden = false
            tabs.isHidden = true
            setNeedsLayout()
            delegate?.emojiLayoutChanged()
        }
        delegate?.emojiSearchActivated(searchEditor)
    }

    /// Back to the full board with the field cleared; the grid keeps what
    /// it was showing.
    private func leaveStrip() {
        guard searchActive else { return }
        searchActive = false
        searchEditor.isActive = false
        searchEditor.clear()
        abcButton.isHidden = true
        setNeedsLayout()
        delegate?.emojiSearchDismissed()
        delegate?.emojiLayoutChanged()
    }

    /// ABC / return: back to the full grid (search cleared, like Apple's).
    func exitSearch() {
        guard searchActive else { return }
        searchResults = nil
        leaveStrip()
        if mode == .emoji { reload() }
    }

    func deactivateSearch() { searchEditor.isActive = false }

    // MARK: Recents

    static func loadRecents() -> [String] {
        guard let dir = AppGroupStore.bridgeDir,
              let data = try? Data(contentsOf: dir.appendingPathComponent(recentsKey)),
              let list = try? JSONDecoder().decode([String].self, from: data)
        else { return EmojiData.seed }
        return list
    }

    /// Frequently Used: what the person used last, each once, topped up with
    /// the world's most used so it stays full, as Apple's does.
    static func frequentlyUsed() -> [String] {
        var out: [String] = []
        for e in loadRecents() + EmojiData.seed where !out.contains(e) {
            out.append(e)
        }
        return Array(out.prefix(40))
    }

    static let tonesKey = "emoji-tones.json"

    /// The tone last picked for each emoji: Apple's board shows it from then on.
    static func loadTones() -> [String: String] {
        guard let dir = AppGroupStore.bridgeDir,
              let data = try? Data(contentsOf: dir.appendingPathComponent(tonesKey)),
              let map = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return map
    }

    static func rememberTone(_ picked: String) {
        let base = EmojiData.base(of: picked)
        guard EmojiData.variants(of: base).count > 1 else { return }
        var map = loadTones()
        map[base] = picked == base ? nil : picked
        guard let dir = AppGroupStore.bridgeDir, let data = try? JSONEncoder().encode(map) else { return }
        try? data.write(to: dir.appendingPathComponent(tonesKey), options: .atomic)
    }

    static func pushRecent(_ e: String) {
        var list = loadRecents().filter { $0 != e }
        list.insert(e, at: 0)
        guard let dir = AppGroupStore.bridgeDir,
              let data = try? JSONEncoder().encode(Array(list.prefix(32))) else { return }
        try? data.write(to: dir.appendingPathComponent(recentsKey), options: .atomic)
    }

    private func reload() {
        let tones = Self.loadTones()
        sections = [("FREQUENTLY USED", Self.frequentlyUsed())] + EmojiData.categories.map {
            (Self.sectionTitles[$0.id] ?? $0.id.uppercased(), $0.emoji.map { tones[$0] ?? $0 })
        }
        collection.reloadData()
        collection.setContentOffset(.zero, animated: false)
    }

    // MARK: Collections

    func numberOfSections(in cv: UICollectionView) -> Int {
        if cv === emoticonGrid || cv === gifGrid { return 1 }
        return searchResults != nil ? 1 : sections.count
    }

    func collectionView(_ cv: UICollectionView, numberOfItemsInSection s: Int) -> Int {
        if cv === emoticonGrid { return emoticonItems.count }
        if cv === gifGrid { return gifItems.count }
        if let results = searchResults { return results.count }
        return sections.indices.contains(s) ? sections[s].emoji.count : 0
    }

    private func emoji(at ip: IndexPath) -> String {
        if let results = searchResults { return results[ip.item] }
        return sections[ip.section].emoji[ip.item]
    }

    func collectionView(_ cv: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if cv === gifGrid {
            let cell = cv.dequeueReusableCell(withReuseIdentifier: "g", for: indexPath) as! GifCell
            let item = gifItems[indexPath.item]
            cell.accessibilityLabel = item.title.isEmpty ? "GIF" : item.title
            cell.accessibilityIdentifier = "emoji:gif:\(indexPath.item)"
            cell.loading = item.preview
            let pixels = max(cell.bounds.width, cell.bounds.height, 100) * UIScreen.main.scale
            GifLoader.shared.preview(item.preview, pixels: pixels) { [weak cell] image in
                guard let cell, cell.loading == item.preview else { return }
                cell.imageView.image = image
            }
            return cell
        }
        if cv === emoticonGrid {
            let cell = cv.dequeueReusableCell(withReuseIdentifier: "t", for: indexPath) as! EmoticonCell
            let text = emoticonItems[indexPath.item]
            cell.label.text = text
            cell.label.textColor = Glass.textPrimary
            cell.accessibilityLabel = text
            cell.accessibilityIdentifier = "emoji:emoticon:\(indexPath.item)"
            return cell
        }
        let cell = cv.dequeueReusableCell(withReuseIdentifier: "e", for: indexPath) as! EmojiCell
        let e = emoji(at: indexPath)
        cell.label.text = e
        if cell.label.font.pointSize != glyphSize {
            cell.label.font = .systemFont(ofSize: glyphSize)
        }
        // VoiceOver reads the emoji's name; tests find a result by its place.
        cell.isAccessibilityElement = true
        cell.accessibilityLabel = EmojiData.info(EmojiData.base(of: e))?.name ?? e
        cell.accessibilityValue = e
        cell.accessibilityIdentifier = searchResults != nil ? "emoji:result:\(indexPath.item)"
            : "emoji:grid:\(indexPath.section):\(indexPath.item)"
        return cell
    }

    func collectionView(_ cv: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        dismissTonePopup()
        if cv === emoticonGrid { typeEmoticon(emoticonItems[indexPath.item]); return }
        if cv === gifGrid { sendGif(at: indexPath); return }
        pick(emoji(at: indexPath))
    }

    func collectionView(_ cv: UICollectionView, layout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        // The emoji grid keeps the size its layout was given; emoticons go
        // three to a row, a thumb's height.
        if cv === gifGrid {
            // Three to a row, a little wider than tall, like most GIFs.
            let w = floor((cv.bounds.width - 16 - 8) / 3)
            return CGSize(width: max(w, 1), height: max(floor(w * 0.74), 1))
        }
        guard cv === emoticonGrid else {
            return (layout as? UICollectionViewFlowLayout)?.itemSize ?? .zero
        }
        let width = cv.bounds.width - 16
        return CGSize(width: floor(width / 3), height: 46)
    }

    private func typeEmoticon(_ text: String) {
        EmoticonRecents.push(text)
        delegate?.emojiBoardType(text)
    }

    /// The tone popup only means something over the emoji it came from: a
    /// tap anywhere else, a category jump or a scroll puts it away.
    private func dismissTonePopup() {
        tonePopup?.removeFromSuperview()
        tonePopup = nil
    }

    private func pick(_ e: String) {
        Self.pushRecent(e)
        delegate?.emojiPicked(e)
    }

    /// The tabs with the tone just picked, the grid left where it was
    /// (Frequently Used catches up next time, as Apple's does).
    private func showPickedTones() {
        guard searchResults == nil, sections.count > 1 else { return }
        let tones = Self.loadTones()
        for (i, c) in EmojiData.categories.enumerated() where i + 1 < sections.count {
            sections[i + 1].emoji = c.emoji.map { tones[$0] ?? $0 }
        }
        let offset = collection.contentOffset
        collection.reloadData()
        collection.layoutIfNeeded()
        collection.setContentOffset(offset, animated: false)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView === collection, tonePopup != nil { dismissTonePopup() }
        // Near the end of the GIFs: the next page.
        if scrollView === gifGrid, let next = gifNext, !gifLoading,
           scrollView.contentOffset.y + scrollView.bounds.height > scrollView.contentSize.height - 160 {
            fetchGifs(page: next)
        }
        guard !searchActive, scrollView === collection, mode == .emoji else { return }
        // The section under the left edge names the grid, as Apple's does.
        let probe = CGPoint(x: scrollView.contentOffset.x + 24, y: 20)
        if let ip = collection.indexPathForItem(at: probe), ip.section != currentCategory {
            highlightTab(ip.section)
        }
    }

    // MARK: Skin tones (long-press)

    @objc private func cellLong(_ g: UILongPressGestureRecognizer) {
        switch g.state {
        case .began:
            let p = g.location(in: collection)
            guard let ip = collection.indexPathForItem(at: p) else { return }
            let base = EmojiData.base(of: emoji(at: ip))
            let variants = EmojiData.variants(of: base)
            guard variants.count > 1, let cell = collection.cellForItem(at: ip) else { return }
            showTonePopup(variants, over: collection.convert(cell.frame, to: self))
        case .ended, .cancelled:
            break
        default:
            break
        }
    }

    private func showTonePopup(_ variants: [String], over rect: CGRect) {
        tonePopup?.removeFromSuperview()
        let pop = UIView()
        pop.backgroundColor = Glass.surfaceCard
        pop.layer.cornerRadius = 12
        pop.layer.cornerCurve = .continuous
        pop.layer.shadowOpacity = 0.25
        pop.layer.shadowRadius = 8
        pop.layer.shadowOffset = CGSize(width: 0, height: 3)
        let w = CGFloat(variants.count) * 40 + 8
        var x = rect.midX - w / 2
        x = max(4, min(x, bounds.width - w - 4))
        pop.frame = CGRect(x: x, y: max(2, rect.minY - 50), width: w, height: 44)
        for (i, v) in variants.enumerated() {
            let b = UIButton(type: .system)
            b.setTitle(v, for: .normal)
            b.titleLabel?.font = .systemFont(ofSize: 26)
            b.frame = CGRect(x: 4 + CGFloat(i) * 40, y: 2, width: 40, height: 40)
            b.addAction(UIAction { [weak self] _ in
                self?.tonePopup?.removeFromSuperview()
                self?.tonePopup = nil
                Self.rememberTone(v)
                self?.pick(v)
                self?.showPickedTones()
            }, for: .touchUpInside)
            pop.addSubview(b)
        }
        addSubview(pop)
        tonePopup = pop
    }

    // MARK: Layout

    /// The emoji face's size for the grid or the search row; the visible
    /// cells take it at once.
    private func setGlyphSize(_ size: CGFloat) {
        guard glyphSize != size else { return }
        glyphSize = size
        collection.reloadData()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let flow = collection.collectionViewLayout as? UICollectionViewFlowLayout
        let isEmoji = mode == .emoji
        if searchActive {
            // Strip mode: [ABC][field][x] + one row (emoji, search terms or
            // emoticons); the letter keys live below this view.
            // Apple's search row: 34.7pt emoji 53pt apart, the first one's
            // ink 11.7pt in, its middle 28.3pt over the first key row.
            let fy = EmojiMetrics.searchFieldTop, fh = EmojiMetrics.searchFieldHeight
            abcButton.frame = CGRect(x: 6, y: fy + (fh - 32) / 2, width: 44, height: 32)
            searchEditor.frame = CGRect(x: 54, y: fy, width: bounds.width - 96, height: fh)
            closeButton.isHidden = false
            closeButton.frame = CGRect(x: bounds.width - 40, y: fy + (fh - 32) / 2, width: 32, height: 32)
            let rowY = EmojiMetrics.searchRowTop, rowH = max(1, bounds.height - rowY)
            let pitch = EmojiMetrics.searchPitch
            let x0 = EmojiMetrics.searchGlyphLeft - (pitch - EmojiMetrics.searchGlyphInk) / 2
            collection.isHidden = !isEmoji
            collection.frame = CGRect(x: x0, y: rowY, width: bounds.width - x0, height: rowH)
            suggestionBar.isHidden = isEmoji
            suggestionBar.frame = CGRect(x: 0, y: rowY + (rowH - 36) / 2, width: bounds.width, height: 36)
            for v in [sectionLabel, lettersButton, deleteButton, tabThumb, tabs,
                      chipFade, modeBar, statusLabel, gifNote, attributionLabel] as [UIView] { v.isHidden = true }
            emoticonGrid.isHidden = true
            gifGrid.isHidden = true
            searchEditor.isHidden = false
            setGlyphSize(EmojiMetrics.searchGlyphFont)
            let size = CGSize(width: pitch, height: rowH)
            if isEmoji, flow?.itemSize != size {
                flow?.itemSize = size; flow?.invalidateLayout()
            }
            return
        }

        // Apple's: the search field across the top (here with the mode
        // glyphs at its end), no close button (ABC is the way back), the
        // section name, the grid, the bottom bar.
        closeButton.isHidden = true
        suggestionBar.isHidden = true
        modeBar.isHidden = false
        let modeW = CGFloat(modeButtons.count) * 34 - 2
        // Apple's field: 40pt tall, 9pt in from the edge (here it ends
        // before the mode glyphs). Every number is in EmojiMetrics.
        let fieldY = EmojiMetrics.fieldTop, fieldH = EmojiMetrics.fieldHeight
        let fieldX = EmojiMetrics.fieldInset
        searchEditor.frame = CGRect(x: fieldX, y: fieldY,
                                    width: bounds.width - fieldX - 8 - modeW - 8, height: fieldH)
        modeBar.frame = CGRect(x: bounds.width - 8 - modeW, y: fieldY + (fieldH - 32) / 2,
                               width: modeW, height: 32)
        for (i, b) in modeButtons.enumerated() {
            b.frame = CGRect(x: CGFloat(i) * 34, y: 0, width: 32, height: 32)
        }
        if modeButtons.indices.contains(mode.rawValue) {
            modeThumb.frame = modeButtons[mode.rawValue].frame
            modeThumb.layer.cornerRadius = 16
        }

        sectionLabel.isHidden = false
        let labelY = EmojiMetrics.labelTop
        let labelX = EmojiMetrics.labelX
        sectionLabel.frame = CGRect(x: labelX, y: labelY, width: bounds.width - labelX * 2, height: 16)
        let barH = EmojiMetrics.barHeight
        let barY = bounds.height - EmojiMetrics.barBottomInset
        lettersButton.isHidden = false
        deleteButton.isHidden = false
        lettersButton.frame = CGRect(x: 4, y: barY, width: 46, height: barH)
        deleteButton.frame = CGRect(x: bounds.width - 48, y: barY, width: 44, height: barH)
        // Apple's nine category glyphs: 33.2pt apart, the first centred at 67.9.
        let barRect = CGRect(x: EmojiMetrics.barX, y: barY,
                             width: bounds.width - EmojiMetrics.barX - EmojiMetrics.barTrailing, height: barH)
        let gridTop = EmojiMetrics.gridTop
        let gridRect = CGRect(x: 0, y: gridTop, width: bounds.width, height: max(0, barY - gridTop - 2))

        tabs.isHidden = !isEmoji
        tabThumb.isHidden = !isEmoji
        collection.isHidden = !isEmoji
        chipFade.isHidden = isEmoji
        emoticonGrid.isHidden = mode != .emoticons
        gifGrid.isHidden = mode != .gifs
        gifNote.isHidden = mode != .gifs
        attributionLabel.isHidden = mode != .gifs || !hasFullAccess
        // No field on the GIF tab (the board covers the letters it would
        // need): its name sits where the field was, the grid right under it.
        searchEditor.isHidden = mode == .gifs
        statusLabel.isHidden = isEmoji || statusText == nil

        if isEmoji {
            tabs.frame = barRect
            // Four rows, each a quarter of the grid's band; the first glyph
            // lines up with the section name, the grid runs to the edge.
            let row = EmojiMetrics.rowPitch(boardHeight: bounds.height)
            let x0 = EmojiMetrics.gridX(rowPitch: row)
            collection.frame = CGRect(x: x0, y: gridTop, width: bounds.width - x0,
                                      height: row * CGFloat(EmojiMetrics.rows) + 0.5)
            setGlyphSize(EmojiMetrics.glyphFont(rowPitch: row))
            let size = CGSize(width: EmojiMetrics.columnPitch(rowPitch: row), height: row)
            if flow?.itemSize != size { flow?.itemSize = size; flow?.invalidateLayout() }
            highlightTab(currentCategory)
        } else {
            if chipFade.frame != barRect {
                chipFade.frame = barRect
                chipBar.frame = chipFade.bounds
                chipFadeMask.frame = chipFade.bounds
                let edge = NSNumber(value: Double(10 / max(barRect.width, 1)))
                chipFadeMask.locations = [0, edge, NSNumber(value: 1 - edge.doubleValue), 1]
                layoutChips()
            }
            emoticonGrid.frame = gridRect
            statusLabel.frame = gridRect.insetBy(dx: 28, dy: 10)
            if mode == .gifs {
                sectionLabel.frame = CGRect(x: labelX, y: fieldY + (fieldH - 16) / 2,
                                            width: bounds.width - labelX - modeW - 24, height: 16)
                let footY = barY - 18
                let top = fieldY + fieldH + 4
                let gifRect = CGRect(x: 0, y: top, width: bounds.width, height: max(0, footY - top - 2))
                if gifGrid.frame.width != gifRect.width { gifGrid.collectionViewLayout.invalidateLayout() }
                gifGrid.frame = gifRect
                statusLabel.frame = gifRect.insetBy(dx: 28, dy: 10)
                gifNote.frame = CGRect(x: labelX, y: footY, width: bounds.width * 0.62 - labelX, height: 16)
                attributionLabel.frame = CGRect(x: bounds.width * 0.62, y: footY,
                                                width: bounds.width * 0.38 - labelX, height: 16)
            }
        }
    }
}

private final class EmojiCell: UICollectionViewCell {
    let label = UILabel()
    override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = .systemFont(ofSize: 32)
        label.textAlignment = .center
        contentView.addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = contentView.bounds
    }
}
