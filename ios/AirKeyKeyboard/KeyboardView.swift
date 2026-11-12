import SwiftUI

/// The AIRKEY keyboard. Ink keys, bone type, and one mint side tab on P:
/// hold P to hand what you typed to your Payment Agent.
struct KeyboardView: View {
    let model: KeyboardModel

    private let letters: [[String]] = [
        ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
        ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
        ["z", "x", "c", "v", "b", "n", "m"],
    ]
    private let numbers: [[String]] = [
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
        ["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""],
        [".", ",", "?", "!", "'", "_", "#"],
    ]

    private let gap: CGFloat = 6

    var body: some View {
        VStack(spacing: 0) {
            AgentBar(model: model)
            GeometryReader { g in
                keys(unit: (g.size.width - 6 - gap * 9) / 10)
                    .padding(.horizontal, 3)
            }
            .frame(height: 44 * 4 + 10 * 3)
            .padding(.top, 6)
            .padding(.bottom, 4)
        }
        .background(AK.ink)
    }

    private var rows: [[String]] { model.layer == .letters ? letters : numbers }

    private func keys(unit u: CGFloat) -> some View {
        let side = u * 1.35
        return VStack(spacing: 10) {
            row(rows[0], unit: u)
            row(rows[1], unit: u).frame(maxWidth: .infinity)
            HStack(spacing: gap) {
                if model.layer == .letters {
                    Key(symbol: model.capsLock ? "capslock.fill" : (model.shift ? "shift.fill" : "shift"), width: side, dark: true, label: "Shift") { model.toggleShift() }
                } else {
                    Key(text: "#+=", width: side, dark: true) {}
                }
                Spacer(minLength: 0)
                row(rows[2], unit: u)
                Spacer(minLength: 0)
                Key(symbol: "delete.left", width: side, dark: true, repeats: true, label: "Delete") { model.delete() }
            }
            HStack(spacing: gap) {
                Key(text: model.layer == .letters ? "123" : "ABC", width: u * 1.3, dark: true) { model.layer = model.layer == .letters ? .numbers : .letters }
                if model.needsGlobe { Key(symbol: "globe", width: u * 1.1, dark: true, label: "Next keyboard") { model.advance() } }
                Key(text: "AIRKEY", small: true) { model.space() }
                Key(text: "return", width: u * 2, dark: true) { model.returnKey() }
            }
        }
    }

    private func row(_ keys: [String], unit: CGFloat) -> some View {
        HStack(spacing: gap) {
            ForEach(keys, id: \.self) { k in
                if k == "p" && model.layer == .letters {
                    Key(text: model.shift || model.capsLock ? "P" : "p", width: unit, agentTab: true, onHold: { model.runTyped() }) { model.type("p") }
                } else {
                    Key(text: model.shift || model.capsLock ? k.uppercased() : k, width: unit) { model.type(k) }
                }
            }
        }
    }
}

/// The strip above the keys: which agent is listening, the two actions, and the result chip.
struct AgentBar: View {
    let model: KeyboardModel

    var body: some View {
        Group {
            if let r = model.result {
                resultChip(r)
            } else if let notice = model.notice {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle").foregroundStyle(AK.amber)
                    Text(notice).font(.system(size: 13)).foregroundStyle(AK.bone).lineLimit(2)
                    Spacer(minLength: 4)
                    Button { model.dismissResult() } label: { Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundStyle(AK.muted) }
                }
                .padding(.horizontal, 12)
            } else {
                HStack(spacing: 8) {
                    KeycapMark(size: 16)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(model.running == nil ? "Payment Agent" : (model.running == "pasted" ? "Inbox Agent checking…" : "Payment Agent working…"))
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(AK.bone)
                        Text(model.running == nil ? "Hold P to run what you typed" : "Asking the leash on NEAR")
                            .font(.system(size: 11)).foregroundStyle(AK.muted)
                    }
                    Spacer(minLength: 4)
                    if model.running != nil { ProgressView().tint(AK.mint).scaleEffect(0.8) }
                    Button { model.runPasted() } label: {
                        Label("Paste & check", systemImage: "doc.on.clipboard").font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AK.amber).padding(.horizontal, 10).padding(.vertical, 7)
                            .overlay(Capsule().strokeBorder(AK.amber.opacity(0.55), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    Button { model.runTyped() } label: {
                        Text("Run").font(.system(size: 13, weight: .bold)).foregroundStyle(AK.ink)
                            .padding(.horizontal, 14).padding(.vertical, 7).background(AK.mint, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .disabled(model.running != nil)
            }
        }
        .frame(height: 50)
    }

    private func resultChip(_ r: Receipt) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2).fill(r.signal.color).frame(width: 3, height: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(r.signal.word).font(.system(size: 10.5, weight: .heavy).width(.expanded)).foregroundStyle(r.signal.color)
                Text(r.message).font(.system(size: 12.5)).foregroundStyle(AK.bone).lineLimit(2)
            }
            Spacer(minLength: 4)
            if r.tx != nil {
                Button { model.insertReceipt() } label: {
                    Text("Share").font(.system(size: 12, weight: .semibold)).foregroundStyle(AK.bone)
                        .padding(.horizontal, 10).padding(.vertical, 6).background(AK.raised, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            Button { model.dismissResult() } label: { Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundStyle(AK.muted).frame(width: 26, height: 26) }
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .background(r.signal.color.opacity(0.08))
    }
}

/// One key. Press shows bone; an agent key carries a mint side tab and runs on hold.
struct Key: View {
    var text: String?
    var symbol: String?
    var width: CGFloat?
    var dark = false
    var small = false
    var agentTab = false
    var repeats = false
    var label: String?
    var onHold: (() -> Void)?
    let action: () -> Void

    init(text: String? = nil, symbol: String? = nil, width: CGFloat? = nil, dark: Bool = false, small: Bool = false, agentTab: Bool = false, repeats: Bool = false, label: String? = nil, onHold: (() -> Void)? = nil, action: @escaping () -> Void) {
        self.text = text; self.symbol = symbol; self.width = width; self.dark = dark; self.small = small
        self.agentTab = agentTab; self.repeats = repeats; self.label = label; self.onHold = onHold; self.action = action
    }

    @State private var pressed = false
    @State private var held = false
    @State private var timer: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .trailing) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(pressed ? AK.bone : (dark ? AK.surface : AK.raised))
            Group {
                if let symbol { Image(systemName: symbol).font(.system(size: 16, weight: .medium)) }
                else if let text { Text(text).font(.system(size: small ? 13 : 21, weight: small ? .semibold : .regular).width(small ? .expanded : .standard)).tracking(small ? 2 : 0) }
            }
            .foregroundStyle(pressed ? AK.ink : (small ? AK.muted : AK.bone))
            .frame(maxWidth: .infinity)
            if agentTab {
                Capsule().fill(held ? AK.bone : AK.mint).frame(width: 3, height: 16).padding(.trailing, 3)
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
