import SwiftUI

/// Who answered, said plainly: the badge in the panel's corner and the
/// small receipt it opens.
struct AssistBadge: View {
    let receipt: AssistReceipt?
    let working: Bool
    let p: AssistPalette

    var body: some View {
        HStack(spacing: 4) {
            if let r = receipt {
                if r.isPrivate {
                    Image(systemName: "checkmark.seal.fill").font(.system(size: 11, weight: .semibold)).foregroundStyle(p.mark)
                    Text("Private · NEAR AI").foregroundStyle(p.text)
                } else if r.isNear {
                    Image(systemName: "seal").font(.system(size: 11, weight: .semibold)).foregroundStyle(p.soft)
                    Text("NEAR AI · partly verified").foregroundStyle(p.soft)
                } else {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10, weight: .semibold))
                    Text("OpenAI (not private)")
                }
            } else {
                Text(working ? "NEAR AI" : " ").foregroundStyle(p.soft)
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(receipt.map { $0.isNear ? p.text : p.amber } ?? p.soft)
        .lineLimit(1)
        .padding(.horizontal, 9)
        .frame(height: 26)
        .background(receipt == nil ? Color.clear : p.function, in: Capsule())
        .contentShape(Capsule())
        .accessibilityLabel(receipt.map(Self.spoken) ?? "")
    }

    static func spoken(_ r: AssistReceipt) -> String {
        r.isPrivate ? "Private, NEAR AI, verified. Show receipt." : r.isNear ? "NEAR AI, partly verified. Show receipt." : "OpenAI, not private. Show receipt."
    }
}

/// The receipt: who answered, each check as passed, failed or unavailable,
/// what is still taken on trust, and how to check it yourself. A checklist,
/// one line per item.
struct AssistReceiptCard: View {
    let receipt: AssistReceipt
    let note: String?
    let p: AssistPalette
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: headerIcon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(receipt.isPrivate ? p.mark : p.amber)
                VStack(alignment: .leading, spacing: 1) {
                    Text(header).font(.headline).foregroundStyle(p.text)
                    HStack(spacing: 5) {
                        Text(receipt.isNear ? "NEAR AI\(receipt.ms.map { " · \(Self.duration($0))" } ?? "")" : "OpenAI")
                            .font(.caption).foregroundStyle(p.soft)
                        // The model's name is for the curious: a small grey label.
                        Text(Self.shortModel(receipt.model)).font(.caption2).foregroundStyle(p.soft.opacity(0.7))
                    }
                    .lineLimit(1)
                }
                Spacer(minLength: 0)
                Button(action: close) {
                    Text("Done").font(.footnote.weight(.semibold)).foregroundStyle(p.text)
                        .padding(.horizontal, 12).frame(height: 28)
                        .background(p.function, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .accessibilityElement(children: .combine)
            // The four checks that matter, whole, with their own corners.
            if receipt.isNear {
                group {
                    ForEach(Array(checkRows.prefix(4).enumerated()), id: \.element.name) { i, row in
                        if i > 0 { divider }
                        check(row)
                    }
                }
            }
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    if receipt.isNear {
                        group {
                            ForEach(Array(checkRows.dropFirst(4).enumerated()), id: \.element.name) { i, row in
                                if i > 0 { divider }
                                check(row)
                            }
                        }
                    } else {
                        group {
                            item("Answered by OpenAI. It left NEAR AI's sealed hardware, so it is not private.", icon: "exclamationmark.triangle.fill", tint: p.amber)
                        }
                    }
                    group {
                        item("Only the text you chose was sent.", icon: "text.cursor", tint: p.soft)
                        if let note, !note.isEmpty {
                            divider
                            item(note, icon: "info.circle", tint: p.soft)
                        }
                    }
                    if receipt.isNear {
                        section("What you still trust")
                        group {
                            item("Phala and NVIDIA give the hardware verdicts; this phone doesn't check them itself.", icon: "building.2", tint: p.soft)
                            divider
                            item("NEAR's copies of a model share one signing key.", icon: "key", tint: p.soft)
                            divider
                            item("The connection isn't tied to the checked machine yet.", icon: "link", tint: p.soft)
                            divider
                            item("NEAR AI's data retention isn't verified by AIRKEY.", icon: "tray", tint: p.soft)
                        }
                        section("Check it yourself")
                        Text("cloud.near.ai/verify, or /v1/ai/attestation on your AIRKEY server")
                            .font(.caption).foregroundStyle(p.soft)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 4)
            }
            .scrollEdgeEffectHidden(true, for: .all)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(p.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var header: String {
        guard receipt.isNear else { return "OpenAI, not private" }
        return receipt.isPrivate ? "Private and verified" : "Partly verified"
    }

    private var headerIcon: String {
        receipt.isPrivate ? "checkmark.seal.fill" : receipt.isNear ? "seal" : "exclamationmark.triangle.fill"
    }

    private struct CheckRow { let name: String; let state: AssistReceipt.CheckState }

    private var checkRows: [CheckRow] {
        let sig: AssistReceipt.CheckState = switch receipt.signature {
        case "verified": .passed
        case "mismatch", "failed": .failed
        default: .unavailable
        }
        return [
            CheckRow(name: "Reply signed", state: sig),
            CheckRow(name: "Signed inside a sealed machine", state: receipt.state("signerMatch")),
            CheckRow(name: "Processor checked", state: receipt.state("tdxQuote")),
            CheckRow(name: "Graphics chip checked", state: receipt.state("nvidia")),
            CheckRow(name: "Fresh check, not a replay", state: receipt.state("nonce")),
            CheckRow(name: "Software matches", state: receipt.state("composeHash")),
        ]
    }

    private var divider: some View {
        Rectangle().fill(p.line).frame(height: 0.5).padding(.leading, 30)
    }

    private func group<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .background(p.function.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func section(_ title: String) -> some View {
        Text(title).font(.footnote.weight(.semibold)).foregroundStyle(p.soft)
            .padding(.horizontal, 4).padding(.bottom, -6)
    }

    private func check(_ row: CheckRow) -> some View {
        let (icon, word, color): (String, String, Color) = switch row.state {
        case .passed: ("checkmark.circle.fill", "Passed", p.mark)
        case .failed: ("xmark.circle.fill", "Failed", p.amber)
        case .unavailable: ("minus.circle", "Not available", p.soft)
        }
        // The icon says passed; only a failure or a gap gets a word.
        return HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 15)).foregroundStyle(color).frame(width: 20)
            Text(row.name).font(.footnote).foregroundStyle(p.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 6)
            if row.state != .passed {
                Text(word).font(.caption.weight(.medium)).foregroundStyle(row.state == .failed ? p.amber : p.soft)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.name): \(word)")
    }

    private func item(_ text: String, icon: String, tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon).font(.system(size: 13)).foregroundStyle(tint).frame(width: 20)
            Text(text).font(.footnote).foregroundStyle(p.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .accessibilityElement(children: .combine)
    }

    /// "deepseek-ai/DeepSeek-V3.1" → "DeepSeek-V3.1".
    static func shortModel(_ m: String) -> String {
        let last = m.split(separator: "/").last.map(String.init) ?? m
        return last.isEmpty ? "unknown" : last
    }

    static func duration(_ ms: Int) -> String {
        ms < 1000 ? "\(ms) ms" : String(format: "%.1f s", Double(ms) / 1000)
    }
}
