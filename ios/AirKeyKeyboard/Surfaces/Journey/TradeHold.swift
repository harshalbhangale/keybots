import SwiftUI

/// Hold to confirm a reviewed trade. A darker band fills the button over
/// 1.2 s with HoldFeel's rising ticks; letting go early cancels ("Cancelled"
/// for a moment). It fires once: after that the button stays disabled.
/// VoiceOver gets a "Confirm trade" action, and "Tap to confirm instead"
/// opens a two-tap confirm for anyone who can't hold.
struct TradeHold: View {
    let label: String
    let disabled: Bool
    let palette: MoneyPalette
    let action: () -> Void
    var duration: Double = 1.2

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 0
    @State private var pressing = false
    @State private var fired = false
    @State private var cancelled = false
    @State private var twoTap = false
    @State private var timer: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 4) {
            if twoTap { taps } else { hold }
            Button {
                Haptics.layer()
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) { twoTap.toggle() }
            } label: {
                Text(twoTap ? "Hold to confirm instead" : "Tap to confirm instead")
                    .font(.caption2.weight(.medium)).underline()
                    .foregroundStyle(palette.soft)
                    .frame(height: 16)
            }
            .buttonStyle(.plain)
            .disabled(disabled || fired)
            .opacity(disabled || fired ? 0 : 1)
            .accessibilityHidden(true)
        }
        .onDisappear { timer?.cancel() }
    }

    private var hold: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(AK.accent)
            GeometryReader { g in
                Capsule().fill(AK.ink.opacity(0.24)).frame(width: g.size.width * progress)
            }
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(AK.ink)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .contentTransition(.opacity)
        }
        .frame(height: 44)
        .clipShape(Capsule())
        .opacity(disabled || fired ? 0.45 : 1)
        .scaleEffect(pressing && !reduceMotion ? 0.97 : 1)
        .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: pressing)
        .contentShape(Capsule())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !pressing { begin() } }
                .onEnded { _ in if !fired { cancel() } }
        )
        .allowsHitTesting(!disabled && !fired)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Press and hold to confirm. Or use the Confirm trade action.")
        .accessibilityAction(named: "Confirm trade") { fire() }
        .accessibilityAction { fire() }
    }

    private var title: String {
        if fired { return "Confirmed" }
        if cancelled { return "Cancelled" }
        return pressing ? "Keep holding…" : label
    }

    /// The accessible alternative: tap "Confirm trade", then tap it again.
    @ViewBuilder private var taps: some View {
        TwoTapConfirm(disabled: disabled || fired, palette: palette) { fire() }
    }

    private func begin() {
        guard !fired, !disabled else { return }
        pressing = true
        cancelled = false
        HoldFeel.begin()
        // The band is progress, not decoration: it fills with Reduce Motion
        // too, only without the press-in scale.
        withAnimation(.linear(duration: duration)) { progress = 1 }
        timer?.cancel()
        timer = Task { @MainActor in
            let steps = HoldFeel.ticks
            for i in 1...steps {
                try? await Task.sleep(for: .seconds(duration / Double(steps)))
                guard !Task.isCancelled, pressing, !fired else { return }
                if i < steps { HoldFeel.tick(Double(i) / Double(steps)) } else { fire() }
            }
        }
    }

    private func cancel() {
        timer?.cancel()
        pressing = false
        withAnimation(.easeOut(duration: 0.2)) { progress = 0 }
        guard !fired else { return }
        cancelled = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            if !pressing { cancelled = false }
        }
    }

    private func fire() {
        guard !fired, !disabled else { return }
        fired = true
        timer?.cancel()
        pressing = false
        progress = 1
        HoldFeel.commit()
        action()
    }
}

/// Two taps: the first arms "Confirm trade", the second sends it.
private struct TwoTapConfirm: View {
    let disabled: Bool
    let palette: MoneyPalette
    let action: () -> Void
    @State private var armed = false

    var body: some View {
        Button {
            if armed { action() } else { Haptics.layer(); armed = true }
        } label: {
            Text(armed ? "Tap again to confirm" : "Confirm trade")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(armed ? AK.ink : palette.text)
                .frame(maxWidth: .infinity).frame(height: 44)
                .background(armed ? AK.accent : palette.fill, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(MoneyPress())
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
    }
}
