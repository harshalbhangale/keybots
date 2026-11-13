import UIKit

/// AIRKEY's mark, drawn for UIKit: a keycap outline with an "A" and the lime
/// side tab (the "leash"). The same proportions as `KeycapMark` in SwiftUI.
final class KeycapMarkView: UIView {
    /// The outline and the letter; the tab is always AIRKEY's lime.
    var ink: UIColor = Glass.textPrimary { didSet { setNeedsDisplay() } }

    /// The mark's width for a given height: the cap plus the tab past its edge.
    static func width(height: CGFloat) -> CGFloat { ceil(height * 1.07) }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        let s = bounds.height
        guard s > 4 else { return }
        let line = max(1.5, s * 0.085)
        let cap = CGRect(x: 0, y: 0, width: s, height: s).insetBy(dx: line / 2, dy: line / 2)
        let outline = UIBezierPath(roundedRect: cap, cornerRadius: s * 0.26 - line / 2)
        outline.lineWidth = line
        ink.setStroke()
        outline.stroke()

        let letter = NSAttributedString(string: "A", attributes: [
            .font: UIFont.systemFont(ofSize: s * 0.5, weight: .bold),
            .foregroundColor: ink,
        ])
        let size = letter.size()
        letter.draw(at: CGPoint(x: (s - size.width) / 2, y: (s - size.height) / 2))

        let tabW = max(2, s * 0.13), tabH = s * 0.46
        let tab = UIBezierPath(roundedRect: CGRect(x: s - tabW / 2 + s * 0.065 - tabW / 2, y: (s - tabH) / 2,
                                                   width: tabW, height: tabH),
                               cornerRadius: tabW / 2)
        Glass.accentPrimary.setFill()
        tab.fill()
    }
}
