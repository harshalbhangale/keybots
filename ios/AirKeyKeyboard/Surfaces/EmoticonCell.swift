import UIKit

/// One emoticon on the emoji board's Emoticons page: text, typed on a tap.
final class EmoticonCell: UICollectionViewCell {
    let label = UILabel()
    override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = .systemFont(ofSize: 17)
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.55
        label.textColor = Glass.textPrimary
        contentView.addSubview(label)
        isAccessibilityElement = true
        accessibilityTraits = .button
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = contentView.bounds.insetBy(dx: 4, dy: 0)
    }
    override var isHighlighted: Bool {
        didSet {
            contentView.backgroundColor = isHighlighted ? Glass.fillSoft : .clear
            contentView.layer.cornerRadius = 8
        }
    }
}


/// Glyphs for the board's mode switch that SF Symbols does not have.
enum BoardGlyphs {

    /// A word as a glyph ("GIF", ":-)"), for places that take an image.
    static func text(_ string: String, size: CGFloat = 13, weight: UIFont.Weight = .bold,
                     boxed: Bool = false) -> UIImage {
        let font = UIFont.systemFont(ofSize: size, weight: weight)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.black]
        let text = (string as NSString).size(withAttributes: attrs)
        let pad: CGFloat = boxed ? 3 : 0
        let canvas = CGSize(width: ceil(text.width) + pad * 2 + 2, height: ceil(text.height) + 2)
        return UIGraphicsImageRenderer(size: canvas).image { _ in
            if boxed {
                let box = UIBezierPath(roundedRect: CGRect(origin: .zero, size: canvas).insetBy(dx: 0.75, dy: 1.5),
                                       cornerRadius: 3)
                box.lineWidth = 1.4
                UIColor.black.setStroke()
                box.stroke()
            }
            (string as NSString).draw(at: CGPoint(x: pad + 1, y: 1), withAttributes: attrs)
        }.withRenderingMode(.alwaysTemplate)
    }
}

/// The emoticons used last, newest first, for the Recently used chip.
enum EmoticonRecents {
    private static var file: URL? {
        AppGroupStore.bridgeDir?.appendingPathComponent("emoticon-recents.json")
    }

    static func load() -> [String] {
        guard let url = file, let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return list
    }

    static func push(_ e: String) {
        var list = load().filter { $0 != e }
        list.insert(e, at: 0)
        guard let url = file, let data = try? JSONEncoder().encode(Array(list.prefix(24))) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
