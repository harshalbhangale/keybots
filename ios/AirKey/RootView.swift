import SwiftUI

enum AppTab: Hashable { case wallet, activity, leash, keyboard }

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: AppTab = .wallet
    @State private var showSettings = false
    @State private var showCommand = false
    @State private var receipt: Receipt?

    var body: some View {
        TabView(selection: $tab) {
            Tab("Wallet", systemImage: "wallet.bifold", value: AppTab.wallet) {
                NavigationStack {
                    WalletView(go: { tab = $0 }, openSettings: { showSettings = true }, open: { receipt = $0 })
                }
            }
            Tab("Activity", systemImage: "clock.arrow.circlepath", value: AppTab.activity) {
                NavigationStack { ActivityView(open: { receipt = $0 }) }
            }
            Tab("Leash", systemImage: "lock.shield.fill", value: AppTab.leash) {
                NavigationStack { LeashView() }
            }
            .badge(model.state?.pending.count ?? 0)
            Tab("Keyboard", systemImage: "keyboard", value: AppTab.keyboard) {
                NavigationStack { KeyboardTab(openSettings: { showSettings = true }) }
            }
        }
        .tint(AK.accent)
        .tabViewBottomAccessory { CommandBar { showCommand = true } }
        .tabBarMinimizeBehavior(.onScrollDown)
        .task { await model.refresh() }
        .onChange(of: scenePhase) { _, phase in
            // Coming back from a chat where the keyboard ran something.
            if phase == .active { Task { await model.refresh() } }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showCommand) {
            CommandSheet { r in
                showCommand = false
                Task {
                    try? await Task.sleep(for: .milliseconds(350))
                    receipt = r
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $receipt) { r in
            ReceiptDetail(r: r).presentationDragIndicator(.visible)
        }
    }
}

/// The bar above the tabs, on every screen: the one place you tell an agent what to do.
struct CommandBar: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                KeycapMark(size: 18)
                Text("Pay, swap, or check a message").font(.subheadline).foregroundStyle(AK.muted).lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.circle.fill").font(.title3).foregroundStyle(AK.accent)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Tell an agent what to do")
    }
}
