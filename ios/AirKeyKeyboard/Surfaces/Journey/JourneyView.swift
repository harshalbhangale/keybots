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

    @State private var sourceOpen = false

    var body: some View {
        let p = palette
        VStack(spacing: 8) {
            header(p)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 8) { content(p) }
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

    static let bottomHeight: CGFloat = 76

    // MARK: Header: back, size, countdown

    private func header(_ p: MoneyPalette) -> some View {
        HStack(spacing: 8) {
            Button { Haptics.layer(); close() } label: {
                Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .background(p.fill, in: Circle()).contentShape(Circle())
            }
            .buttonStyle(MoneyPress())
            .accessibilityLabel(model.phase == .receipt ? "Back to Calls" : "Back")
            if model.phase == .receipt {
                Text("Receipt").font(.subheadline.weight(.semibold))
            } else {
                sizes(p)
            }
            Spacer(minLength: 4)
            countdown(p)
        }
        .frame(height: 32)
    }

    private func sizes(_ p: MoneyPalette) -> some View {
        let locked = model.phase == .sending || model.confirmed
        return HStack(spacing: 2) {
            ForEach(JourneyModel.sizes, id: \.self) { size in
                let on = size == model.usd
                Button { model.pick(size) } label: {
                    Text("$\(size)").font(.footnote.weight(on ? .semibold : .medium).monospacedDigit())
                        .foregroundStyle(on ? p.text : p.soft)
                        .frame(width: 44, height: 28)
                        .background { if on { Capsule().fill(p.thumb).shadow(color: .black.opacity(p.dark ? 0 : 0.1), radius: 2, y: 1) } }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Trade \(size) dollars")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(2)
        .background(p.fill, in: Capsule())
        .disabled(locked)
        .opacity(locked ? 0.5 : 1)
    }

    @ViewBuilder private func countdown(_ p: MoneyPalette) -> some View {
        switch model.phase {
        case .review:
            let s = model.secondsLeft
            HStack(spacing: 5) {
                ZStack {
                    Circle().stroke(p.line, lineWidth: 2)
                    Circle().trim(from: 0, to: CGFloat(s) / 30)
                        .stroke(s <= 5 ? p.warn : p.soft, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.25), value: s)
                }
                .frame(width: 14, height: 14)
                Text("\(s)s")
                    .font(.footnote.weight(.semibold).monospacedDigit())
                    .foregroundStyle(s <= 5 ? p.warn : p.soft)
                    .contentTransition(.numericText(countsDown: true))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Quote good for \(s) seconds")
        case .expired:
            Text("Expired").font(.footnote.weight(.semibold)).foregroundStyle(p.warn)
        case .receipt:
            Text(model.receipt.flatMap { $0.at }.map(Self.clock) ?? "").font(.footnote.monospacedDigit()).foregroundStyle(p.soft)
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
                if sourceOpen { post(r, p) }
                ReviewCard(review: r, palette: p, dim: model.phase == .expired, source: AnyView(source(r, p)))
            }
        case .receipt:
            if let r = model.receipt { ReceiptCard(receipt: r, palette: p, actions: actions) }
        case .uncertain(let message):
            StateCard(icon: "questionmark", tint: p.warn, title: "Result not known yet", message: message,
                      foot: nil, palette: p)
        case .failed(let message):
            StateCard(icon: "exclamationmark", tint: p.warn, title: "Couldn't review this trade", message: message,
                      foot: message.contains("check Wallet") ? nil : "Nothing was swapped.", palette: p)
        }
    }

    /// The post itself, opened from the source line.
    private func post(_ r: TradeReview, _ p: MoneyPalette) -> some View {
        let post = model.post
        return KolCardView(handle: post?.handle ?? r.call.handle, name: post?.name ?? r.call.name,
                           postedAt: post?.postedAt ?? r.call.postedAt, url: post?.url ?? r.call.url,
                           text: r.call.text.isEmpty ? post?.text : r.call.text,
                           asset: r.call.asset, direction: r.call.direction,
                           hits: post?.hits, misses: post?.misses,
                           reading: r.reading.isEmpty ? nil : r.reading, sample: false,
                           palette: p, actions: actions, review: nil)
            .transition(.opacity)
    }

    /// Where the call came from: one quiet line at the top of the card; tap to read the post.
    private func source(_ r: TradeReview, _ p: MoneyPalette) -> some View {
        let post = model.post
        let handle = post?.handle ?? r.call.handle
        return Button {
            Haptics.layer()
            withAnimation(.snappy(duration: 0.22)) { sourceOpen.toggle() }
        } label: {
            HStack(spacing: 5) {
                Text(handle.map { "@\($0)" } ?? "Copied post").fontWeight(.semibold).foregroundStyle(p.text).lineLimit(1)
                if let ago = J.ago(post?.postedAt ?? r.call.postedAt) {
                    Text("· \(ago)").lineLimit(1).fixedSize()
                }
                Spacer(minLength: 4)
                Text("\(r.call.direction == "sell" ? "Sell" : "Buy") \(r.call.asset)").lineLimit(1).fixedSize()
                Image(systemName: sourceOpen ? "chevron.up" : "chevron.down").font(.system(size: 10, weight: .semibold))
            }
            .font(.caption)
            .foregroundStyle(p.soft)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("From \(handle.map { "@\($0)" } ?? "a copied post"), \(r.call.direction) \(r.call.asset)")
        .accessibilityHint(sourceOpen ? "Hides the post" : "Shows the post")
    }

    // MARK: Under the card: the hold (or what replaced it)

    @ViewBuilder private func bottom(_ p: MoneyPalette) -> some View {
        VStack(spacing: 4) {
            Spacer(minLength: 0)
            switch model.phase {
            case .reviewing:
                status("Reviewing…", spinning: true, p)
            case .review:
                if let note = model.note {
                    Text(note).font(.caption).foregroundStyle(p.soft).lineLimit(1)
                }
                TradeHold(label: holdLabel, disabled: model.confirmed, palette: p) { model.confirm() }
            case .sending:
                status("Sending to Spend Limits…", spinning: true, p)
            case .expired:
                wide("Review again", primary: true, p) { model.again() }
                    .accessibilityHint("Quotes last 30 seconds so the price you see is the price you get.")
            case .receipt:
                HStack(spacing: 8) {
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
                    Text(note).font(.caption).foregroundStyle(p.soft).lineLimit(1)
                }
                HStack(spacing: 8) {
                    wide("Done", primary: false, p) { close() }
                    wide("Check status", primary: true, p) { model.checkStatus() }
                }
            }
        }
        .padding(.bottom, 8)
    }

    private var holdLabel: String {
        // Name the trade that really runs, not the post's coin: on testnet a
        // "buy BTC" post swaps NEAR to USDC, and the button must say so.
        guard let r = model.review else { return "Hold to confirm" }
        return "Hold to swap \(r.pay.amount) \(r.pay.symbol) → \(r.receive.symbol)"
    }

    private func status(_ text: String, spinning: Bool, _ p: MoneyPalette) -> some View {
        HStack(spacing: 8) {
            if spinning { ProgressView().controlSize(.small).tint(p.soft) }
            Text(text).font(.subheadline.weight(.semibold)).foregroundStyle(p.soft)
        }
        .frame(maxWidth: .infinity).frame(height: 44)
        .background(p.fill, in: Capsule())
        .accessibilityElement(children: .combine)
    }

    private func wide(_ title: String, primary: Bool, _ p: MoneyPalette, action: @escaping () -> Void) -> some View {
        Button { Haptics.letter(); action() } label: {
            Text(title).font(.subheadline.weight(.semibold))
                .foregroundStyle(primary ? AK.ink : p.text)
                .frame(maxWidth: .infinity).frame(height: 44)
                .background(primary ? AK.accent : p.fill, in: Capsule()).contentShape(Capsule())
        }
        .buttonStyle(MoneyPress())
    }

    static func clock(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    /// The skeleton's shape: the real card's, with placeholder words.
    static let placeholder = TradeReview(
        reviewId: "", expiresAt: .distantFuture,
        call: .init(handle: nil, name: nil, postedAt: nil, url: nil, text: "", asset: "NEAR", direction: "buy"),
        reading: "", network: "NEAR testnet", venue: "Rhea, pool 0000",
        pay: Amount(amount: "0.0000", symbol: "NEAR"), receive: Amount(amount: "0.0000", symbol: "USDC"),
        receiveMin: "0.0000", slippagePct: "1", fundsSit: "In Spend Limits",
        standIn: nil, mainnet: nil,
        limits: .init(agentName: "Trading Agent", perTrade: "1", daily: "2", spentToday: "0", stopped: false, within: true,
                      sentence: "", willRefuse: nil, refusedBy: nil))
}

// MARK: - Shared pieces

/// A label on the left, its value on the right, on one baseline.
struct InfoRow: View {
    let label: String
    let value: String
    let palette: MoneyPalette
    var tint: Color?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).foregroundStyle(palette.soft).lineLimit(1).layoutPriority(1)
            Spacer(minLength: 8)
            Text(value).fontWeight(.medium).foregroundStyle(tint ?? palette.text)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.footnote)
        .accessibilityElement(children: .combine)
    }
}

/// One compact amber line with an icon: a refusal ahead, or the testnet stand-in.
struct Callout: View {
    let icon: String
    let text: String
    let tint: Color
    let palette: MoneyPalette

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(systemName: icon).font(.system(size: 11, weight: .semibold))
            Text(text).font(.caption.weight(.medium)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(tint.opacity(palette.dark ? 0.16 : 0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// A thin bar for today's spend against the daily limit.
struct SpendBar: View {
    let fraction: Double
    let tint: Color
    let palette: MoneyPalette

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(palette.fill)
                Capsule().fill(tint).frame(width: max(4, g.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }
}

/// The card for a state with nothing to show but words: lost answer, failed review.
struct StateCard: View {
    let icon: String
    let tint: Color
    let title: String
    let message: String
    let foot: String?
    let palette: MoneyPalette

    var body: some View {
        let p = palette
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 28, height: 28).background(tint, in: Circle())
                Text(title).font(.headline)
            }
            Text(message).font(.footnote).foregroundStyle(p.soft)
                .fixedSize(horizontal: false, vertical: true)
            if let foot { Text(foot).font(.footnote.weight(.medium)) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(p.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - The review

/// The trade at a glance: what you pay and get, then the details as rows,
/// then the limits in one line.
struct ReviewCard: View {
    let review: TradeReview
    let palette: MoneyPalette
    let dim: Bool
    var source: AnyView?

    var body: some View {
        let p = palette, r = review
        VStack(alignment: .leading, spacing: 6) {
            if let source { source }
            HStack(alignment: .bottom, spacing: 8) {
                side("You pay", r.pay.amount, r.pay.symbol, p)
                Image(systemName: "arrow.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(p.faint)
                    .padding(.bottom, 5)
                    .accessibilityHidden(true)
                side("You get about", r.receive.amount, r.receive.symbol, p)
            }
            if let callout = callout(r, p) { callout }
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
                GridRow {
                    cell("At least", "\(r.receiveMin) \(r.receive.symbol)", p)
                    cell("Slippage", "\(r.slippagePct)%", p)
                }
                GridRow {
                    cell("Network", r.network, p)
                    cell("Venue", r.venue.isEmpty ? "—" : r.venue, p)
                }
            }
            limits(r, p)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(p.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .opacity(dim ? 0.45 : 1)
        .accessibilityElement(children: .contain)
    }

    private func side(_ label: String, _ amount: String, _ symbol: String, _ p: MoneyPalette) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.caption).foregroundStyle(p.soft)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(amount).font(.title3.weight(.semibold).monospacedDigit())
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(symbol).font(.footnote.weight(.semibold)).foregroundStyle(p.soft)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// A label and its value on one line, half the card wide.
    private func cell(_ label: String, _ value: String, _ p: MoneyPalette) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label).foregroundStyle(p.soft)
            Spacer(minLength: 4)
            Text(value).fontWeight(.medium).foregroundStyle(p.text)
        }
        .font(.caption)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    /// One amber line: a refusal ahead wins over the stand-in.
    private func callout(_ r: TradeReview, _ p: MoneyPalette) -> Callout? {
        if let refuse = r.limits.willRefuse {
            let then = r.limits.refusedBy == "server" ? "Nothing will be sent." : "Spend Limits will refuse it on chain."
            return Callout(icon: "hand.raised.fill", text: "\(Plain.scrub(refuse)) \(then)", tint: p.warn, palette: p)
        }
        if r.standIn != nil {
            return Callout(icon: "info.circle.fill",
                           text: "Testnet has no \(r.call.asset), so this swaps \(r.pay.symbol) to \(r.receive.symbol).",
                           tint: p.warn, palette: p)
        }
        return nil
    }

    private func limits(_ r: TradeReview, _ p: MoneyPalette) -> some View {
        let l = r.limits
        let spent = Double(l.spentToday) ?? 0, daily = Double(l.daily) ?? 0
        let fraction = daily > 0 ? spent / daily : 0
        let tint: Color = l.stopped ? p.bad : fraction > 0.8 ? p.warn : p.text.opacity(0.7)
        return HStack(spacing: 8) {
            (Text("Funds in ").foregroundStyle(p.soft) + Text("Spend Limits").fontWeight(.semibold))
                .font(.caption).fixedSize()
            SpendBar(fraction: l.stopped ? 1 : fraction, tint: tint, palette: p)
                .frame(minWidth: 32, maxWidth: 64)
            Spacer(minLength: 4)
            Text(l.stopped ? "Stopped" : "\(l.spentToday) of \(l.daily) NEAR today")
                .font(.caption.monospacedDigit()).foregroundStyle(l.stopped ? p.bad : p.soft)
                .lineLimit(1).minimumScaleFactor(0.75)
        }
        .padding(.top, 8)
        .overlay(alignment: .top) { Rectangle().fill(p.line).frame(height: 0.5) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(l.stopped ? "Spend Limits: stopped" :
            "Spend Limits: \(l.spentToday) of \(l.daily) NEAR spent today, up to \(l.perTrade) NEAR a trade. You can stop it.")
    }
}

// MARK: - The receipt

/// The verdict first, then the proof, then the numbers.
struct ReceiptCard: View {
    let receipt: TradeReceipt
    let palette: MoneyPalette
    let actions: MoneyActions

    var body: some View {
        let p = palette, r = receipt
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(r.swapped ? AK.ink : .white)
                    .frame(width: 36, height: 36)
                    .background(tint, in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.title3.weight(.semibold))
                    Text(decidedBy).font(.footnote).foregroundStyle(p.soft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            if let tx = r.txURL, let url = URL(string: tx) {
                link("View transaction", "arrow.up.right", url, p)
            }
            if r.repeated {
                Text("Already confirmed. Nothing was sent again.").font(.caption).foregroundStyle(p.soft)
            }
            if r.blocked || r.status == "failed", let reason = r.reason {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Plain.scrub(reason)).font(.footnote.weight(.medium)).foregroundStyle(r.blocked ? p.bad : p.warn)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if let rule = r.rule {
                        Text("Rule \(rule)").font(.caption2.weight(.medium)).foregroundStyle(p.faint)
                            .accessibilityHidden(true)
                    }
                }
            } else if r.unknown {
                Text(Plain.scrub(r.summary)).font(.footnote).foregroundStyle(p.soft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 6) {
                if let pay = r.pay {
                    InfoRow(label: "Paid", value: r.swapped ? pay.line : r.unknown ? "Unknown" : "Nothing, \(pay.line) stayed", palette: p)
                }
                InfoRow(label: "Received", value: r.receive?.line ?? (r.unknown ? "Unknown" : "Nothing"), palette: p,
                        tint: r.swapped ? p.good : nil)
                if let venue = r.venue { InfoRow(label: "Venue", value: venue, palette: p) }
                if let at = r.at { InfoRow(label: "Time", value: at.formatted(date: .abbreviated, time: .shortened), palette: p) }
            }
            if let post = r.postURL, let url = URL(string: post) {
                Button {
                    Haptics.letter()
                    actions.open(url) { ok in if !ok { UIPasteboard.general.string = url.absoluteString } }
                } label: {
                    HStack(spacing: 4) {
                        Text(r.postAuthor.map { "From @\($0.replacingOccurrences(of: "@", with: ""))'s post" } ?? "From a post")
                        Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .semibold))
                    }
                    .font(.caption.weight(.medium)).foregroundStyle(p.soft)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(p.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var icon: String {
        receipt.swapped ? "checkmark" : receipt.blocked ? "hand.raised.fill" : receipt.unknown ? "questionmark" : "xmark"
    }

    private var tint: Color {
        receipt.swapped ? AK.accent : receipt.blocked ? palette.bad : palette.warn
    }

    private var title: String {
        switch receipt.status {
        case "swapped": "Swapped"
        case "blocked": "Refused"
        case "unknown": "Result unknown"
        default: "Failed"
        }
    }

    private var decidedBy: String {
        if receipt.unknown { return "NEAR didn't answer in time" }
        return receipt.byContract ? "Decided by Spend Limits on NEAR" : "Stopped by the AIRKEY server"
    }

    private func link(_ title: String, _ icon: String, _ url: URL, _ p: MoneyPalette) -> some View {
        Button {
            Haptics.letter()
            actions.open(url) { ok in if !ok { UIPasteboard.general.string = url.absoluteString } }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "link").font(.system(size: 12, weight: .semibold))
                Text(title).font(.subheadline.weight(.semibold))
                Spacer(minLength: 4)
                Text("nearblocks").font(.caption).foregroundStyle(p.soft)
                Image(systemName: icon).font(.system(size: 11, weight: .semibold)).foregroundStyle(p.soft)
            }
            .padding(.horizontal, 12).frame(height: 40)
            .background(p.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(MoneyPress())
        .accessibilityLabel("View transaction on nearblocks")
    }
}
