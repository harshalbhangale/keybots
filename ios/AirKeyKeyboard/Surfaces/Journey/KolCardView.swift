import SwiftUI
import UIKit

/// One caller's post, compact: who, when, a link to it, what it said, their
/// record, and how it was read. Nothing trades when a post appears; the only
/// action is Review trade.
struct KolCardView: View {
    let handle: String?
    let name: String?
    let postedAt: Date?
    let url: String?
    let text: String?
    let asset: String
    let direction: String
    let hits: Int?
    let misses: Int?
    /// The rules' reading; nil shows the plain line.
    let reading: String?
    let sample: Bool
    let palette: MoneyPalette
    let actions: MoneyActions
    /// nil hides the button (the card is the header of a review).
    var review: (() -> Void)?

    @State private var expanded = false

    var body: some View {
        let p = palette
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(handle.map { "@\($0)" } ?? "Copied post").font(.footnote.weight(.bold)).lineLimit(1)
                if let name { Text(name).font(.caption).foregroundStyle(p.soft).lineLimit(1) }
                if let ago = J.ago(postedAt) {
                    Text("· \(ago)").font(.caption).foregroundStyle(p.soft).lineLimit(1).fixedSize()
                }
                Spacer(minLength: 4)
                if sample {
                    Text("Sample post").font(.caption2.weight(.bold)).foregroundStyle(p.warn)
                        .padding(.horizontal, 6).frame(height: 18)
                        .overlay(Capsule().stroke(p.warn.opacity(0.6), lineWidth: 0.75))
                }
                if let url, let link = URL(string: url) {
                    Button {
                        Haptics.letter()
                        actions.open(link) { ok in if !ok { UIPasteboard.general.string = url } }
                    } label: {
                        Text("Post ↗").font(.caption.weight(.semibold)).foregroundStyle(p.text)
                            .padding(.horizontal, 8).frame(height: 22)
                            .background(p.fill, in: Capsule()).contentShape(Capsule())
                    }
                    .buttonStyle(MoneyPress())
                    .accessibilityLabel("Open the post")
                }
            }
            if let text, !text.isEmpty {
                Text(text)
                    .font(.footnote).foregroundStyle(p.text.opacity(0.85))
                    .lineLimit(expanded ? nil : 3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(.snappy(duration: 0.2)) { expanded.toggle() } }
                    .accessibilityHint(expanded ? "Tap to shorten" : "Tap to read it all")
            }
            HStack(spacing: 6) {
                Text("$\(asset)").font(.caption.weight(.heavy))
                Text(direction == "sell" ? "Sell" : "Buy").font(.caption.weight(.bold))
                    .foregroundStyle(direction == "sell" ? p.bad : p.good)
                if let hits, let misses {
                    Text("· Record \(hits) hit\(hits == 1 ? "" : "s"), \(misses) miss\(misses == 1 ? "" : "es")")
                        .font(.caption).foregroundStyle(p.soft).lineLimit(1).minimumScaleFactor(0.85)
                }
                Spacer(minLength: 0)
            }
            Text(reading.map { "Read by rules, not AI · \($0)" } ?? "Read by rules, not AI")
                .font(.caption2).foregroundStyle(p.soft).lineLimit(2)
            if let review {
                Button {
                    Haptics.letter()
                    review()
                } label: {
                    Text("Review trade").font(.footnote.weight(.bold)).foregroundStyle(AK.ink)
                        .frame(maxWidth: .infinity).frame(height: 32)
                        .background(AK.accent, in: Capsule()).contentShape(Capsule())
                }
                .buttonStyle(MoneyPress())
                .padding(.top, 2)
                .accessibilityHint("Shows the trade first. Nothing trades yet.")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(p.fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

extension KolCardView {
    init(call: KolCall, sample: Bool, palette: MoneyPalette, actions: MoneyActions, review: @escaping () -> Void) {
        self.init(handle: call.handle, name: call.name, postedAt: call.postedAt, url: call.url, text: call.text,
                  asset: call.asset, direction: call.direction, hits: call.hits, misses: call.misses,
                  reading: nil, sample: sample, palette: palette, actions: actions, review: review)
    }
}
