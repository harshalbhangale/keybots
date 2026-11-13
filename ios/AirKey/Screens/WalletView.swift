import SwiftUI

/// The first screen: what the leash holds, anything waiting for you, a swap,
/// what's being watched, and what the agents did lately.
struct WalletView: View {
    @Environment(AppModel.self) private var model
    let go: (AppTab) -> Void
    let openSettings: () -> Void
    let open: (Receipt) -> Void

    private var network: String {
        (model.state?.explorer.contains("testnet") ?? true) ? "NEAR TESTNET" : "NEAR"
    }

    var body: some View {
        Screen(tint: model.mood) {
            Masthead(eyebrow: "AIRKEY · \(network)", title: "WALLET") {
                Button(action: openSettings) {
                    Image(systemName: "gearshape").font(.system(size: 16, weight: .semibold)).foregroundStyle(AK.bone)
                        .frame(width: 38, height: 38)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel("Settings")
            }
            balances
            status
            if let s = model.state, let url = URL(string: "\(s.explorer)/address/\(s.leash)") {
                AddressRow(address: s.leash, url: url)
            }
            if let pending = model.state?.pending {
                ForEach(pending) { ApprovalCard(pending: $0) }
            }
            SwapCard()
            if !model.watching.isEmpty { watching }
            recent
        }
        .toolbarVisibility(.hidden, for: .navigationBar)
    }

    private var balances: some View {
        HStack(spacing: 10) {
            Stat(label: "NEAR", value: model.state.map { Fmt.near($0.available, unit: false) }, sub: "spendable")
            ForEach(model.state?.holdings ?? []) { h in
                Stat(label: h.symbol, value: h.amount, color: AK.bone)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var status: some View {
        if let s = model.state {
            HStack(spacing: 8) {
                Circle().fill(model.mood).frame(width: 8, height: 8)
                Text(s.paused ? "Everything is stopped. No agent can pay."
                    : s.pending.isEmpty ? "\(s.shownAgents.count) agents ready · \(model.paidToday) paid today"
                    : "\(s.pending.count) waiting for you")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(s.paused ? AK.red : AK.bone)
                Spacer(minLength: 0)
                if model.blockedToday > 0 {
                    Badge(text: "\(model.blockedToday) BLOCKED", color: AK.red)
                }
            }
        } else if model.loading {
            Text("Connecting…").font(.subheadline).foregroundStyle(AK.muted)
        }
    }

    /// Trades the Trading Agent will make when a price is reached.
    private var watching: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHead("WATCHING", trailing: "\(model.watching.count)")
            ForEach(model.watching) { o in
                Card(padding: 12, spacing: 0) {
                    HStack(spacing: 12) {
                        SignalBadge(signal: .watch, size: 30)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(o.command.prefix(1).uppercased() + o.command.dropFirst()).font(.system(size: 15, weight: .semibold)).foregroundStyle(AK.bone).lineLimit(1)
                            Text(o.condition).font(.footnote).foregroundStyle(AK.muted).lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        Button { Task { await model.cancel(o) } } label: {
                            Text("CANCEL").font(.system(size: 10, weight: .heavy)).foregroundStyle(AK.red)
                                .padding(.horizontal, 8).frame(height: 22)
                                .overlay(RoundedRectangle(cornerRadius: 5).stroke(AK.red.opacity(0.5)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder private var recent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.receipts.isEmpty {
                sectionHead("RECENT")
                Card {
                    Text(model.loading ? "Loading…" : "Nothing yet").font(.subheadline.weight(.semibold)).foregroundStyle(AK.bone)
                    Text("Use the AIRKEY keyboard in any chat, or tap the bar below to pay, swap, or check a message.")
                        .font(.subheadline).foregroundStyle(AK.muted).fixedSize(horizontal: false, vertical: true)
                }
            } else {
                sectionHead("RECENT", trailing: "SEE ALL") { go(.activity) }
                ReceiptGroup(receipts: Array(model.receipts.prefix(4)), open: open)
            }
        }
    }

    private func sectionHead(_ title: String, trailing: String? = nil, action: (() -> Void)? = nil) -> some View {
        HStack {
            Text(title).font(.system(size: 12, weight: .heavy)).foregroundStyle(AK.muted)
            Spacer()
            if let trailing {
                if let action {
                    Button(trailing, action: action).font(.system(size: 12, weight: .heavy)).foregroundStyle(AK.accent)
                } else {
                    Text(trailing).font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundStyle(AK.muted)
                }
            }
        }
    }
}
