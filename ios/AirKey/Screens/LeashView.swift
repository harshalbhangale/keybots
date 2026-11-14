import SwiftUI

/// The control panel: stop everything, what's waiting, the limits, and who is
/// allowed or blocked. Every change here is signed on this phone after Face ID.
struct LeashView: View {
    @Environment(AppModel.self) private var model
    @State private var adding: ListKind?
    @State private var account = ""
    @State private var reason = ""

    enum ListKind: String, Identifiable { case allow, block; var id: String { rawValue } }

    var body: some View {
        Screen(tint: model.mood) {
            Masthead(eyebrow: "AIRKEY · WHAT YOUR AGENTS MAY SPEND", title: "LIMITS")
            Text("Your agents spend from a NEAR smart contract with these limits. They can't change them; only you can, with Face ID.")
                .font(.subheadline).foregroundStyle(AK.muted).fixedSize(horizontal: false, vertical: true)
            if let state = model.state {
                killSwitch(state)
                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle("Agents", trailing: "\(state.shownAgents.count)")
                    ForEach(state.shownAgents) { AgentCard(entry: $0, paused: state.paused, explorer: state.explorer) }
                }
                if !state.pending.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle("Waiting for you", trailing: "\(state.pending.count)")
                        ForEach(state.pending) { ApprovalCard(pending: $0) }
                    }
                }
                limits(state)
                allowed(state)
                blocked(state)
                footer(state)
            } else if model.loading {
                ProgressView().tint(AK.muted).frame(maxWidth: .infinity).padding(.top, 40)
            }
        }
        .toolbarVisibility(.hidden, for: .navigationBar)
        .alert(adding == .allow ? "Allow someone" : "Block someone", isPresented: Binding(get: { adding != nil }, set: { if !$0 { adding = nil } })) {
            TextField("name.near", text: $account).textInputAutocapitalization(.never).autocorrectionDisabled()
            if adding == .block { TextField("Why (optional)", text: $reason) }
            Button("Cancel", role: .cancel) { clear() }
            Button(adding == .allow ? "Allow" : "Block") { submit() }
        } message: {
            Text(adding == .allow
                ? "A payment to this account from a message you copy goes through without asking you, up to your limits."
                : "No agent can pay this account.")
        }
    }

    private func submit() {
        let name = account.trimmingCharacters(in: .whitespaces).lowercased()
        let why = reason.trimmingCharacters(in: .whitespaces)
        let kind = adding
        clear()
        guard !name.isEmpty, let kind else { return }
        Task {
            switch kind {
            case .allow: await model.owner("allow", ["account": name], reason: "Allow \(name)")
            case .block: await model.owner("block", ["account": name, "reason": why.isEmpty ? "You blocked it" : why], reason: "Block \(name)")
            }
        }
    }

    private func clear() { adding = nil; account = ""; reason = "" }

    private func killSwitch(_ s: LeashState) -> some View {
        let on = s.paused
        return Button {
            Task { await model.owner("set_paused", ["paused": !on], reason: on ? "Let your agents work again" : "Stop every agent now") }
        } label: {
            HStack(spacing: 16) {
                Image(systemName: "power")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(on ? AK.ink : AK.red)
                    .frame(width: 52, height: 52)
                    .background(on ? AK.red : AK.red.opacity(0.16), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(on ? "Everything is stopped" : "Stop everything").font(.headline).foregroundStyle(on ? AK.red : AK.bone)
                    Text(on ? "No agent can pay. Tap to let them work again." : "One tap, and no agent can pay.")
                        .font(.subheadline).foregroundStyle(AK.muted).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                if model.busy == "set_paused" { ProgressView().tint(AK.muted) }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(on ? .regular.tint(AK.red.opacity(0.22)).interactive() : .regular.interactive(), in: .rect(cornerRadius: AK.radius))
        }
        .buttonStyle(.plain)
        .disabled(model.busy != nil)
        .accessibilityLabel(on ? "Everything is stopped. Tap to let agents work again." : "Stop everything")
    }

    private func limits(_ s: LeashState) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Balance")
            Panel {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Fmt.near(s.available, unit: false)).font(AK.number(28)).foregroundStyle(AK.bone)
                    Text("NEAR your agents can spend").font(.subheadline).foregroundStyle(AK.muted)
                }
                Text("They spend from this balance, never from your own account.")
                    .font(.footnote).foregroundStyle(AK.muted)
                Hairline()
                ForEach(s.shownAgents) { a in
                    KeyValue(
                        key: Fmt.agentName(account: a.account),
                        value: "\(Fmt.near(a.agent.per_payment_cap, unit: false)) at a time · \(Fmt.near(a.agent.daily_cap, unit: false)) a day"
                    )
                }
            }
        }
    }

    private func allowed(_ s: LeashState) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Allowed", trailing: "Add") { adding = .allow }
            Panel {
                if s.allowlist.isEmpty {
                    Text("No one yet. A payment from a message you copy waits for you.").font(.subheadline).foregroundStyle(AK.muted)
                }
                ForEach(Array(s.allowlist.enumerated()), id: \.element) { i, a in
                    if i > 0 { Hairline() }
                    HStack {
                        Text(a).font(AK.mono).foregroundStyle(AK.bone).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 12)
                        Button("Remove") { Task { await model.owner("disallow", ["account": a], reason: "Remove \(a) from your allowed list") } }
                            .font(.subheadline).foregroundStyle(AK.muted)
                    }
                }
            }
        }
        .disabled(model.busy != nil)
    }

    private func blocked(_ s: LeashState) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Blocked", trailing: "Add") { adding = .block }
            Panel {
                if s.blocklist.isEmpty {
                    Text("No one.").font(.subheadline).foregroundStyle(AK.muted)
                }
                ForEach(Array(s.blocklist.enumerated()), id: \.element.id) { i, b in
                    if i > 0 { Hairline() }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(b.account).font(AK.mono).foregroundStyle(AK.bone).lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 12)
                            Button("Unblock") { Task { await model.owner("unblock", ["account": b.account], reason: "Unblock \(b.account)") } }
                                .font(.subheadline).foregroundStyle(AK.muted)
                        }
                        Text(Plain.blockedReason(b.reason)).font(.footnote).foregroundStyle(AK.red.opacity(0.9)).lineLimit(3)
                    }
                }
            }
        }
        .disabled(model.busy != nil)
    }

    @ViewBuilder private func footer(_ s: LeashState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let tx = model.lastOwnerTx, let url = URL(string: tx.url) {
                Link(destination: url) {
                    Label("Last change you signed: \(Plain.change(tx.method))", systemImage: "checkmark.seal.fill").font(.footnote).foregroundStyle(AK.accent)
                }
            }
            if let url = URL(string: "\(s.explorer)/address/\(s.leash)") {
                Link(destination: url) {
                    Label("See the smart contract on NEAR", systemImage: "arrow.up.right").font(.footnote).foregroundStyle(AK.muted)
                }
            }
        }
        .padding(.horizontal, 4)
    }
}
