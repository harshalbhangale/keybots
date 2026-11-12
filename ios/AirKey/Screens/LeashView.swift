import SwiftUI

/// The control panel: kill switch, what the leash holds, who's allowed and
/// blocked, and the payments waiting for you. Every change here is signed on
/// this phone after Face ID.
struct LeashView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Screen(title: "Leash", subtitle: "The rules your agents can't change. Enforced by a NEAR contract, not by this app.") {
            if let error = model.error { ErrorBanner(text: error) }
            if let state = model.state {
                killSwitch(state)
                pending(state)
                limits(state)
                lists(state)
                if let tx = model.lastOwnerTx {
                    Link(destination: URL(string: tx.url)!) {
                        Text("Last signed: \(tx.method) · \(String(tx.txHash.prefix(10)))… ↗").font(AK.mono).foregroundStyle(AK.mint)
                    }
                }
                Link(destination: URL(string: "\(state.explorer)/address/\(state.leash)")!) {
                    Text("Contract \(state.leash) ↗").font(AK.mono).foregroundStyle(AK.muted)
                }
            } else if model.loading {
                ProgressView().tint(AK.muted).frame(maxWidth: .infinity).padding(.top, 40)
            }
        }
    }

    private func killSwitch(_ s: LeashState) -> some View {
        let on = s.paused
        return Button {
            Task { await model.owner("set_paused", ["paused": !on], reason: on ? "Turn the kill switch off" : "Stop every agent now") }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(on ? AK.red : AK.raised).frame(width: 46, height: 46)
                    Image(systemName: "power").font(.system(size: 20, weight: .bold)).foregroundStyle(on ? AK.ink : AK.red)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(on ? "Kill switch is ON" : "Kill switch").font(.system(size: 18, weight: .semibold)).foregroundStyle(on ? AK.red : AK.bone)
                    Text(on ? "No agent can pay. Tap to let them work again." : "Tap to stop every agent at once.").font(.system(size: 13)).foregroundStyle(AK.muted)
                }
                Spacer()
                if model.busy == "set_paused" { ProgressView().tint(AK.muted) }
            }
            .padding(16)
            .background((on ? AK.red.opacity(0.1) : AK.surface), in: RoundedRectangle(cornerRadius: AK.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AK.radius, style: .continuous).strokeBorder(on ? AK.red.opacity(0.5) : AK.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(model.busy != nil)
        .accessibilityLabel(on ? "Kill switch on. Turn off." : "Kill switch off. Turn on.")
    }

    @ViewBuilder private func pending(_ s: LeashState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Eyebrow("Waiting for you", color: s.pending.isEmpty ? AK.muted : AK.amber); Spacer(); Text("\(s.pending.count)").font(AK.number(14)).foregroundStyle(AK.muted) }
            if s.pending.isEmpty {
                Text("Nothing waiting.").font(.system(size: 14)).foregroundStyle(AK.faint)
            }
            ForEach(s.pending) { p in
                Panel {
                    HStack(alignment: .firstTextBaseline) {
                        Text(Fmt.near(p.amount)).font(AK.number(22)).foregroundStyle(AK.bone)
                        Spacer()
                        Pill(text: p.rule, color: AK.amber)
                    }
                    KeyValue(key: "To", value: p.receiver, mono: true)
                    KeyValue(key: "Agent", value: Fmt.short(p.agent), mono: true)
                    if let memo = p.memo { KeyValue(key: "For", value: memo) }
                    Text(p.reason).font(.system(size: 13)).foregroundStyle(AK.amber).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 10) {
                        ActionButton(title: "Reject", color: AK.red, outline: true) { Task { await model.owner("reject", ["id": p.id], reason: "Reject \(Fmt.near(p.amount)) to \(p.receiver)") } }
                        ActionButton(title: model.busy == "approve" ? "Signing…" : "Approve", color: AK.mint) { Task { await model.owner("approve", ["id": p.id], reason: "Pay \(Fmt.near(p.amount)) to \(p.receiver)") } }
                    }
                    .disabled(model.busy != nil)
                }
            }
        }
    }

    private func limits(_ s: LeashState) -> some View {
        Panel {
            Eyebrow("Holds")
            Text(Fmt.near(s.available)).font(AK.number(30)).foregroundStyle(AK.bone)
            Text("Agents spend from here, never from your account.").font(.system(size: 13)).foregroundStyle(AK.muted)
            Hairline()
            ForEach(s.agents) { a in
                KeyValue(key: Fmt.agentName(a.agent.tier), value: "\(Fmt.near(a.agent.per_payment_cap, unit: false)) per payment · \(Fmt.near(a.agent.daily_cap)) a day")
            }
        }
    }

    private func lists(_ s: LeashState) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Panel {
                Eyebrow("Allowed", color: AK.mint)
                if s.allowlist.isEmpty { Text("No one yet.").font(.system(size: 14)).foregroundStyle(AK.faint) }
                ForEach(s.allowlist, id: \.self) { a in
                    HStack {
                        Text(a).font(AK.mono).foregroundStyle(AK.bone).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button("Remove") { Task { await model.owner("disallow", ["account": a], reason: "Remove \(a) from your allowlist") } }
                            .font(.system(size: 13, weight: .medium)).foregroundStyle(AK.muted)
                    }
                }
            }
            Panel {
                Eyebrow("Blocked", color: AK.red)
                if s.blocklist.isEmpty { Text("No one.").font(.system(size: 14)).foregroundStyle(AK.faint) }
                ForEach(s.blocklist) { b in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(b.account).font(AK.mono).foregroundStyle(AK.bone).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button("Unblock") { Task { await model.owner("unblock", ["account": b.account], reason: "Unblock \(b.account)") } }
                                .font(.system(size: 13, weight: .medium)).foregroundStyle(AK.muted)
                        }
                        Text(b.reason).font(.system(size: 12)).foregroundStyle(AK.red.opacity(0.85)).lineLimit(3)
                    }
                }
            }
        }
    }
}
