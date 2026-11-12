import SwiftUI

/// Key colours that follow the app you're typing in, light or dark, the way
/// the system keyboard does. The keyboard sits on iOS's own glass tray.
struct KeyPalette {
    let dark: Bool
    var key: Color { dark ? .white.opacity(0.24) : .white }
    var function: Color { dark ? .white.opacity(0.11) : .black.opacity(0.11) }
    var pressed: Color { dark ? .white.opacity(0.44) : .black.opacity(0.20) }
    var text: Color { dark ? .white : .black }
    var soft: Color { text.opacity(0.5) }
}

/// The AIRKEY keyboard: a normal keyboard, plus a bar that shows what your
/// words would do and lets an agent do it. P carries a lime tab: hold it to run.
struct KeyboardView: View {
    let model: KeyboardModel
    @Environment(\.colorScheme) private var scheme

    private let letters: [[String]] = [
        ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
        ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
        ["z", "x", "c", "v", "b", "n", "m"],
    ]
    private let numbers: [[String]] = [
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
        ["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""],
        [".", ",", "?", "!", "'"],
    ]
    private let symbols: [[String]] = [
        ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="],
        ["_", "\\", "|", "~", "<", ">", "€", "£", "₹", "•"],
        [".", ",", "?", "!", "'"],
    ]

    private let gap: CGFloat = 6
    private let rowHeight: CGFloat = 44
    private let rowGap: CGFloat = 10

    var body: some View {
        let palette = KeyPalette(dark: scheme == .dark)
        VStack(spacing: 0) {
            AgentBar(model: model, palette: palette)
                .frame(height: 52)
                .padding(.horizontal, 6)
            GeometryReader { g in
                keys(unit: (g.size.width - 6 - gap * 9) / 10, palette: palette)
                    .padding(.horizontal, 3)
            }
            .frame(height: rowHeight * 4 + rowGap * 3)
            .padding(.top, 2)
            .padding(.bottom, 4)
        }
    }

    private var rows: [[String]] {
        switch model.layer {
        case .letters: letters
        case .numbers: numbers
        case .symbols: symbols
        }
    }

    private func keys(unit u: CGFloat, palette: KeyPalette) -> some View {
        let side = u * 1.35
        let isLetters = model.layer == .letters
        return VStack(spacing: rowGap) {
            row(rows[0], unit: u, palette: palette)
            row(rows[1], unit: u, palette: palette).frame(maxWidth: .infinity)
            HStack(spacing: gap) {
                if isLetters {
                    Key(symbol: model.capsLock ? "capslock.fill" : (model.shift ? "shift.fill" : "shift"), width: side, function: true, palette: palette, label: "Shift") { model.toggleShift() }
                } else {
                    Key(text: model.layer == .numbers ? "#+=" : "123", width: side, function: true, small: true, palette: palette, label: model.layer == .numbers ? "Symbols" : "Numbers") {
                        model.layer = model.layer == .numbers ? .symbols : .numbers
                    }
                }
                Spacer(minLength: 0)
                row(rows[2], unit: isLetters ? u : u * 1.4, palette: palette)
                Spacer(minLength: 0)
                Key(symbol: "delete.left", width: side, function: true, palette: palette, repeats: true, label: "Delete") { model.delete() }
            }
            HStack(spacing: gap) {
                Key(text: isLetters ? "123" : "ABC", width: u * 1.35, function: true, small: true, palette: palette, label: isLetters ? "Numbers" : "Letters") {
                    model.layer = isLetters ? .numbers : .letters
                }
                if model.needsGlobe {
                    Key(symbol: "globe", width: u * 1.1, function: true, palette: palette, label: "Next keyboard") { model.advance() }
                }
                Key(text: "AIRKEY", brand: true, palette: palette, label: "Space") { model.space() }
                Key(text: model.returnLabel, width: u * 2.1, function: true, small: true, palette: palette, label: model.returnLabel.capitalized) { model.returnKey() }
            }
        }
    }

    private func row(_ keys: [String], unit: CGFloat, palette: KeyPalette) -> some View {
        let upper = model.shift || model.capsLock
        return HStack(spacing: gap) {
            ForEach(keys, id: \.self) { k in
                if k == "p" && model.layer == .letters {
                    Key(text: upper ? "P" : "p", width: unit, agentTab: true, palette: palette, onHold: { model.runTyped() }) { model.type("p") }
                } else {
                    Key(text: upper ? k.uppercased() : k, width: unit, palette: palette) { model.type(k) }
                }
            }
        }
    }
}

/// The bar above the keys. It says one thing at a time: the outcome of what
/// just ran, what your words would do, or how to start.
struct AgentBar: View {
    let model: KeyboardModel
    let palette: KeyPalette

    var body: some View {
        Group {
            if let r = model.result {
                result(r)
            } else if let notice = model.notice {
                self.notice(notice)
            } else if let source = model.running {
                working(source)
            } else if let intent = model.intent {
                ready(intent)
            } else if let a = model.answer {
                suggestion(
                    icon: a.buy == nil ? "banknote" : "chart.line.uptrend.xyaxis", title: a.title, detail: a.detail,
                    action: a.buy == nil ? "Insert" : "Buy", primary: a.buy != nil,
                    onTap: { model.insertAnswer() }, onAction: { a.buy == nil ? model.insertAnswer() : model.buyAnswer() }
                )
            } else if let i = model.instant {
                suggestion(icon: "equal", title: i.title, detail: i.detail, action: "Insert", primary: false, onTap: { model.insertInstant() }, onAction: { model.insertInstant() })
            } else {
                idle
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Nothing to act on yet: a quiet hint, and the check for copied text.
    private var idle: some View {
        HStack(spacing: 8) {
            KeycapMark(size: 17, color: palette.text)
            Text("Type “pay harshal 0.2 for dinner”")
                .font(.footnote)
                .foregroundStyle(palette.soft)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 4)
            Button { model.runPasted() } label: {
                Label("Check copied", systemImage: "doc.on.clipboard")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(palette.text)
                    .padding(.horizontal, 13)
                    .frame(height: 36)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .capsule)
            .accessibilityHint("Sends what you copied to the Inbox Agent to check")
        }
        .padding(.leading, 8)
    }

    /// Your words read as an action. One tap runs it.
    private func ready(_ intent: Intent) -> some View {
        Button { model.runTyped() } label: {
            HStack(spacing: 10) {
                Image(systemName: intent.icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AK.ink)
                    .frame(width: 28, height: 28)
                    .background(AK.accent, in: Circle())
                VStack(alignment: .leading, spacing: 0) {
                    Text(intent.title).font(.footnote.weight(.semibold)).foregroundStyle(palette.text).lineLimit(1).minimumScaleFactor(0.8)
                    if let detail = intent.detail {
                        Text(detail).font(.caption2).foregroundStyle(palette.soft).lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                Text("Run")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(AK.ink)
                    .padding(.horizontal, 16)
                    .frame(height: 30)
                    .background(AK.accent, in: Capsule())
            }
            .padding(.leading, 7)
            .padding(.trailing, 7)
            .frame(height: 44)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .accessibilityLabel("\(intent.title). Run with your Payment Agent.")
    }

    /// An answer the keyboard found: a price, a conversion or a sum. Tap it
    /// to put it in the message; the button on the right is the one next step.
    private func suggestion(icon: String, title: String, detail: String, action: String, primary: Bool, onTap: @escaping () -> Void, onAction: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Button(action: onTap) {
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(palette.text)
                        .frame(width: 28, height: 28)
                        .background(palette.function, in: Circle())
                    VStack(alignment: .leading, spacing: 0) {
                        Text(title).font(.footnote.weight(.semibold)).foregroundStyle(palette.text).lineLimit(1).minimumScaleFactor(0.8)
                        Text(detail).font(.caption2).foregroundStyle(palette.soft).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(title). \(detail). Tap to add it to your message.")
            Button(action: onAction) {
                Text(action)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(primary ? AK.ink : palette.text)
                    .padding(.horizontal, 16)
                    .frame(height: 30)
                    .background(primary ? AK.accent : palette.function, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 7)
        .padding(.trailing, 7)
        .frame(height: 44)
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    private func working(_ source: String) -> some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small).tint(palette.text)
            Text(source == "pasted" ? "Inbox Agent is checking it…" : model.runningKind == .swap ? "Trading Agent is getting a quote…" : "Asking the leash on NEAR…")
                .font(.footnote.weight(.medium))
                .foregroundStyle(palette.text)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .glassEffect(.regular, in: .capsule)
    }

    private func result(_ r: Receipt) -> some View {
        let plain = r.signal == .quote || r.signal == .neutral
        return HStack(spacing: 10) {
            Image(systemName: r.signal.icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(plain ? palette.text : AK.ink)
                .frame(width: 28, height: 28)
                .background(plain ? palette.function : r.signal.color, in: Circle())
            Text(r.message)
                .font(.caption.weight(.medium))
                .foregroundStyle(palette.text)
                .lineLimit(2)
                .minimumScaleFactor(0.9)
            Spacer(minLength: 4)
            if r.tx != nil {
                Button { model.insertReceipt() } label: {
                    Text("Share").font(.footnote.weight(.semibold)).foregroundStyle(palette.text)
                        .padding(.horizontal, 12).frame(height: 30).background(palette.function, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Puts the receipt in the chat")
            }
            close
        }
        .padding(.leading, 7)
        .padding(.trailing, 4)
        .frame(height: 44)
        .glassEffect(plain ? .regular : .regular.tint(r.signal.color.opacity(0.22)), in: .capsule)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(r.signal.title). \(r.message)")
    }

    private func notice(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle.fill").foregroundStyle(AK.amber)
            Text(text).font(.caption.weight(.medium)).foregroundStyle(palette.text).lineLimit(2).minimumScaleFactor(0.9)
            Spacer(minLength: 4)
            close
        }
        .padding(.leading, 14)
        .padding(.trailing, 4)
        .frame(height: 44)
        .glassEffect(.regular, in: .capsule)
    }

    private var close: some View {
        Button { model.dismissResult() } label: {
            Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(palette.soft).frame(width: 34, height: 34).contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Dismiss")
    }
}

/// One key. An agent key carries a lime side tab and runs on hold.
struct Key: View {
    var text: String?
    var symbol: String?
    var width: CGFloat?
    var function = false
    var small = false
    var brand = false
    var agentTab = false
    let palette: KeyPalette
    var repeats = false
    var label: String?
    var onHold: (() -> Void)?
    let action: () -> Void

    @State private var pressed = false
    @State private var held = false
    @State private var timer: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .trailing) {
            RoundedRectangle(cornerRadius: 8.5, style: .continuous)
                .fill(pressed ? palette.pressed : (function ? palette.function : palette.key))
                .shadow(color: .black.opacity(palette.dark ? 0 : 0.28), radius: 0, y: 1)
            Group {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 17, weight: .medium))
                } else if let text {
                    if brand {
                        Text(text).font(.system(size: 11, weight: .semibold).width(.expanded)).tracking(2).foregroundStyle(palette.soft)
                    } else {
                        Text(text).font(.system(size: small ? 15 : 22, weight: .regular))
                    }
                }
            }
            .foregroundStyle(palette.text)
            .frame(maxWidth: .infinity)
            if agentTab {
                Capsule().fill(held ? palette.text : AK.accent).frame(width: 3, height: 16).padding(.trailing, 3)
            }
        }
        .frame(width: width, height: 44)
        .frame(maxWidth: width == nil ? .infinity : nil)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !pressed else { return }
                    pressed = true
                    held = false
                    startTimer()
                }
                .onEnded { _ in
                    timer?.cancel()
                    if !held { action() }
                    pressed = false
                    held = false
                }
        )
        .accessibilityElement()
        .accessibilityLabel(label ?? text ?? "")
        .accessibilityAddTraits(.isKeyboardKey)
        .accessibilityHint(agentTab ? "Hold to run what you typed with your Payment Agent" : "")
        .accessibilityAction { action() }
    }

    private func startTimer() {
        timer?.cancel()
        guard onHold != nil || repeats else { return }
        timer = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(repeats ? 400 : 450))
            guard !Task.isCancelled, pressed else { return }
            held = true
            if let onHold {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onHold()
                return
            }
            while !Task.isCancelled && pressed {
                action()
                try? await Task.sleep(for: .milliseconds(70))
            }
        }
    }
}
