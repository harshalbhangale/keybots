import SwiftUI

/// Spend Limits: the NEAR contract that holds the money and decides what each
/// agent may spend. Stop everything, the agents and their limits, what waits
/// for you, and who is allowed or blocked. Every change here is signed on this
/// phone after Face ID.
struct LeashView: View {
    @Environment(AppModel.self) private var model
    @State private var adding: ListKind?
    @State private var account = ""
    @State private var reason = ""

    enum ListKind: String, Identifiable { case allow, block; var id: String { rawValue } }

    var body: some View {
        Screen(tint: model.mood) {
            Masthead(eyebrow: "Decides what each agent may spend.", title: "Spend Limits")
            if let state = model.state {
                stopControl(state)
                if !state.pending.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle("Waiting for you", trailing: "\(state.pending.count)")
                        ForEach(state.pending) { ApprovalCard(pending: $0) }
                    }
                }
                agents(state)
                allowed(state)
                blocked(state)
                footer(state)
            } else if model.loading {
                ProgressView().tint(AK.muted).frame(maxWidth: .infinity).padding(.top, 40)
            }
        }
        .alert(adding == .allow ? "Allow an account" : "Block an account", isPresented: Binding(get: { adding != nil }, set: { if !$0 { adding = nil } })) {
            TextField("name.near", text: $account).textInputAutocapitalization(.never).autocorrectionDisabled()
            if adding == .block { TextField("Why (optional)", text: $reason) }
            Button("Cancel", role: .cancel) { clear() }
            Button(adding == .allow ? "Allow" : "Block") { submit() }
        } message: {
            Text(adding == .allow
                ? "A payment to this account from a message you copy goes through without asking you, up to its agent's limits."
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

    /// One clear control. Its height stays the same on and off, so nothing jumps.
    private func stopControl(_ s: LeashState) -> some View {
        let on = s.paused
        let working = model.busy == "set_paused"
        return Button {
            Task { await model.owner("set_paused", ["paused": !on], reason: on ? "Let your agents spend again" : "Stop every agent now") }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: on ? "play.circle.fill" : "stop.circle")
                    .font(.title.weight(.regular))
                    .foregroundStyle(on ? AK.accentText : AK.redText)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(on ? "Everything is stopped" : "Stop everything")
                        .font(.headline)
                        .foregroundStyle(AK.redText)
                    Text(on ? "Tap to let agents spend again" : "No agent can spend until you start again")
                        .font(.subheadline).foregroundStyle(AK.muted)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                ZStack {
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(AK.faint)
                        .opacity(working ? 0 : 1)
                    if working { ProgressView().tint(AK.muted) }
                }
                .frame(width: 20)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AK.surface, in: RoundedRectangle(cornerRadius: AK.radius, style: .continuous))
            .overlay {
                if on { RoundedRectangle(cornerRadius: AK.radius, style: .continuous).stroke(AK.red.opacity(0.6), lineWidth: 1) }
            }
            .contentShape(RoundedRectangle(cornerRadius: AK.radius, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(model.busy != nil)
        .accessibilityLabel(on ? "Everything is stopped" : "Stop everything")
        .accessibilityHint(on ? "Lets your agents spend again, after Face ID" : "Stops every agent from spending, after Face ID")
    }

    private func agents(_ s: LeashState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Agents")
            VStack(spacing: 0) {
                ForEach(Array(s.shownAgents.enumerated()), id: \.element.id) { i, a in
                    if i > 0 { Hairline().padding(.leading, 16) }
                    AgentCard(entry: a, paused: s.paused, explorer: s.explorer)
                }
            }
            .background(AK.surface, in: RoundedRectangle(cornerRadius: AK.radius, style: .continuous))
            Text("Only you can change these, with Face ID.")
                .font(.footnote).foregroundStyle(AK.muted)
                .padding(.horizontal, 4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func allowed(_ s: LeashState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Allowed", trailing: "Add") { adding = .allow }
            accountList(
                s.allowlist.map { ($0, nil) },
                empty: "No one yet. A payment from a message you copy waits for you.",
                action: "Remove"
            ) { a in
                Task { await model.owner("disallow", ["account": a], reason: "Remove \(a) from your allowed list") }
            }
        }
        .disabled(model.busy != nil)
    }

    private func blocked(_ s: LeashState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Blocked", trailing: "Add") { adding = .block }
            accountList(
                s.blocklist.map { ($0.account, Plain.blockedReason($0.reason)) },
                empty: "No one.",
                action: "Unblock"
            ) { a in
                Task { await model.owner("unblock", ["account": a], reason: "Unblock \(a)") }
            }
        }
        .disabled(model.busy != nil)
    }

    private func accountList(_ rows: [(String, String?)], empty: String, action: String, run: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if rows.isEmpty {
                Text(empty).font(.subheadline).foregroundStyle(AK.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(16)
            }
            ForEach(Array(rows.enumerated()), id: \.element.0) { i, row in
                if i > 0 { Hairline().padding(.leading, 16) }
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.0).font(.subheadline.monospaced()).foregroundStyle(AK.bone).lineLimit(1).minimumScaleFactor(0.7)
                        if let note = row.1 {
                            Text(note).font(.footnote).foregroundStyle(AK.muted).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 8)
                    Button(action) { run(row.0) }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AK.accentText)
                        .accessibilityLabel("\(action) \(row.0)")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .frame(minHeight: 48)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AK.surface, in: RoundedRectangle(cornerRadius: AK.radius, style: .continuous))
    }

    @ViewBuilder private func footer(_ s: LeashState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let tx = model.lastOwnerTx, let url = URL(string: tx.url) {
                Link(destination: url) {
                    Label("Last change you signed: \(Plain.change(tx.method))", systemImage: "checkmark.seal.fill")
                        .font(.footnote).foregroundStyle(AK.accentText)
                }
            }
            if let url = URL(string: "\(s.explorer)/address/\(s.leash)") {
                Text("Spend Limits is a small program on NEAR that holds your money. Agents ask it before they spend, and only you can change it.")
                    .font(.footnote).foregroundStyle(AK.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Link(destination: url) {
                    HStack(spacing: 4) {
                        Text("See it on NEAR")
                        Image(systemName: "arrow.up.right").font(.caption.weight(.semibold))
                    }
                    .font(.footnote.weight(.medium)).foregroundStyle(AK.accentText)
                }
                .accessibilityHint("Opens the NEAR explorer")
            }
        }
        .padding(.horizontal, 4)
    }
}
