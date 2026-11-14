import SwiftUI
import UIKit

/// A typed payment, on its own screen before anything is sent: who gets it,
/// how much, the network fee, the Pay Agent's limits left today, then hold
/// (or tap twice) to pay. The receipt lands on the same screen.
struct PayRequest: Equatable {
    let name: String
    let amount: String
    let memo: String?
    /// What was typed, taken out of the message box once it's paid.
    let typed: String
}

@Observable
@MainActor
final class PayModel {
    enum Phase: Equatable { case loading, ready, sending, done }

    let request: PayRequest
    var phase: Phase = .loading
    /// The account the name stands for ("harshal" is friend.airkey-harshal.testnet).
    var account: String?
    var usd: Double?
    var perPayment: Double?
    var daily: Double?
    var spentToday: Double?
    var stopped = false
    var network = "NEAR testnet"
    var receipt: Receipt?
    var error: String?
    private var started = false

    init(request: PayRequest) { self.request = request }

    var amount: Double { Double(request.amount) ?? 0 }
    var leftToday: Double? { daily.map { max(0, $0 - (spentToday ?? 0)) } }

    /// What Spend Limits will say, before it's asked: the same checks, read from its state.
    var willRefuse: String? {
        if stopped { return "Stop everything is on. Spend Limits will refuse it." }
        if let per = perPayment, amount > per { return "Over the \(Self.near(per)) per-payment limit. Spend Limits will refuse it." }
        if let left = leftToday, amount > left { return "Over what's left today (\(Self.near(left))). Spend Limits will refuse it." }
        return nil
    }

    func load() {
        guard !started else { return }
        started = true
        Task {
            async let state = try? API().state()
            async let price = try? API().price("NEAR")
            let (s, p) = await (state, price)
            usd = p.map { $0.usd * amount }
            if let s {
                network = s.explorer.contains("testnet") ? "NEAR testnet" : "NEAR mainnet"
                stopped = s.paused
                let key = request.name.lowercased()
                account = s.contacts[key] ?? (key.contains(".") ? key : nil)
                if let pay = s.shownAgents.first(where: { $0.account == s.active?.trusted }) {
                    perPayment = Self.value(pay.agent.per_payment_cap)
                    daily = Self.value(pay.agent.daily_cap)
                    spentToday = Self.value(pay.agent.spent_today)
                }
            } else {
                error = "Can't reach the Keybots server right now."
            }
            phase = .ready
        }
    }

    func pay(done: @escaping (Receipt) -> Void) {
        guard phase == .ready else { return }
        phase = .sending
        let memo = request.memo.map { " for \($0)" } ?? ""
        Task {
            do {
                let r = try await API().command("pay \(account ?? request.name) \(request.amount)\(memo)", source: "typed")
                receipt = r
                phase = .done
                done(r)
                if r.signal == .block { Haptics.warning() } else { Haptics.success() }
            } catch {
                self.error = error.localizedDescription
                phase = .ready
                Haptics.warning()
            }
        }
    }

    static func value(_ yocto: String) -> Double { (Double(yocto) ?? 0) / 1e24 }
    static func near(_ v: Double) -> String {
        let s = String(format: "%.4f", v).replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
        return "\(s) NEAR"
    }
}

struct PayView: View {
    let model: PayModel
    let palette: MoneyPalette
    let actions: MoneyActions
    let close: () -> Void
    let paid: (Receipt) -> Void

    var body: some View {
        let p = palette
        VStack(spacing: 0) {
            HStack {
                Button(action: close) {
                    Image(systemName: "xmark").font(.subheadline.weight(.semibold)).foregroundStyle(p.text)
                        .frame(width: 34, height: 34).background(p.fill, in: Circle())
                }
                .buttonStyle(MoneyPress())
                .accessibilityLabel("Close")
                Spacer()
                VStack(spacing: 0) {
                    Text("Pay").font(.headline).foregroundStyle(p.text)
                    Text(model.network).font(.caption2).foregroundStyle(model.network.contains("mainnet") ? p.warn : p.soft)
                }
                Spacer()
                Color.clear.frame(width: 34, height: 34)
            }
            .padding(.horizontal, MoneyPalette.inset).padding(.top, 6)

            if let r = model.receipt { result(r, p) } else { review(p) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { model.load() }
    }

    private func review(_ p: MoneyPalette) -> some View {
        VStack(spacing: 10) {
            // Who gets it.
            HStack(spacing: 12) {
                Text(String(model.request.name.prefix(1)).uppercased())
                    .font(.title3.weight(.bold)).foregroundStyle(AK.ink)
                    .frame(width: 44, height: 44).background(AK.accent, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.request.name).font(.headline).foregroundStyle(p.text)
                    Text(model.account ?? (model.phase == .loading ? "Looking up…" : "Account checked when it's sent"))
                        .font(.caption.monospaced()).foregroundStyle(p.soft).lineLimit(1).minimumScaleFactor(0.7)
                    if let memo = model.request.memo {
                        Text("for \(memo)").font(.caption).foregroundStyle(p.soft).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(model.request.amount) NEAR").font(.title2.weight(.bold).monospacedDigit()).foregroundStyle(p.text)
                    if let usd = model.usd {
                        Text(String(format: "≈ $%.2f", usd)).font(.caption.monospacedDigit()).foregroundStyle(p.soft)
                    }
                }
            }
            .padding(10)
            .background(p.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityElement(children: .combine)

            VStack(spacing: 4) {
                InfoRow(label: "Paid by", value: "Pay Agent, from Spend Limits", palette: p)
                InfoRow(label: "Network fee", value: "≈ 0.0005 NEAR", palette: p, note: "Pay Agent's gas")
                if let left = model.leftToday, let daily = model.daily {
                    let over = model.amount > left || model.amount > (model.perPayment ?? .infinity)
                    InfoRow(label: "Left today", value: "\(PayModel.near(left)) of \(PayModel.near(daily))", palette: p,
                            tint: over ? p.bad : nil, note: model.perPayment.map { "up to \(PayModel.near($0)) each" })
                }
            }
            if let refuse = model.willRefuse {
                Label(refuse, systemImage: "hand.raised.fill").font(.caption.weight(.medium)).foregroundStyle(p.warn)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let error = model.error {
                Label(error, systemImage: "wifi.exclamationmark").font(.caption.weight(.medium)).foregroundStyle(p.warn)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 0)
            if model.phase == .sending {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Asking Spend Limits on NEAR…").font(.subheadline.weight(.medium)).foregroundStyle(p.text)
                }
                .frame(maxWidth: .infinity).frame(height: 52)
            } else {
                TradeHold(label: "Hold to pay \(model.request.amount) NEAR", disabled: model.phase != .ready,
                          neutral: model.willRefuse != nil, palette: p, action: { model.pay(done: paid) },
                          confirmLabel: "Confirm payment")
            }
        }
        .padding(.horizontal, MoneyPalette.inset).padding(.top, 8).padding(.bottom, 12)
    }

    private func result(_ r: Receipt, _ p: MoneyPalette) -> some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)
            Image(systemName: r.signal == .block ? "xmark.octagon.fill" : "checkmark.circle.fill")
                .font(.system(size: 44)).foregroundStyle(r.signal == .block ? p.bad : p.good)
            Text(Plain.title(r)).font(.headline).foregroundStyle(p.text).multilineTextAlignment(.center)
            Text(Plain.body(r)).font(.footnote).foregroundStyle(p.soft).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let tx = r.tx, let url = URL(string: tx.url) {
                Button { actions.open(url) { ok in if !ok { UIPasteboard.general.string = tx.url } } } label: {
                    Text("See it on NEAR ↗").font(.footnote.weight(.semibold)).foregroundStyle(p.text)
                        .padding(.horizontal, 14).frame(height: 32).background(p.fill, in: Capsule())
                }
                .buttonStyle(MoneyPress())
            }
            Spacer(minLength: 0)
            Button(action: close) {
                Text("Done").font(.subheadline.weight(.bold)).foregroundStyle(AK.ink)
                    .frame(maxWidth: .infinity).frame(height: 48).background(AK.accent, in: Capsule())
            }
            .buttonStyle(MoneyPress())
        }
        .padding(.horizontal, MoneyPalette.inset).padding(.bottom, 10)
    }
}

/// The pay screen over the whole keyboard: SwiftUI in a host, let go on close.
final class PaySurface: UIView {
    private let host: UIHostingController<AnyView>

    init(request: PayRequest, dark: Bool, actions: MoneyActions, close: @escaping () -> Void, paid: @escaping (Receipt) -> Void) {
        let model = PayModel(request: request)
        host = UIHostingController(rootView: AnyView(
            PayView(model: model, palette: MoneyPalette(dark: dark), actions: actions, close: close, paid: paid)
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
        host.willMove(toParent: nil)
        host.view.removeFromSuperview()
        host.removeFromParent()
        removeFromSuperview()
    }
}
