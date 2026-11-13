import SwiftUI
import UIKit

/// The Wallet, over the keys: everything the leash holds and has done, in
/// five short sections. It only reads. The one thing it writes is words into
/// the message ("pay vendor 0.2", an address, a receipt), and paying still
/// takes the strip's press and hold.
struct WalletView: View {
    let model: WalletModel
    let actions: MoneyActions
    @Environment(\.colorScheme) private var scheme

    enum Tab: Hashable { case balance, activity, orders, pay, addresses }
    @State private var tab: Tab = .balance
    /// The receipt opened from Activity.
    @State private var opened: Receipt?
    @State private var copied = false
    @State private var linkNote: String?
    // Pay
    @State private var payee: String?
    @State private var amount = ""

    private var palette: MoneyPalette { MoneyPalette(dark: scheme == .dark) }

    var body: some View {
        let p = palette
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                MoneyTabs(tabs: tabs, selection: $tab, palette: p)
                    .padding(.horizontal, 10)
            }
            .scrollEdgeEffectHidden(true, for: .all)
            Group {
                if !actions.fullAccess() {
                    MoneyEmpty(text: "Turn on Allow Full Access for AIRKEY so the wallet can reach your server.", palette: p)
                } else if let s = model.state {
                    switch tab {
                    case .balance: balance(s, p)
                    case .activity: activity(p)
                    case .orders: orders(p)
                    case .pay: pay(s, p)
                    case .addresses: addresses(p)
                    }
                } else if let problem = model.problem {
                    VStack(spacing: 10) {
                        Text(problem).font(.footnote).foregroundStyle(p.soft).multilineTextAlignment(.center)
                        pill("Retry", p, primary: true) { Haptics.letter(); model.retry() }
                    }
                    .padding(.horizontal, 24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 10) {
                        ProgressView().tint(p.text)
                        Text("Reading the leash on NEAR…").font(.footnote).foregroundStyle(p.soft)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.top, 4)
        .padding(.bottom, 4)
        .foregroundStyle(p.text)
        .onAppear { model.start() }
        .onDisappear { model.stop() }
        .onChange(of: tab) { opened = nil; linkNote = nil }
    }

    private var tabs: [(tab: Tab, label: String)] {
        let waiting = model.watchingOrders.count
        return [
            (.balance, "Balance"), (.activity, "Activity"),
            (.orders, waiting > 0 ? "Orders \(waiting)" : "Orders"),
            (.pay, "Pay"), (.addresses, "Addresses"),
        ]
    }

    // MARK: Balance

    private func balance(_ s: LeashState, _ p: MoneyPalette) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 0) {
                        label("Spendable", p)
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text(Fmt.near(s.available, unit: false))
                                .font(.system(size: 32, weight: .bold, design: .rounded).monospacedDigit())
                                .contentTransition(.numericText())
                                .lineLimit(1).minimumScaleFactor(0.6)
                            Text("NEAR").font(.footnote.weight(.bold)).foregroundStyle(p.soft)
                        }
                        Text(model.usd(Fmt.near(s.available, unit: false), "NEAR") ?? " ")
                            .font(.footnote.weight(.medium).monospacedDigit()).foregroundStyle(p.soft)
                            .contentTransition(.numericText())
                    }
                    Spacer(minLength: 0)
                    account(s.leash, p)
                }

                // NEAR and every token the leash holds.
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                    token("NEAR", Fmt.near(s.available, unit: false), p)
                    ForEach(s.holdings ?? []) { h in token(h.symbol, h.amount, p) }
                }

                VStack(alignment: .leading, spacing: 8) {
                    label("Agents · today", p)
                    ForEach(s.shownAgents) { entry in agent(entry, s, p) }
                }

                VStack(alignment: .leading, spacing: 6) {
                    status(icon: s.paused ? "hand.raised.fill" : "checkmark.shield",
                           tint: s.paused ? p.bad : p.soft,
                           title: s.paused ? "Kill switch is on. Agents are stopped." : "Kill switch is off",
                           detail: "Change in the AIRKEY app", p)
                    status(icon: s.pending.isEmpty ? "tray" : "hourglass",
                           tint: s.pending.isEmpty ? p.soft : p.warn,
                           title: s.pending.isEmpty ? "Nothing waiting for you"
                               : "\(s.pending.count) payment\(s.pending.count == 1 ? "" : "s") waiting for you",
                           detail: s.pending.isEmpty ? nil : "Open the AIRKEY app to approve", p)
                }
            }
            .padding(.bottom, 8)
        }
        .scrollEdgeEffectHidden(true, for: .all)
        .animation(.snappy(duration: 0.25), value: s.available)
    }

    /// leash.airkey-harshal.testnet with a copy glyph: tap to copy it whole.
    private func account(_ account: String, _ p: MoneyPalette) -> some View {
        Button {
            UIPasteboard.general.string = account
            Haptics.success()
            withAnimation(.snappy(duration: 0.2)) { copied = true }
            Task {
                try? await Task.sleep(for: .seconds(1.4))
                withAnimation(.snappy(duration: 0.2)) { copied = false }
            }
        } label: {
            HStack(spacing: 5) {
                Text(copied ? "Copied" : account)
                    .font(.caption.weight(.semibold).monospaced())
                    .lineLimit(1).truncationMode(.middle)
                Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(copied ? p.good : p.text)
            .padding(.horizontal, 10)
            .frame(maxWidth: 190)
            .frame(height: 28)
            .fixedSize(horizontal: true, vertical: false)
            .background(p.fill, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(MoneyPress())
        .accessibilityLabel("Copy the leash account, \(account)")
    }

    private func token(_ symbol: String, _ amount: String, _ p: MoneyPalette) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(symbol).font(.caption2.weight(.heavy)).foregroundStyle(p.soft)
            Text(amount).font(.subheadline.weight(.bold).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
            Text(model.usd(amount, symbol) ?? " ").font(.caption2.monospacedDigit()).foregroundStyle(p.soft).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(p.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// One agent: its role, what it has spent today of its daily cap, as a thin bar.
    private func agent(_ entry: LeashState.AgentEntry, _ s: LeashState, _ p: MoneyPalette) -> some View {
        let share = Fmt.share(entry.agent.spent_today, of: entry.agent.daily_cap)
        return VStack(spacing: 4) {
            HStack {
                Text(s.roleNames[entry.account] ?? Fmt.agentName(account: entry.account)).font(.footnote.weight(.semibold))
                Spacer(minLength: 4)
                Text("\(Fmt.near(entry.agent.spent_today, unit: false)) of \(Fmt.near(entry.agent.daily_cap))")
                    .font(.caption.monospacedDigit()).foregroundStyle(p.soft)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(p.fill)
                    Capsule().fill(share >= 1 ? p.warn : p.good)
                        .frame(width: share > 0 ? max(3, g.size.width * share) : 0)
                }
            }
            .frame(height: 3)
        }
        .accessibilityElement(children: .combine)
    }

    private func status(icon: String, tint: Color, title: String, detail: String?, _ p: MoneyPalette) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 12, weight: .semibold)).foregroundStyle(tint).frame(width: 18)
            Text(title).font(.footnote.weight(.medium)).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            if let detail { Text(detail).font(.caption).foregroundStyle(p.soft).lineLimit(1).minimumScaleFactor(0.8) }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Activity

    @ViewBuilder
    private func activity(_ p: MoneyPalette) -> some View {
        if let r = opened {
            receipt(r, p).transition(.move(edge: .trailing).combined(with: .opacity))
        } else if model.receipts.isEmpty {
            MoneyEmpty(text: "Nothing yet. What your agents pay, swap or stop shows here.", palette: p)
        } else {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(model.receipts) { r in
                        Button {
                            Haptics.letter()
                            withAnimation(.snappy(duration: 0.22)) { opened = r }
                        } label: {
                            HStack(spacing: 10) {
                                mark(r.signal, p, size: 22)
                                Text(r.message).font(.footnote).lineLimit(1)
                                Spacer(minLength: 6)
                                Text(Fmt.time(r.date)).font(.caption2.monospacedDigit()).foregroundStyle(p.soft)
                            }
                            .frame(height: 36)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(MoneyPress())
                        .overlay(alignment: .bottom) { Rectangle().fill(p.line).frame(height: 1) }
                        .accessibilityLabel("\(r.signal.title). \(r.message)")
                    }
                }
                .padding(.bottom, 8)
            }
            .scrollEdgeEffectHidden(true, for: .all)
            .transition(.move(edge: .leading).combined(with: .opacity))
        }
    }

    /// The outcome's mark: lime for done, amber for waiting, red for stopped.
    private func mark(_ signal: Signal, _ p: MoneyPalette, size: CGFloat) -> some View {
        Image(systemName: signal.icon)
            .font(.system(size: size * 0.45, weight: .bold))
            .foregroundStyle(signal.plain ? p.text : AK.ink)
            .frame(width: size, height: size)
            .background(signal.plain ? p.fill : signal.color, in: Circle())
    }

    /// One receipt, whole: what happened, who did it, the transaction, and
    /// Share to put it in the chat.
    private func receipt(_ r: Receipt, _ p: MoneyPalette) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    Haptics.letter()
                    withAnimation(.snappy(duration: 0.22)) { opened = nil; linkNote = nil }
                } label: {
                    Image(systemName: "chevron.left").font(.system(size: 13, weight: .bold))
                        .frame(width: 28, height: 28).background(p.fill, in: Circle()).contentShape(Circle())
                }
                .buttonStyle(MoneyPress())
                .accessibilityLabel("Back to activity")
                mark(r.signal, p, size: 22)
                Text(r.signal.title).font(.footnote.weight(.bold))
                Spacer(minLength: 4)
                Text(Fmt.time(r.date)).font(.caption.monospacedDigit()).foregroundStyle(p.soft)
            }
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(r.message).font(.footnote).fixedSize(horizontal: false, vertical: true)
                    Text(detail(r)).font(.caption).foregroundStyle(p.soft).fixedSize(horizontal: false, vertical: true)
                    if let linkNote { Text(linkNote).font(.caption).foregroundStyle(p.soft) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollEdgeEffectHidden(true, for: .all)
            HStack(spacing: 8) {
                if let tx = r.tx, let url = URL(string: tx.url) {
                    pill("Transaction ↗", p, primary: false) {
                        Haptics.letter()
                        actions.open(url) { opened in
                            if !opened {
                                UIPasteboard.general.string = tx.url
                                linkNote = "Link copied. Paste it in Safari."
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
                pill("Share in chat", p, primary: true) {
                    Haptics.letter()
                    actions.share(MoneyText.receiptLine(message: r.message, signal: r.signal, tx: r.tx))
                }
            }
        }
        .padding(.bottom, 6)
    }

    /// "“pay drain 3” · Payment Agent · tx 9xQ…k2a"
    private func detail(_ r: Receipt) -> String {
        var parts = ["“\(r.input.text)”"]
        if let a = r.agent { parts.append(Fmt.agentName(account: a.account)) }
        if let rule = r.decision?.rule { parts.append("rule: \(rule)") }
        if let tx = r.tx { parts.append("tx \(tx.hash.prefix(6))…\(tx.hash.suffix(4))") }
        return parts.joined(separator: " · ")
    }

    // MARK: Orders

    @ViewBuilder
    private func orders(_ p: MoneyPalette) -> some View {
        let watching = model.watchingOrders
        if watching.isEmpty {
            MoneyEmpty(text: "No orders watching a price. Type one, like “sell 1 near if it drops below 2”.", palette: p)
        } else {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(watching) { o in
                        HStack(spacing: 10) {
                            Image(systemName: "eye").font(.system(size: 11, weight: .bold))
                                .frame(width: 24, height: 24).background(p.fill, in: Circle())
                            VStack(alignment: .leading, spacing: 0) {
                                Text(o.command).font(.footnote.weight(.semibold)).lineLimit(1)
                                Text(o.condition).font(.caption2).foregroundStyle(p.soft).lineLimit(1)
                            }
                            Spacer(minLength: 6)
                            if model.cancelling == o.id {
                                ProgressView().controlSize(.small).tint(p.text).frame(width: 64)
                            } else {
                                Button { Haptics.modifier(); model.cancel(o) } label: {
                                    Text("Cancel").font(.footnote.weight(.semibold)).foregroundStyle(p.bad)
                                        .padding(.horizontal, 12).frame(height: 28)
                                        .background(p.fill, in: Capsule()).contentShape(Capsule())
                                }
                                .buttonStyle(MoneyPress())
                                .accessibilityLabel("Cancel \(o.command) \(o.condition)")
                            }
                        }
                        .frame(height: 42)
                        .overlay(alignment: .bottom) { Rectangle().fill(p.line).frame(height: 1) }
                    }
                    if let note = model.note { Text(note).font(.caption).foregroundStyle(p.bad).padding(.top, 6) }
                }
                .padding(.bottom, 8)
            }
            .scrollEdgeEffectHidden(true, for: .all)
        }
    }

    // MARK: Pay

    /// Pick a contact and an amount; Fill writes "pay vendor 0.2" in the
    /// message, where the strip offers its hold. Nothing is sent from here.
    private func pay(_ s: LeashState, _ p: MoneyPalette) -> some View {
        let names = model.payees
        let ready = payee != nil && (Double(amount) ?? 0) > 0
        return HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                label("Pay someone", p)
                if names.isEmpty {
                    Text("No contacts on this server yet.").font(.caption).foregroundStyle(p.soft)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(names, id: \.self) { name in
                                let on = payee == name
                                Button { Haptics.layer(); payee = name } label: {
                                    Text(name).font(.footnote.weight(.semibold))
                                        .foregroundStyle(on ? AK.ink : p.text)
                                        .padding(.horizontal, 11).frame(height: 28)
                                        .background(on ? AK.accent : p.fill, in: Capsule()).contentShape(Capsule())
                                }
                                .buttonStyle(MoneyPress())
                            }
                        }
                    }
                    .scrollEdgeEffectHidden(true, for: .all)
                }
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(amount.isEmpty ? "0" : amount)
                        .font(.system(size: 28, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(amount.isEmpty ? p.faint : p.text)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text("NEAR").font(.footnote.weight(.bold)).foregroundStyle(p.soft)
                    Text(model.usd(amount, "NEAR") ?? "").font(.caption.monospacedDigit()).foregroundStyle(p.soft)
                }
                Spacer(minLength: 0)
                Button {
                    guard ready, let payee else { return }
                    Haptics.modifier()
                    actions.insert("pay \(payee) \(amount)")
                } label: {
                    Text(payee.map { "Fill “pay \($0) \(amount.isEmpty ? "…" : amount)”" } ?? "Pick who to pay")
                        .font(.footnote.weight(.bold)).foregroundStyle(ready ? AK.ink : p.soft)
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity).frame(height: 34)
                        .background(ready ? AK.accent : p.fill, in: Capsule()).contentShape(Capsule())
                }
                .buttonStyle(MoneyPress())
                .disabled(!ready)
                Text("Goes in the message. You hold to pay.").font(.caption2).foregroundStyle(p.soft).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            pad(p).frame(width: 150)
        }
        .padding(.bottom, 6)
    }

    private static let padKeys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", ".", "0", "⌫"]

    /// The amount's own number keys: the letters are under the panel.
    private func pad(_ p: MoneyPalette) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 3), spacing: 5) {
            ForEach(Self.padKeys, id: \.self) { key in
                Button { tap(key) } label: {
                    Group {
                        if key == "⌫" { Image(systemName: "delete.left").font(.system(size: 15, weight: .medium)) }
                        else { Text(key).font(.system(size: 19, weight: .medium, design: .rounded)) }
                    }
                    .frame(maxWidth: .infinity).frame(height: 36)
                    .background(p.fill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(MoneyPress())
                .accessibilityLabel(key == "⌫" ? "Delete" : key)
            }
        }
    }

    private func tap(_ key: String) {
        switch key {
        case "⌫":
            guard !amount.isEmpty else { return }
            Haptics.delete()
            amount.removeLast()
        case ".":
            guard !amount.contains(".") else { return }
            Haptics.letter()
            amount += amount.isEmpty ? "0." : "."
        default:
            // Up to 4 decimals, the way NEAR amounts are shown; no "007".
            if let dot = amount.firstIndex(of: "."), amount[dot...].count > 4 { return }
            guard amount.count < 9 else { return }
            Haptics.letter()
            amount = amount == "0" ? key : amount + key
        }
    }

    // MARK: Addresses

    /// Your NEAR account and saved addresses. A tap puts one in the message.
    @ViewBuilder
    private func addresses(_ p: MoneyPalette) -> some View {
        let items = Vault.all
        if items.isEmpty {
            MoneyEmpty(text: "Add addresses in the AIRKEY app, in Settings › Vault.", palette: p)
        } else {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(items) { item in
                        Button { Haptics.letter(); actions.insert(item.value) } label: {
                            HStack(spacing: 10) {
                                Text(item.label).font(.footnote.weight(.semibold)).lineLimit(1)
                                Spacer(minLength: 6)
                                Text(item.value).font(.caption.monospaced()).foregroundStyle(p.soft)
                                    .lineLimit(1).truncationMode(.middle).frame(maxWidth: 200, alignment: .trailing)
                                Image(systemName: "arrow.up.left").font(.system(size: 10, weight: .bold)).foregroundStyle(p.faint)
                            }
                            .frame(height: 38)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(MoneyPress())
                        .overlay(alignment: .bottom) { Rectangle().fill(p.line).frame(height: 1) }
                        .accessibilityLabel("Insert \(item.label), \(item.value)")
                    }
                }
                .padding(.bottom, 8)
            }
            .scrollEdgeEffectHidden(true, for: .all)
        }
    }

    // MARK: Pieces

    private func label(_ text: String, _ p: MoneyPalette) -> some View {
        Text(text.uppercased()).font(.system(size: 10, weight: .heavy)).tracking(0.6).foregroundStyle(p.soft)
    }

    private func pill(_ title: String, _ p: MoneyPalette, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.footnote.weight(.semibold))
                .foregroundStyle(primary ? AK.ink : p.text)
                .padding(.horizontal, 14).frame(height: 30)
                .background(primary ? AK.accent : p.fill, in: Capsule()).contentShape(Capsule())
        }
        .buttonStyle(MoneyPress())
    }
}
