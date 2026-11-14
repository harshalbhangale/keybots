import SwiftUI

/// A quiet grouped surface for content. Not glass: glass is for controls.
struct Panel<Content: View>: View {
    var padding: CGFloat = 18
    var spacing: CGFloat = 14
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AK.surface, in: RoundedRectangle(cornerRadius: AK.radius, style: .continuous))
    }
}

/// Section heading above a panel or list.
struct SectionTitle: View {
    let text: String
    var trailing: String?
    var action: (() -> Void)?

    init(_ text: String, trailing: String? = nil, action: (() -> Void)? = nil) {
        self.text = text
        self.trailing = trailing
        self.action = action
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text).font(.title3.bold()).foregroundStyle(AK.bone)
            Spacer()
            if let trailing {
                if let action {
                    Button(trailing, action: action).font(.subheadline.weight(.medium)).foregroundStyle(AK.accentText)
                } else {
                    Text(trailing).font(.subheadline.monospacedDigit()).foregroundStyle(AK.muted)
                }
            }
        }
        .padding(.horizontal, 4)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Small status tag: Your words, Stopped…
struct Pill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.14), in: Capsule())
            .fixedSize()
    }
}

/// The round badge that says what happened: lime check, amber hand, red cross.
struct SignalBadge: View {
    let signal: Signal
    var size: CGFloat = 30

    var body: some View {
        Image(systemName: signal.icon)
            .font(.system(size: size * 0.42, weight: .bold))
            .foregroundStyle(signal.plain ? AK.bone : signal == .block ? Color.white : AK.ink)
            .frame(width: size, height: size)
            .background(signal.plain ? AK.raised : signal.color, in: Circle())
            .accessibilityLabel(signal.title)
    }
}

/// An outcome on glass, tinted with its signal colour. Used where a result
/// arrives: the command sheet and the top of a receipt.
struct OutcomeCard: View {
    let signal: Signal
    var title: String?
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            SignalBadge(signal: signal, size: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text(title ?? signal.title).font(.title3.weight(.semibold)).foregroundStyle(AK.bone).fixedSize(horizontal: false, vertical: true)
                Text(message).font(.subheadline).foregroundStyle(AK.muted).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AK.surface, in: RoundedRectangle(cornerRadius: AK.radius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct KeyValue: View {
    let key: String
    let value: String
    var mono = false
    var color: Color = AK.bone

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(key).font(.subheadline).foregroundStyle(AK.muted).layoutPriority(1)
            Spacer(minLength: 16)
            Text(value)
                .font(mono ? AK.mono : .subheadline.weight(.medium))
                .foregroundStyle(color)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .truncationMode(.middle)
        }
        .accessibilityElement(children: .combine)
    }
}

struct Hairline: View {
    @Environment(\.displayScale) private var scale
    var body: some View { Rectangle().fill(AK.line).frame(height: 1 / max(scale, 1)) }
}

/// Spend so far today against the daily cap.
struct SpendBar: View {
    let share: Double
    var color: Color = AK.accent

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(AK.raised)
                Capsule().fill(share > 0.85 ? AK.amber : color).frame(width: share > 0 ? max(4, g.size.width * share) : 0)
            }
        }
        .frame(height: 4)
        .accessibilityLabel("\(Int(share * 100)) percent of today's limit used")
    }
}

struct ErrorBanner: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "wifi.exclamationmark").foregroundStyle(AK.amberText)
            Text(text).font(.subheadline).foregroundStyle(AK.bone).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(AK.amber.opacity(0.14), in: RoundedRectangle(cornerRadius: AK.radius, style: .continuous))
    }
}

/// A payment an agent wants to make that is waiting for the owner. Approving
/// or rejecting is signed on this phone after Face ID.
struct ApprovalCard: View {
    @Environment(AppModel.self) private var model
    let pending: LeashState.Pending

    private var working: Bool { model.busy == "approve" || model.busy == "reject" }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(Fmt.near(pending.amount)).font(AK.number(30)).foregroundStyle(AK.bone).lineLimit(1).minimumScaleFactor(0.6)
                Spacer()
                Pill(text: "Waiting for you", color: AK.amberText)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("to \(Plain.name(pending.receiver))").font(AK.mono).foregroundStyle(AK.bone).lineLimit(1).truncationMode(.middle)
                if let memo = pending.memo, !memo.isEmpty {
                    Text("for \(memo)").font(.subheadline).foregroundStyle(AK.muted)
                }
            }
            Text(Plain.pending(pending))
                .font(.footnote)
                .foregroundStyle(AK.muted)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button(role: .destructive) {
                    Task { await model.owner("reject", ["id": pending.id], reason: "Reject \(Fmt.near(pending.amount)) to \(Plain.name(pending.receiver))") }
                } label: {
                    Text(model.busy == "reject" ? "…" : "Reject")
                }
                .buttonStyle(BigButtonStyle(primary: false, height: 50))
                .frame(width: 96)
                .disabled(working)

                // Approving pays someone, so it takes a hold, then Face ID.
                HoldToConfirm(
                    label: model.busy == "approve" ? "Signing…" : "Hold to approve",
                    icon: "faceid",
                    height: 50,
                    font: .body.weight(.semibold),
                    disabled: working
                ) {
                    Task { await model.owner("approve", ["id": pending.id], reason: "Pay \(Fmt.near(pending.amount)) to \(Plain.name(pending.receiver))") }
                }
            }
        }
        .padding(16)
        .background(AK.surface, in: RoundedRectangle(cornerRadius: AK.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AK.radius, style: .continuous).stroke(AK.amber.opacity(0.55), lineWidth: 1))
    }
}

/// One line of activity: what happened, what was said and when, and a badge.
struct ReceiptRow: View {
    let r: Receipt

    var body: some View {
        let b = r.badge
        HStack(alignment: .center, spacing: 12) {
            SignalBadge(signal: r.signal, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(Plain.line(r)).font(.subheadline.weight(.semibold)).foregroundStyle(AK.bone).lineLimit(2).multilineTextAlignment(.leading)
                Text([r.input.source == "typed" ? "Typed" : "Copied", Fmt.time(r.date)].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.footnote)
                    .foregroundStyle(AK.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Badge(text: b.text, color: b.color, filled: b.filled)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the receipt")
    }
}

/// A list of receipts in one grouped card, with hairlines between rows.
struct ReceiptGroup: View {
    let receipts: [Receipt]
    let open: (Receipt) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(receipts.enumerated()), id: \.element.id) { i, r in
                if i > 0 { Hairline().padding(.leading, 60) }
                Button { open(r) } label: { ReceiptRow(r: r) }.buttonStyle(.plain)
            }
        }
        .background(AK.surface, in: RoundedRectangle(cornerRadius: AK.radius, style: .continuous))
    }
}

/// The frame every tab shares: ambient backdrop, scrolling content, pull to refresh.
struct Screen<Content: View>: View {
    @Environment(AppModel.self) private var model
    var tint: Color = AK.accent
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if let error = model.error { ErrorBanner(text: error) }
                content
            }
            .padding(.horizontal, AK.gutter)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background { Ambient(tint: tint) }
        .refreshable { await model.refresh() }
    }
}
