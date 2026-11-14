import SwiftUI

/// Testnet or Mainnet, side by side, so a demo can say plainly which one it is.
/// Mainnet runs Spend Limits Lite on limits.hellbuddy.near with real NEAR.
struct NetworkSwitch: View {
    @Environment(AppModel.self) private var model
    @State private var network = Settings.network
    private let mainnetReady = Settings.mainnetURL != nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Network", selection: $network) {
                Text("Testnet").tag("testnet")
                Text("Mainnet").tag("mainnet")
            }
            .pickerStyle(.segmented)
            .disabled(!mainnetReady)
            .onChange(of: network) { _, n in
                Settings.network = n
                UISelectionFeedbackGenerator().selectionChanged()
                Task {
                    model.state = nil
                    model.receipts = []
                    await model.refresh()
                }
            }
            HStack(spacing: 6) {
                Circle().fill(network == "mainnet" ? AK.amber : AK.accent).frame(width: 7, height: 7)
                Text(network == "mainnet"
                     ? "Real NEAR. Spend Limits Lite on limits.hellbuddy.near: limits, blocked list, Stop everything. No swaps."
                     : "Test NEAR. The full Spend Limits on testnet: limits, approvals, swaps on Rhea.")
                    .font(.footnote).foregroundStyle(AK.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 4)
        }
        .accessibilityElement(children: .contain)
    }
}
