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
            Text(text).font(.headline).foregroundStyle(AK.bone)
            Spacer()
            if let trailing {
                if let action {
                    Button(trailing, action: action).font(.subheadline.weight(.medium)).foregroundStyle(AK.accent)
                } else {
                    Text(trailing).font(.subheadline).foregroundStyle(AK.muted)
                }
            }
        }
        .padding(.horizontal, 4)
    }
}

/// Small status tag: Trusted, Untrusted, R6…
struct Pill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(color.opacity(0.14), in: Capsule())
    }
}

/// The round badge that says what happened: lime check, amber hand, red cross.
struct SignalBadge: View {
    let signal: Signal
    var size: CGFloat = 30

    var body: some View {
        Image(systemName: signal.icon)
            .font(.system(size: size * 0.42, weight: .bold))
            .foregroundStyle(signal == .quote || signal == .neutral ? AK.bone : AK.ink)
            .frame(width: size, height: size)
            .background(signal == .quote || signal == .neutral ? AK.raised : signal.color, in: Circle())
            .accessibilityLabel(signal.title)
    }
}

/// An outcome on glass, tinted with its signal colour. Used where a result
/// arrives: the command sheet and the top of a receipt.
struct OutcomeCard: View {
    let signal: Signal
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            SignalBadge(signal: signal, size: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text(signal.title).font(.headline).foregroundStyle(signal == .neutral ? AK.bone : signal.color)
                Text(message).font(.subheadline).foregroundStyle(AK.bone).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .glassEffect(.regular.tint(signal.color.opacity(0.16)), in: .rect(cornerRadius: AK.radius))
    }
}

struct KeyValue: View {
    let key: String
    let value: String
    var mono = false
    var color: Color = AK.bone

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(key).font(.subheadline).foregroundStyle(AK.muted)
            Spacer(minLength: 16)
            Text(value)
                .font(mono ? AK.mono : .subheadline.weight(.medium))
                .foregroundStyle(color)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .truncationMode(.middle)
        }
    }
}

struct Hairline: View {
    var body: some View { Rectangle().fill(AK.line).frame(height: 1) }
}

/// Spend so far today against the daily cap.
struct SpendBar: View {
    let share: Double
    var color: Color = AK.accent

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(AK.raised)
                Capsule().fill(share > 0.85 ? AK.amber : color).frame(width: share > 0 ? max(6, g.size.width * share) : 0)
            }
        }
        .frame(height: 6)
        .accessibilityLabel("\(Int(share * 100)) percent of today's cap used")
    }
}

struct ErrorBanner: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "wifi.exclamationmark").foregroundStyle(AK.amber)
            Text(text).font(.subheadline).foregroundStyle(AK.bone).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(AK.amber.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                Text(Fmt.near(pending.amount)).font(AK.number(30)).foregroundStyle(AK.bone)
                Spacer()
                Pill(text: "Waiting for you", color: AK.amber)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("to \(pending.receiver)").font(AK.mono).foregroundStyle(AK.bone).lineLimit(1).truncationMode(.middle)
                if let memo = pending.memo, !memo.isEmpty {
                    Text("for \(memo)").font(.subheadline).foregroundStyle(AK.muted)
                }
            }
            Text("\(Fmt.agentName(account: pending.agent)) asked because: \(pending.reason)")
                .font(.footnote)
                .foregroundStyle(AK.muted)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button(role: .destructive) {
                    Task { await model.owner("reject", ["id": pending.id], reason: "Reject \(Fmt.near(pending.amount)) to \(pending.receiver)") }
                } label: {
                    Text("Reject").frame(maxWidth: .infinity).padding(.vertical, 4)
                }
                .buttonStyle(.glass)

                Button {
                    Task { await model.owner("approve", ["id": pending.id], reason: "Pay \(Fmt.near(pending.amount)) to \(pending.receiver)") }
                } label: {
                    Label(model.busy == "approve" ? "Signing…" : "Approve", systemImage: "faceid")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.glassProminent)
                .tint(AK.accent)
                .foregroundStyle(AK.ink)
            }
            .font(.body.weight(.semibold))
            .disabled(working)
        }
        .padding(18)
        .glassEffect(.regular.tint(AK.amber.opacity(0.12)), in: .rect(cornerRadius: AK.radius))
    }
}

/// One line of activity: what happened, what was said, when.
struct ReceiptRow: View {
    let r: Receipt

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            SignalBadge(signal: r.signal, size: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(r.message).font(.subheadline.weight(.medium)).foregroundStyle(AK.bone).lineLimit(2).multilineTextAlignment(.leading)
                Text(r.input.source == "typed" ? "You typed “\(r.input.text)”" : "Pasted “\(r.input.text)”")
                    .font(.footnote)
                    .foregroundStyle(AK.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(Fmt.time(r.date)).font(.footnote).foregroundStyle(AK.faint)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

/// A list of receipts in one panel, with hairlines between rows.
struct ReceiptGroup: View {
    let receipts: [Receipt]
    let open: (Receipt) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(receipts.enumerated()), id: \.element.id) { i, r in
                if i > 0 { Hairline().padding(.leading, 40) }
                Button { open(r) } label: { ReceiptRow(r: r) }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 2)
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
            VStack(alignment: .leading, spacing: 24) {
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
