import SwiftUI

struct AgentsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Screen(tint: model.mood) {
            Text("Each agent is its own NEAR account. Its key can only ask the leash.")
                .font(.subheadline).foregroundStyle(AK.muted).fixedSize(horizontal: false, vertical: true)
            if let state = model.state {
                ForEach(state.agents) { a in
                    AgentCard(entry: a, paused: state.paused, explorer: state.explorer)
                }
            } else if model.loading {
                ProgressView().tint(AK.muted).frame(maxWidth: .infinity).padding(.top, 40)
            }
        }
        .navigationTitle("Agents")
    }
}

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
                    Text(Fmt.agentName(account: entry.account)).font(.title3.weight(.semibold)).foregroundStyle(AK.bone)
                    if let url = URL(string: "\(explorer)/address/\(entry.account)") {
                        Link(destination: url) {
                            Text(entry.account).font(AK.mono).foregroundStyle(AK.muted).lineLimit(1).truncationMode(.middle)
                        }
                    }
                }
                Spacer(minLength: 8)
                if paused { Pill(text: "Stopped", color: AK.red) } else { Pill(text: trusted ? "Trusted" : "Untrusted", color: tierColor) }
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
            Label("Can't send NEAR on its own. Every payment goes through the leash.", systemImage: "lock.fill")
                .font(.footnote).foregroundStyle(AK.accent).fixedSize(horizontal: false, vertical: true)
        }
    }
}
