import SwiftUI
import UIKit

/// Swap NEAR from the leash into a token on Rhea: type an amount (or pick
/// one), see a live quote, hold to swap. It runs the same command the keyboard
/// sends ("swap 0.25 near to usdc"), so the Trading Agent, the leash's caps and
/// the receipt are exactly the same. The token lands back in the leash.
struct SwapCard: View {
    @Environment(AppModel.self) private var model
    enum Step { case idle, quoting, review(SwapQuote), swapping, done(String), failed(String) }

    @State private var to = "USDC"
    @State private var amount = ""
    @State private var step = Step.idle
    @FocusState private var typing: Bool

    private let tokens = ["USDC", "USDT"]
    private let presets = ["0.1", "0.25", "0.5"]

    /// The Trading Agent's limits, as the leash has them on chain.
    private var trader: LeashState.AgentEntry? {
        model.state?.shownAgents.first { Fmt.agentName(account: $0.account) == Plain.trades }
    }

    /// The most one swap may be now: the per-trade cap, what's left today, what the leash holds.
    private var most: Double? {
        guard let s = model.state, let t = trader else { return nil }
        let left = near(t.agent.daily_cap) - near(t.agent.spent_today)
        return max(0, min(near(t.agent.per_payment_cap), left, near(s.available) - 0.05))
    }

    private var blocked: String? {
        guard model.state != nil else { return "Loading your limits…" }
        guard trader != nil else { return "Trades aren't set up yet" }
        if model.state?.paused == true { return "Stop everything is on" }
        guard let n = Double(amount), n > 0 else { return "Enter an amount" }
        if let most, n > most + 1e-9 { return "Up to \(Self.trim(most)) NEAR now" }
        return nil
    }

    private var busy: Bool {
        switch step { case .quoting, .swapping: true; default: false }
    }

    var body: some View {
        Card(spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                CardTitle(text: "Swap NEAR")
                Spacer()
                Text("On Rhea").font(.footnote).foregroundStyle(AK.muted)
            }
            if case .review(let q) = step { review(q) } else { form }
            switch step {
            case .done(let line):
                Label(line, systemImage: "checkmark.circle.fill").font(.footnote.weight(.semibold)).foregroundStyle(AK.accentText)
                    .fixedSize(horizontal: false, vertical: true)
            case .failed(let message):
                Text(message).font(.footnote).foregroundStyle(AK.redText).fixedSize(horizontal: false, vertical: true)
            default:
                EmptyView()
            }
        }
        .animation(.snappy(duration: 0.25), value: stepKey)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                TextField("0", text: $amount)
                    .keyboardType(.decimalPad)
                    .focused($typing)
                    .font(.system(.title, design: .rounded, weight: .semibold).monospacedDigit())
                    .foregroundStyle(AK.bone)
                    .onChange(of: amount) { _, v in
                        let clean = Self.clean(v)
                        if clean != v { amount = clean }
                        // A new amount clears the last result; the swap clearing the field doesn't.
                        guard !clean.isEmpty else { return }
                        if case .done = step { step = .idle }
                        if case .failed = step { step = .idle }
                    }
                Text("NEAR").font(.footnote.weight(.semibold)).foregroundStyle(AK.muted)
                Image(systemName: "arrow.right").font(.footnote.weight(.bold)).foregroundStyle(AK.faint)
                Picker("Into", selection: $to) {
                    ForEach(tokens, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.menu)
                .tint(AK.bone)
                .fixedSize()
            }
            .padding(.leading, 14)
            .padding(.trailing, 6)
            .frame(height: 58)
            .background(AK.raised.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(typing ? AK.accent : .clear, lineWidth: 1.5))
            .onTapGesture { typing = true }

            HStack(spacing: 8) {
                ForEach(presets, id: \.self) { v in preset(v, on: amount == v) { amount = v } }
                preset("Max", on: most.map { amount == Self.trim($0) } ?? false) {
                    if let most, most > 0 { amount = Self.trim(most) }
                }
            }
            if let most {
                Text("Up to \(Self.trim(most)) NEAR now, within your trade limit")
                    .font(.footnote).foregroundStyle(AK.muted)
            }
            Button(action: quote) {
                Text(busy ? "Getting a quote…" : blocked ?? "Review swap")
            }
            .buttonStyle(BigButtonStyle(primary: blocked == nil, height: 48))
            .disabled(blocked != nil || busy)
        }
    }

    private func review(_ q: SwapQuote) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                TokenPair(from: "NEAR", to: q.to, size: 26)
                Text("\(q.amountIn) NEAR → \(q.amountOut) \(q.to)").font(.system(.title2, design: .rounded, weight: .semibold).monospacedDigit()).foregroundStyle(AK.bone)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            line("You pay", "\(q.amountIn) NEAR from your Keybots balance")
            line("You get", "≈ \(q.amountOut) \(q.to)")
            line("At least", "\(q.minAmountOut) \(q.to), or it doesn't fill")
            line("Where", "Rhea pool #\(q.pool) · NEAR testnet")
            line("Lands in", "your Keybots balance")
            HStack(spacing: 8) {
                Button { step = .idle } label: { Text("Back") }
                    .buttonStyle(BigButtonStyle(primary: false, height: 48))
                    .frame(width: 90)
                HoldToConfirm(label: "Hold to swap", holding: "Keep holding", height: 48, font: .body.weight(.semibold), disabled: busy, action: confirm)
            }
            .padding(.top, 4)
        }
    }

    private func line(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.subheadline).foregroundStyle(AK.muted)
            Spacer(minLength: 8)
            Text(value).font(.subheadline.weight(.medium).monospacedDigit()).foregroundStyle(AK.bone).multilineTextAlignment(.trailing)
        }
    }

    private func preset(_ label: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            typing = false
            action()
        } label: {
            Text(label).font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(on ? AK.ink : AK.bone)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(on ? AK.accent : AK.raised.opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func quote() {
        guard blocked == nil, !busy else { return }
        typing = false
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        step = .quoting
        Task {
            do {
                step = .review(try await API().swapQuote(amount: amount, to: to.lowercased()))
            } catch {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                step = .failed(error.localizedDescription)
            }
        }
    }

    private func confirm() {
        guard !busy else { return }
        step = .swapping
        Task {
            let r = await model.run("swap \(amount) near to \(to.lowercased())", source: "typed")
            if let r, r.outcome == "swapped" {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                step = .done(Plain.line(r))
                amount = ""
            } else {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                step = .failed(r.map(Plain.line) ?? model.error ?? "The swap didn't go through.")
            }
        }
    }

    private var stepKey: Int {
        switch step { case .idle: 0; case .quoting: 1; case .review: 2; case .swapping: 3; case .done: 4; case .failed: 5 }
    }

    private func near(_ yocto: String) -> Double { (Double(yocto) ?? 0) / 1e24 }

    /// Digits and one dot, four decimals at most.
    static func clean(_ v: String) -> String {
        var out = ""
        var dot = false
        var decimals = 0
        for ch in v.replacingOccurrences(of: ",", with: ".") {
            if ch == "." {
                if dot { continue }
                dot = true
                out.append(out.isEmpty ? "0." : ".")
            } else if ch.isNumber {
                if dot { if decimals >= 4 { continue }; decimals += 1 }
                if out.count >= 8 { continue }
                out.append(ch)
            }
        }
        return out
    }

    /// 0.9566 -> "0.95": rounded down to two decimals so MAX never asks for too much.
    static func trim(_ v: Double) -> String {
        let r = (v * 100).rounded(.down) / 100
        return r == r.rounded() ? String(Int(r)) : String(format: "%.2f", r).replacingOccurrences(of: #"0$"#, with: "", options: .regularExpression)
    }
}
