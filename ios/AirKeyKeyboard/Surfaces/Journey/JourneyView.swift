import SwiftUI
import UIKit

/// A call's review, its hold and its receipt, in the keyboard. The card area
/// keeps one height through every state (reviewing, sending, swapped,
/// refused, failed, expired); only what is inside it changes.
struct JourneyView: View {
    let model: JourneyModel
    let actions: MoneyActions
    let palette: MoneyPalette
    let close: () -> Void

    var body: some View {
        let p = palette
        VStack(spacing: 6) {
            header(p)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 6) { content(p) }
                    .padding(.bottom, 4)
            }
            .scrollEdgeEffectHidden(true, for: .all)
            .frame(maxHeight: .infinity)
            bottom(p)
                .frame(height: Self.bottomHeight, alignment: .bottom)
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 4)
        .foregroundStyle(p.text)
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    static let bottomHeight: CGFloat = 96

    // MARK: Header: back, size, countdown

    private func header(_ p: MoneyPalette) -> some View {
        HStack(spacing: 6) {
            Button { Haptics.layer(); close() } label: {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold))
                    Text(model.phase == .receipt ? "Calls" : "Back").font(.footnote.weight(.semibold))
                }
                .padding(.horizontal, 10).frame(height: 28)
                .background(p.fill, in: Capsule()).contentShape(Capsule())
            }
            .buttonStyle(MoneyPress())
            if model.phase != .receipt {
                ForEach(JourneyModel.sizes, id: \.self) { size in
                    let on = size == model.usd
                    Button { model.pick(size) } label: {
                        Text("$\(size)").font(.footnote.weight(.semibold).monospacedDigit())
                            .foregroundStyle(on ? AK.ink : p.text)
                            .frame(width: 38, height: 28)
                            .background(on ? AK.accent : p.fill, in: Capsule()).contentShape(Capsule())
                    }
                    .buttonStyle(MoneyPress())
                    .disabled(model.phase == .sending || model.confirmed)
                    .accessibilityLabel("Trade \(size) dollars")
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            Spacer(minLength: 4)
            countdown(p)
        }
    }

    @ViewBuilder private func countdown(_ p: MoneyPalette) -> some View {
        switch model.phase {
        case .review:
            let s = model.secondsLeft
            Text("Quote \(s) s")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(s <= 5 ? p.warn : p.soft)
                .contentTransition(.numericText(countsDown: true))
                .accessibilityLabel("Quote good for \(s) seconds")
        case .expired:
            Text("Quote expired").font(.caption.weight(.semibold)).foregroundStyle(p.warn)
        case .receipt:
            Text(model.receipt.flatMap { $0.at }.map(Self.clock) ?? "").font(.caption.monospacedDigit()).foregroundStyle(p.soft)
        default:
            EmptyView()
        }
    }

    // MARK: The card

    @ViewBuilder private func content(_ p: MoneyPalette) -> some View {
        switch model.phase {
        case .reviewing:
            ReviewCard(review: Self.placeholder, palette: p, dim: false)
                .redacted(reason: .placeholder)
                .accessibilityLabel("Reviewing the trade")
        case .review, .sending, .expired:
            if let r = model.review {
                // The numbers first, readable at a glance; the post they came from under them.
                ReviewCard(review: r, palette: p, dim: model.phase == .expired)
                postHeader(r, p)
            }
        case .receipt:
            if let r = model.receipt { ReceiptCard(receipt: r, palette: p, actions: actions) }
        case .uncertain(let message):
            VStack(alignment: .leading, spacing: 6) {
                Label("Result not known yet", systemImage: "questionmark.circle")
                    .font(.footnote.weight(.semibold)).foregroundStyle(p.warn)
                Text(message).font(.footnote).foregroundStyle(p.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 6) {
                Label("Couldn't review this trade", systemImage: "exclamationmark.circle")
                    .font(.footnote.weight(.semibold)).foregroundStyle(p.warn)
                Text(message).font(.footnote).foregroundStyle(p.text)
                    .fixedSize(horizontal: false, vertical: true)
                if !message.contains("check Wallet") {
                    Text("Nothing was swapped.").font(.caption).foregroundStyle(p.soft)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(p.fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func postHeader(_ r: TradeReview, _ p: MoneyPalette) -> some View {
        let post = model.post
        return KolCardView(handle: post?.handle ?? r.call.handle, name: post?.name ?? r.call.name,
                           postedAt: post?.postedAt ?? r.call.postedAt, url: post?.url ?? r.call.url,
                           text: r.call.text.isEmpty ? post?.text : r.call.text,
                           asset: r.call.asset, direction: r.call.direction,
                           hits: post?.hits, misses: post?.misses,
                           reading: r.reading.isEmpty ? nil : r.reading, sample: false,
                           palette: p, actions: actions, review: nil)
    }

    // MARK: Under the card: the stand-in, then the hold (or what replaced it)

    @ViewBuilder private func bottom(_ p: MoneyPalette) -> some View {
        VStack(spacing: 5) {
            Spacer(minLength: 0)
            switch model.phase {
            case .reviewing:
                status("Reviewing…", spinning: true, p)
            case .review:
                if let s = model.review?.standIn {
                    Text(s).font(.caption).foregroundStyle(p.warn).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let note = model.note {
                    Text(note).font(.caption).foregroundStyle(p.soft).lineLimit(1)
                }
                TradeHold(label: holdLabel, disabled: model.confirmed, palette: p) { model.confirm() }
            case .sending:
                if let note = model.note {
                    Text(note).font(.caption).foregroundStyle(p.soft).lineLimit(1)
                }
                status("Sending to Spend Limits…", spinning: true, p)
            case .expired:
                Text("Quotes last 30 seconds so the price you saw is the price you get.")
                    .font(.caption).foregroundStyle(p.soft).lineLimit(2)
                wide("Quote expired · Review again", primary: true, p) { model.again() }
            case .receipt:
                HStack(spacing: 6) {
                    wide("Done", primary: false, p) { close() }
                    if let line = model.receiptLine {
                        wide("Insert", primary: true, p) { actions.share(line) }
                            .accessibilityHint("Puts one line and the transaction link in the chat")
                    }
                }
            case .failed:
                wide("Review again", primary: true, p) { model.again() }
            case .uncertain:
                if let note = model.note {
                    Text(note).font(.caption).foregroundStyle(p.soft).lineLimit(2)
                }
                HStack(spacing: 6) {
                    wide("Done", primary: false, p) { close() }
                    wide("Check status", primary: true, p) { model.checkStatus() }
                }
            }
        }
    }

    private var holdLabel: String {
        // Name the trade that really runs, not the post's coin: on testnet a
        // "buy BTC" post swaps NEAR to USDC, and the button must say so.
        guard let r = model.review else { return "Hold to confirm" }
        return "Hold to swap \(r.pay.amount) \(r.pay.symbol) → \(r.receive.symbol)"
    }

    private func status(_ text: String, spinning: Bool, _ p: MoneyPalette) -> some View {
        HStack(spacing: 8) {
            if spinning { ProgressView().controlSize(.small).tint(p.text) }
            Text(text).font(.subheadline.weight(.semibold)).foregroundStyle(p.soft)
        }
        .frame(maxWidth: .infinity).frame(height: 44)
        .background(p.fill, in: Capsule())
        .padding(.bottom, 20)
        .accessibilityElement(children: .combine)
    }

    private func wide(_ title: String, primary: Bool, _ p: MoneyPalette, action: @escaping () -> Void) -> some View {
        Button { Haptics.letter(); action() } label: {
            Text(title).font(.subheadline.weight(.bold))
                .foregroundStyle(primary ? AK.ink : p.text)
                .frame(maxWidth: .infinity).frame(height: 44)
                .background(primary ? AK.accent : p.fill, in: Capsule()).contentShape(Capsule())
        }
        .buttonStyle(MoneyPress())
        .padding(.bottom, 20)
    }

    static func clock(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: d)
    }

    /// The skeleton's shape: the real card's, with placeholder words.
    static let placeholder = TradeReview(
        reviewId: "", expiresAt: .distantFuture,
        call: .init(handle: nil, name: nil, postedAt: nil, url: nil, text: "", asset: "NEAR", direction: "buy"),
        reading: "", network: "NEAR testnet", venue: "Rhea, pool 0000",
        pay: Amount(amount: "0.0000", symbol: "NEAR"), receive: Amount(amount: "0.0000", symbol: "USDC"),
        receiveMin: "0.0000", slippagePct: "1", fundsSit: "In your leash account until the swap",
        standIn: nil, mainnet: .init(label: "Mainnet price, dry run", payAmount: "0.0000", receiveAmount: "0.0000", symbol: "USDC"),
        limits: .init(agentName: "Trading Agent", perTrade: "1", daily: "2", spentToday: "0", stopped: false, within: true,
                      sentence: "The Trading Agent can spend up to 1 NEAR a trade and 2 NEAR a day. You can stop it.", willRefuse: nil, refusedBy: nil))
}

/// Everything about the trade, readable at a glance.
struct ReviewCard: View {
    let review: TradeReview
    let palette: MoneyPalette
    let dim: Bool

    var body: some View {
        let p = palette, r = review
        VStack(alignment: .leading, spacing: 4) {
            (Text("You pay ").foregroundStyle(p.soft) + Text(r.pay.line).bold()
             + Text(" · You get about ").foregroundStyle(p.soft) + Text(r.receive.line).bold()
             + Text(" (at least \(r.receiveMin))").foregroundStyle(p.soft))
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
            Text(([r.slippagePct + "% slippage", r.network, r.venue].filter { !$0.isEmpty }).joined(separator: " · "))
                .font(.caption.weight(.medium)).foregroundStyle(p.text)
                .fixedSize(horizontal: false, vertical: true)
            if !r.fundsSit.isEmpty {
                Text("Funds: \(r.fundsSit)").font(.caption).foregroundStyle(p.soft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let m = r.mainnet {
                Text("\(m.label): \(m.payAmount) \(r.pay.symbol) → \(m.receiveAmount) \(m.symbol)")
                    .font(.caption).foregroundStyle(p.soft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            (Text(r.limits.sentence.isEmpty ? "\(r.limits.agentName): \(r.limits.perTrade) NEAR a trade, \(r.limits.daily) NEAR a day." : r.limits.sentence)
             + Text(r.limits.stopped ? " Stopped." : " Spent today: \(r.limits.spentToday) of \(r.limits.daily) NEAR.")
                .foregroundStyle(r.limits.stopped ? p.bad : p.soft))
                .font(.caption).foregroundStyle(p.text)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
            if let refuse = r.limits.willRefuse {
                Label {
                    Text(refuse + (r.limits.refusedBy == "server" ? " Nothing is sent." : " You can still hold, to see the refusal on chain."))
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle").font(.caption2.weight(.bold))
                }
                .font(.caption).foregroundStyle(p.warn)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(p.fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .opacity(dim ? 0.5 : 1)
        .accessibilityElement(children: .combine)
    }

    private func line(_ k: String, _ v: String, _ p: MoneyPalette) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(k).font(.caption).foregroundStyle(p.soft).frame(width: 92, alignment: .leading).lineLimit(2)
            Text(v).font(.caption.weight(.medium)).foregroundStyle(p.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

/// What happened, who decided, and the proof.
struct ReceiptCard: View {
    let receipt: TradeReceipt
    let palette: MoneyPalette
    let actions: MoneyActions

    var body: some View {
        let p = palette, r = receipt
        VStack(alignment: .leading, spacing: 6) {
            if r.repeated {
                Text("Already confirmed. This is that trade's receipt; nothing was sent again.")
                    .font(.caption).foregroundStyle(p.soft)
            }
            HStack(spacing: 8) {
                Image(systemName: r.swapped ? "checkmark" : r.blocked ? "hand.raised.fill" : r.unknown ? "questionmark" : "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(r.swapped ? AK.ink : .white)
                    .frame(width: 22, height: 22)
                    .background(r.swapped ? AK.accent : r.blocked ? p.bad : p.warn, in: Circle())
                Text(title).font(.subheadline.weight(.bold))
            }
            if !r.summary.isEmpty {
                Text(Plain.scrub(r.summary)).font(.footnote).fixedSize(horizontal: false, vertical: true)
            }
            if r.blocked || r.status == "failed", let reason = r.reason {
                Text((r.rule.map { "Rule \($0): " } ?? "") + reason)
                    .font(.footnote.weight(.medium)).foregroundStyle(r.blocked ? p.bad : p.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Label(r.unknown ? "Result unknown: check Spend Limits on nearblocks" : r.byContract ? "Decided by the Spend Limits contract on NEAR" : "Stopped by the AIRKEY server",
                  systemImage: r.unknown ? "questionmark.circle" : r.byContract ? "link" : "server.rack")
                .font(.caption.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                if let tx = r.txURL, let url = URL(string: tx) {
                    link("View on nearblocks ↗", url, p)
                }
                if let post = r.postURL, let url = URL(string: post) {
                    link(r.postAuthor.map { "@\($0.replacingOccurrences(of: "@", with: ""))'s post ↗" } ?? "The post ↗", url, p)
                }
            }
            .padding(.top, 2)
            if let pay = r.pay { line("Paid", r.swapped ? pay.line : r.unknown ? "Unknown" : "Nothing (\(pay.line) stayed put)", p) }
            line("Received", r.receive?.line ?? (r.unknown ? "Unknown" : "Nothing received"), p)
            if r.status == "failed", r.receive == nil {
                Text("Nothing was swapped.").font(.caption).foregroundStyle(p.soft)
            }
            if let venue = r.venue { line("Venue", venue, p) }
            if let s = r.standIn {
                Text(s).font(.caption).foregroundStyle(p.warn).fixedSize(horizontal: false, vertical: true)
            }
            line("Agent", r.agent, p)
            if let at = r.at { line("Time", at.formatted(date: .abbreviated, time: .standard), p) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(p.fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var title: String {
        switch receipt.status {
        case "swapped": "Swapped"
        case "blocked": receipt.byContract ? "Refused by the contract" : "Refused by the AIRKEY server"
        case "unknown": "Result unknown"
        default: "Failed"
        }
    }

    private func line(_ k: String, _ v: String, _ p: MoneyPalette) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(k).font(.caption).foregroundStyle(p.soft).frame(width: 62, alignment: .leading)
            Text(v).font(.caption.weight(.medium)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func link(_ title: String, _ url: URL, _ p: MoneyPalette) -> some View {
        Button {
            Haptics.letter()
            actions.open(url) { ok in if !ok { UIPasteboard.general.string = url.absoluteString } }
        } label: {
            Text(title).font(.caption.weight(.semibold)).lineLimit(1)
                .padding(.horizontal, 10).frame(height: 26)
                .background(p.fill, in: Capsule()).contentShape(Capsule())
        }
        .buttonStyle(MoneyPress())
    }
}
