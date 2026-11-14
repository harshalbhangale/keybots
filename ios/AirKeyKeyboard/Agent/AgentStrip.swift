import SwiftUI

/// Colours that follow the app you're typing in, light or dark, the way the
/// keys do.
struct StripPalette {
    let dark: Bool
    var function: Color { dark ? .white.opacity(0.12) : .black.opacity(0.08) }
    var text: Color { dark ? .white : Color(white: 0.07) }
    var soft: Color { text.opacity(0.55) }
}

/// AIRKEY's agents in the strip above the keys. It takes the toolbar's place
/// while it has something to say, one thing at a time: the outcome of what
/// just ran, a note, the work in progress, your saved addresses, what your
/// words would do, or an answer looked up as you type.
struct AgentStrip: View {
    let model: AgentModel
    @Environment(\.colorScheme) private var scheme
    /// The result chip is showing its technical message (the rule code and all) in place of the plain line.
    @State private var showDetails = false

    /// Which chip is up, so one soft tap marks a new one arriving and
    /// nothing fires while its words change as you type.
    private var chip: Int {
        if model.result != nil || model.notice != nil || model.pasteWarning != nil || model.running != nil || model.vaultOpen { return 0 }
        if model.ready != nil { return 1 }
        if model.answer != nil { return 2 }
        return model.instant != nil ? 3 : 0
    }

    var body: some View {
        let palette = StripPalette(dark: scheme == .dark)
        Group {
            if let r = model.result {
                result(r, palette)
            } else if let notice = model.notice {
                self.notice(notice, palette)
            } else if let warning = model.pasteWarning {
                self.warning(warning, palette)
            } else if let source = model.running {
                working(source, palette)
            } else if model.vaultOpen {
                vault(palette)
            } else if let ready = model.ready {
                self.ready(ready, palette)
            } else if let a = model.answer {
                suggestion(
                    icon: a.buy == nil ? "banknote" : "chart.line.uptrend.xyaxis", title: a.title, detail: a.detail,
                    action: a.buy == nil ? "Insert" : "Buy", primary: a.buy != nil, palette: palette,
                    onTap: { model.insertAnswer() }, onAction: { a.buy == nil ? model.insertAnswer() : model.buyAnswer() }
                )
            } else if let i = model.instant {
                suggestion(icon: "equal", title: i.title, detail: i.detail, action: "Insert", primary: false, palette: palette,
                           onTap: { model.insertInstant() }, onAction: { model.insertInstant() })
            }
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.snappy(duration: 0.22), value: model.ready)
        .animation(.snappy(duration: 0.22), value: model.running)
        .onChange(of: chip) { old, new in if new != 0, old == 0 { Haptics.chip() } }
        .onChange(of: model.result?.id) { showDetails = false }
    }

    private static let height: CGFloat = 38

    /// Your NEAR account and saved addresses. A tap puts one in the message.
    private func vault(_ palette: StripPalette) -> some View {
        HStack(spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(model.vaultItems) { item in
                        Button { model.insertVault(item) } label: {
                            HStack(spacing: 6) {
                                Text(item.label).font(.footnote.weight(.semibold)).foregroundStyle(palette.text)
                                Text(item.value)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(palette.soft)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .frame(maxWidth: 150)
                            }
                            .padding(.horizontal, 12)
                            .frame(height: 30)
                            .background(palette.function, in: Capsule())
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Insert \(item.label), \(item.value)")
                    }
                }
                .padding(.leading, 4)
            }
            // In a strip this short, iOS's soft scroll-edge blur would cover the chips.
            .scrollEdgeEffectHidden(true, for: .all)
            close(palette)
        }
        .frame(height: Self.height)
        .glassEffect(.regular, in: .capsule)
    }

    /// Your words read as an action. Press and hold to run it, so a stray
    /// tap while chatting never moves money.
    private func ready(_ intent: AgentModel.Ready, _ palette: StripPalette) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: intent.icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AK.ink)
                    .frame(width: 28, height: 28)
                    .background(AK.accent, in: Circle())
                VStack(alignment: .leading, spacing: 0) {
                    Text(intent.title).font(.footnote.weight(.semibold)).foregroundStyle(palette.text).lineLimit(1).minimumScaleFactor(0.8)
                    if !intent.lines.isEmpty {
                        // A copied call's checks, one line at a time.
                        TimelineView(.periodic(from: .now, by: 2.6)) { context in
                            let i = Int(context.date.timeIntervalSinceReferenceDate / 2.6) % intent.lines.count
                            Text(intent.lines[i]).font(.caption2).foregroundStyle(palette.soft).lineLimit(1).minimumScaleFactor(0.75)
                                .contentTransition(.opacity)
                                .animation(.easeInOut(duration: 0.35), value: i)
                        }
                    } else if let detail = intent.detail {
                        Text(detail).font(.caption2).foregroundStyle(palette.soft).lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
            }
            .accessibilityElement(children: .combine)
            // Trade panel hook: a tap on a trade's chip opens the swap screen too.
            .contentShape(Rectangle())
            .onTapGesture {
                if intent.callText != nil, model.reviewCall() { Haptics.layer() }
                else if intent.kind == .swap, model.reviewReady() { Haptics.layer() }
            }
            if intent.callText != nil {
                // A copied call: one path to a trade, through its review card.
                Button { Haptics.layer(); model.reviewCall() } label: {
                    Text("Review trade").font(.footnote.weight(.semibold)).foregroundStyle(AK.ink)
                        .padding(.horizontal, 12).frame(height: 30)
                        .background(AK.accent, in: Capsule()).contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .fixedSize()
                .accessibilityHint("Shows the trade first. Nothing trades yet.")
            } else {
                HoldToConfirm(label: intent.holdLabel, holding: nil, icon: nil, height: 30, font: .footnote.weight(.semibold)) {
                    model.runReady()
                }
                .fixedSize()
            }
        }
        .padding(.leading, 5)
        .padding(.trailing, 5)
        .frame(height: Self.height)
        .glassEffect(.regular, in: .capsule)
    }

    /// An answer the keyboard found: a price, a conversion or a sum. Tap it
    /// to put it in the message; the button on the right is the one next step.
    private func suggestion(icon: String, title: String, detail: String, action: String, primary: Bool, palette: StripPalette,
                            onTap: @escaping () -> Void, onAction: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
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
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(primary ? AK.ink : palette.text)
                    .padding(.horizontal, 14)
                    .frame(height: 30)
                    .background(primary ? AK.accent : palette.function, in: Capsule())
            }
            .buttonStyle(.plain)
            close(palette)
        }
        .padding(.leading, 5)
        .frame(height: Self.height)
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    private func working(_ source: String, _ palette: StripPalette) -> some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small).tint(palette.text)
            Text(Plain.working(pasted: source == "pasted", swap: model.runningKind == .swap))
                .font(.footnote.weight(.medium))
                .foregroundStyle(palette.text)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(height: Self.height)
        .glassEffect(.regular, in: .capsule)
    }

    private func result(_ r: Receipt, _ palette: StripPalette) -> some View {
        let plain = r.signal.plain
        return HStack(spacing: 8) {
            Image(systemName: r.signal.icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(plain ? palette.text : AK.ink)
                .frame(width: 28, height: 28)
                .background(plain ? palette.function : r.signal.color, in: Circle())
            // The plain line; a tap turns it over to the technical message, rule code and all.
            Button {
                Haptics.layer()
                showDetails.toggle()
            } label: {
                HStack(spacing: 4) {
                    Text(showDetails ? Plain.details(r) : Plain.line(r))
                        .font(showDetails ? .caption2.monospaced() : .caption.weight(.medium))
                        .foregroundStyle(palette.text)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(showDetails ? Plain.details(r) : "\(Plain.title(r)). \(Plain.body(r))")
            .accessibilityHint(showDetails ? "Shows the plain line" : "Shows the details")
            if !showDetails, r.decision?.rule != nil || r.message != Plain.line(r) {
                Text("Details").font(.caption2.weight(.semibold)).foregroundStyle(palette.soft)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
            if r.tx != nil, !showDetails {
                Button { model.insertReceipt() } label: {
                    Text("Share").font(.footnote.weight(.semibold)).foregroundStyle(palette.text)
                        .padding(.horizontal, 12).frame(height: 30).background(palette.function, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Puts the receipt in the chat")
            }
            close(palette)
        }
        .padding(.leading, 5)
        .frame(height: Self.height)
        .glassEffect(plain ? .regular : .regular.tint(r.signal.color.opacity(0.22)), in: .capsule)
        .accessibilityElement(children: .contain)
    }

    private func notice(_ text: String, _ palette: StripPalette) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle.fill").foregroundStyle(AK.amber)
            Text(text).font(.caption.weight(.medium)).foregroundStyle(palette.text).lineLimit(2).minimumScaleFactor(0.85)
            Spacer(minLength: 4)
            close(palette)
        }
        .padding(.leading, 12)
        .frame(height: Self.height)
        .glassEffect(.regular, in: .capsule)
    }

    /// The paste guard: an address you don't know arrived whole.
    private func warning(_ text: String, _ palette: StripPalette) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.shield.fill").foregroundStyle(AK.amber)
            Text(text).font(.caption.weight(.medium)).foregroundStyle(palette.text).lineLimit(2).minimumScaleFactor(0.85)
            Spacer(minLength: 4)
            close(palette)
        }
        .padding(.leading, 12)
        .frame(height: Self.height)
        .glassEffect(.regular.tint(AK.amber.opacity(0.22)), in: .capsule)
        .accessibilityElement(children: .combine)
    }

    private func close(_ palette: StripPalette) -> some View {
        Button { model.dismiss() } label: {
            Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(palette.soft)
                .frame(width: 32, height: 32).contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Dismiss")
    }
}
