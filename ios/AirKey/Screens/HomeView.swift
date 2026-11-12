import SwiftUI

/// Home answers three things: how much the agents can reach, whether anything
/// needs you, and what they did lately.
struct HomeView: View {
    @Environment(AppModel.self) private var model
    let go: (AppTab) -> Void
    let openSettings: () -> Void
    let open: (Receipt) -> Void

    var body: some View {
        Screen(tint: model.mood) {
            balance
            if let pending = model.state?.pending {
                ForEach(pending) { ApprovalCard(pending: $0) }
            }
            today
            recent
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Wordmark(size: 15).fixedSize().padding(.leading, 4) }
                .sharedBackgroundVisibility(.hidden)
            ToolbarItem(placement: .topBarTrailing) {
                Button("Settings", systemImage: "gearshape", action: openSettings)
            }
        }
    }

    private var balance: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("The leash holds").font(.subheadline).foregroundStyle(AK.muted)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(model.state.map { Fmt.near($0.available, unit: false) } ?? "–")
                    .font(AK.number(60))
                    .foregroundStyle(AK.bone)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("NEAR").font(.title3.weight(.medium)).foregroundStyle(AK.muted)
            }
            status
        }
        .padding(.top, 12)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var status: some View {
        if let s = model.state {
            HStack(spacing: 8) {
                Circle().fill(model.mood).frame(width: 8, height: 8)
                Text(s.paused ? "Everything is stopped. No agent can pay."
                    : s.pending.isEmpty ? "\(s.agents.count) agents ready"
                    : "\(s.pending.count) waiting for you")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(s.paused ? AK.red : AK.bone)
            }
        } else if model.loading {
            Text("Connecting…").font(.subheadline).foregroundStyle(AK.muted)
        }
    }

    private var today: some View {
        HStack(spacing: 0) {
            stat(model.paidToday, "paid today", AK.bone)
            Rectangle().fill(AK.line).frame(width: 1, height: 34)
            stat("\(model.state?.pending.count ?? 0)", "waiting", (model.state?.pending.isEmpty ?? true) ? AK.bone : AK.amber)
            Rectangle().fill(AK.line).frame(width: 1, height: 34)
            stat("\(model.blockedToday)", "blocked today", model.blockedToday > 0 ? AK.red : AK.bone)
        }
        .padding(.vertical, 16)
        .background(AK.surface, in: RoundedRectangle(cornerRadius: AK.radius, style: .continuous))
    }

    private func stat(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value).font(AK.number(20)).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.6).contentTransition(.numericText())
            Text(label).font(.footnote).foregroundStyle(AK.muted).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 6)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var recent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.receipts.isEmpty {
                SectionTitle("Recent")
                Panel {
                    Text(model.loading ? "Loading…" : "Nothing yet")
                        .font(.subheadline.weight(.medium)).foregroundStyle(AK.bone)
                    Text("Tap the bar below and tell an agent what to do, or use the AIRKEY keyboard in any chat.")
                        .font(.subheadline).foregroundStyle(AK.muted).fixedSize(horizontal: false, vertical: true)
                }
            } else {
                SectionTitle("Recent", trailing: "See all") { go(.activity) }
                ReceiptGroup(receipts: Array(model.receipts.prefix(4)), open: open)
            }
        }
    }
}
