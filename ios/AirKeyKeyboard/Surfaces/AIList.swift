import UIKit

/// The rows the AI bar lists: a rewrite's versions as they are written,
/// search results, my glyfs. Text only. One row is "this one" (a lime
/// edge); the bar's buttons act on it.
final class AIList: UIView {

    struct Row {
        /// The small word above: "Clean", "near.org", "Mine".
        var caption: String?
        var text: String
        /// A quieter line under the text (a result's snippet, a glyf's prompt).
        var detail: String?
        /// A leading symbol instead of a caption (Build your own).
        var symbol: String?
        /// Shows a small ✕ that asks to remove the row.
        var removable = false
    }

    /// Rows that can be picked show the lime edge on the picked one.
    var picks = true
    var onSelect: ((Int) -> Void)?
    var onRemove: ((Int) -> Void)?

    private(set) var selected = 0
    private let scroll = ControlScrollView()
    private var rows: [AIRowView] = []

    init() {
        super.init(frame: .zero)
        scroll.showsVerticalScrollIndicator = false
        scroll.alwaysBounceVertical = true
        addSubview(scroll)
    }

    required init?(coder: NSCoder) { fatalError() }

    var count: Int { rows.count }

    func set(_ items: [Row], selected index: Int = 0) {
        rows.forEach { $0.removeFromSuperview() }
        rows = []
        selected = index
        for item in items { add(item, animated: false) }
        scroll.setContentOffset(.zero, animated: false)
        setNeedsLayout()
    }

    /// One more row at the end: a version that was just finished rises in.
    func append(_ item: Row) {
        add(item, animated: !Glass.reduceMotion)
        setNeedsLayout()
        layoutIfNeeded()
    }

    private func add(_ item: Row, animated: Bool) {
        let v = AIRowView(item)
        let index = rows.count
        v.accessibilityIdentifier = "ai:row:\(index)"
        v.addAction(UIAction { [weak self] _ in self?.tapped(index) }, for: .touchUpInside)
        v.onRemove = { [weak self] in self?.onRemove?(index) }
        v.picked = picks && index == selected
        rows.append(v)
        scroll.addSubview(v)
        guard animated else { return }
        v.alpha = 0
        v.transform = CGAffineTransform(translationX: 0, y: 8)
        UIViewPropertyAnimator(duration: 0.32, dampingRatio: 0.86) {
            v.alpha = 1
            v.transform = .identity
        }.startAnimation()
    }

    private func tapped(_ index: Int) {
        if picks, index != selected {
            selected = index
            for (i, r) in rows.enumerated() { r.picked = i == index }
        }
        onSelect?(index)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scroll.frame = bounds
        // A point of room all round, so the picked row's edge is never clipped.
        var y: CGFloat = 1
        for r in rows {
            // The rise-in animates the transform; frames are set around it.
            let t = r.transform
            r.transform = .identity
            let h = r.height(for: bounds.width - 2)
            r.frame = CGRect(x: 1, y: y, width: bounds.width - 2, height: h)
            r.transform = t
            y += h + 6
        }
        scroll.contentSize = CGSize(width: bounds.width, height: max(0, y - 5))
    }
}

private final class AIRowView: UIControl {
    private let caption = UILabel()
    private let body = UILabel()
    private let detail = UILabel()
    private let icon = UIImageView()
    private let remove = UIButton(type: .system)
    var onRemove: (() -> Void)?

    var picked = false {
        didSet {
            layer.borderWidth = picked ? 1.5 : 0
            caption.textColor = picked ? Glass.chipAccent : Glass.textSecondary
        }
    }

    init(_ row: AIList.Row) {
        super.init(frame: .zero)
        backgroundColor = Glass.surfaceTile
        layer.cornerRadius = 14
        layer.cornerCurve = .continuous
        layer.borderColor = Glass.chipAccent.cgColor

        caption.font = .systemFont(ofSize: 11.5, weight: .semibold)
        caption.textColor = Glass.textSecondary
        caption.text = row.caption
        caption.isHidden = row.caption == nil

        body.font = .systemFont(ofSize: 15.5)
        body.textColor = Glass.textPrimary
        body.numberOfLines = row.detail == nil ? 0 : 2
        body.text = row.text

        detail.font = .systemFont(ofSize: 13)
        detail.textColor = Glass.textSecondary
        detail.numberOfLines = 2
        detail.text = row.detail
        detail.isHidden = row.detail == nil

        icon.image = row.symbol.flatMap { UIImage(systemName: $0) }
        icon.preferredSymbolConfiguration = .init(pointSize: 15, weight: .semibold)
        icon.tintColor = Glass.chipAccent
        icon.contentMode = .center
        icon.isHidden = row.symbol == nil

        remove.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)), for: .normal)
        remove.tintColor = Glass.textSecondary
        remove.isHidden = !row.removable
        remove.accessibilityLabel = "Remove"
        remove.addAction(UIAction { [weak self] _ in self?.onRemove?() }, for: .touchUpInside)

        for v in [caption, body, detail, icon] as [UIView] {
            v.isUserInteractionEnabled = false
            addSubview(v)
        }
        addSubview(remove)
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = [row.caption, row.text, row.detail].compactMap { $0 }.joined(separator: ", ")
    }

    required init?(coder: NSCoder) { fatalError() }

    private static let pad: CGFloat = 11

    private func textWidth(_ w: CGFloat) -> CGFloat {
        w - Self.pad * 2 - (icon.isHidden ? 0 : 28) - (remove.isHidden ? 0 : 26)
    }

    func height(for w: CGFloat) -> CGFloat {
        let tw = textWidth(w)
        var h = Self.pad
        if !caption.isHidden { h += 15 + 2 }
        h += ceil(body.sizeThatFits(CGSize(width: tw, height: .greatestFiniteMagnitude)).height)
        if !detail.isHidden { h += 2 + ceil(detail.sizeThatFits(CGSize(width: tw, height: .greatestFiniteMagnitude)).height) }
        return h + Self.pad
    }

    override var isHighlighted: Bool {
        didSet { backgroundColor = isHighlighted ? Glass.surfaceTile.withAlphaComponent(0.6) : Glass.surfaceTile }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width
        let tw = textWidth(w)
        var x = Self.pad
        if !icon.isHidden {
            icon.frame = CGRect(x: x, y: 0, width: 22, height: bounds.height)
            x += 28
        }
        var y = Self.pad
        if !caption.isHidden {
            caption.frame = CGRect(x: x, y: y, width: tw, height: 15)
            y += 17
        }
        let bh = ceil(body.sizeThatFits(CGSize(width: tw, height: .greatestFiniteMagnitude)).height)
        body.frame = CGRect(x: x, y: y, width: tw, height: bh)
        y += bh
        if !detail.isHidden {
            let dh = ceil(detail.sizeThatFits(CGSize(width: tw, height: .greatestFiniteMagnitude)).height)
            detail.frame = CGRect(x: x, y: y + 2, width: tw, height: dh)
        }
        remove.frame = CGRect(x: w - 36, y: 0, width: 36, height: min(bounds.height, 44))
    }
}
