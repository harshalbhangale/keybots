import SwiftUI

// The app's building blocks, after Kall Markets' look: near-black, graphite
// cards with hairlines, a mono eyebrow over a heavy uppercase title that ends
// in a lime full stop, heavy uppercase buttons, big lime numbers.

extension AK {
    static let graphite = Color(red: 0.102, green: 0.102, blue: 0.102)
    static let hairline = Color(red: 0.165, green: 0.165, blue: 0.165)
}

/// The keycap mark, a mono eyebrow, and a heavy title ending in a lime full stop.
struct Masthead<Trailing: View>: View {
    let eyebrow: String
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                KeycapMark(size: 26)
                Text(eyebrow)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(AK.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                trailing
            }
            (Text(title).foregroundColor(AK.bone) + Text(".").foregroundColor(AK.accent))
                .font(.system(size: 36, weight: .black))
                .tracking(-1)
                .accessibilityAddTraits(.isHeader)
        }
    }
}

extension Masthead where Trailing == EmptyView {
    init(eyebrow: String, title: String) {
        self.init(eyebrow: eyebrow, title: title) { EmptyView() }
    }
}

/// A graphite card with a hairline edge.
struct Card<Content: View>: View {
    var padding: CGFloat = 16
    var spacing: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AK.graphite.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AK.hairline))
    }
}

/// A small heavy lime label at the top of a card: "SWAP NEAR", "SET UP".
struct CardTitle: View {
    let text: String
    var icon: String?
    var color: Color = AK.accent

    var body: some View {
        Group {
            if let icon { Label(text, systemImage: icon) } else { Text(text) }
        }
        .font(.system(size: 12, weight: .heavy))
        .foregroundStyle(color)
    }
}

/// A balance: mono label, big number, an optional line under it.
struct Stat: View {
    let label: String
    let value: String?
    var sub: String?
    var color: Color = AK.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(AK.muted)
            Text(value ?? "…")
                .font(.system(size: 28, weight: .black).monospacedDigit())
                .foregroundStyle(color)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .contentTransition(.numericText())
            if let sub {
                Text(sub).font(.system(size: 11, weight: .semibold).monospacedDigit()).foregroundStyle(AK.muted).lineLimit(1).minimumScaleFactor(0.8)
            }
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AK.graphite, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AK.hairline))
        .accessibilityElement(children: .combine)
    }
}

/// Heavy uppercase buttons: lime for the main thing, graphite for the rest.
struct BigButtonStyle: ButtonStyle {
    var primary = true
    var height: CGFloat = 50

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .heavy))
            .tracking(0.5)
            .foregroundStyle(primary ? AK.ink : AK.bone)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(primary ? AK.accent : AK.graphite, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                if !primary { RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AK.hairline) }
            }
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == BigButtonStyle {
    static var bigPrimary: BigButtonStyle { BigButtonStyle() }
    static var bigSecondary: BigButtonStyle { BigButtonStyle(primary: false) }
}

/// A short uppercase status: PAID, SWAPPED, BLOCKED, WAITING.
struct Badge: View {
    let text: String
    let color: Color
    var filled = false

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .heavy))
            .foregroundStyle(filled ? AK.ink : color)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(filled ? color : AK.graphite, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

extension Receipt {
    /// The badge a receipt gets in lists.
    var badge: (text: String, color: Color, filled: Bool) {
        switch outcome {
        case "paid": ("PAID", AK.accent, true)
        case "swapped": ("SWAPPED", AK.accent, true)
        case "approval": ("WAITING", AK.amber, true)
        case "blocked": ("BLOCKED", AK.red, false)
        case "quoted": ("QUOTE", AK.bone, false)
        case "watching": ("WATCHING", AK.bone, false)
        default: ("NOT SENT", AK.muted, false)
        }
    }
}

/// A numbered step: "01  Open Settings".
struct NumberedStep: View {
    let n: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(String(format: "%02d", n)).font(.system(size: 12, design: .monospaced)).foregroundStyle(AK.accent)
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
            Text(address).font(.system(size: 12, design: .monospaced)).foregroundStyle(AK.bone).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 4)
            Button {
                UIPasteboard.general.string = address
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                copied = true
            } label: {
                Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 12, weight: .bold)).foregroundStyle(AK.bone)
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
        .padding(12)
        .background(AK.graphite, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
