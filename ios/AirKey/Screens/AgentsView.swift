import SwiftUI

/// One agent on Spend Limits, as a row: "Trading Agent", "Up to 1 NEAR a
/// trade, 2 a day", what it spent today, and a small bar.
struct AgentCard: View {
    let entry: LeashState.AgentEntry
    let paused: Bool
    let explorer: String

    private var a: LeashState.Agent { entry.agent }
    private var name: String { Fmt.agentName(account: entry.account) }
    private var unit: String { name == Plain.trades ? "a trade" : "a payment" }
    private var limits: String { "Up to \(Fmt.near(a.per_payment_cap)) \(unit)" }
    private var used: String { "\(Fmt.near(a.spent_today, unit: false)) of \(Fmt.near(a.daily_cap))" }
    private var trusted: Bool { a.tier == "trusted" }

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
            SpendBar(share: Fmt.share(a.spent_today, of: a.daily_cap), color: paused ? AK.faint : AK.accent)
            Text(limits)
                .font(.footnote.monospacedDigit()).foregroundStyle(AK.muted)
                .fixedSize(horizontal: false, vertical: true)
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
