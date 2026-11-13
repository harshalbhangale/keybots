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

    /// Draws the mascot image (`Mascot.xcassets/MascotMark`), centred in the view's height.
    override func draw(_ rect: CGRect) {
        let s = bounds.height
        guard s > 4, let image = UIImage(named: "MascotMark") else { return }
        image.draw(in: CGRect(x: (bounds.width - s) / 2, y: 0, width: s, height: s))
    }
}
