import SwiftUI
import UIKit

/// What the Keybots key opens: the bots and what they did, then the tools.
/// Read-only; every number comes from Spend Limits through the server.
@Observable
@MainActor
final class HomeModel {
    struct Bot: Identifiable {
        let id: String
        let name: String
        let spent: Double
        let daily: Double
        /// The last thing it did, if anything.
        var last: Receipt? = nil
    }

    var bots: [Bot] = []
    var recent: [Receipt] = []
    /// Calls read today, by where they were posted.
    var xToday = 0
    var telegramToday = 0
    /// The newest call in the feed, when nothing was traded today.
    var latestCall: KolCall?
    /// Trades that came from a call you reviewed or a trader you follow, today.
    var tradedToday: [Receipt] = []
    /// Everything the bots did today that moved money or was stopped.
    var doneToday: [Receipt] = []
    var stopped = false
    var network = ""
    var available: String?
    var loaded = false
    var failed = false
    /// "testnet" or "mainnet", as the switch shows it.
    var choice = Settings.network
    private var task: Task<Void, Never>?

    /// The app and the keyboard share this setting; the panel reloads from the other server.
    func switchTo(_ network: String) {
        Settings.network = network
        choice = Settings.network
        bots = []
        recent = []
        available = nil
        stop()
        start()
    }

    func start() {
        guard task == nil else { return }
        task = Task {
            while !Task.isCancelled {
                await load()
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    func stop() { task?.cancel(); task = nil }

    private func load() async {
        async let s = try? API().state()
        async let r = try? API().receipts(limit: 60)
        async let f = try? JourneyAPI().feed()
        let asked = choice
        let (state, receipts, feed) = await (s, r, f)
        // Switched network while this was on its way: it belongs to the other one.
        guard asked == choice else { return }
        if let state {
            Fmt.roleNames = state.roleNames
            stopped = state.paused
            network = state.explorer.contains("testnet") ? "Testnet" : "Mainnet"
            available = Fmt.near(state.available)
            let all = receipts ?? []
            bots = state.shownAgents.map { a in
                Bot(id: a.account, name: Fmt.agentName(account: a.account),
                    spent: (Double(a.agent.spent_today) ?? 0) / 1e24, daily: (Double(a.agent.daily_cap) ?? 0) / 1e24,
                    last: all.first { $0.agent?.account == a.account && $0.outcome != "not-sent" })
            }
        }
        // Only what moved money or was stopped: no readings that found nothing to do.
        if let receipts {
            let money = receipts.filter { ["paid", "swapped", "blocked", "approval"].contains($0.outcome) }
            recent = Array(money.prefix(4))
            let today = money.filter { r in r.date.map { Calendar.current.isDateInToday($0) } ?? false }
            doneToday = today
            tradedToday = Array(today.filter { ["reviewed-call", "follow"].contains($0.input.source) }.prefix(3))
        }
        if let feed, !feed.sample {
            let fresh = feed.calls.filter { c in c.postedAt.map { Calendar.current.isDateInToday($0) } ?? false }
            xToday = fresh.filter { !$0.telegram }.count
            telegramToday = fresh.filter(\.telegram).count
            latestCall = feed.calls.first
        }
        failed = state == nil
        loaded = true
    }
}

struct HomeView: View {
    let model: HomeModel
    let palette: MoneyPalette
    let tools: [(id: String, title: String, icon: String)]
    let open: (String) -> Void
    let customize: () -> Void
    let close: () -> Void

    var body: some View {
        let p = palette
        VStack(alignment: .leading, spacing: 12) {
            header(p)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    bots(p)
                    today(p)
                    signals(p)
                    recent(p)
                }
            }
            toolRow(p)
        }
        .padding(.horizontal, MoneyPalette.inset)
        .padding(.top, 10).padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    private func header(_ p: MoneyPalette) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Keybots").font(.headline).foregroundStyle(p.text)
                if let a = model.available, !model.bots.isEmpty {
                    Text(model.stopped ? "All bots stopped · \(a) held" : "\(model.bots.count) bots running · \(a) to spend")
                        .font(.caption.monospacedDigit()).foregroundStyle(model.stopped ? p.bad : p.soft).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if Settings.mainnetURL != nil { netSwitch(p) }
            Button(action: close) {
                Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(p.text)
                    .frame(width: 30, height: 30).background(p.fill, in: Circle())
            }
            .buttonStyle(MoneyPress())
            .accessibilityLabel("Close")
        }
    }

    /// Testnet or Mainnet, small, on the right: the same setting as the app's.
    private func netSwitch(_ p: MoneyPalette) -> some View {
        HStack(spacing: 2) {
            ForEach(["testnet", "mainnet"], id: \.self) { n in
                let on = model.choice == n
                Button {
                    guard !on else { return }
                    Haptics.layer()
                    model.switchTo(n)
                } label: {
                    Text(n == "testnet" ? "Testnet" : "Mainnet")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(on ? (n == "mainnet" ? AK.ink : p.text) : p.soft)
                        .padding(.horizontal, 8).frame(height: 24)
                        .background { if on { Capsule().fill(n == "mainnet" ? p.warn : p.thumb) } }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(n == "testnet" ? "Testnet" : "Mainnet, real NEAR")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(2)
        .background(p.fill, in: Capsule())
    }

    @ViewBuilder private func bots(_ p: MoneyPalette) -> some View {
        VStack(spacing: 0) {
            if model.bots.isEmpty {
                Text(model.failed ? "Can't reach Keybots right now." : "Loading…")
                    .font(.footnote).foregroundStyle(p.soft)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(12)
            }
            ForEach(Array(model.bots.enumerated()), id: \.element.id) { i, b in
                if i > 0 { Rectangle().fill(p.line).frame(height: 0.5).padding(.leading, 30) }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 10) {
                        PulseDot(color: model.stopped ? p.bad : p.good, live: !model.stopped)
                        Text(b.name).font(.footnote.weight(.semibold)).foregroundStyle(p.text).lineLimit(1)
                        Spacer(minLength: 6)
                        Text(model.stopped ? "Stopped" : "Running")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(model.stopped ? p.bad : p.good)
                            .padding(.horizontal, 7).frame(height: 18)
                            .background((model.stopped ? p.bad : p.good).opacity(0.14), in: Capsule())
                    }
                    Text(Self.detail(b))
                        .font(.caption.monospacedDigit()).foregroundStyle(p.soft).lineLimit(1)
                        .padding(.leading, 17)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .accessibilityElement(children: .combine)
            }
        }
        .background(p.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// What the bots did today, in numbers: paid, swapped, refused, waiting.
    @ViewBuilder private func today(_ p: MoneyPalette) -> some View {
        if !model.bots.isEmpty {
            let count = { (o: String) in model.doneToday.filter { $0.outcome == o }.count }
            HStack(spacing: 8) {
                stat("\(count("paid"))", "paid", p.good, p)
                stat("\(count("swapped"))", "swapped", p.good, p)
                stat("\(count("blocked"))", "refused", p.bad, p)
                stat("\(count("approval"))", "waiting", p.warn, p)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Today: \(count("paid")) paid, \(count("swapped")) swapped, \(count("blocked")) refused, \(count("approval")) waiting for you")
        }
    }

    private func stat(_ n: String, _ label: String, _ color: Color, _ p: MoneyPalette) -> some View {
        VStack(spacing: 1) {
            Text(n).font(.headline.monospacedDigit()).foregroundStyle(n == "0" ? p.soft : color)
            Text(label).font(.caption2).foregroundStyle(p.soft)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 7)
        .background(p.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// Calls from X and Telegram: what came in today, what was traded, and a way to follow someone.
    private func signals(_ p: MoneyPalette) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Signals").font(.caption.weight(.semibold)).foregroundStyle(p.soft)
                Spacer(minLength: 4)
                Text("Today: \(model.xToday) from X · \(model.telegramToday) from Telegram")
                    .font(.caption.monospacedDigit()).foregroundStyle(p.soft).lineLimit(1)
            }
            if model.tradedToday.isEmpty {
                if let c = model.latestCall {
                    HStack(spacing: 8) {
                        Text(c.telegram ? "TG" : "X").font(.caption2.weight(.bold)).foregroundStyle(p.text)
                            .frame(width: 22, height: 18).background(p.fill, in: Capsule())
                        Text("\(c.telegram ? (c.name ?? c.handle) : "@" + c.handle) · \(c.sell ? "Sell" : "Buy") \(c.asset)")
                            .font(.footnote).foregroundStyle(p.text).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(J.ago(c.postedAt) ?? "").font(.caption).foregroundStyle(p.faint).fixedSize()
                    }
                }
                Text("No call traded today. Every trade waits for your review and hold.")
                    .font(.caption).foregroundStyle(p.soft)
            } else {
                ForEach(model.tradedToday) { r in
                    HStack(spacing: 8) {
                        Image(systemName: Self.icon(r)).font(.caption.weight(.bold)).foregroundStyle(Self.tint(r, p)).frame(width: 20)
                        Text(Plain.line(r)).font(.footnote).foregroundStyle(p.text).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(r.input.handle.map { "@" + $0 } ?? "").font(.caption).foregroundStyle(p.soft).lineLimit(1)
                    }
                }
            }
            HStack(spacing: 8) {
                pill("See calls", "chart.line.uptrend.xyaxis", p) { open("calls") }
                pill("Follow someone", "person.badge.plus", p) { open("calls-following") }
            }
        }
        .padding(12)
        .background(p.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func pill(_ title: String, _ icon: String, _ p: MoneyPalette, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.caption.weight(.semibold)).foregroundStyle(p.text)
                .padding(.horizontal, 10).frame(height: 28)
                .background(p.fill, in: Capsule())
        }
        .buttonStyle(MoneyPress())
    }

    @ViewBuilder private func recent(_ p: MoneyPalette) -> some View {
        if !model.recent.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Recent").font(.caption.weight(.semibold)).foregroundStyle(p.soft)
                ForEach(model.recent) { r in
                    HStack(spacing: 10) {
                        Image(systemName: Self.icon(r))
                            .font(.caption.weight(.bold)).foregroundStyle(Self.tint(r, p))
                            .frame(width: 20)
                        Text(Plain.line(r)).font(.footnote).foregroundStyle(p.text).lineLimit(1).truncationMode(.tail)
                        Spacer(minLength: 6)
                        Text(J.ago(r.date) ?? "").font(.caption).foregroundStyle(p.faint).lineLimit(1).fixedSize()
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func toolRow(_ p: MoneyPalette) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tools, id: \.id) { t in
                    Button { open(t.id) } label: {
                        VStack(spacing: 4) {
                            Image(systemName: t.icon).font(.system(size: 17, weight: .medium))
                            Text(t.title).font(.caption2).lineLimit(1)
                        }
                        .foregroundStyle(p.text)
                        .frame(width: 64, height: 54)
                        .background(p.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(MoneyPress())
                    .accessibilityLabel(t.title)
                }
                Button(action: customize) {
                    VStack(spacing: 4) {
                        Image(systemName: "slider.horizontal.3").font(.system(size: 17, weight: .medium))
                        Text("Customize").font(.caption2).lineLimit(1)
                    }
                    .foregroundStyle(p.soft)
                    .frame(width: 70, height: 54)
                }
                .buttonStyle(MoneyPress())
            }
        }
    }

    /// "0.2 of 1 NEAR today · Paid 0.01 NEAR to harshal · 2 h ago".
    static func detail(_ b: HomeModel.Bot) -> String {
        var parts = ["\(num(b.spent)) of \(num(b.daily)) NEAR today"]
        if let r = b.last {
            parts.append(Plain.line(r))
            if let ago = J.ago(r.date) { parts.append(ago) }
        } else {
            parts.append("Waiting for work")
        }
        return parts.joined(separator: " · ")
    }

    static func num(_ v: Double) -> String {
        String(format: "%.4f", v).replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
    }

    static func icon(_ r: Receipt) -> String {
        switch r.outcome {
        case "paid": "arrow.up.right"
        case "swapped": "arrow.left.arrow.right"
        case "blocked": "xmark.octagon.fill"
        case "approval": "hand.raised.fill"
        default: "circle"
        }
    }

    static func tint(_ r: Receipt, _ p: MoneyPalette) -> Color {
        switch r.outcome {
        case "paid", "swapped": p.good
        case "blocked": p.bad
        case "approval": p.warn
        default: p.soft
        }
    }
}

/// The Keybots panel over the keyboard, built when it opens and let go when it closes.
final class HomeSurface: UIView {
    private let host: UIHostingController<AnyView>
    private let model = HomeModel()

    init(dark: Bool, tools: [(id: String, title: String, icon: String)],
         open: @escaping (String) -> Void, customize: @escaping () -> Void, close: @escaping () -> Void) {
        let m = model
        host = UIHostingController(rootView: AnyView(
            HomeView(model: m, palette: MoneyPalette(dark: dark), tools: tools, open: open, customize: customize, close: close)
                .environment(\.colorScheme, dark ? .dark : .light)))
        super.init(frame: .zero)
        host.view.backgroundColor = .clear
        host.sizingOptions = []
        host.safeAreaRegions = []
        addSubview(host.view)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        host.view.frame = bounds
    }

    func attach(to parent: UIViewController) {
        parent.addChild(host)
        host.didMove(toParent: parent)
    }

    func close() {
        model.stop()
        host.willMove(toParent: nil)
        host.view.removeFromSuperview()
        host.removeFromParent()
        removeFromSuperview()
    }
}

/// A status dot that breathes while its bot is running; still when it isn't,
/// or when Reduce Motion is on.
private struct PulseDot: View {
    let color: Color
    let live: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var on = false

    var body: some View {
        ZStack {
            if live && !reduceMotion {
                Circle().fill(color.opacity(0.35))
                    .frame(width: 7, height: 7)
                    .scaleEffect(on ? 2.4 : 1)
                    .opacity(on ? 0 : 1)
                    .animation(.easeOut(duration: 1.6).repeatForever(autoreverses: false), value: on)
            }
            Circle().fill(color).frame(width: 7, height: 7)
        }
        .frame(width: 14, height: 14)
        .onAppear { on = true }
        .accessibilityHidden(true)
    }
}
