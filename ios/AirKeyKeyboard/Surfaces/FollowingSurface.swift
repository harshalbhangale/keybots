import SwiftUI
import UIKit

/// Calls › Following, over the keys: the people whose calls trade for you,
/// each with their record and today's spend, a switch for auto, and what
/// their calls traded for you below. A tap opens that person's rules.
struct FollowingView: View {
    @Bindable var model: FollowsModel
    let actions: MoneyActions
    let palette: MoneyPalette

    /// The person whose rules are open.
    @State private var opened: String?

    var body: some View {
        let p = palette
        VStack(spacing: 6) {
            if let notice = model.notice {
                Button { withAnimation(.snappy(duration: 0.2)) { model.notice = nil } } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle.fill").font(.caption).foregroundStyle(p.warn)
                        Text(MoneyText.plain(notice)).font(.caption).foregroundStyle(p.text).lineLimit(2).multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(p.fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .transition(.opacity)
                .accessibilityHint("Tap to dismiss")
            }
            if let handle = opened, let f = model.follow(handle) {
                FollowRulesView(follow: f, model: model, actions: actions, palette: p) {
                    withAnimation(.snappy(duration: 0.22)) { opened = nil }
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                list(p).transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
        .onChange(of: model.landed) { Haptics.success() }
        .animation(.snappy(duration: 0.25), value: model.trades.map(\.id))
        .animation(.easeOut(duration: 0.6), value: model.fresh)
    }

    @ViewBuilder
    private func list(_ p: MoneyPalette) -> some View {
        if let follows = model.follows {
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 6) {
                    add(p)
                    ForEach(follows) { f in
                        FollowRow(follow: f, model: model, palette: p) {
                            Haptics.letter()
                            model.notice = nil
                            withAnimation(.snappy(duration: 0.22)) { opened = f.id }
                        }
                    }
                    if follows.isEmpty {
                        Text("Follow someone and their calls can trade for you, within rules you set. Nothing trades until you turn auto on.")
                            .font(.caption).foregroundStyle(p.soft).fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 4).padding(.vertical, 4)
                    }
                    label("Traded for you", p).padding(.top, 6)
                    if model.trades.isEmpty {
                        Text("Nothing yet. When someone you follow posts a call that fits your rules, the trade shows here.")
                            .font(.caption).foregroundStyle(p.soft).fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 4)
                    } else {
                        ForEach(model.trades) { t in
                            TradedRow(trade: t, fresh: model.fresh.contains(t.id), palette: p, open: open)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                }
                .padding(.bottom, 8)
            }
            .scrollEdgeEffectHidden(true, for: .all)
        } else if let problem = model.problem {
            VStack(spacing: 10) {
                Text(problem).font(.footnote).foregroundStyle(p.soft).multilineTextAlignment(.center)
                Button { Haptics.letter(); model.retry() } label: {
                    Text("Retry").font(.footnote.weight(.semibold)).foregroundStyle(AK.ink)
                        .padding(.horizontal, 14).frame(height: 30).background(AK.accent, in: Capsule())
                }
                .buttonStyle(MoneyPress())
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 10) {
                ProgressView().tint(p.text)
                Text("Reading who you follow…").font(.footnote).foregroundStyle(p.soft)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Add someone: paste a handle you copied, or pick a caller Kall tracks.
    /// (The panel sits over the keys, so a handle is pasted, not typed.)
    private func add(_ p: MoneyPalette) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Button { paste() } label: {
                    HStack(spacing: 5) {
                        if model.saving != nil {
                            ProgressView().controlSize(.mini).tint(AK.ink)
                        } else {
                            Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                        }
                        Text("Paste a handle").font(.footnote.weight(.bold))
                    }
                    .foregroundStyle(AK.ink)
                    .padding(.horizontal, 12).frame(height: 36)
                    .background(AK.accent, in: Capsule()).contentShape(Capsule())
                }
                .buttonStyle(MoneyPress())
                .disabled(model.saving != nil)
                .accessibilityHint("Follows the @handle or x.com link you copied.")
                ForEach(model.suggestions) { c in
                    Button {
                        Haptics.letter()
                        Task { if await model.add(c.handle) == false { Haptics.warning() } }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "plus").font(.system(size: 9, weight: .bold)).foregroundStyle(p.soft)
                            VStack(alignment: .leading, spacing: 0) {
                                HStack(spacing: 4) {
                                    Text("@\(c.handle)").font(.footnote.weight(.semibold))
                                    Text("\(c.record.hits) hits").font(.caption2.monospacedDigit()).foregroundStyle(p.soft)
                                }
                                if let focus = c.focus {
                                    Text(focus).font(.caption2).foregroundStyle(p.soft).lineLimit(1)
                                }
                            }
                        }
                        .padding(.horizontal, 11).frame(height: 36)
                        .background(p.fill, in: Capsule()).contentShape(Capsule())
                    }
                    .buttonStyle(MoneyPress())
                    .disabled(model.saving != nil)
                    .accessibilityLabel("Follow @\(c.handle), \(c.record.line)\(c.focus.map { ", calls \($0)" } ?? "")")
                }
            }
        }
        .scrollEdgeEffectHidden(true, for: .all)
    }

    private func paste() {
        guard let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            model.notice = UIPasteboard.general.hasStrings
                ? "To paste: Settings › Apps › AIRKEY › Paste from Other Apps › Allow."
                : "Copy someone's @handle or profile link first, or pick one here."
            Haptics.warning()
            return
        }
        Haptics.letter()
        Task { if await model.add(text) == false { Haptics.warning() } }
    }

    private func open(_ link: String) {
        guard let url = URL(string: link) else { return }
        Haptics.letter()
        actions.open(url) { opened in
            if !opened {
                UIPasteboard.general.string = link
                model.notice = "Link copied. Paste it in Safari."
            }
        }
    }

    private func label(_ text: String, _ p: MoneyPalette) -> some View {
        Text(text.uppercased()).font(.system(size: 10, weight: .heavy)).tracking(0.6).foregroundStyle(p.soft)
    }
}

/// One person: handle, record, today's spend, and the auto switch.
private struct FollowRow: View {
    let follow: Follow
    let model: FollowsModel
    let palette: MoneyPalette
    let open: () -> Void

    var body: some View {
        let p = palette
        HStack(spacing: 10) {
            Button(action: open) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("@\(follow.handle)").font(.subheadline.weight(.heavy)).lineLimit(1)
                        if follow.paused {
                            Text(MoneyText.plain(follow.pausedReason ?? "")).font(.caption2.weight(.semibold)).foregroundStyle(p.warn).lineLimit(1)
                        } else {
                            Text(follow.recordLine).font(.caption2.monospacedDigit()).foregroundStyle(p.soft).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 4)
                    if !follow.paused {
                        Text(follow.usedLine).font(.caption2.monospacedDigit()).foregroundStyle(follow.spentTodayUsd >= follow.perDayUsd ? p.warn : p.soft)
                            .lineLimit(1)
                    }
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(p.faint)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(MoneyPress())
            .accessibilityLabel("@\(follow.handle). \(follow.paused ? follow.pausedReason ?? "" : follow.recordLine). \(follow.usedLine) today.")
            .accessibilityHint("Opens the rules for their calls")
            if follow.paused {
                ResumeButton(handle: follow.handle, model: model, palette: p)
            } else {
                MiniSwitch(on: follow.auto, palette: p, label: "Trade @\(follow.handle)'s calls for me") { on in
                    Task { await model.setAuto(follow.handle, on) }
                }
            }
        }
        .padding(.horizontal, 12).frame(height: 48)
        .background(p.fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// A trade made (or not) for you: the plain line, who and when, the post and the transaction.
struct TradedRow: View {
    let trade: AutoTrade
    let fresh: Bool
    let palette: MoneyPalette
    let open: (String) -> Void

    var body: some View {
        let p = palette
        HStack(spacing: 9) {
            Image(systemName: trade.icon)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(trade.signal.plain ? p.soft : AK.ink)
                .frame(width: 20, height: 20)
                .background(trade.signal.plain ? p.fill : trade.signal.color, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(MoneyText.plain(trade.message)).font(.caption.weight(trade.traded ? .semibold : .regular))
                    .foregroundStyle(trade.traded ? p.text : trade.failed ? p.warn : p.soft).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Text(byLine).font(.caption2.monospacedDigit()).foregroundStyle(p.soft).lineLimit(1)
            }
            Spacer(minLength: 4)
            if let post = trade.postUrl { small("Post ↗", p) { open(post) } }
            if let tx = trade.txUrl { small("Tx ↗", p) { open(tx) } }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(fresh ? AK.accent.opacity(p.dark ? 0.18 : 0.30) : p.fill,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(fresh ? p.good.opacity(0.6) : .clear, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    /// "@CryptoKaleo · 2 min. ago" (· "you asked" when it came from the hold)
    private var byLine: String {
        var parts = ["@\(trade.handle)"]
        let time = Fmt.time(trade.date)
        if !time.isEmpty { parts.append(time) }
        if trade.onRequest { parts.append("you asked") }
        return parts.joined(separator: " · ")
    }

    private func small(_ title: String, _ p: MoneyPalette, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.caption2.weight(.semibold))
                .padding(.horizontal, 8).frame(height: 24)
                .background(p.fill, in: Capsule()).contentShape(Capsule())
        }
        .buttonStyle(MoneyPress())
    }
}

/// One person's rules, in the panel: dollars per call and per day, which
/// sides, how sure a call must be, when to stop, Unfollow, and a hold that
/// trades their latest call now.
private struct FollowRulesView: View {
    let follow: Follow
    let model: FollowsModel
    let actions: MoneyActions
    let palette: MoneyPalette
    let back: () -> Void

    @State private var confirmUnfollow = false

    var body: some View {
        let p = palette
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    Haptics.letter()
                    back()
                } label: {
                    Image(systemName: "chevron.left").font(.system(size: 13, weight: .bold))
                        .frame(width: 28, height: 28).background(p.fill, in: Circle()).contentShape(Circle())
                }
                .buttonStyle(MoneyPress())
                .accessibilityLabel("Back to the people you follow")
                VStack(alignment: .leading, spacing: 0) {
                    Text("@\(follow.handle)").font(.footnote.weight(.heavy)).lineLimit(1)
                    Text(follow.recordLine).font(.caption2.monospacedDigit()).foregroundStyle(p.soft).lineLimit(1)
                }
                Spacer(minLength: 4)
                Text(follow.auto ? "Auto on" : "Auto off").font(.caption.weight(.semibold)).foregroundStyle(follow.auto ? p.good : p.soft)
                MiniSwitch(on: follow.auto, palette: p, label: "Trade @\(follow.handle)'s calls for me") { set(\.auto, $0) }
            }
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 8) {
                    row("Per call", p) {
                        chips([1.0, 2, 5], selected: follow.perCallUsd, p) { set(\.perCallUsd, $0) }
                    }
                    row("Per day", p) {
                        chips([3.0, 5, 10], selected: follow.perDayUsd, p) { set(\.perDayUsd, $0) }
                    }
                    row("Calls", p) {
                        HStack(spacing: 5) {
                            chip("Buy only", on: follow.buyOnly, p) { set(\.sides, "buy") }
                            chip("Buy and sell", on: !follow.buyOnly, p) { set(\.sides, "both") }
                        }
                    }
                    toggle("Only sure calls", detail: "Skip calls the reader isn't sure of", on: follow.highOnly, p) { set(\.highOnly, $0) }
                    toggle("Stop after 3 misses in a row", detail: "Auto turns off by itself", on: follow.stopAfterMisses > 0, p) {
                        set(\.stopAfterMisses, $0 ? 3 : 0)
                    }
                    if follow.paused {
                        HStack(spacing: 8) {
                            Text(MoneyText.plain(follow.pausedReason ?? "")).font(.caption).foregroundStyle(p.warn)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 4)
                            ResumeButton(handle: follow.handle, model: model, palette: p)
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        if model.checking == follow.handle {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small).tint(p.text)
                                Text("Reading their latest call…").font(.caption.weight(.medium)).foregroundStyle(p.soft)
                                Spacer(minLength: 0)
                            }
                            .frame(height: 34)
                        } else {
                            HoldToConfirm(label: "Hold to trade their latest call", holding: nil, icon: nil,
                                          height: 34, font: .footnote.weight(.bold), disabled: model.checking != nil) {
                                tradeLatest()
                            }
                        }
                        Text("Up to \(Dollars.text(follow.perCallUsd)), a real testnet trade, within your limits.")
                            .font(.caption2).foregroundStyle(p.soft)
                    }
                    .padding(.top, 2)
                    Button {
                        if confirmUnfollow {
                            Haptics.modifier()
                            let handle = follow.handle
                            back()
                            Task { await model.unfollow(handle) }
                        } else {
                            Haptics.letter()
                            withAnimation(.snappy(duration: 0.2)) { confirmUnfollow = true }
                        }
                    } label: {
                        Text(confirmUnfollow ? "Tap again to unfollow @\(follow.handle)" : "Unfollow")
                            .font(.footnote.weight(.semibold)).foregroundStyle(p.bad)
                            .padding(.horizontal, 14).frame(height: 30)
                            .background(p.fill, in: Capsule()).contentShape(Capsule())
                    }
                    .buttonStyle(MoneyPress())
                }
                .padding(.bottom, 8)
            }
            .scrollEdgeEffectHidden(true, for: .all)
        }
    }

    private func set<V>(_ key: WritableKeyPath<FollowRules, V>, _ value: V) {
        var rules = follow.rules
        rules[keyPath: key] = value
        guard rules != follow.rules else { return }
        Task { if await model.save(follow.handle, rules) == false { Haptics.error() } }
    }

    private func tradeLatest() {
        let handle = follow.handle
        Task {
            let row = await model.tradeLatest(handle)
            switch row?.status {
            case "traded": Haptics.success()
            case "failed": Haptics.error()
            default: Haptics.warning()
            }
        }
    }

    private func row<Content: View>(_ title: String, _ p: MoneyPalette, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.footnote.weight(.semibold))
            Spacer(minLength: 4)
            content()
        }
    }

    private func chips(_ values: [Double], selected: Double, _ p: MoneyPalette, pick: @escaping (Double) -> Void) -> some View {
        HStack(spacing: 5) {
            ForEach(values, id: \.self) { v in
                chip(Dollars.text(v), on: v == selected, p) { pick(v) }
            }
        }
    }

    private func chip(_ title: String, on: Bool, _ p: MoneyPalette, action: @escaping () -> Void) -> some View {
        Button {
            guard !on else { return }
            Haptics.layer()
            action()
        } label: {
            Text(title).font(.footnote.weight(.semibold).monospacedDigit())
                .foregroundStyle(on ? AK.ink : p.text)
                .padding(.horizontal, 11).frame(height: 28)
                .background(on ? AK.accent : p.fill, in: Capsule()).contentShape(Capsule())
        }
        .buttonStyle(MoneyPress())
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func toggle(_ title: String, detail: String, on: Bool, _ p: MoneyPalette, change: @escaping (Bool) -> Void) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.footnote.weight(.semibold)).lineLimit(1)
                Text(detail).font(.caption2).foregroundStyle(p.soft).lineLimit(1)
            }
            Spacer(minLength: 4)
            MiniSwitch(on: on, palette: p, label: title, change: change)
        }
    }
}

/// A small switch drawn in the panel's colours: lime when on.
struct MiniSwitch: View {
    let on: Bool
    let palette: MoneyPalette
    let label: String
    let change: (Bool) -> Void

    var body: some View {
        Button {
            Haptics.layer()
            change(!on)
        } label: {
            ZStack(alignment: on ? .trailing : .leading) {
                Capsule().fill(on ? AK.accent : palette.fill)
                Circle().fill(on ? AK.ink : palette.text.opacity(0.85))
                    .frame(width: 18, height: 18)
                    .padding(3)
            }
            .frame(width: 42, height: 24)
            .animation(.snappy(duration: 0.18), value: on)
            .contentShape(Capsule())
        }
        .buttonStyle(MoneyPress())
        .accessibilityLabel(label)
        .accessibilityValue(on ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
    }
}

/// A paused follow's way back: auto on again, which clears the pause.
private struct ResumeButton: View {
    let handle: String
    let model: FollowsModel
    let palette: MoneyPalette

    var body: some View {
        Button {
            Haptics.layer()
            Task { await model.setAuto(handle, true) }
        } label: {
            Text("Turn back on").font(.caption.weight(.bold)).foregroundStyle(AK.ink)
                .padding(.horizontal, 10).frame(height: 26)
                .background(AK.accent, in: Capsule()).contentShape(Capsule())
        }
        .buttonStyle(MoneyPress())
        .disabled(model.saving != nil)
        .accessibilityLabel("Turn @\(handle)'s calls back on")
    }
}
