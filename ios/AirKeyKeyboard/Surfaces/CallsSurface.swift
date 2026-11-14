import Observation
import SwiftUI
import UIKit

/// The calls book, as the Calls panel shows it: every copied call the server
/// checked (GET /v1/calls), the ones still to act on and the ones that are
/// done. A call only ever trades on a press and hold, and the hold asks the
/// server to check the call again first.
@Observable
@MainActor
final class CallsModel {
    enum Tab: Hashable { case posts, open, done, following }

    var tab: Tab = .posts
    /// The callers' posts (GET /v1/kol/feed); nil until the first read lands.
    var feed: KolFeed?
    var feedProblem: String?
    /// A call being reviewed, held and confirmed; the panel shows only it.
    var journey: JourneyModel?
    /// The panel wants the whole keyboard (a review) or just the key area.
    @ObservationIgnored var onFull: ((Bool) -> Void)?
    /// nil until the first read lands.
    var calls: [CallRecord]?
    var problem: String?
    /// One line about the last thing that happened (a paste that wasn't a call, a link copied).
    var notice: String?
    /// The clipboard is being checked.
    var checking = false
    /// The call whose hold is running, and what it is doing right now.
    var running: String?
    var stage = ""

    /// The people you follow, whose calls trade for you within your rules.
    let following = FollowsModel()

    @ObservationIgnored private var watching: Task<Void, Never>?

    var open: [CallRecord] { (calls ?? []).filter(\.open) }
    var done: [CallRecord] { (calls ?? []).filter { !$0.open } }

    /// Retry every 4 seconds until the book loads, then every 20 (the prices move).
    func start() {
        guard watching == nil else { return }
        watching = Task { [weak self] in
            while !Task.isCancelled {
                await self?.load()
                guard let self else { return }
                try? await Task.sleep(for: .seconds(self.calls == nil ? 4 : 20))
            }
        }
    }

    func stop() {
        watching?.cancel()
        watching = nil
        following.stop()
    }

    func retry() {
        problem = nil
        Task { await load() }
    }

    func load() async {
        do {
            let f = try await JourneyAPI().feed()
            guard !Task.isCancelled else { return }
            feed = f
            feedProblem = nil
        } catch {
            if feed == nil, !Task.isCancelled { feedProblem = error.localizedDescription }
        }
        do {
            let list = try await API().calls()
            guard !Task.isCancelled else { return }
            calls = list
            problem = nil
        } catch {
            if calls == nil, !Task.isCancelled { problem = error.localizedDescription }
        }
    }

    /// Paste a call: what's on the clipboard goes to the server's rules. A
    /// call lands in the book (Open with its trade, or Done with why not);
    /// anything else is left alone. Nothing runs.
    func paste() {
        guard !checking else { return }
        guard let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            // A keyboard can't show iOS's "Allow Paste" prompt, so a refused read looks like an empty clipboard.
            notice = UIPasteboard.general.hasStrings
                ? "To check copied text: Settings › Apps › AIRKEY › Paste from Other Apps › Allow."
                : "Copy a post first, then tap Paste a call."
            Haptics.warning()
            return
        }
        notice = nil
        checking = true
        Task {
            defer { checking = false }
            do {
                let check = try await API().call(text)
                guard check.call.isCall else {
                    notice = "That isn't a trade call: no token with a direction."
                    Haptics.warning()
                    return
                }
                await load()
                let available = check.route.status == "available"
                withAnimation(.snappy(duration: 0.2)) { tab = available ? .open : .done }
                notice = available ? nil : check.route.reason.map(MoneyText.plain)
                if available { Haptics.letter() } else { Haptics.warning() }
            } catch {
                notice = error.localizedDescription
                Haptics.error()
            }
        }
    }

    /// The hold on a call's chip. The call is checked again (token, caps,
    /// today's price); only if a trade is still on offer does its command go
    /// to the Trading Agent, tied to the call so the book keeps the outcome.
    func run(_ call: CallRecord) {
        guard running == nil else { return }
        Haptics.hold()
        notice = nil
        running = call.id
        stage = "Checking it again…"
        Task {
            defer { running = nil }
            do {
                let check = try await API().call(call.text)
                guard check.route.status == "available", let command = check.route.command else {
                    notice = check.route.reason.map(MoneyText.plain) ?? "That trade isn't on offer any more."
                    Haptics.warning()
                    await load()
                    return
                }
                stage = "Trading Agent is on it…"
                let receipt = try await API().command(command, callId: check.id ?? call.id)
                switch receipt.signal {
                case .allow: Haptics.success()
                case .warn: Haptics.warning()
                case .block: Haptics.error()
                default: Haptics.letter()
                }
                await load()
                withAnimation(.snappy(duration: 0.2)) { tab = .done }
            } catch {
                notice = error.localizedDescription
                Haptics.error()
            }
        }
    }

    /// Review a feed post's trade. Nothing trades until the hold.
    func review(_ post: KolCall) {
        open(JourneyModel(callId: post.id, text: post.text, post: post))
    }

    /// Review a copied call's trade (the strip's chip, a call in the book).
    func review(text: String) {
        open(JourneyModel(callId: nil, text: text))
    }

    private func open(_ j: JourneyModel) {
        journey?.stop()
        notice = nil
        withAnimation(.snappy(duration: 0.22)) { journey = j }
        onFull?(true)
    }

    func closeJourney() {
        journey?.stop()
        withAnimation(.snappy(duration: 0.22)) { journey = nil }
        onFull?(false)
        Task { await load() }
    }

    /// Put a call away without trading it.
    func dismiss(_ call: CallRecord) {
        Haptics.letter()
        withAnimation(.snappy(duration: 0.2)) { calls?.removeAll { $0.id == call.id } }
        Task {
            try? await API().dismissCall(call.id)
            await load()
        }
    }
}

/// Calls, over the keys: "Open" is every call you checked and haven't acted
/// on, each with its small trade ready to hold; "Done" is what was traded,
/// stopped or couldn't be traded, with the outcome and the transaction.
struct CallsView: View {
    @Bindable var model: CallsModel
    let actions: MoneyActions
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = MoneyPalette(dark: scheme == .dark)
        if let journey = model.journey {
            JourneyView(model: journey, actions: actions, palette: p) { model.closeJourney() }
                .transition(.opacity)
        } else {
            book(p)
        }
    }

    private func book(_ p: MoneyPalette) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                MoneyTabs(tabs: [(.posts, "Posts"), (.open, count("Open", model.open.count)), (.done, count("Done", model.done.count)),
                                 (.following, "Following")],
                          selection: $model.tab, palette: p)
                Spacer(minLength: 4)
                if model.tab == .open || model.tab == .done {
                Button { model.paste() } label: {
                    HStack(spacing: 5) {
                        if model.checking {
                            ProgressView().controlSize(.mini).tint(AK.ink)
                        } else {
                            Image(systemName: "doc.on.clipboard").font(.system(size: 11, weight: .bold))
                        }
                        Text("Paste a call").font(.footnote.weight(.bold))
                    }
                    .foregroundStyle(AK.ink)
                    .padding(.horizontal, 12).frame(height: 28)
                    .background(AK.accent, in: Capsule()).contentShape(Capsule())
                }
                .buttonStyle(MoneyPress())
                .disabled(model.checking || !actions.fullAccess())
                .accessibilityHint("Checks the post you copied. Nothing runs.")
                .transition(.opacity)
                }
            }
            if let notice = model.notice, model.tab != .following {
                Button { withAnimation(.snappy(duration: 0.2)) { model.notice = nil } } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle.fill").font(.caption).foregroundStyle(p.warn)
                        Text(notice).font(.caption).foregroundStyle(p.text).lineLimit(2).multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(p.fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .transition(.opacity)
                .accessibilityHint("Tap to dismiss")
            }
            content(p)
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 4)
        .foregroundStyle(p.text)
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    private func count(_ title: String, _ n: Int) -> String { n > 0 ? "\(title) \(n)" : title }

    /// The callers' posts, newest first. Nothing trades when one appears.
    @ViewBuilder
    private func posts(_ p: MoneyPalette) -> some View {
        if let feed = model.feed {
            if feed.calls.isEmpty {
                MoneyEmpty(text: "No posts from the callers right now.", palette: p)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 6) {
                        if feed.sample {
                            HStack(alignment: .top, spacing: 6) {
                                Text("Sample posts").font(.caption.weight(.bold)).foregroundStyle(p.warn)
                                Text(feed.note ?? "Kall's feed isn't reachable, so these are examples.")
                                    .font(.caption).foregroundStyle(p.soft).fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                        } else if let note = feed.note {
                            Text(note).font(.caption).foregroundStyle(p.soft).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        ForEach(feed.calls) { call in
                            KolCardView(call: call, sample: feed.sample, palette: p, actions: actions) { model.review(call) }
                        }
                    }
                    .padding(.bottom, 8)
                }
                .scrollEdgeEffectHidden(true, for: .all)
            }
        } else if let problem = model.feedProblem {
            MoneyEmpty(text: problem, palette: p)
        } else {
            VStack(spacing: 10) {
                ProgressView().tint(p.text)
                Text("Reading the callers' posts…").font(.footnote).foregroundStyle(p.soft)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func content(_ p: MoneyPalette) -> some View {
        if model.tab == .posts, actions.fullAccess() {
            posts(p)
        } else if model.tab == .following, actions.fullAccess() {
            FollowingView(model: model.following, actions: actions, palette: p)
        } else if !actions.fullAccess() {
            MoneyEmpty(text: "Turn on Allow Full Access for AIRKEY so Calls can reach your server.", palette: p)
        } else if model.calls == nil {
            if let problem = model.problem {
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
                    Text("Reading your calls…").font(.footnote).foregroundStyle(p.soft)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            let list = model.tab == .open ? model.open : model.done
            if list.isEmpty {
                MoneyEmpty(text: model.tab == .open
                    ? "No open calls. Copy a post like “$NEAR breakout, loading up” and tap Paste a call."
                    : "Nothing here yet. Calls you trade, or that can't be traded, land here.", palette: p)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 6) {
                        ForEach(list) { call in
                            CallRow(call: call, model: model, actions: actions, palette: p)
                        }
                    }
                    .padding(.bottom, 8)
                }
                .scrollEdgeEffectHidden(true, for: .all)
            }
        }
    }
}

/// One call: the token and which way, the post itself, how the price has
/// moved since, and either its trade to hold or what became of it.
private struct CallRow: View {
    let call: CallRecord
    let model: CallsModel
    let actions: MoneyActions
    let palette: MoneyPalette

    var body: some View {
        let p = palette
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text("$\(call.asset ?? "?")").font(.subheadline.weight(.heavy))
                HStack(spacing: 2) {
                    Image(systemName: call.bearish ? "arrow.down.right" : "arrow.up.right").font(.system(size: 9, weight: .heavy))
                    Text(call.direction?.capitalized ?? "No direction").font(.caption.weight(.bold))
                }
                .foregroundStyle(call.direction == nil ? p.soft : call.bearish ? p.bad : p.good)
                if call.verified == true {
                    Image(systemName: "checkmark.seal.fill").font(.system(size: 11)).foregroundStyle(p.good)
                        .accessibilityLabel("Token verified on NEAR Intents")
                }
                Spacer(minLength: 4)
                if let move = call.move {
                    // Flat to two decimals is "0.00%", in no colour: never "-0.00%".
                    let flat = abs(move) < 0.005
                    Text(flat ? "0.00%" : String(format: "%+.2f%%", move)).font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(flat ? p.soft : move > 0 ? p.good : p.bad)
                        .contentTransition(.numericText())
                        .accessibilityLabel(String(format: "%+.2f percent since the call", move))
                }
                Text(Fmt.time(call.date)).font(.caption2.monospacedDigit()).foregroundStyle(p.soft)
            }
            Text(call.text).font(.footnote).foregroundStyle(p.text.opacity(0.8)).lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            footer(p)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(p.fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func footer(_ p: MoneyPalette) -> some View {
        if call.open {
            if model.running == call.id {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).tint(p.text)
                    Text(model.stage).font(.caption.weight(.medium)).foregroundStyle(p.soft)
                    Spacer(minLength: 0)
                }
                .frame(height: 30)
            } else {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(call.title ?? "").font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                        Text(call.standIn.map(MoneyText.plain) ?? prices ?? "Nothing runs until you review and hold")
                            .font(.caption2).foregroundStyle(p.soft).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    Spacer(minLength: 4)
                    Button { model.dismiss(call) } label: {
                        Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(p.soft)
                            .frame(width: 28, height: 28).contentShape(Circle())
                    }
                    .buttonStyle(MoneyPress())
                    .accessibilityLabel("Put this call away")
                    Button { Haptics.letter(); model.review(text: call.text) } label: {
                        Text("Review trade").font(.footnote.weight(.bold)).foregroundStyle(AK.ink)
                            .padding(.horizontal, 12).frame(height: 30)
                            .background(AK.accent, in: Capsule()).contentShape(Capsule())
                    }
                    .buttonStyle(MoneyPress())
                    .fixedSize()
                    .accessibilityHint("Shows the trade first. Nothing trades yet.")
                }
            }
        } else if let trade = call.trade {
            HStack(spacing: 8) {
                Image(systemName: trade.signal.icon)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(trade.signal.plain ? p.text : AK.ink)
                    .frame(width: 20, height: 20)
                    .background(trade.signal.plain ? p.fill : trade.signal.color, in: Circle())
                Text(MoneyText.plain(trade.message)).font(.caption).foregroundStyle(p.soft).lineLimit(2).minimumScaleFactor(0.85)
                Spacer(minLength: 4)
                if let tx = trade.tx, let url = URL(string: tx.url) {
                    small("Tx ↗", p) {
                        actions.open(url) { opened in
                            if !opened {
                                UIPasteboard.general.string = tx.url
                                model.notice = "Link copied. Paste it in Safari."
                            }
                        }
                    }
                }
                small("Share", p) {
                    actions.share(MoneyText.receiptLine(message: trade.message, signal: trade.signal, tx: trade.tx))
                }
            }
        } else {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "minus.circle").font(.caption).foregroundStyle(p.soft)
                Text(call.dismissed == true ? "Put away, not traded." : call.reason.map(MoneyText.plain) ?? "No trade for this call.")
                    .font(.caption).foregroundStyle(p.soft).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
    }

    /// "$3.50 at the call, $3.58 now"
    private var prices: String? {
        guard let then = call.priceThen, let now = call.priceNow else { return nil }
        return "\(Fmt.usd(then)) at the call, \(Fmt.usd(now)) now"
    }

    private func small(_ title: String, _ p: MoneyPalette, action: @escaping () -> Void) -> some View {
        Button { Haptics.letter(); action() } label: {
            Text(title).font(.caption.weight(.semibold))
                .padding(.horizontal, 10).frame(height: 26)
                .background(p.fill, in: Capsule()).contentShape(Capsule())
        }
        .buttonStyle(MoneyPress())
    }
}
