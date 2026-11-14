import SwiftUI

// The app's building blocks: system-grouped surfaces, SF Pro, sentence case,
// one lime accent. Each card leads with one number or verdict.

extension AK {
    static let graphite = AK.surface
    static let hairline = AK.line
}

/// A screen header like a first-party app: a large bold title, a quiet line
/// under it, and an optional control on the right.
struct Masthead<Trailing: View>: View {
    let eyebrow: String
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.largeTitle.bold())
                    .foregroundStyle(AK.bone)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .accessibilityAddTraits(.isHeader)
                if !eyebrow.isEmpty {
                    Text(eyebrow)
                        .font(.subheadline)
                        .foregroundStyle(AK.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.top, 4)
    }
}

extension Masthead where Trailing == EmptyView {
    init(eyebrow: String, title: String) {
        self.init(eyebrow: eyebrow, title: title) { EmptyView() }
    }
}

/// A grouped card.
struct Card<Content: View>: View {
    var padding: CGFloat = 16
    var spacing: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AK.surface, in: RoundedRectangle(cornerRadius: AK.radius, style: .continuous))
    }
}

/// A card's heading: "Swap NEAR".
struct CardTitle: View {
    let text: String
    var icon: String?
    var color: Color = AK.bone

    var body: some View {
        Group {
            if let icon { Label(text, systemImage: icon) } else { Text(text) }
        }
        .font(.headline)
        .foregroundStyle(color)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A balance: a quiet label, one big number, an optional line under it.
struct Stat: View {
    let label: String
    let value: String?
    var sub: String?
    var color: Color = AK.bone

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.footnote.weight(.medium)).foregroundStyle(AK.muted).lineLimit(1)
            Text(value ?? "–")
                .font(.system(.title, design: .rounded, weight: .semibold).monospacedDigit())
                .foregroundStyle(color)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .contentTransition(.numericText())
            Text(sub ?? " ").font(.footnote).foregroundStyle(AK.muted).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AK.surface, in: RoundedRectangle(cornerRadius: AK.radius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Buttons: lime for the main thing, a quiet fill for the rest.
struct BigButtonStyle: ButtonStyle {
    var primary = true
    var height: CGFloat = 50
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(primary ? AK.ink : (enabled ? AK.bone : AK.muted))
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(primary ? AK.accent : AK.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == BigButtonStyle {
    static var bigPrimary: BigButtonStyle { BigButtonStyle() }
    static var bigSecondary: BigButtonStyle { BigButtonStyle(primary: false) }
}

/// A short status: Paid, Swapped, Blocked, Waiting.
struct Badge: View {
    let text: String
    let color: Color
    var filled = false

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(filled ? AK.ink : color)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(filled ? AnyShapeStyle(AK.accent) : AnyShapeStyle(color.opacity(0.14)), in: Capsule())
            .fixedSize()
    }
}

extension Receipt {
    /// The badge a receipt gets in lists.
    var badge: (text: String, color: Color, filled: Bool) {
        switch outcome {
        case "paid": ("Paid", AK.accent, true)
        case "swapped": ("Swapped", AK.accent, true)
        case "approval": ("Waiting", AK.amberText, false)
        case "blocked": ("Blocked", AK.redText, false)
        case "quoted": ("Quote", AK.muted, false)
        case "watching": ("Watching", AK.muted, false)
        default: ("Not sent", AK.muted, false)
        }
    }
}

/// A numbered step: "01  Open Settings".
struct NumberedStep: View {
    let n: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)").font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(AK.muted).frame(minWidth: 16, alignment: .leading)
            Text(text).font(.subheadline).foregroundStyle(AK.bone).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A mono address with Copy and a link to the explorer.
struct AddressRow: View {
    let address: String
    var url: URL?
    @State private var copied = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: 10) {
            Text(address).font(.footnote.monospaced()).foregroundStyle(AK.bone).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 4)
            Button {
                UIPasteboard.general.string = address
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                copied = true
            } label: {
                Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .font(.subheadline.weight(.medium)).foregroundStyle(AK.accentText)
            }
            .buttonStyle(.plain)
            if let url {
                Button { openURL(url) } label: {
                    Image(systemName: "arrow.up.right.square").font(.system(size: 15, weight: .semibold)).foregroundStyle(AK.muted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("See it on NEAR")
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 48)
        .background(AK.surface, in: RoundedRectangle(cornerRadius: AK.radius, style: .continuous))
    }
}
