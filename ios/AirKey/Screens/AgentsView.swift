import SwiftUI

/// One agent on Spend Limits: its name and NEAR account, what it acts on,
/// what it spent today against its daily limit, and the last thing it did.
struct AgentCard: View {
    let entry: LeashState.AgentEntry
    let paused: Bool
    let explorer: String
    /// Its newest receipt, if it has done anything.
    var last: Receipt? = nil

    private var a: LeashState.Agent { entry.agent }
    private var name: String { Fmt.agentName(account: entry.account) }
    private var unit: String { name == Plain.trades ? "a trade" : "a payment" }
    private var limits: String { "Up to \(Fmt.near(a.per_payment_cap)) \(unit)" }
    private var used: String { "\(Fmt.near(a.spent_today, unit: false)) of \(Fmt.near(a.daily_cap))" }
    private var trusted: Bool { a.tier == "trusted" }

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
