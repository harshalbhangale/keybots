import SwiftUI
import UIKit

/// Give Claude Code (or any MCP agent) a way to ask Keybots for money: one line to
/// paste in a terminal. It asks through the copied-messages lane, so a stranger
/// waits for your Face ID and anything over the cap is refused on chain.
struct ConnectAgentCard: View {
    @Environment(AppModel.self) private var model
    @State private var copied = false
    @State private var showKey = false

    private var server: String { Settings.serverURL }
    private var token: String { Settings.token }
    private var testnet: Bool { Settings.network != "mainnet" }

    /// The line to paste: the Keybots MCP server, pointed at this network, with this key.
    private func command(_ key: String) -> String {
        "claude mcp add keybots -s user -e KEYBOTS_SERVER=\(server) -e KEYBOTS_TOKEN=\(key) -- node ~/keybots/tools/keybots-mcp/index.mjs"
    }

    private var masked: String {
        token.count > 8 ? String(token.prefix(4)) + String(repeating: "•", count: 8) + String(token.suffix(4)) : "••••"
    }

    /// The newest thing an agent asked for, if any.
    private var lastAsk: Receipt? { model.receipts.first { $0.input.client == "claude-code" } }

    var body: some View {
        Card(spacing: 14) {
            CardTitle(text: "Connect Claude Code", icon: "terminal")
            Text("Let Claude Code, or any agent that speaks MCP, ask Keybots to pay. It can ask; only you can say yes.")
                .font(.footnote).foregroundStyle(AK.muted)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                Text(command(showKey ? token : masked))
                    .font(.caption.monospaced()).foregroundStyle(AK.bone)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Button(showKey ? "Hide key" : "Show key") { showKey.toggle() }
                    .font(.caption.weight(.semibold)).foregroundStyle(AK.accentText)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AK.ink.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            Button {
                UIPasteboard.general.string = command(token)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                copied = true
                Task { try? await Task.sleep(for: .seconds(2)); copied = false }
            } label: {
                Label(copied ? "Copied" : "Copy command", systemImage: copied ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.bigPrimary)
            .disabled(token.isEmpty)

            VStack(alignment: .leading, spacing: 6) {
                rule("tray.and.arrow.down", "Asks through Messages you copy, with that lane's small limits")
                rule("faceid", "Someone new waits for your Face ID, here or from the keyboard")
                rule("xmark.octagon", "Over the cap is refused on chain, whoever asked")
            }

            if let r = lastAsk {
                HStack(spacing: 8) {
                    Circle().fill(AK.lanePay).frame(width: 8, height: 8)
                    Text("Connected · last asked \(Fmt.when(r.date))").font(.footnote).foregroundStyle(AK.bone)
                }
            }

            Text("\(testnet ? "Testnet" : "Mainnet") server. Paste it in a terminal on your Mac; ~/keybots is where you cloned the repo. This is your Keybots server key: give it only to agents you run yourself.")
                .font(.caption).foregroundStyle(AK.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func rule(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon).font(.caption.weight(.semibold)).foregroundStyle(AK.accentText).frame(width: 18)
            Text(text).font(.footnote).foregroundStyle(AK.bone).fixedSize(horizontal: false, vertical: true)
        }
    }
}
