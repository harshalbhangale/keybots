import SwiftUI

/// The first screen: what Spend Limits holds, anything waiting for you, a swap,
/// what's being watched, and what the agents did lately.
struct WalletView: View {
    @Environment(AppModel.self) private var model
    let go: (AppTab) -> Void
    let openSettings: () -> Void
    let open: (Receipt) -> Void

    private var network: String {
        (model.state?.explorer.contains("testnet") ?? true) ? "On NEAR testnet" : "On NEAR"
    }

    var body: some View {
        Screen(tint: model.mood) {
            Masthead(eyebrow: network, title: "Wallet") {
                Menu {
                    Button("Settings", systemImage: "gearshape", action: openSettings)
                    if let s = model.state, let url = URL(string: "\(s.explorer)/address/\(s.leash)") {
                        Link(destination: url) { Label("See your account on NEAR", systemImage: "arrow.up.right") }
                    }
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
            }
            VStack(alignment: .leading, spacing: 12) {
                balances
                if model.state?.pending.isEmpty ?? true { status }
                if let s = model.state {
                    AddressRow(label: "Your Spend Limits account", address: s.leash)
                }
            }
            if let pending = model.state?.pending {
                ForEach(pending) { ApprovalCard(pending: $0) }
            }
            SwapCard()
            if !model.watching.isEmpty { watching }
            FollowingSection()
            recent
        }
    }

    private var balances: some View {
        HStack(spacing: 10) {
            Stat(label: "NEAR", value: model.state.map { Fmt.near($0.available, unit: false) }, sub: "Available to agents")
            ForEach(model.state?.holdings ?? []) { h in
                Stat(label: h.symbol, value: Self.dollars(h), sub: "From your swaps")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// A dollar stablecoin as dollars: "$3.41".
    static func dollars(_ h: LeashState.Holding) -> String {
        guard ["USDC", "USDT"].contains(h.symbol.uppercased()), let v = Double(h.amount) else { return h.amount }
        return String(format: "$%.2f", v)
    }

    @ViewBuilder private var status: some View {
        if let s = model.state {
            HStack(spacing: 8) {
                Circle().fill(model.mood).frame(width: 8, height: 8)
                Text(s.paused ? "Everything is stopped. No agent can pay."
                    : (["\(s.shownAgents.count) agents ready", "\(model.paidToday) paid today"]
                        + (model.blockedToday > 0 ? ["\(model.blockedToday) blocked"] : [])).joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(s.paused ? AK.redText : AK.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
            .accessibilityElement(children: .combine)
        } else {
            Text(model.loading ? "Connecting…" : " ").font(.subheadline).foregroundStyle(AK.muted).padding(.horizontal, 4)
        }
    }

    /// Trades the Trading Agent will make when a price is reached.
    private var watching: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Watching", trailing: "\(model.watching.count)")
            VStack(spacing: 0) {
                ForEach(Array(model.watching.enumerated()), id: \.element.id) { i, o in
                    if i > 0 { Hairline().padding(.leading, 60) }
                    HStack(spacing: 12) {
                        SignalBadge(signal: .watch, size: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Fmt.sentence(o.command)).font(.subheadline.weight(.semibold)).foregroundStyle(AK.bone).lineLimit(1)
                            Text(o.condition.prefix(1).uppercased() + o.condition.dropFirst()).font(.footnote).foregroundStyle(AK.muted).lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        Button("Cancel") { Task { await model.cancel(o) } }
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(AK.redText)
                            .accessibilityLabel("Cancel \(o.command)")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .background(AK.surface, in: RoundedRectangle(cornerRadius: AK.radius, style: .continuous))
        }
    }

    @ViewBuilder private var recent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.receipts.isEmpty {
                SectionTitle("Recent")
                Card {
                    Text(model.loading ? "Loading…" : "Nothing yet").font(.headline).foregroundStyle(AK.bone)
                    Text("Use the AIRKEY keyboard in any chat, or tap the bar below to pay, swap, or check a message.")
                        .font(.subheadline).foregroundStyle(AK.muted).fixedSize(horizontal: false, vertical: true)
                }
            } else {
                SectionTitle("Recent", trailing: "See all") { go(.activity) }
                ReceiptGroup(receipts: Array(model.receipts.prefix(4)), open: open)
            }
        }
    }
}
