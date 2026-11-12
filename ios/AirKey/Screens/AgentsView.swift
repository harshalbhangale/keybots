import SwiftUI

struct AgentsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Screen(title: "Agents", subtitle: "Each agent is its own NEAR account. Its only key can ask the leash, nothing else.") {
            if let error = model.error { ErrorBanner(text: error) }
            if let state = model.state {
                ForEach(state.agents) { a in AgentCard(entry: a, paused: state.paused, explorer: state.explorer, leash: state.leash, recent: Array(model.receipts(for: a.account).prefix(3))) }
            } else if model.loading {
                ProgressView().tint(AK.muted).frame(maxWidth: .infinity).padding(.top, 40)
            }
        }
    }
}

struct AgentCard: View {
    let entry: LeashState.AgentEntry
    let paused: Bool
    let explorer: String
    let leash: String
    let recent: [Receipt]

    private var tierColor: Color { entry.agent.tier == "trusted" ? AK.mint : AK.amber }

    var body: some View {
        Panel(padding: 18) {
            HStack(alignment: .top) {
                KeycapMark(size: 30, tab: tierColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text(Fmt.agentName(entry.agent.tier)).font(.system(size: 19, weight: .semibold)).foregroundStyle(AK.bone)
                    Link(destination: URL(string: "\(explorer)/address/\(entry.account)")!) {
                        Text(entry.account).font(AK.mono).foregroundStyle(AK.muted).lineLimit(1).truncationMode(.middle)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Pill(text: paused ? "Paused" : "Active", color: paused ? AK.red : AK.mint)
                    Pill(text: entry.agent.tier, color: tierColor)
                }
            }

            Text(Fmt.agentPurpose(entry.agent.tier)).font(.system(size: 14)).foregroundStyle(AK.muted).fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(Fmt.near(entry.agent.spent_today, unit: false)).font(AK.number(26)).foregroundStyle(AK.bone)
                    Text("of \(Fmt.near(entry.agent.daily_cap)) today").font(.system(size: 14)).foregroundStyle(AK.muted)
                }
                SpendBar(share: Fmt.share(entry.agent.spent_today, of: entry.agent.daily_cap), color: tierColor)
            }

            Hairline()
            KeyValue(key: "Per payment", value: Fmt.near(entry.agent.per_payment_cap))
            KeyValue(key: "Daily cap", value: Fmt.near(entry.agent.daily_cap))
            KeyValue(key: "Its key can call", value: "\(Fmt.short(leash)).pay, report", mono: true)
            KeyValue(key: "Send NEAR directly", value: "No: function-call key only", color: AK.mint)

            if !recent.isEmpty {
                Hairline()
                Eyebrow("Recent")
                ForEach(recent) { r in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle().fill(r.signal.color).frame(width: 6, height: 6)
                        Text(r.message).font(.system(size: 13)).foregroundStyle(AK.bone).lineLimit(2)
                        Spacer(minLength: 0)
                        Text(Fmt.time(r.date)).font(.system(size: 12)).foregroundStyle(AK.faint)
                    }
                }
            }
        }
    }
}
