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
            // The card fills the space between the header and the action, so
            // its height never changes between review, sending and receipt.
            GeometryReader { g in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 8) { content(p) }
                        .frame(minHeight: g.size.height, alignment: .top)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollEdgeEffectHidden(true, for: .all)
            }
            .frame(maxHeight: .infinity)
            bottom(p)
                .frame(height: Self.bottomHeight, alignment: .top)
        }
        .padding(.horizontal, MoneyPalette.inset)
        .padding(.top, 6)
        .padding(.bottom, 4)
        .foregroundStyle(p.text)
        // Text grows up to xLarge; past that the card would only scroll.
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    /// The action sits at the same y in every state: a 44pt button, then
    /// a line kept for "Tap to confirm instead" even when it is hidden.
    static let bottomHeight: CGFloat = 72

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
        let failed: Bool = { if case .failed = model.phase { return true }; return false }()
        let locked = model.phase == .sending || model.confirmed || failed
        return HStack(spacing: 2) {
            ForEach(JourneyModel.sizes, id: \.self) { size in
                let on = size == model.usd && !failed
                Button { model.pick(size) } label: {
                    Text("$\(size)").font(.footnote.weight(on ? .semibold : .medium).monospacedDigit())
                        .foregroundStyle(on ? p.text : p.soft)
                        .frame(minWidth: 44, minHeight: 28)
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
                // Time left as a filled arc that empties as the quote ages.
                ZStack {
                    Circle().fill(p.fill)
                    Circle().trim(from: 0, to: CGFloat(s) / 30)
                        .stroke(s <= 5 ? p.warn : p.soft, style: StrokeStyle(lineWidth: 7))
                        .rotationEffect(.degrees(-90))
                        .padding(3.5)
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
            Text("Price expired").font(.footnote.weight(.semibold)).foregroundStyle(p.warn)
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
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        case .receipt:
            if let r = model.receipt {
                ReceiptCard(receipt: r, palette: p, actions: actions)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        case .uncertain(let message):
            StateCard(icon: "questionmark", tint: p.warn, title: "Result not known yet",
                      subtitle: "It won't be sent again.", message: message, palette: p)
                .frame(maxHeight: .infinity, alignment: .top)
        case .failed(let message):
            // A missing quote is the common case: say it plainly, nothing else.
            let quote = message.localizedCaseInsensitiveContains("quote") || message.localizedCaseInsensitiveContains("price")
            StateCard(icon: "exclamationmark", tint: p.warn,
                      title: quote ? "Couldn't get a price" : "Couldn't review this trade",
                      subtitle: message.contains("check Wallet") ? nil : "Nothing was swapped.",
                      message: quote ? nil : Plain.scrub(message), palette: p)
                .frame(maxHeight: .infinity, alignment: .top)
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
                           source: post?.source ?? "x", palette: p, actions: actions, review: nil)
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
                // A Telegram call says which group it came from; an X call, the handle.
                Text(post?.telegram == true ? (post?.name ?? handle ?? "Telegram") : (handle.map { "@\($0)" } ?? "Copied post"))
                    .fontWeight(.semibold).foregroundStyle(p.text).lineLimit(1)
                if let ago = J.ago(post?.postedAt ?? r.call.postedAt) {
                    Text("· \(ago)").lineLimit(1).fixedSize()
                }
                Spacer(minLength: 4)
                HStack(spacing: 3) {
                    Text("\(r.call.direction == "sell" ? "Sell" : "Buy") \(r.call.asset)").fontWeight(.semibold).lineLimit(1).fixedSize()
                    Image(systemName: sourceOpen ? "chevron.up" : "chevron.down").font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(p.text)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(p.fill, in: Capsule())
            }
            .font(.caption)
            .foregroundStyle(p.soft)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("From \(post?.telegram == true ? (post?.name ?? "Telegram") : (handle.map { "@\($0)" } ?? "a copied post")), \(r.call.direction) \(r.call.asset)")
        .accessibilityHint(sourceOpen ? "Hides the post" : "Shows the post")
    }

    // MARK: Under the card: the hold (or what replaced it)

    /// The action row: always 44pt at the top of the bottom area, with a
    /// line under it (the hold's "Tap to confirm instead", a note, or empty),
    /// so the main button never moves between states.
    @ViewBuilder private func bottom(_ p: MoneyPalette) -> some View {
        VStack(spacing: 4) {
            switch model.phase {
            case .reviewing:
                status("Reviewing…", spinning: true, p)
                noteLine(nil, p)
            case .review:
                TradeHold(label: holdLabel, disabled: model.confirmed,
                          neutral: model.review?.limits.willRefuse != nil, palette: p) { model.confirm() }
            case .sending:
                status("Sending…", spinning: true, p)
                noteLine(nil, p)
            case .expired:
                wide("Review again", primary: true, p) { model.again() }
                    .accessibilityHint("Quotes last 30 seconds so the price you see is the price you get.")
                noteLine(nil, p)
            case .receipt:
                let r = model.receipt
                HStack(spacing: 8) {
                    wide("Done", primary: false, p) { close() }
                    if r?.unknown == true {
                        wide("Check transaction", primary: true, p) { model.checkStatus() }
                    } else if let line = model.receiptLine {
                        // Lime only when it went through; a refusal's receipt is still shareable, but quiet.
                        wide("Insert receipt", primary: r?.swapped == true, p) { actions.share(line) }
                            .accessibilityHint("Puts one line and the transaction link in the chat")
                    }
                }
                noteLine(model.note, p)
            case .failed:
                wide("Try again", primary: true, p) { model.again() }
                noteLine(nil, p)
            case .uncertain:
                HStack(spacing: 8) {
                    wide("Done", primary: false, p) { close() }
                    wide("Check transaction", primary: true, p) { model.checkStatus() }
                }
                noteLine(model.note, p)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 2)
    }

    /// The line under the action: a short note ("Checking…"), or held empty.
    private func noteLine(_ note: String?, _ p: MoneyPalette) -> some View {
        Text(note ?? " ").font(.caption).foregroundStyle(p.soft).lineLimit(1)
            .minimumScaleFactor(0.85)
            .frame(maxWidth: .infinity).frame(height: 18)
            .accessibilityHidden(note == nil)
    }

    private var holdLabel: String {
        // Name the trade that really runs, not the post's coin: on testnet a
        // "buy BTC" post swaps NEAR to USDC, and the button must say so.
        guard let r = model.review else { return "Hold to confirm" }
        // A refusal ahead: a grey button that says what will happen.
        if r.limits.willRefuse != nil {
            return r.limits.refusedBy == "server" ? "Try anyway, nothing will be sent" : "Send anyway, it will be refused"
        }
        // The amounts are on the card above; the button only names the act.
        return "Hold to swap"
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
                .lineLimit(1).minimumScaleFactor(0.85)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity).frame(height: 44)
                .background(primary ? AK.accent : p.fill, in: Capsule()).contentShape(Capsule())
        }
        .buttonStyle(MoneyPress())
    }

    static func clock(_ d: Date) -> String {
        // The locale's own time style: 2:28 PM where the clock is 12-hour.
        d.formatted(date: .omitted, time: .shortened)
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

/// A label on the left, its value on the right, on one baseline. Wraps to
/// two lines at large text instead of shrinking.
struct InfoRow: View {
    let label: String
    let value: String
    let palette: MoneyPalette
    var tint: Color?
    /// A small grey note after the value, like a pool number or a rule id.
    var note: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).foregroundStyle(palette.soft)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value).fontWeight(.medium).foregroundStyle(tint ?? palette.text)
                if let note {
                    Text(note).font(.caption2).foregroundStyle(palette.faint)
                }
            }
            .multilineTextAlignment(.trailing)
            .fixedSize(horizontal: false, vertical: true)
        }
        .font(.footnote)
        .accessibilityElement(children: .combine)
    }
}

/// A refusal ahead: red-orange text on a 10% tint (4.5:1 in both modes).
/// Only refusals get a fill; a plain note is just secondary text.
struct Callout: View {
    let icon: String
    let text: String
    let palette: MoneyPalette

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(systemName: icon).font(.system(size: 11, weight: .semibold))
            Text(text).font(.footnote.weight(.medium)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(palette.refuse)
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(palette.bad.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// A quiet note with an info glyph and no fill: the testnet stand-in.
struct NoteLine: View {
    let text: String
    let palette: MoneyPalette

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "info.circle").font(.system(size: 11, weight: .medium))
            Text(text).font(.caption).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(palette.soft)
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

/// The verdict at the top of a receipt or a state card: one circle, a
/// title and a quiet line. Same size and inset everywhere.
struct VerdictHeader: View {
    let icon: String
    let tint: Color
    let glyph: Color
    let title: String
    let subtitle: String?
    let palette: MoneyPalette

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(glyph)
                .frame(width: 36, height: 36)
                .background(tint, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.title3.weight(.semibold))
                if let subtitle {
                    Text(subtitle).font(.footnote).foregroundStyle(palette.soft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The card for a state with nothing to show but words: lost answer, failed review.
struct StateCard: View {
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String?
    let message: String?
    let palette: MoneyPalette

    var body: some View {
        let p = palette
        VStack(alignment: .leading, spacing: 10) {
            VerdictHeader(icon: icon, tint: tint, glyph: AK.ink, title: title, subtitle: subtitle, palette: p)
            if let message {
                Text(message).font(.footnote).foregroundStyle(p.soft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(p.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - The review

/// The trade at a glance: what you get as the one big number, what you
/// pay quieter under it, then three plain rows and the limits in one line.
struct ReviewCard: View {
    let review: TradeReview
    let palette: MoneyPalette
    let dim: Bool
    var source: AnyView?

    var body: some View {
        let p = palette, r = review
        VStack(alignment: .leading, spacing: 8) {
            if let source { source }
            hero(r, p)
            if let refuse = r.limits.willRefuse {
                Callout(icon: "hand.raised.fill", text: Plain.scrub(refuse), palette: p)
            } else if r.standIn != nil {
                NoteLine(text: "Testnet has no \(r.call.asset), so this swaps \(r.pay.symbol) to \(r.receive.symbol).", palette: p)
            }
            VStack(spacing: 3) {
                InfoRow(label: "At least", value: "\(r.receiveMin) \(r.receive.symbol)", palette: p,
                        tint: dim ? p.soft : nil)
                InfoRow(label: "Price can move", value: "\(r.slippagePct)%", palette: p)
                InfoRow(label: "Swap on", value: venueName(r.venue), palette: p,
                        note: venueNote(r))
                if let line = r.intentsLine {
                    InfoRow(label: "Checked by", value: "NEAR Intents", palette: p, note: intentsNote(r))
                        .accessibilityLabel(line)
                }
            }
            Spacer(minLength: 0)
            limits(r, p)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
        .background(p.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    /// "You get about 0.6302 USDC", big; "for 0.2994 NEAR" quieter beside it,
    /// or under it when the text is large.
    private func hero(_ r: TradeReview, _ p: MoneyPalette) -> some View {
        let get = HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(r.receive.amount).font(.title.weight(.semibold).monospacedDigit())
                .foregroundStyle(dim ? p.faint : p.text)
            Text(r.receive.symbol).font(.headline).foregroundStyle(dim ? p.faint : p.soft)
        }
        let pay = Text("for \(r.pay.amount) \(r.pay.symbol)")
            .font(.subheadline.monospacedDigit()).foregroundStyle(p.soft)
        return VStack(alignment: .leading, spacing: 0) {
            Text(dim ? "Price expired" : "You get about")
                .font(.caption.weight(dim ? .semibold : .regular))
                .foregroundStyle(dim ? p.warn : p.soft)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    get
                    Spacer(minLength: 8)
                    pay
                }
                VStack(alignment: .leading, spacing: 0) { get; pay }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(dim ? "Price expired. Was about \(r.receive.amount) \(r.receive.symbol) for \(r.pay.amount) \(r.pay.symbol)"
                                : "You get about \(r.receive.amount) \(r.receive.symbol) for \(r.pay.amount) \(r.pay.symbol)")
    }

    /// "Rhea, pool 1103" reads as "Rhea" with the pool as a small grey label.
    private func venueName(_ venue: String) -> String {
        guard !venue.isEmpty else { return "—" }
        return venue.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? venue
    }

    /// "ETH listed · NEAR $2.10": the short form of the server's Intents line.
    private func intentsNote(_ r: TradeReview) -> String {
        let listed = r.standIn == nil ? "\(r.call.asset) listed" : "\(r.call.asset) listed on mainnet"
        guard let price = r.nearPrice else { return listed }
        return "\(listed) · NEAR $\(String(format: "%.2f", price))"
    }

    private func venueNote(_ r: TradeReview) -> String? {
        var parts: [String] = []
        if let comma = r.venue.firstIndex(of: ",") {
            parts.append(r.venue[r.venue.index(after: comma)...].trimmingCharacters(in: .whitespaces))
        }
        if r.network.localizedCaseInsensitiveContains("testnet") { parts.append("testnet") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func limits(_ r: TradeReview, _ p: MoneyPalette) -> some View {
        let l = r.limits
        let spent = Double(l.spentToday) ?? 0, daily = Double(l.daily) ?? 0
        let fraction = daily > 0 ? spent / daily : 0
        let tint: Color = l.stopped ? p.bad : fraction > 0.8 ? p.warn : p.text.opacity(0.7)
        return HStack(spacing: 8) {
            Text("Spend Limits").font(.caption.weight(.semibold)).fixedSize()
            SpendBar(fraction: l.stopped ? 1 : fraction, tint: tint, palette: p)
                .frame(minWidth: 24, maxWidth: 64)
            Spacer(minLength: 4)
            Text(l.stopped ? "Stopped" : "\(l.spentToday) of \(l.daily) NEAR today")
                .font(.caption.monospacedDigit()).foregroundStyle(l.stopped ? p.bad : p.soft)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.trailing)
        }
        .padding(.top, 8)
        .overlay(alignment: .top) { Rectangle().fill(p.line).frame(height: 0.5) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(l.stopped ? "Spend Limits: stopped" :
            "Spend Limits: \(l.spentToday) of \(l.daily) NEAR spent today, up to \(l.perTrade) NEAR a trade. You can stop it.")
    }
}

// MARK: - The receipt

/// The verdict first, then one hero line for what happened, then the proof.
struct ReceiptCard: View {
    let receipt: TradeReceipt
    let palette: MoneyPalette
    let actions: MoneyActions

    var body: some View {
        let p = palette, r = receipt
        VStack(alignment: .leading, spacing: 10) {
            VerdictHeader(icon: icon, tint: tint, glyph: r.blocked ? .white : AK.ink,
                          title: title, subtitle: subtitle, palette: p)
            if let hero {
                Text(hero).font(.title2.weight(.semibold).monospacedDigit())
                    .accessibilityLabel(heroLabel ?? hero)
            }
            if r.blocked || r.status == "failed", let reason = r.reason {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Plain.scrub(reason)).font(.footnote).foregroundStyle(p.soft)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if let rule = r.rule {
                        Text("Rule \(rule)").font(.caption2.weight(.medium)).foregroundStyle(p.faint)
                            .accessibilityHidden(true)
                    }
                }
            }
            if r.repeated {
                Text("Already confirmed. Nothing was sent again.").font(.caption).foregroundStyle(p.soft)
            }
            if r.swapped, let pay = r.pay {
                InfoRow(label: "Paid", value: pay.line, palette: p)
            }
            if r.postSource == "telegram", let group = r.postAuthor {
                // A Telegram call: the group, and its t.me link when the group is public.
                if let post = r.postURL, let url = URL(string: post) {
                    Button {
                        Haptics.letter()
                        actions.open(url) { ok in if !ok { UIPasteboard.general.string = url.absoluteString } }
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("From").foregroundStyle(p.soft)
                            Spacer(minLength: 8)
                            Text(group).fontWeight(.medium).foregroundStyle(p.text).lineLimit(1)
                            Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(p.soft)
                        }
                        .font(.footnote)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open the message from \(group) in Telegram")
                } else {
                    InfoRow(label: "From", value: group, palette: p)
                }
            } else if let post = r.postURL, let url = URL(string: post) {
                Button {
                    Haptics.letter()
                    actions.open(url) { ok in if !ok { UIPasteboard.general.string = url.absoluteString } }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("From").foregroundStyle(p.soft)
                        Spacer(minLength: 8)
                        Text(r.postAuthor.map { "@\($0.replacingOccurrences(of: "@", with: ""))" } ?? "a post")
                            .fontWeight(.medium).foregroundStyle(p.text)
                        Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(p.soft)
                    }
                    .font(.footnote)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open the post\(r.postAuthor.map { " by \($0)" } ?? "")")
            }
            Spacer(minLength: 0)
            if let url = explorerURL {
                link(r.txURL != nil ? "View transaction" : "View activity", url, p)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
        .background(p.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// The transaction, or for a result we can't confirm, the agent's
    /// activity on the explorer: the place to see whether it went through.
    private var explorerURL: URL? {
        if let tx = receipt.txURL { return URL(string: tx) }
        guard receipt.unknown, !receipt.agent.isEmpty else { return nil }
        let host = receipt.agent.hasSuffix(".testnet") ? "testnet.nearblocks.io" : "nearblocks.io"
        return URL(string: "https://\(host)/address/\(receipt.agent)")
    }

    private var hero: String? {
        let r = receipt
        if r.swapped, let got = r.receive { return "+\(got.line)" }
        if r.blocked, let kept = r.pay { return "\(kept.line) kept" }
        if r.unknown { return nil }
        return nil
    }

    private var heroLabel: String? {
        let r = receipt
        if r.swapped, let got = r.receive { return "Got \(got.line)" }
        return nil
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

    private var subtitle: String {
        if receipt.unknown { return "We couldn't confirm this trade. It won't be sent again." }
        return receipt.byContract ? "Checked by your Spend Limits" : "Stopped by the Keybots server"
    }

    private func link(_ title: String, _ url: URL, _ p: MoneyPalette) -> some View {
        Button {
            Haptics.letter()
            actions.open(url) { ok in if !ok { UIPasteboard.general.string = url.absoluteString } }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "link").font(.system(size: 12, weight: .semibold))
                Text(title).font(.subheadline.weight(.semibold))
                Spacer(minLength: 4)
                Text("nearblocks").font(.caption2).foregroundStyle(p.faint)
                Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(p.soft)
            }
            .padding(.horizontal, 12).frame(minHeight: 40)
            .background(p.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(MoneyPress())
        .accessibilityLabel("\(title) on the NEAR explorer")
    }
}
