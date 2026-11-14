import SwiftUI

/// What Keybots is connected to: Spend Limits, Rhea, NEAR Intents, NEAR AI
/// Cloud, X (via Kall) and Telegram, each checked live by the server when the
/// page opens.
struct ConnectedView: View {
    @Environment(AppModel.self) private var model
    @State private var connected: Connected?
    @State private var error: String?

    var body: some View {
        Screen(tint: model.mood) {
            Masthead(eyebrow: summary, title: "Connected")
            if let connected {
                VStack(spacing: 10) {
                    ForEach(connected.services) { ServiceCard(service: $0) }
                }
                Text("Checked \(Fmt.time(ISO8601DateFormatter().date(from: connected.checkedAt))). Pull to check again.")
                    .font(.footnote).foregroundStyle(AK.muted).padding(.horizontal, 4)
            } else if let error {
                Card { Text(error).font(.subheadline).foregroundStyle(AK.muted) }
            } else {
                ProgressView().tint(AK.muted).frame(maxWidth: .infinity).padding(.top, 40)
            }
        }
        .refreshable { await load() }
        .task { await load() }
    }

    private var summary: String {
        guard let c = connected else { return "Checking…" }
        let live = c.services.filter { $0.status == "live" }.count
        return "\(live) of \(c.services.count) live · NEAR \(c.network)"
    }

    private func load() async {
        do {
            connected = try await model.api.connected()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct ServiceCard: View {
    let service: Connected.Service

    private var color: Color {
        switch service.status {
        case "live": AK.accent
        case "down": AK.red
        default: AK.faint
        }
    }

    private var word: String {
        switch service.status {
        case "live": "Live"
        case "down": "Down"
        default: "Off"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(service.name).font(.headline).foregroundStyle(AK.bone)
                Spacer(minLength: 8)
                HStack(spacing: 6) {
                    Circle().fill(color).frame(width: 8, height: 8)
                    Text(word).font(.subheadline.weight(.semibold)).foregroundStyle(service.status == "down" ? AK.redText : AK.bone)
                }
            }
            Text(service.role).font(.subheadline).foregroundStyle(AK.muted)
                .fixedSize(horizontal: false, vertical: true)
            Text(service.detail).font(.footnote.monospaced()).foregroundStyle(AK.muted)
                .lineLimit(2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AK.surface, in: RoundedRectangle(cornerRadius: AK.radius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
