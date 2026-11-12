import SwiftUI

/// Small expanded caps label, the only "heading" style below the title.
struct Eyebrow: View {
    let text: String
    var color: Color = AK.muted
    init(_ text: String, color: Color = AK.muted) { self.text = text; self.color = color }
    var body: some View {
        Text(text.uppercased()).font(AK.label).tracking(1.2).foregroundStyle(color)
    }
}

/// Status pill: ACTIVE, PAUSED, TRUSTED, PAID, BLOCKED...
struct Pill: View {
    let text: String
    let color: Color
    var filled = false
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .bold).width(.expanded))
            .tracking(0.8)
            .foregroundStyle(filled ? AK.ink : color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(filled ? color : color.opacity(0.12), in: Capsule())
    }
}

/// The outcome chip: the same mint / amber / red the keyboard shows.
struct OutcomeChip: View {
    let signal: Signal
    let message: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle().fill(signal.color).frame(width: 8, height: 8).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
            VStack(alignment: .leading, spacing: 3) {
                Text(signal.word).font(.system(size: 11, weight: .heavy).width(.expanded)).foregroundStyle(signal.color)
                Text(message).font(.system(size: 14)).foregroundStyle(AK.bone).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(signal.color.opacity(0.08), in: RoundedRectangle(cornerRadius: AK.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AK.radius, style: .continuous).strokeBorder(signal.color.opacity(0.35), lineWidth: 1))
    }
}

/// A plain grouped block: no shadow, a hairline at most.
struct Panel<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AK.surface, in: RoundedRectangle(cornerRadius: AK.radius, style: .continuous))
    }
}

struct KeyValue: View {
    let key: String
    let value: String
    var mono = false
    var color: Color = AK.bone
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(key).font(.system(size: 14)).foregroundStyle(AK.muted)
            Spacer(minLength: 12)
            Text(value).font(mono ? AK.mono : .system(size: 14, weight: .medium)).foregroundStyle(color).multilineTextAlignment(.trailing).lineLimit(2).truncationMode(.middle)
        }
    }
}

struct Hairline: View {
    var body: some View { Rectangle().fill(AK.line).frame(height: 1) }
}

/// Spend so far today against the daily cap.
struct SpendBar: View {
    let share: Double
    var color: Color = AK.mint
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(AK.raised)
                Capsule().fill(share > 0.85 ? AK.amber : color).frame(width: max(4, g.size.width * share))
            }
        }
        .frame(height: 6)
    }
}

struct ActionButton: View {
    let title: String
    var color: Color = AK.mint
    var outline = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(outline ? color : AK.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(outline ? Color.clear : color, in: Capsule())
                .overlay(Capsule().strokeBorder(outline ? color.opacity(0.6) : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct ErrorBanner: View {
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(AK.amber)
            Text(text).font(.system(size: 14)).foregroundStyle(AK.bone)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(AK.amber.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// The screen frame every tab shares: ink background, big title, scroll.
struct Screen<Content: View>: View {
    let title: String
    var subtitle: String?
    var trailing: AnyView?
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title).font(AK.title()).foregroundStyle(AK.bone)
                        if let subtitle { Text(subtitle).font(AK.body).foregroundStyle(AK.muted) }
                    }
                    Spacer()
                    trailing
                }
                .padding(.top, 8)
                content
            }
            .padding(.horizontal, AK.gutter)
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .background(AK.ink.ignoresSafeArea())
    }
}
