import SwiftUI
import UIKit

/// The Assist panel's colours, read against the keyboard's own sheet.
struct AssistPalette {
    let dark: Bool
    var text: Color { dark ? .white : Color(white: 0.07) }
    var soft: Color { text.opacity(0.55) }
    var function: Color { dark ? .white.opacity(0.12) : .black.opacity(0.07) }
    var card: Color { dark ? Color(white: 0.19) : .white }
    var line: Color { dark ? .white.opacity(0.10) : .black.opacity(0.08) }
    /// Lime on a dark sheet, deep olive on a light one (lime on white can't be read).
    var mark: Color { Color(uiColor: Glass.chipAccent) }
    var amber: Color { dark ? AK.amber : Color(uiColor: Glass.accentWarning) }
}

/// Hold space: the AI on what you wrote (or what you copied). The whole
/// keyboard while an answer is on screen; a strip over the keys while a
/// question is typed on them.
final class AssistPanel: UIView {

    static let stripHeight: CGFloat = 54

    let model: AssistModel
    /// What the keys type into while a question is being written: a
    /// keyboard can't summon a keyboard, so the keys route characters here
    /// and the panel draws the words itself.
    let editor = InlineEditor(placeholder: "")
    /// The panel changed shape: `editor` when the keys should type into it.
    var onShape: ((InlineEditor?) -> Void)?
    private let host: UIHostingController<AnyView>

    var isStrip: Bool { model.typing }

    init(model: AssistModel, dark: Bool) {
        self.model = model
        host = UIHostingController(rootView: AnyView(
            AssistView(model: model).environment(\.colorScheme, dark ? .dark : .light)))
        super.init(frame: .zero)
        host.view.backgroundColor = .clear
        host.sizingOptions = []
        host.safeAreaRegions = []
        addSubview(host.view)
        editor.isHidden = true
        addSubview(editor)
        editor.onChange = { [weak model] text in model?.typed(text) }
        model.onTyping = { [weak self] on in
            guard let self else { return }
            if on { self.editor.setText(self.model.question) }
            self.onShape?(on ? self.editor : nil)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func attach(to parent: UIViewController) {
        parent.addChild(host)
        host.didMove(toParent: parent)
    }

    /// Stops the request and lets the panel go.
    func detach() {
        model.stop()
        host.willMove(toParent: nil)
        host.view.removeFromSuperview()
        host.removeFromParent()
        removeFromSuperview()
    }

    /// Slides up into place in a quarter of a second; a plain fade when
    /// Reduce Motion is on.
    func rise() {
        Haptics.popupOpen()
        if Glass.reduceMotion {
            host.view.alpha = 0
            UIView.animate(withDuration: 0.2) { self.host.view.alpha = 1 }
            return
        }
        host.view.transform = CGAffineTransform(translationX: 0, y: 28)
        host.view.alpha = 0
        UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.92, initialSpringVelocity: 0.4,
                       options: [.allowUserInteraction]) {
            self.host.view.transform = .identity
            self.host.view.alpha = 1
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let t = host.view.transform
        host.view.transform = .identity
        host.view.frame = bounds
        host.view.transform = t
    }
}

// MARK: - The view

struct AssistView: View {
    let model: AssistModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = AssistPalette(dark: scheme == .dark)
        Group {
            if model.typing { questionStrip(p) } else { panel(p) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Whole panel

    private func panel(_ p: AssistPalette) -> some View {
        VStack(spacing: 8) {
            header(p)
            // The receipt lies over the tasks and the answer, never pushing them.
            // The receipt takes the answer's place: nothing is drawn behind
            // it, so no chip or button shows through its corners.
            ZStack(alignment: .top) {
                if model.receiptOpen, let r = model.receipt {
                    AssistReceiptCard(receipt: r, note: model.note, p: p) { model.toggleReceipt() }
                        .transition(.opacity)
                } else {
                    VStack(spacing: 8) {
                        tasks(p)
                        if model.task == .translate { languageRow(p) }
                        content(p)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        actions(p)
                    }
                    .transition(.opacity)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .animation(Glass.reduceMotion ? nil : .easeInOut(duration: 0.18), value: model.receiptOpen)
        }
        .padding(.horizontal, MoneyPalette.inset)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    /// Close, what it works on, and who answers.
    private func header(_ p: AssistPalette) -> some View {
        HStack(spacing: 8) {
            Button { model.close() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(p.soft)
                    .frame(width: 28, height: 28)
                    .background(p.function, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
            if model.canCopy { sourceSwitch(p) } else {
                Text("Draft").font(.footnote.weight(.semibold)).foregroundStyle(p.soft)
            }
            Spacer(minLength: 0)
            Button { model.toggleReceipt() } label: {
                AssistBadge(receipt: model.receipt, working: model.phase == .working, p: p)
            }
            .buttonStyle(.plain)
            .disabled(model.receipt == nil)
            // The open receipt says the same in its title.
            .opacity(model.receiptOpen ? 0 : 1)
        }
        .frame(height: 28)
    }

    private func sourceSwitch(_ p: AssistPalette) -> some View {
        HStack(spacing: 0) {
            ForEach([(AssistModel.Source.draft, "Draft"), (.copied, "Copied text")], id: \.1) { source, title in
                let on = model.source == source
                Button { model.pick(source: source) } label: {
                    Text(title)
                        .font(.caption.weight(on ? .semibold : .medium))
                        .foregroundStyle(on ? p.text : p.soft)
                        .padding(.horizontal, 9)
                        .frame(height: 24)
                        .background(on ? p.function : .clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(2)
        .background(p.function.opacity(0.5), in: Capsule())
    }

    /// Fix · Shorter · Warmer · Formal · Reply · Translate · Ask · Search.
    private func tasks(_ p: AssistPalette) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(AssistTask.allCases) { t in
                        let on = t == model.task
                        Button { model.select(t) } label: {
                            Text(t.title)
                                .font(.footnote.weight(on ? .semibold : .medium))
                                .foregroundStyle(on ? AK.ink : p.text)
                                .padding(.horizontal, 12)
                                .frame(height: 30)
                                .background(on ? AK.accent : p.function, in: Capsule())
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .id(t)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
            // The row runs to the panel's edges and scrolls under them; the
            // first and last chips rest at the same inset as everything else.
            .contentMargins(.horizontal, MoneyPalette.inset, for: .scrollContent)
            .padding(.horizontal, -MoneyPalette.inset)
            .scrollEdgeEffectHidden(true)
            .onAppear { proxy.scrollTo(model.task, anchor: .center) }
            .onChange(of: model.task) { _, t in
                withAnimation(Glass.reduceMotion ? nil : .snappy(duration: 0.2)) { proxy.scrollTo(t, anchor: .center) }
            }
        }
        .frame(height: 30)
    }

    private func languageRow(_ p: AssistPalette) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(model.languages, id: \.self) { l in
                    let on = l == model.language
                    Button { model.pick(language: l) } label: {
                        Text(l)
                            .font(.caption.weight(on ? .semibold : .regular))
                            .foregroundStyle(on ? p.text : p.soft)
                            .padding(.horizontal, 9)
                            .frame(height: 24)
                            .overlay(Capsule().stroke(on ? p.mark : .clear, lineWidth: 1))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollEdgeEffectHidden(true)
        .frame(height: 24)
        .animation(Glass.reduceMotion ? nil : .snappy(duration: 0.2), value: model.languages)
    }

    // MARK: What came back

    @ViewBuilder
    private func content(_ p: AssistPalette) -> some View {
        switch model.phase {
        case .empty:
            quiet("Write something first, or copy some text.", p)
        case .failed(let why):
            VStack(alignment: .leading, spacing: 8) {
                Text(why).font(.subheadline).foregroundStyle(p.soft)
                Button { model.again() } label: {
                    Text("Try again").font(.footnote.weight(.semibold)).foregroundStyle(p.text)
                        .padding(.horizontal, 12).frame(height: 30)
                        .background(p.function, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)
        case .money:
            moneyGuard(p)
        case .waiting:
            questionLine(p)
        case .working, .finished:
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 8) {
                        if model.task.takesQuestion { questionLine(p) }
                        switch model.task {
                        case .reply where !model.options.isEmpty: replies(p)
                        case .search: search(p)
                        default: writing(p, size: 17)
                        }
                        if model.phase == .finished, let note = model.note, !note.isEmpty {
                            Text(note).font(.caption).foregroundStyle(p.soft)
                        }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                }
                .scrollEdgeEffectHidden(true)
                .onChange(of: model.shown) { _, _ in
                    guard model.task != .search else { return }
                    proxy.scrollTo("end", anchor: .bottom)
                }
            }
        }
    }

    private func quiet(_ text: String, _ p: AssistPalette) -> some View {
        Text(text).font(.subheadline).foregroundStyle(p.soft).padding(.top, 4)
    }

    /// The answer as it arrives, a soft caret at its end while it is written.
    @ViewBuilder
    private func writing(_ p: AssistPalette, size: CGFloat) -> some View {
        if model.writing {
            TimelineView(.periodic(from: .now, by: 0.45)) { ctx in
                let lit = Glass.reduceMotion || Int(ctx.date.timeIntervalSinceReferenceDate / 0.45) % 2 == 0
                (Text(model.shown).foregroundColor(p.text)
                 + Text(model.shown.isEmpty ? "▍" : " ▍").foregroundColor(p.mark.opacity(lit ? 0.9 : 0.25)))
                    .font(.system(size: size))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text(model.shown)
                .font(.system(size: size))
                .foregroundStyle(p.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.disabled)
        }
    }

    /// Ask or Search: the words asked, tap to change them.
    private func questionLine(_ p: AssistPalette) -> some View {
        Button { model.editQuestion() } label: {
            HStack(spacing: 6) {
                Image(systemName: model.task == .search ? "magnifyingglass" : "text.bubble")
                    .font(.system(size: 12, weight: .semibold))
                Text(model.question.isEmpty ? placeholder : model.question)
                    .font(.footnote.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "pencil").font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(p.soft)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(p.function, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var placeholder: String {
        model.task == .search ? "Search the web" : "Ask about your text"
    }

    private func replies(_ p: AssistPalette) -> some View {
        VStack(spacing: 6) {
            ForEach(Array(model.options.enumerated()), id: \.element.id) { i, o in
                let on = i == model.picked
                Button {
                    Haptics.chip()
                    model.picked = i
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(o.label.isEmpty ? "Reply \(i + 1)" : o.label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(on ? p.mark : p.soft)
                        Text(o.text)
                            .font(.subheadline)
                            .foregroundStyle(p.text)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(p.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(on ? p.mark : p.line, lineWidth: on ? 1.5 : 0.5))
                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .offset(y: 8)))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .animation(Glass.reduceMotion ? nil : .snappy(duration: 0.25), value: model.options)
    }

    private func search(_ p: AssistPalette) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.phase == .working, model.shown.isEmpty, model.links.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).tint(p.soft)
                    Text("Searching the web").font(.subheadline).foregroundStyle(p.soft)
                }
                .padding(.top, 2)
            } else if !model.shown.isEmpty || model.writing { writing(p, size: 15) }
            ForEach(model.links) { l in
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(l.site).font(.caption2.weight(.medium)).foregroundStyle(p.soft).lineLimit(1)
                        Text(l.title).font(.footnote.weight(.semibold)).foregroundStyle(p.text).lineLimit(1)
                        if !l.snippet.isEmpty {
                            Text(l.snippet).font(.caption).foregroundStyle(p.soft).lineLimit(2)
                        }
                    }
                    Spacer(minLength: 0)
                    Button { model.insert(link: l) } label: {
                        Text("Insert link")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(p.text)
                            .padding(.horizontal, 10)
                            .frame(height: 26)
                            .background(p.function, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(10)
                .background(p.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(p.line, lineWidth: 0.5))
                .transition(.opacity.combined(with: .offset(y: 8)))
            }
        }
        .animation(Glass.reduceMotion ? nil : .snappy(duration: 0.25), value: model.links)
    }

    /// Money is never the AI's: one line, and the way to the agents.
    private func moneyGuard(_ p: AssistPalette) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "lock.shield").font(.system(size: 14, weight: .semibold)).foregroundStyle(p.amber)
                Text("This looks like a payment. AIRKEY's agents handle money, not the AI.")
                    .font(.subheadline)
                    .foregroundStyle(p.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button { model.useAgent() } label: {
                Text("Use the agent")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AK.ink)
                    .padding(.horizontal, 16)
                    .frame(height: 36)
                    .background(AK.accent, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 4)
    }

    // MARK: Actions

    private func actions(_ p: AssistPalette) -> some View {
        let live = model.canAct
        let hidden = model.phase == .money || model.phase == .empty
        return HStack(spacing: 6) {
            Button { model.again() } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(p.text)
                    .frame(width: 40, height: 40)
                    .background(p.function, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(model.phase == .working || model.phase == .waiting)
            .accessibilityLabel("Again")
            if model.canReplace {
                // Three items: Copy lives on a long press of Insert.
                pill(model.copiedFlash ? "Copied" : "Insert", primary: false, p) { model.insert() }
                    .contextMenu { Button("Copy", systemImage: "doc.on.doc") { model.copy() } }
                    .accessibilityAction(named: "Copy") { model.copy() }
                    .accessibilityHint("Adds it after your text. Touch and hold to copy.")
                pill("Replace", primary: true, p) { model.replace() }
                    .accessibilityHint("Swaps your text for this one.")
            } else {
                pill(model.copiedFlash ? "Copied" : "Copy", primary: false, p) { model.copy() }
                pill("Insert", primary: true, p) { model.insert() }
            }
        }
        .frame(height: 40)
        .opacity(hidden ? 0 : live ? 1 : 0.45)
        .allowsHitTesting(!hidden)
        .disabled(!live && !hidden && model.phase != .finished)
        .animation(.easeOut(duration: 0.18), value: live)
    }

    private func pill(_ title: String, primary: Bool, _ p: AssistPalette, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(primary ? AK.ink : p.text)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(primary ? AK.accent : p.function, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!model.canAct)
    }

    // MARK: Typing a question

    /// Over the keys while Ask or Search is typed: the words, and the arrow.
    private func questionStrip(_ p: AssistPalette) -> some View {
        HStack(spacing: 8) {
            Button { model.close() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(p.soft)
                    .frame(width: 30, height: 30)
                    .background(p.function, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
            HStack(spacing: 6) {
                Image(systemName: model.task == .search ? "magnifyingglass" : "text.bubble")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(p.soft)
                TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                    let lit = Glass.reduceMotion || Int(ctx.date.timeIntervalSinceReferenceDate / 0.5) % 2 == 0
                    HStack(spacing: 1) {
                        if model.question.isEmpty {
                            caret(p, lit)
                            Text(placeholder).foregroundStyle(p.soft)
                        } else {
                            Text(model.question).foregroundStyle(p.text).lineLimit(1).truncationMode(.head)
                            caret(p, lit)
                        }
                    }
                    .font(.system(size: 16))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(p.card, in: Capsule())
            .overlay(Capsule().stroke(p.line, lineWidth: 0.5))
            let empty = model.question.trimmingCharacters(in: .whitespaces).isEmpty
            Button { model.submit() } label: {
                // Lime only once there is something to send.
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(empty ? p.soft : AK.ink)
                    .frame(width: 38, height: 38)
                    .background(empty ? p.function : AK.accent, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(empty)
            .accessibilityLabel(model.task == .search ? "Search" : "Ask")
        }
        .padding(.horizontal, 10)
    }

    private func caret(_ p: AssistPalette, _ lit: Bool) -> some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(p.mark.opacity(lit ? 0.9 : 0.2))
            .frame(width: 2, height: 20)
    }
}
