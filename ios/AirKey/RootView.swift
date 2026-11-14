import SwiftUI

enum AppTab: Hashable { case wallet, activity, leash, keyboard }

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: AppTab = .wallet
    @State private var showSettings = false
    @State private var showCommand = false
    @State private var receipt: Receipt?
    /// A payment the keyboard asked to approve (keybots://approve?id=…).
    @State private var approving: ApproveLink?

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
            Tab("Spend Limits", systemImage: "gauge.with.dots.needle.33percent", value: AppTab.leash) {
                NavigationStack { LeashView() }
            }
            .badge(model.state?.pending.count ?? 0)
            Tab("Keyboard", systemImage: "keyboard", value: AppTab.keyboard) {
                NavigationStack { KeyboardTab(openSettings: { showSettings = true }) }
            }
        }
        .tint(AK.accentText)
        // The command bar lives on Wallet only; the other tabs stay quiet.
        .commandBar(on: tab == .wallet) { showCommand = true }
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
        .sheet(item: $approving) { link in
            ApproveSheet(id: link.id).presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        }
        .onOpenURL { url in
            guard let link = ApproveLink(url) else { return }
            if let net = link.network, net != Settings.network { Settings.network = net }
            tab = .wallet
            Task { await model.refresh(); approving = link }
        }
    }
}

/// The bar above the tabs on Wallet: the one place you tell an agent what to do.
struct CommandBar: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                KeycapMark(size: 18)
                Text("Pay, swap, or check a message").font(.subheadline).foregroundStyle(AK.muted).lineLimit(1).minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Pay, swap, or check a message")
    }
}

extension View {
    /// The command bar under Wallet only. Before iOS 26.1 it can't be hidden
    /// per tab, so it stays on every tab there.
    @ViewBuilder func commandBar(on: Bool, action: @escaping () -> Void) -> some View {
        if #available(iOS 26.1, *) {
            tabViewBottomAccessory(isEnabled: on) { CommandBar(action: action) }
        } else {
            tabViewBottomAccessory { CommandBar(action: action) }
        }
    }
}

/// keybots://approve?id=12&net=testnet: open one waiting payment, ready for Face ID.
struct ApproveLink: Identifiable {
    let id: Int
    let network: String?

    init?(_ url: URL) {
        guard url.scheme == "keybots", url.host == "approve",
              let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let id = q.first(where: { $0.name == "id" })?.value.flatMap(Int.init) else { return nil }
        self.id = id
        network = q.first { $0.name == "net" }?.value.flatMap { ["testnet", "mainnet"].contains($0) ? $0 : nil }
    }
}

/// The one payment the keyboard sent you here for: who, how much, why it waits, then Hold to approve.
struct ApproveSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let id: Int

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let p = model.state?.pending.first(where: { $0.id == id }) {
                        ApprovalCard(pending: p)
                    } else if model.state == nil {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                    } else {
                        Label("Nothing waiting here any more. It was approved, rejected or ran out.", systemImage: "checkmark.circle")
                            .font(.subheadline).foregroundStyle(AK.muted)
                    }
                }
                .padding(.horizontal, AK.gutter).padding(.top, 8)
            }
            .navigationTitle("Approve").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .onChange(of: model.state?.pending.contains { $0.id == id }) { was, now in
                if was == true, now == false { dismiss() }
            }
        }
    }
}
