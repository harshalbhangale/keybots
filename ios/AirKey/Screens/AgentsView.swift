import SwiftUI

/// One agent on the Limits tab: who it is, what it may spend, and what it spent today.
struct AgentCard: View {
    let entry: LeashState.AgentEntry
    let paused: Bool
    let explorer: String

    private var trusted: Bool { entry.agent.tier == "trusted" }
    private var tierColor: Color { trusted ? AK.accent : AK.amber }

    var body: some View {
        Panel(spacing: 16) {
            HStack(spacing: 12) {
                KeycapMark(size: 34, tab: tierColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Fmt.agentName(account: entry.account)).font(.title3.weight(.semibold)).foregroundStyle(AK.bone).lineLimit(1).minimumScaleFactor(0.7)
                    if let url = URL(string: "\(explorer)/address/\(entry.account)") {
                        Link(destination: url) {
                            Text(entry.account).font(AK.mono).foregroundStyle(AK.muted).lineLimit(1).truncationMode(.middle)
                        }
                    }
                }
                Spacer(minLength: 8)
                if paused { Pill(text: "Stopped", color: AK.red) } else { Pill(text: Plain.tier(entry.agent.tier), color: tierColor) }
            }

            Text(Fmt.agentPurpose(account: entry.account, tier: entry.agent.tier))
                .font(.subheadline).foregroundStyle(AK.muted).fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Fmt.near(entry.agent.spent_today, unit: false)).font(AK.number(28)).foregroundStyle(AK.bone)
                    Text("of \(Fmt.near(entry.agent.daily_cap)) spent today").font(.subheadline).foregroundStyle(AK.muted)
                }
                SpendBar(share: Fmt.share(entry.agent.spent_today, of: entry.agent.daily_cap), color: tierColor)
            }

            Hairline()
            KeyValue(key: "Most per payment", value: Fmt.near(entry.agent.per_payment_cap))
            KeyValue(key: "Most per day", value: Fmt.near(entry.agent.daily_cap))
            Label("Can't move money on its own. Every payment is checked against these limits.", systemImage: "lock.fill")
                .font(.footnote).foregroundStyle(AK.accent).fixedSize(horizontal: false, vertical: true)
        }
    }
}
