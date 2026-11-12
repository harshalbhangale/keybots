import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model
    let go: (Tab) -> Void
    let openSettings: () -> Void

    @State private var command = ""
    @State private var pasted = false
    @State private var last: Receipt?
    @State private var running = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Wordmark(size: 17)
                    Spacer()
                    Button(action: openSettings) {
                        Image(systemName: "gearshape").font(.system(size: 18)).foregroundStyle(AK.muted).frame(width: 40, height: 40)
                    }
                    .accessibilityLabel("Settings")
                }
                .padding(.top, 6)

                VStack(alignment: .leading, spacing: 6) {
                    Text("\(Fmt.greeting()), \(Settings.name).").font(AK.title(32)).foregroundStyle(AK.bone)
                    if model.state?.paused == true {
                        Text("Kill switch is on. No agent can pay.").font(AK.body).foregroundStyle(AK.red)
                    } else {
                        Text("Your agents are ready.").font(AK.body).foregroundStyle(AK.muted)
                    }
                }

                if let error = model.error { ErrorBanner(text: error) }

                agents
                activity
                tryIt

                HStack(spacing: 10) {
                    ActionButton(title: "Manage agents", color: AK.bone, outline: true) { go(.agents) }
                    ActionButton(title: "View receipts", color: AK.bone, outline: true) { go(.receipts) }
                }
            }
            .padding(.horizontal, AK.gutter)
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .background(AK.ink.ignoresSafeArea())
    }

    private var agents: some View {
        VStack(spacing: 0) {
            if let agents = model.state?.agents, !agents.isEmpty {
                ForEach(Array(agents.enumerated()), id: \.element.id) { i, a in
                    if i > 0 { Hairline() }
                    Button { go(.agents) } label: {
                        HStack(spacing: 12) {
                            KeycapMark(size: 22, tab: a.agent.tier == "trusted" ? AK.mint : AK.amber)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(Fmt.agentName(a.agent.tier)).font(.system(size: 16, weight: .semibold)).foregroundStyle(AK.bone)
                                Text(a.account).font(AK.mono).foregroundStyle(AK.muted).lineLimit(1).truncationMode(.middle)
                            }
                            Spacer()
                            if model.state?.paused == true { Pill(text: "Paused", color: AK.red) } else { Pill(text: "Active", color: AK.mint) }
                        }
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Text(model.loading ? "Loading your agents…" : "No agents yet. Check the server in Settings.")
                    .font(AK.body).foregroundStyle(AK.muted).padding(.vertical, 14)
            }
        }
        .padding(.horizontal, 16)
        .background(AK.surface, in: RoundedRectangle(cornerRadius: AK.radius, style: .continuous))
    }

    private var activity: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow("Today")
            HStack(spacing: 10) {
                stat(model.paidToday, "paid", AK.mint)
                stat("\(model.approvalsToday)", "waiting for you", AK.amber)
                stat("\(model.blockedToday)", "blocked", AK.red)
            }
        }
    }

    private func stat(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value).font(AK.number(20)).foregroundStyle(AK.bone).lineLimit(1).minimumScaleFactor(0.6)
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(label).font(.system(size: 12)).foregroundStyle(AK.muted).lineLimit(1).minimumScaleFactor(0.8)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AK.surface, in: RoundedRectangle(cornerRadius: AK.radius, style: .continuous))
    }

    private func runNow() {
        let text = command.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !running else { return }
        Task {
            running = true
            last = await model.run(text, source: pasted ? "pasted" : "typed")
            running = false
        }
    }

    /// Run a command from the app, the same way the keyboard does.
    private var tryIt: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow("Ask an agent")
            TextField("", text: $command, prompt: Text("Pay harshal.near 0.2 NEAR for dinner").foregroundStyle(AK.faint))
                .font(.system(size: 16))
                .foregroundStyle(AK.bone)
                .submitLabel(.go)
                .onSubmit(runNow)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(14)
                .background(AK.surface, in: RoundedRectangle(cornerRadius: AK.radius, style: .continuous))
            HStack(spacing: 8) {
                Picker("", selection: $pasted) {
                    Text("I typed it").tag(false)
                    Text("Someone sent it").tag(true)
                }
                .pickerStyle(.segmented)
                Button(action: runNow) {
                    Group { if running { ProgressView().tint(AK.ink) } else { Text("Run").font(.system(size: 15, weight: .semibold)) } }
                        .foregroundStyle(AK.ink).frame(width: 64, height: 32).background(AK.mint, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(command.trimmingCharacters(in: .whitespaces).isEmpty || running)
            }
            if let last { OutcomeChip(signal: last.signal, message: last.message) }
        }
    }
}
