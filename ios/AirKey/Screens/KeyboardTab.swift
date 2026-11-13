import SwiftUI
import UIKit

/// How to turn the keyboard on, and what it does once it's on.
struct KeyboardTab: View {
    let openSettings: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        Screen {
            Masthead(eyebrow: "AIRKEY · THE KEYBOARD", title: "KEYBOARD")
            Card(spacing: 14) {
                CardTitle(text: "SET UP", icon: "keyboard")
                NumberedStep(n: 1, text: "Settings › Apps › AIRKEY › Keyboards, and turn on AIRKEY.")
                NumberedStep(n: 2, text: "Turn on Allow Full Access, so your agents can reach the server.")
                NumberedStep(n: 3, text: "In any chat, hold the globe key and pick AIRKEY.")
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: {
                    Text("OPEN SETTINGS  ↗")
                }
                .buttonStyle(.bigPrimary)
            }
            Card(spacing: 14) {
                CardTitle(text: "IN ANY CHAT")
                feature("hand.tap.fill", "Hold to pay or swap", "“pay harshal 0.2”, “swap $5 of near to usdc”")
                feature("text.badge.checkmark", "Typing that knows money", "Never changes names, accounts or amounts")
                feature("wallet.bifold", "Vault", "Your NEAR account in one tap")
                NavigationLink { KeysView() } label: { KeysLink() }.buttonStyle(.plain)
            }
        }
        .toolbarVisibility(.hidden, for: .navigationBar)
    }

    private func feature(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AK.accent)
                .frame(width: 30, height: 30)
                .background(AK.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(AK.bone)
                Text(detail).font(.footnote).foregroundStyle(AK.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
