import SwiftUI
import UIKit

@MainActor
protocol TradeSurfaceDelegate: AnyObject {
    func tradeClosed()
    /// The panel changed shape: the whole keyboard, or a strip over the keys
    /// with `editor` taking what they type (`digits` for an amount).
    func tradeLayoutChanged(editor: InlineEditor?, digits: Bool)
    /// The hold: send `command` as typed. `clearing` is the text the panel
    /// was opened from, to take out of the message box when it ran.
    func tradeRun(_ command: String, clearing: String?)
}

/// The keyboard's trade panel (TradePanel, in SwiftUI) and what ties it to
/// the keys: it owns the whole keyboard while the trade is on screen, and
/// shrinks to a strip over the keys while an amount, a price or a token
/// search is typed on them.
final class TradeSurface: UIView {

    weak var delegate: TradeSurfaceDelegate?
    let model: TradeModel
    private let host: UIHostingController<TradePanel>
    /// What the keys type into. A keyboard can't summon a keyboard, so the
    /// key grid routes characters here; the panel draws the value itself.
    private let editor = InlineEditor(placeholder: "")
    /// The text in the message box when the panel was opened from its chip.
    private let origin: String?

    /// The keyboard stands this tall while the whole panel is up.
    static let panelHeight: CGFloat = 316
    static let numberStripHeight: CGFloat = 64
    static let searchStripHeight: CGFloat = 92

    /// The strip's height while the keys are in use; nil while the panel has the whole keyboard.
    var stripHeight: CGFloat? {
        switch model.mode {
        case .number: Self.numberStripHeight
        case .search: Self.searchStripHeight
        default: nil
        }
    }
    var wantsDigits: Bool { if case .number = model.mode { true } else { false } }

    init(seed: TradeModel.Seed?, origin: String?, hasFullAccess: Bool) {
        model = TradeModel(seed: seed ?? TradeModel.Seed())
        model.hasFullAccess = hasFullAccess
        host = UIHostingController(rootView: TradePanel(model: model))
        self.origin = origin
        super.init(frame: .zero)
        host.view.backgroundColor = .clear
        host.sizingOptions = []
        host.safeAreaRegions = []
        addSubview(host.view)
        editor.isHidden = true
        addSubview(editor)

        editor.onChange = { [weak self] text in self?.model.typed(text) }
        model.onTyped = { [weak self] text in
            guard let editor = self?.editor, editor.text != text else { return }
            editor.setText(text)
        }
        model.onMode = { [weak self] in
            guard let self else { return }
            let typing = self.model.typing
            if let typing, self.editor.text != typing { self.editor.setText(typing) }
            self.delegate?.tradeLayoutChanged(editor: typing == nil ? nil : self.editor, digits: self.wantsDigits)
        }
        model.onClose = { [weak self] in self?.delegate?.tradeClosed() }
        model.onRun = { [weak self] command in
            guard let self else { return }
            self.delegate?.tradeRun(command, clearing: self.origin)
        }
        model.open()
    }

    required init?(coder: NSCoder) { fatalError() }

    /// SwiftUI's controller joins the keyboard's, so its views get the right traits.
    func attach(to parent: UIViewController) {
        parent.addChild(host)
        host.didMove(toParent: parent)
    }

    func detach() {
        host.willMove(toParent: nil)
        host.removeFromParent()
        removeFromSuperview()
    }

    /// Return on the keys: done typing, back to the whole panel (or the list).
    func returnPressed() {
        if case .search(let side) = model.mode { model.show(.tokens(side)) } else { model.show(.panel) }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        host.view.frame = bounds
    }
}
