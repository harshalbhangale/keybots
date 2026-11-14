import SwiftUI

/// The trade panel, in the keyboard: what you pay over what you get, the
/// quote's details under them, and one press-and-hold to run it. Amounts are
/// typed on the keyboard's own keys; tokens come from NEAR Intents' list.
struct TradePanel: View {
    let model: TradeModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = StripPalette(dark: scheme == .dark)
        Group {
            switch model.mode {
            case .panel: panel(p)
            case .number(let field): numberStrip(field, p)
            case .tokens(let side): tokenList(side, p)
            case .search(let side): searchStrip(side, p)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.snappy(duration: 0.22), value: model.live)
        .animation(.snappy(duration: 0.22), value: model.kind)
    }

    // MARK: The panel

    private func panel(_ p: StripPalette) -> some View {
        VStack(spacing: 6) {
            header(p)
            ZStack {
                VStack(spacing: 4) {
                    card(.pay, p)
                    card(.get, p)
                }
                flip(p)
            }
            if model.isOrder { triggerRow(p) }
            details(p)
            if let line = model.orderLine {
                Text(line)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(p.soft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
            }
            Spacer(minLength: 0)
            go(p)
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    /// Swap · Limit · Stop-loss · Take profit, and the way out.
    private func header(_ p: StripPalette) -> some View {
        HStack(spacing: 6) {
            HStack(spacing: 0) {
                ForEach(TradeModel.Kind.allCases) { kind in
                    let on = kind == model.kind
                    Button { model.set(kind: kind) } label: {
                        Text(kind.title)
                            .font(.footnote.weight(on ? .semibold : .medium))
                            .foregroundStyle(on ? p.text : p.soft)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .padding(.horizontal, 10)
                            .frame(height: 26)
                            .background(on ? p.function : .clear, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(2)
            .background(p.function.opacity(0.5), in: Capsule())
            Spacer(minLength: 0)
            Button { model.onClose?() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(p.soft)
                    .frame(width: 30, height: 30)
                    .background(p.function, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .frame(height: 30)
    }

    /// One side of the trade: what it is and its dollar value, the amount,
    /// the token, and what the leash holds of it.
    private func card(_ side: TradeModel.Side, _ p: StripPalette) -> some View {
        let pay = side == .pay
        let symbol = pay ? model.from : model.to
        let shown: String = pay ? model.amount : (model.live?.amountOut ?? "")
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Text(pay ? "You pay" : model.isOrder ? "You'd get" : "You get")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(p.soft)
                    if let d = model.dollars(side) {
                        Text(d).font(.caption.monospacedDigit()).foregroundStyle(p.soft).contentTransition(.numericText())
                    }
                }
                Text(shown.isEmpty ? "0" : shown)
                    .font(.system(size: 24, weight: .semibold).monospacedDigit())
                    .foregroundStyle(shown.isEmpty ? p.soft : p.text)
                    .opacity(!pay && model.asking ? 0.45 : 1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { if pay { Haptics.layer(); model.show(.number(.amount)) } }
                    .accessibilityLabel(pay ? "Amount, \(shown.isEmpty ? "none" : shown) \(symbol). Tap to change." : "\(shown.isEmpty ? "No quote yet" : shown) \(symbol)")
            }
            VStack(alignment: .trailing, spacing: 3) {
                Button { Haptics.layer(); model.show(.tokens(side)) } label: { pill(symbol, p) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(symbol). Tap to change token.")
                if let held = model.held(side) {
                    Text(held)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(p.soft)
                        .lineLimit(1)
                        .onTapGesture { if pay { model.useMax() } }
                        .accessibilityHint(pay ? "Tap to use all of it" : "")
                }
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .frame(height: model.isOrder ? 52 : 58)
        .background(p.function, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func pill(_ symbol: String, _ p: StripPalette) -> some View {
        HStack(spacing: 5) {
            mark(symbol, p, size: 18)
            Text(symbol).font(.subheadline.weight(.semibold)).foregroundStyle(p.text)
            Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(p.soft)
        }
        .padding(.leading, 5)
        .padding(.trailing, 9)
        .frame(height: 28)
        .background(p.function, in: Capsule())
        .contentShape(Capsule())
    }

    /// A token's mark: its first letter on a disc (no image files in a keyboard).
    private func mark(_ symbol: String, _ p: StripPalette, size: CGFloat) -> some View {
        Text(String(symbol.prefix(1)))
            .font(.system(size: size * 0.55, weight: .bold, design: .rounded))
            .foregroundStyle(symbol == "NEAR" ? AK.ink : p.text)
            .frame(width: size, height: size)
            .background(symbol == "NEAR" ? AK.accent : p.text.opacity(0.14), in: Circle())
    }

    private func flip(_ p: StripPalette) -> some View {
        Button { model.flip() } label: {
            Image(systemName: "arrow.down")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(p.text)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel("Swap the two tokens")
    }

    /// An order's price: "When NEAR is below $ 1.5 · now $3.52".
    private func triggerRow(_ p: StripPalette) -> some View {
        HStack(spacing: 8) {
            Text("When \(model.watched) is \(model.direction)")
                .font(.footnote.weight(.medium))
                .foregroundStyle(p.soft)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Button { Haptics.layer(); model.show(.number(.trigger)) } label: {
                Text(model.trigger.isEmpty ? "$ price" : "$\(model.trigger)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(model.trigger.isEmpty ? p.soft : p.text)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(p.function, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Trigger price, \(model.trigger.isEmpty ? "not set" : model.trigger) dollars. Tap to change.")
            Spacer(minLength: 0)
            if let now = model.watchedPrice {
                Text("Now \(Fmt.usd(now))").font(.caption.monospacedDigit()).foregroundStyle(p.soft).lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
        .background(p.function, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// The quote, line by line. Dashes until one lands: never a made-up figure.
    private func details(_ p: StripPalette) -> some View {
        let q = model.live
        var rows: [(String, String)] = [("Rate", q?.rate ?? "—")]
        if !model.isOrder {
            rows.append(("Minimum received", q.map { "\($0.minReceived) \($0.to.symbol) · impact \(Self.impact($0))" } ?? "—"))
            rows.append(("Route", q.map(Self.route) ?? "—"))
        }
        rows.append(("Network fee", q.map { "\($0.networkFee.amount) \($0.networkFee.symbol)" + ($0.networkFee.usd.map { " ≈ $\($0)" } ?? "") } ?? "—"))
        rows.append(("Trading Agent limit", q?.caps.map { "\($0.perTrade) NEAR a trade · \($0.leftToday) left today" } ?? "—"))
        return VStack(spacing: 2) {
            ForEach(rows, id: \.0) { row in
                HStack(spacing: 8) {
                    Text(row.0).font(.caption).foregroundStyle(p.soft).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(row.1)
                        .font(.caption.weight(.medium).monospacedDigit())
                        .foregroundStyle(p.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .contentTransition(.numericText())
                }
                .frame(height: 15)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, 8)
        .opacity(model.asking && q == nil ? 0.5 : 1)
    }

    private static func route(_ q: TradeQuote) -> String {
        if q.route.venue == "Rhea" {
            let pools = q.route.pools ?? q.route.pool.map { [$0] } ?? []
            return pools.count > 1 ? "Rhea testnet · pools \(pools.map(String.init).joined(separator: " → "))" : "Rhea testnet · pool \(pools.first.map(String.init) ?? "")"
        }
        if let s = q.route.seconds { return "\(q.route.venue) · ~\(Int(s)) s" }
        return q.route.venue
    }

    private static func impact(_ q: TradeQuote) -> String {
        guard let i = q.priceImpact else { return "—" }
        return i < 0.01 ? "<0.01%" : "\(String(format: "%.2f", i))%"
    }

    /// The one button: a hold when the trade may run, the reason when it may not.
    @ViewBuilder
    private func go(_ p: StripPalette) -> some View {
        if let why = model.blocked {
            HStack(spacing: 8) {
                if model.asking { ProgressView().controlSize(.small).tint(p.soft) }
                Text(why).font(.subheadline.weight(.semibold)).foregroundStyle(p.soft).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(p.function, in: Capsule())
            .accessibilityLabel("\(model.kind.hold) is off: \(why)")
        } else {
            HoldToConfirm(label: model.holdLabel, holding: "Keep holding", icon: nil, height: 44, font: .body.weight(.bold)) {
                model.run()
            }
        }
    }

    // MARK: Typing a value

    /// Over the keys while an amount or a price is typed: the value, what it
    /// gets right now, and Done.
    private func numberStrip(_ field: TradeModel.Field, _ p: StripPalette) -> some View {
        let value = field == .amount ? model.amount : model.trigger
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text(field == .amount ? "You pay · \(model.from)" : "\(model.watched) \(model.direction) · price in $")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(p.soft)
                    .lineLimit(1)
                HStack(spacing: 2) {
                    if field == .trigger { Text("$").font(.system(size: 24, weight: .semibold)).foregroundStyle(p.soft) }
                    Text(value.isEmpty ? "0" : value)
                        .font(.system(size: 24, weight: .semibold).monospacedDigit())
                        .foregroundStyle(value.isEmpty ? p.soft : p.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Caret()
                }
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 1) {
                if field == .amount {
                    if let q = model.live {
                        Text("→ \(q.amountOut) \(q.to.symbol)").font(.footnote.weight(.semibold).monospacedDigit()).foregroundStyle(p.text)
                    } else if model.asking {
                        ProgressView().controlSize(.small).tint(p.soft)
                    }
                    if let held = model.held(.pay) { Text(held).font(.caption2.monospacedDigit()).foregroundStyle(p.soft) }
                } else if let now = model.watchedPrice {
                    Text("Now \(Fmt.usd(now))").font(.footnote.weight(.semibold).monospacedDigit()).foregroundStyle(p.text)
                }
            }
            .lineLimit(1)
            done(p)
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
    }

    private func done(_ p: StripPalette) -> some View {
        Button { Haptics.layer(); model.show(.panel) } label: {
            Text("Done")
                .font(.footnote.weight(.bold))
                .foregroundStyle(AK.ink)
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(AK.accent, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: Tokens

    /// NEAR Intents' tokens, what trades here first, with the leash's balances.
    private func tokenList(_ side: TradeModel.Side, _ p: StripPalette) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Button { model.show(.panel) } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(p.text)
                        .frame(width: 34, height: 34)
                        .background(p.function, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
                Button { Haptics.layer(); model.show(.search(side)) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").font(.system(size: 13, weight: .semibold))
                        Text("Search tokens").font(.subheadline)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(p.soft)
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(p.function, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            if model.tokens.isEmpty {
                VStack(spacing: 8) {
                    if model.tokensFailed {
                        Text("The token list didn't load.").font(.footnote).foregroundStyle(p.soft)
                        Button("Try again") { model.loadTokens() }.font(.footnote.weight(.semibold)).tint(p.text)
                    } else {
                        ProgressView().tint(p.soft)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.tokens) { token in
                            Button { model.pick(token, for: side) } label: { row(token, p) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                .scrollEdgeEffectHidden(true, for: .all)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
    }

    private func row(_ token: PickerToken, _ p: StripPalette) -> some View {
        HStack(spacing: 10) {
            mark(token.symbol, p, size: 26)
            VStack(alignment: .leading, spacing: 0) {
                Text(token.symbol).font(.subheadline.weight(.semibold)).foregroundStyle(p.text)
                Text(token.tradable ? "Swaps from Spend Limits" : "Quote only here · \(token.chain)")
                    .font(.caption2)
                    .foregroundStyle(p.soft)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 0) {
                if let price = token.price { Text(Fmt.usd(price)).font(.footnote.monospacedDigit()).foregroundStyle(p.text) }
                if let held = token.balance { Text("\(held) held").font(.caption2.monospacedDigit()).foregroundStyle(p.soft) }
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 42)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// Over the letter keys while a token is searched: the search and its matches.
    private func searchStrip(_ side: TradeModel.Side, _ p: StripPalette) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 13, weight: .semibold)).foregroundStyle(p.soft)
                    Text(model.query.isEmpty ? "Search tokens" : model.query)
                        .font(.subheadline.weight(model.query.isEmpty ? .regular : .semibold))
                        .foregroundStyle(model.query.isEmpty ? p.soft : p.text)
                    Caret(height: 18)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(p.function, in: Capsule())
                Button { Haptics.layer(); model.show(.tokens(side)) } label: {
                    Text("Done")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(AK.ink)
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .background(AK.accent, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 6) {
                    ForEach(model.matches) { token in
                        Button { model.pick(token, for: side) } label: {
                            HStack(spacing: 6) {
                                mark(token.symbol, p, size: 18)
                                Text(token.symbol).font(.footnote.weight(.semibold)).foregroundStyle(p.text)
                                if let price = token.price { Text(Fmt.usd(price)).font(.caption2.monospacedDigit()).foregroundStyle(p.soft) }
                            }
                            .padding(.leading, 6)
                            .padding(.trailing, 10)
                            .frame(height: 32)
                            .background(p.function, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    if model.matches.isEmpty {
                        Text(model.tokens.isEmpty ? "Loading tokens…" : "NEAR Intents lists no token like that.")
                            .font(.footnote)
                            .foregroundStyle(p.soft)
                            .frame(height: 32)
                    }
                }
            }
            .scrollEdgeEffectHidden(true, for: .all)
            .frame(height: 32)
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// The blinking bar after a value typed on the keys.
private struct Caret: View {
    var height: CGFloat = 24
    @State private var on = true

    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(AK.accent)
            .frame(width: 2, height: height)
            .opacity(on ? 1 : 0.15)
            .onAppear { withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) { on = false } }
            .accessibilityHidden(true)
    }
}
