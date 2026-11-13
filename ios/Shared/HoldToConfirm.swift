import SwiftUI
import UIKit

/// How a hold feels: a soft touch as it starts, ticks that rise while the
/// band fills, and a thud when it fires. What happened next (success, a
/// warning, an error) is played by whoever gets the answer. The generators
/// are made once and kept prepared. The keyboard turns `enabled` off when it
/// has no Full Access or the person switched haptics off.
@MainActor
enum HoldFeel {
    static var enabled = true
    static let ticks = 6

    private static let soft = UIImpactFeedbackGenerator(style: .soft)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let heavy = UIImpactFeedbackGenerator(style: .heavy)

    static func begin() {
        guard enabled else { return }
        soft.impactOccurred(intensity: 0.5)
        rigid.prepare()
        heavy.prepare()
    }

    /// `progress` runs 0...1 through the hold.
    static func tick(_ progress: Double) {
        guard enabled else { return }
        rigid.impactOccurred(intensity: 0.25 + 0.65 * progress)
        rigid.prepare()
    }

    static func commit() {
        guard enabled else { return }
        heavy.impactOccurred(intensity: 1)
    }
}

/// The one control for anything that moves your money on your say-so.
/// Press and hold: a darker band sweeps across the button with haptic ticks
/// that grow stronger, and it fires when the band reaches the end. Letting go
/// early cancels, so a stray tap in a chat never pays anyone.
/// VoiceOver users get a plain Activate action instead of the hold.
struct HoldToConfirm: View {
    let label: String
    /// Shown while held; nil keeps the label, for tight spots like the keyboard.
    var holding: String? = "Keep holding"
    var icon: String? = "hand.tap.fill"
    var duration: Double = 0.75
    var height: CGFloat = 52
    var font: Font = .body.weight(.semibold)
    var fill: Color = AK.accent
    var disabled = false
    let action: () -> Void

    @State private var progress: CGFloat = 0
    @State private var pressing = false
    @State private var fired = false
    @State private var ticks: Task<Void, Never>?

    var body: some View {
        ZStack {
            Capsule().fill(fill)
            GeometryReader { g in
                Capsule()
                    .fill(AK.ink.opacity(0.22))
                    .frame(width: g.size.width * progress)
            }
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: fired ? "checkmark" : icon)
                        .font(.system(size: height * 0.3, weight: .bold))
                        .contentTransition(.symbolEffect(.replace))
                }
                Text(pressing && !fired ? (holding ?? label) : label)
                    .lineLimit(1)
                    .contentTransition(.opacity)
            }
            .font(font)
            .foregroundStyle(AK.ink)
            .padding(.horizontal, height * 0.4)
        }
        .frame(height: height)
        .clipShape(Capsule())
        .opacity(disabled ? 0.4 : 1)
        .scaleEffect(pressing && !fired ? 0.96 : 1)
        .animation(.snappy(duration: 0.2), value: pressing)
        .contentShape(Capsule())
        .onLongPressGesture(minimumDuration: duration, maximumDistance: 40, perform: complete, onPressingChanged: pressed)
        .allowsHitTesting(!disabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Press and hold to confirm.")
        .accessibilityAction { if !disabled { complete() } }
        .onDisappear { ticks?.cancel() }
    }

    private func pressed(_ down: Bool) {
        if down {
            guard !fired else { return }
            pressing = true
            HoldFeel.begin()
            withAnimation(.linear(duration: duration)) { progress = 1 }
            ticks?.cancel()
            ticks = Task { @MainActor in
                let steps = HoldFeel.ticks
                for i in 1..<steps {
                    try? await Task.sleep(for: .seconds(duration / Double(steps)))
                    guard !Task.isCancelled, pressing, !fired else { return }
                    HoldFeel.tick(Double(i) / Double(steps))
                }
            }
        } else {
            // iOS can report the finger lifting just before the hold counts,
            // so give `complete` a moment to land before calling it a cancel.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(30))
                if !fired { cancel() }
            }
        }
    }

    private func complete() {
        guard !fired else { return }
        fired = true
        ticks?.cancel()
        progress = 1
        HoldFeel.commit()
        action()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            pressing = false
            withAnimation(.easeOut(duration: 0.25)) { progress = 0 }
            fired = false
        }
    }

    private func cancel() {
        ticks?.cancel()
        pressing = false
        withAnimation(.easeOut(duration: 0.25)) { progress = 0 }
    }
}

#Preview {
    VStack(spacing: 20) {
        HoldToConfirm(label: "Hold to approve") {}
        HoldToConfirm(label: "Hold to pay", holding: nil, icon: nil, height: 30, font: .footnote.weight(.bold)) {}
            .fixedSize()
    }
    .padding()
    .background(AK.ink)
}
