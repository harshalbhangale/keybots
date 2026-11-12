import SwiftUI

enum Tab: String, CaseIterable {
    case home, agents, leash, receipts

    var title: String { rawValue.capitalized }
    var icon: String {
        switch self {
        case .home: "circle.grid.2x2"
        case .agents: "person.2"
        case .leash: "shield.lefthalf.filled"
        case .receipts: "doc.text"
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var tab: Tab = .home
    @State private var showSettings = false
    @State private var keyboardUp = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch tab {
                case .home: HomeView(go: { tab = $0 }, openSettings: { showSettings = true })
                case .agents: AgentsView()
                case .leash: LeashView()
                case .receipts: ReceiptsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if !keyboardUp { TabBar(tab: $tab).transition(.opacity) }
        }
        .animation(.easeOut(duration: 0.15), value: keyboardUp)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardUp = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardUp = false }
        .background(AK.ink.ignoresSafeArea())
        .task { await model.refresh() }
        .refreshable { await model.refresh() }
        .sheet(isPresented: $showSettings) { SettingsView().presentationDetents([.large]) }
    }
}

/// A floating bar: four words, no labels hidden behind icons.
struct TabBar: View {
    @Binding var tab: Tab
    var body: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases, id: \.self) { t in
                Button { tab = t } label: {
                    VStack(spacing: 4) {
                        Image(systemName: t.icon).font(.system(size: 17, weight: .medium))
                        Text(t.title).font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(tab == t ? AK.ink : AK.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(tab == t ? AK.bone : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(tab == t ? .isSelected : [])
            }
        }
        .padding(5)
        .background(AK.raised.opacity(0.96), in: Capsule())
        .overlay(Capsule().strokeBorder(AK.line, lineWidth: 1))
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
    }
}
