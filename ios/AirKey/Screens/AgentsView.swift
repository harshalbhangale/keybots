import SwiftUI

/// One agent on Spend Limits: its name and NEAR account, what it acts on,
/// what it spent today against its daily limit, and the last thing it did.
struct AgentCard: View {
    let entry: LeashState.AgentEntry
    let paused: Bool
    let explorer: String
    /// Its newest receipt, if it has done anything.
    var last: Receipt? = nil
    @State private var editing = false

    private var a: LeashState.Agent { entry.agent }
    private var name: String { Fmt.agentName(account: entry.account) }
    private var unit: String { name == Plain.trades ? "a trade" : "a payment" }
    private var limits: String { "Up to \(Fmt.near(a.per_payment_cap)) \(unit)" }
    private var used: String { "\(Fmt.near(a.spent_today, unit: false)) of \(Fmt.near(a.daily_cap))" }
    private var trusted: Bool { a.tier == "trusted" }
    /// What its key may call on Spend Limits: the Trading Agent also swaps.
    private var mayCall: String { name == Plain.trades ? "pay and swap" : "pay" }

    static func mark(_ outcome: String) -> String {
        switch outcome {
        case "paid", "swapped": "checkmark.circle.fill"
        case "blocked": "xmark.octagon.fill"
        case "approval": "hand.raised.fill"
        default: "circle.fill"
        }
    }

    static func tint(_ outcome: String) -> Color {
        switch outcome {
        case "paid", "swapped": AK.accentText
        case "blocked": AK.redText
        case "approval": AK.amber
        default: AK.faint
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(name).font(.body.weight(.semibold)).foregroundStyle(AK.bone).lineLimit(1).minimumScaleFactor(0.85)
                if paused {
                    Pill(text: "Stopped", color: AK.redText)
                }
                Spacer(minLength: 8)
                Text(used)
                    .font(.subheadline.weight(.medium).monospacedDigit())
                    .foregroundStyle(AK.bone)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
            Text(Fmt.agentPurpose(account: entry.account, tier: a.tier))
                .font(.subheadline).foregroundStyle(AK.muted)
                .fixedSize(horizontal: false, vertical: true)
            SpendBar(share: Fmt.share(a.spent_today, of: a.daily_cap), color: paused ? AK.faint : AK.accent)
            HStack(spacing: 6) {
                Text(limits)
                Spacer(minLength: 8)
                Text(entry.account).monospaced().lineLimit(1).truncationMode(.middle)
            }
            .font(.footnote.monospacedDigit()).foregroundStyle(AK.muted)
            Label("Its key can only call \(mayCall) on Spend Limits. It holds no money, only gas for its calls.", systemImage: "key")
                .font(.caption).foregroundStyle(AK.faint)
                .fixedSize(horizontal: false, vertical: true)
            if let last {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: Self.mark(last.outcome)).font(.caption.weight(.semibold))
                        .foregroundStyle(Self.tint(last.outcome))
                    Text(Plain.line(last)).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(Fmt.time(last.date)).foregroundStyle(AK.faint)
                }
                .font(.footnote).foregroundStyle(AK.bone)
                .padding(.top, 2)
            }
        }
        .padding(16)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button("Change limits") { editing = true }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AK.accentText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).padding(.bottom, 14)
                .accessibilityHint("Opens a sheet to set its limits, signed after Face ID")
        }
        .sheet(isPresented: $editing) {
            LimitsSheet(entry: entry, name: name).presentationDetents([.medium])
        }
        .contentShape(Rectangle())
        .contextMenu {
            if let url = URL(string: "\(explorer)/address/\(entry.account)") {
                Link(destination: url) { Label("See \(entry.account) on NEAR", systemImage: "arrow.up.right") }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name). \(Fmt.near(a.spent_today)) of \(Fmt.near(a.daily_cap)) spent today. \(limits).\(trusted ? "" : " Asks you first for anyone not on your allowed list.")\(paused ? " Stopped." : "")")
    }
}

/// Set one agent's per-payment and daily limits. The phone signs the change
/// after Face ID; Spend Limits keeps the agent's tier and today's spend.
struct LimitsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let entry: LeashState.AgentEntry
    let name: String
    @State private var per = ""
    @State private var daily = ""

    private var perY: String? { Fmt.yocto(near: per) }
    private var dailyY: String? { Fmt.yocto(near: daily) }
    /// The same sense checks the server makes, said before you sign.
    private var problem: String? {
        guard let p = perY, let d = dailyY else { return "Type amounts in NEAR, like 0.5" }
        guard let pv = Decimal(string: p), let dv = Decimal(string: d) else { return "Type amounts in NEAR, like 0.5" }
        if pv <= 0 { return "The per-payment limit must be more than zero" }
        if pv > dv { return "The per-payment limit can't be more than the daily limit" }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Each payment, up to") {
                        TextField("0.5", text: $per).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Each day, up to") {
                        TextField("1", text: $daily).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                } footer: {
                    Text(problem ?? "In NEAR. Signed on this phone after Face ID, then checked again by Spend Limits.")
                        .foregroundStyle(problem == nil ? AK.muted : AK.amberText)
                }
            }
            .navigationTitle(name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let p = perY, let d = dailyY else { return }
                        Task {
                            await model.owner("add_agent",
                                              ["agent": entry.account, "tier": entry.agent.tier, "per_payment_cap": p, "daily_cap": d],
                                              reason: "Change \(name)'s limits")
                            if model.error == nil { dismiss() }
                        }
                    }
                    .disabled(problem != nil || model.busy != nil)
                }
            }
            .onAppear {
                per = Fmt.near(entry.agent.per_payment_cap, unit: false)
                daily = Fmt.near(entry.agent.daily_cap, unit: false)
            }
        }
    }
}
