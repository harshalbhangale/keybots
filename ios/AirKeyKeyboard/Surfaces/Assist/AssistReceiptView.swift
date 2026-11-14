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
/// what is still taken on trust, and how to check it yourself.
struct AssistReceiptCard: View {
    let receipt: AssistReceipt
    let note: String?
    let p: AssistPalette
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: headerIcon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(receipt.isPrivate ? p.mark : p.amber)
                VStack(alignment: .leading, spacing: 0) {
                    Text(header).font(.subheadline.weight(.semibold)).foregroundStyle(p.text)
                    Text(receipt.isNear ? "NEAR AI · \(Self.shortModel(receipt.model))\(receipt.ms.map { " · \(Self.duration($0))" } ?? "")"
                         : "OpenAI · \(Self.shortModel(receipt.model))")
                        .font(.caption).foregroundStyle(p.soft).lineLimit(1)
                }
                Spacer(minLength: 0)
                Button(action: close) {
                    Text("Done").font(.footnote.weight(.semibold)).foregroundStyle(p.soft)
                        .padding(.horizontal, 10).frame(height: 26)
                        .background(p.function, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 6) {
                    if receipt.isNear {
                        ForEach(checkRows, id: \.name) { row in check(row) }
                    } else {
                        bullet("This text was answered by OpenAI. It left NEAR AI's sealed hardware, so it is not private.", tone: .bad)
                    }
                    Text("Only the text you choose is sent.")
                        .font(.footnote).foregroundStyle(p.text).padding(.top, 2)
                    if receipt.isNear {
                        Text("What you still trust").font(.footnote.weight(.semibold)).foregroundStyle(p.text).padding(.top, 4)
                        bullet("The Intel TDX and GPU verdicts come from Phala and NVIDIA; this phone doesn't check them itself.")
                        bullet("NEAR's instances of a model share one signing key.")
                        bullet("The connection isn't bound to the attested machine yet.")
                        bullet("NEAR AI's data retention isn't verified by AIRKEY.")
                        Text("How to check it yourself").font(.footnote.weight(.semibold)).foregroundStyle(p.text).padding(.top, 4)
                        Text("GET /v1/ai/attestation on the AIRKEY server, and NEAR's own verifier at https://cloud.near.ai/verify")
                            .font(.caption).foregroundStyle(p.soft)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let note, !note.isEmpty {
                        bullet(note).padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(p.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(p.line, lineWidth: 0.5))
    }

    private var header: String {
        guard receipt.isNear else { return "OpenAI, not private" }
        return receipt.isPrivate ? "Verified" : "Partly verified"
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
            CheckRow(name: "Signature on this answer", state: sig),
            CheckRow(name: "Signer matches the attested enclave", state: receipt.state("signerMatch")),
            CheckRow(name: "Intel TDX quote (verdict from Phala's verifier)", state: receipt.state("tdxQuote")),
            CheckRow(name: "NVIDIA GPU (verdict from NVIDIA NRAS)", state: receipt.state("nvidia")),
            CheckRow(name: "Fresh nonce", state: receipt.state("nonce")),
            CheckRow(name: "Compose hash", state: receipt.state("composeHash")),
        ]
    }

    private func check(_ row: CheckRow) -> some View {
        let (icon, word, color): (String, String, Color) = switch row.state {
        case .passed: ("checkmark", "passed", p.mark)
        case .failed: ("xmark", "failed", p.amber)
        case .unavailable: ("minus", "unavailable", p.soft)
        }
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon).font(.system(size: 11, weight: .bold)).foregroundStyle(color).frame(width: 14)
            Text(row.name).font(.footnote).foregroundStyle(p.text).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Text(word).font(.caption.weight(.semibold)).foregroundStyle(row.state == .failed ? p.amber : p.soft)
        }
        .accessibilityElement(children: .combine)
    }

    private enum Tone { case plain, bad }

    private func bullet(_ text: String, tone: Tone = .plain) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("·").font(.footnote.weight(.bold)).foregroundStyle(p.soft).frame(width: 14)
            Text(text).font(.caption).foregroundStyle(tone == .bad ? p.amber : p.soft)
                .fixedSize(horizontal: false, vertical: true)
        }
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
