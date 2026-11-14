import SwiftUI

/// On the Wallet: the people whose calls trade for you, and what their calls
/// traded. The same list as the keyboard's Calls › Following, read every 15
/// seconds while it's on screen. A tap opens that person's rules.
struct FollowingSection: View {
    @State private var model = FollowsModel()
    @State private var handle = ""
    @State private var opened: Opened?
    @FocusState private var typing: Bool
    @Environment(\.openURL) private var openURL

    struct Opened: Identifiable { let id: String }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Following", trailing: model.follows.map { $0.isEmpty ? nil : "\($0.count)" } ?? nil)
            add
            if let notice = model.notice {
                Text(notice).font(.footnote).foregroundStyle(AK.amber).fixedSize(horizontal: false, vertical: true)
                    .onTapGesture { model.notice = nil }
            }
            if let follows = model.follows {
                ForEach(follows) { f in row(f) }
            } else if let problem = model.problem {
                Text(problem).font(.footnote).foregroundStyle(AK.muted)
            }
            SectionTitle("Traded for you").padding(.top, 8)
            if model.trades.isEmpty {
                Card(padding: 14) {
                    Text("When someone you follow posts a call that fits your rules, the trade shows here with the post and the transaction.")
                        .font(.subheadline).foregroundStyle(AK.muted).fixedSize(horizontal: false, vertical: true)
                }
            } else {
                ForEach(model.trades.prefix(8)) { t in
                    AppTradedRow(trade: t, fresh: model.fresh.contains(t.id)) { openURL($0) }
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .animation(.snappy(duration: 0.25), value: model.trades.map(\.id))
        .animation(.easeOut(duration: 0.6), value: model.fresh)
        .onAppear { model.start() }
        .onDisappear { model.stop() }
        .sensoryFeedback(.success, trigger: model.landed)
        .sheet(item: $opened) { o in
            AppFollowRules(handle: o.id, model: model)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    /// Type a handle, or pick a caller Kall tracks.
    private var add: some View {
        Card(padding: 12, spacing: 10) {
            HStack(spacing: 10) {
                Text("@").font(AK.mono).foregroundStyle(AK.muted)
                TextField("", text: $handle, prompt: Text("handle on X").foregroundStyle(AK.faint))
                    .font(AK.mono).foregroundStyle(AK.bone)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($typing)
                    .onSubmit(follow)
                Button(action: follow) {
                    Group {
                        if model.saving != nil { ProgressView().tint(AK.ink) } else { Text("FOLLOW") }
                    }
                    .font(.system(size: 12, weight: .heavy)).foregroundStyle(AK.ink)
                    .padding(.horizontal, 12).frame(height: 30)
                    .background(AK.accent.opacity(Follow.valid(Follow.clean(handle)) ? 1 : 0.4), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!Follow.valid(Follow.clean(handle)) || model.saving != nil)
            }
            if !model.suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(model.suggestions) { c in
                            Button {
                                Task { await model.add(c.handle) }
                            } label: {
                                VStack(alignment: .leading, spacing: 1) {
                                    HStack(spacing: 5) {
                                        Text("@\(c.handle)").font(.system(size: 13, weight: .semibold)).foregroundStyle(AK.bone)
                                        Text("\(c.record.hits) hits").font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(AK.muted)
                                    }
                                    if let focus = c.focus {
                                        Text(focus).font(.system(size: 11)).foregroundStyle(AK.muted).lineLimit(1)
                                    }
                                }
                                .padding(.horizontal, 10).frame(height: 40)
                                .background(AK.graphite, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(AK.hairline))
                            }
                            .buttonStyle(.plain)
                            .disabled(model.saving != nil)
                            .accessibilityLabel("Follow @\(c.handle), \(c.record.line)")
                        }
                    }
                }
            }
        }
    }

    private func resume(_ f: Follow) -> some View {
        Button { Task { await model.setAuto(f.handle, true) } } label: {
            Text("TURN BACK ON").font(.system(size: 11, weight: .heavy)).foregroundStyle(AK.ink)
                .padding(.horizontal, 10).frame(height: 28)
                .background(AK.accent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(model.saving != nil)
        .accessibilityLabel("Turn @\(f.handle)'s calls back on")
    }

    private func follow() {
        let h = handle
        Task {
            if await model.add(h) {
                handle = ""
                typing = false
            }
        }
    }

    private func row(_ f: Follow) -> some View {
        Card(padding: 12, spacing: 0) {
            HStack(spacing: 12) {
                Button { opened = Opened(id: f.id) } label: {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("@\(f.handle)").font(.system(size: 15, weight: .semibold)).foregroundStyle(AK.bone).lineLimit(1)
                            if f.paused {
                                Text(f.pausedReason ?? "").font(.system(size: 12, weight: .semibold)).foregroundStyle(AK.amber).lineLimit(2)
                            } else {
                                Text(f.recordLine).font(.system(size: 12, design: .monospaced)).foregroundStyle(AK.muted).lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                        }
                        Spacer(minLength: 6)
                        if !f.paused {
                            Text(f.usedLine).font(.system(size: 11, weight: .semibold).monospacedDigit())
                                .foregroundStyle(f.spentTodayUsd >= f.perDayUsd ? AK.amber : AK.muted).lineLimit(1)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the rules for their calls")
                if f.paused {
                    resume(f)
                } else {
                    Toggle("Trade @\(f.handle)'s calls for me", isOn: Binding(
                        get: { f.auto },
                        set: { on in Task { await model.setAuto(f.handle, on) } }
                    ))
                    .labelsHidden()
                    .tint(AK.accent)
                }
            }
        }
    }
}

/// A trade made (or not) for you, in the app's look.
struct AppTradedRow: View {
    let trade: AutoTrade
    let fresh: Bool
    let open: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: trade.icon)
                    .font(.system(size: 12.6, weight: .bold))
                    .foregroundStyle(trade.signal.plain ? AK.muted : AK.ink)
                    .frame(width: 30, height: 30)
                    .background(trade.signal.plain ? AK.raised : trade.signal.color, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(trade.message).font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(trade.traded ? AK.bone : trade.failed ? AK.amber : AK.muted)
                        .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                    Text(byLine).font(.footnote).foregroundStyle(AK.muted).lineLimit(1)
                }
                Spacer(minLength: 6)
                Badge(text: badge.text, color: badge.color, filled: badge.filled)
            }
            if trade.postUrl != nil || trade.txUrl != nil {
                HStack(spacing: 16) {
                    if let s = trade.postUrl, let url = URL(string: s) { link("THE POST", url) }
                    if let s = trade.txUrl, let url = URL(string: s) { link("TRANSACTION", url) }
                    Spacer(minLength: 0)
                }
                .padding(.leading, 42)
            }
        }
        .padding(12)
        .background(fresh ? AK.accent.opacity(0.12) : AK.graphite.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(fresh ? AK.accent.opacity(0.7) : AK.hairline))
    }

    private var badge: (text: String, color: Color, filled: Bool) {
        switch trade.status {
        case "traded": ("TRADED", AK.accent, true)
        case "failed": ("FAILED", AK.amber, false)
        default: ("SKIPPED", AK.muted, false)
        }
    }

    private var byLine: String {
        var parts = ["@\(trade.handle)"]
        let time = trade.ago
        if !time.isEmpty { parts.append(time) }
        if trade.onRequest { parts.append("you asked") }
        return parts.joined(separator: " · ")
    }

    private func link(_ title: String, _ url: URL) -> some View {
        Button { open(url) } label: {
            HStack(spacing: 4) {
                Text(title)
                Image(systemName: "arrow.up.right")
            }
            .font(.system(size: 11, weight: .heavy)).foregroundStyle(AK.accent)
        }
        .buttonStyle(.plain)
    }
}

/// One person's rules: dollars per call and per day, which sides, how sure
/// a call must be, when to stop, a hold that trades their latest call now,
/// and Unfollow. Each change is saved as you make it.
struct AppFollowRules: View {
    let handle: String
    let model: FollowsModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmUnfollow = false
    @State private var result: AutoTrade?
    @State private var resultTick = 0

    var body: some View {
        ScrollView {
            if let f = model.follow(handle) {
                content(f)
            } else {
                Text("You don't follow @\(handle) any more.").font(.subheadline).foregroundStyle(AK.muted).padding(AK.gutter)
            }
        }
        .scrollIndicators(.hidden)
        .background(AK.ink)
        .sensoryFeedback(trigger: resultTick) { _, _ in
            switch result?.status {
            case "traded": .success
            case "failed": .error
            default: .warning
            }
        }
    }

    private func content(_ f: Follow) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                (Text("@\(f.handle)").foregroundColor(AK.bone) + Text(".").foregroundColor(AK.accent))
                    .font(.system(size: 30, weight: .black)).tracking(-0.8).lineLimit(1).minimumScaleFactor(0.6)
                Text(f.recordLine).font(.system(size: 12, design: .monospaced)).foregroundStyle(AK.muted)
                Text("\(f.usedLine) today").font(.system(size: 12, design: .monospaced)).foregroundStyle(AK.muted)
            }
            .padding(.top, 12)

            Card(padding: 14) {
                Toggle(isOn: binding(f, \.auto)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Trade their calls for me").font(.system(size: 15, weight: .semibold)).foregroundStyle(AK.bone)
                        Text("A new call that fits these rules trades by itself.").font(.footnote).foregroundStyle(AK.muted)
                    }
                }
                .tint(AK.accent)
                if f.paused {
                    HStack(spacing: 10) {
                        Text(f.pausedReason ?? "").font(.footnote).foregroundStyle(AK.amber).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        Button { set(f, \.auto, true, force: true) } label: {
                            Text("TURN BACK ON").font(.system(size: 11, weight: .heavy)).foregroundStyle(AK.ink)
                                .padding(.horizontal, 10).frame(height: 28)
                                .background(AK.accent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Card(padding: 14, spacing: 14) {
                choice("PER CALL", [1.0, 2, 5].map { (Dollars.text($0), $0) }, f.perCallUsd) { set(f, \.perCallUsd, $0) }
                choice("PER DAY", [3.0, 5, 10].map { (Dollars.text($0), $0) }, f.perDayUsd) { set(f, \.perDayUsd, $0) }
                choice("CALLS", [("Buy only", "buy"), ("Buy and sell", "both")], f.buyOnly ? "buy" : "both") { set(f, \.sides, $0) }
            }

            Card(padding: 14, spacing: 14) {
                toggle("Only sure calls", "Skip calls the reader isn't sure of.", binding(f, \.highOnly))
                Hairline()
                toggle("Stop after 3 misses in a row", "Auto turns off by itself.", Binding(
                    get: { f.stopAfterMisses > 0 },
                    set: { set(f, \.stopAfterMisses, $0 ? 3 : 0) }
                ))
            }

            VStack(alignment: .leading, spacing: 8) {
                HoldToConfirm(
                    label: model.checking == f.handle ? "READING THEIR LATEST CALL…" : "HOLD TO TRADE THEIR LATEST CALL",
                    height: 50,
                    font: .system(size: 14, weight: .heavy),
                    disabled: model.checking != nil
                ) {
                    Task {
                        result = await model.tradeLatest(f.handle)
                        resultTick += 1
                    }
                }
                Text("Up to \(Dollars.text(f.perCallUsd)), a real testnet trade, within your limits.")
                    .font(.footnote).foregroundStyle(AK.muted)
            }

            if let result {
                AppTradedRow(trade: result, fresh: false) { _ in }
            } else if resultTick > 0, let notice = model.notice {
                Text(notice).font(.footnote).foregroundStyle(AK.amber)
            }

            Button(role: .destructive) { confirmUnfollow = true } label: {
                Text("UNFOLLOW").foregroundStyle(AK.red)
            }
            .buttonStyle(.bigSecondary)
            .confirmationDialog("Unfollow @\(f.handle)?", isPresented: $confirmUnfollow, titleVisibility: .visible) {
                Button("Unfollow", role: .destructive) {
                    Task { if await model.unfollow(f.handle) { dismiss() } }
                }
            } message: {
                Text("Their calls stop trading for you. What already traded stays in your history.")
            }
        }
        .padding(.horizontal, AK.gutter)
        .padding(.bottom, 24)
        .sensoryFeedback(.selection, trigger: f.rules)
    }

    private func binding(_ f: Follow, _ key: WritableKeyPath<FollowRules, Bool>) -> Binding<Bool> {
        Binding(get: { f.rules[keyPath: key] }, set: { set(f, key, $0) })
    }

    private func set<V>(_ f: Follow, _ key: WritableKeyPath<FollowRules, V>, _ value: V, force: Bool = false) {
        var rules = f.rules
        rules[keyPath: key] = value
        guard force || rules != f.rules else { return }
        Task { await model.save(f.handle, rules) }
    }

    private func toggle(_ title: String, _ detail: String, _ on: Binding<Bool>) -> some View {
        Toggle(isOn: on) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(AK.bone)
                Text(detail).font(.footnote).foregroundStyle(AK.muted)
            }
        }
        .tint(AK.accent)
    }

    private func choice<V: Equatable>(_ title: String, _ options: [(String, V)], _ selected: V, pick: @escaping (V) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(AK.muted)
            HStack(spacing: 8) {
                ForEach(options.indices, id: \.self) { i in
                    let (label, value) = options[i]
                    let on = value == selected
                    Button { if !on { pick(value) } } label: {
                        Text(label).font(.system(size: 14, weight: .heavy).monospacedDigit())
                            .foregroundStyle(on ? AK.ink : AK.bone)
                            .frame(maxWidth: .infinity).frame(height: 38)
                            .background(on ? AK.accent : AK.graphite, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay { if !on { RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(AK.hairline) } }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
    }
}
