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
                    Text("NEAR AI · not verified").foregroundStyle(p.soft)
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
        r.isPrivate ? "Private, NEAR AI, verified. Show receipt." : r.isNear ? "NEAR AI, not verified. Show receipt." : "OpenAI, not private. Show receipt."
    }
}

/// The receipt: which model, what was checked and how long it took.
struct AssistReceiptCard: View {
    let receipt: AssistReceipt
    let note: String?
    let p: AssistPalette
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(receipt.isNear ? "Answered on NEAR AI" : "Answered by OpenAI")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(p.text)
                Spacer(minLength: 0)
                Button(action: close) {
                    Text("Done").font(.footnote.weight(.semibold)).foregroundStyle(p.soft)
                        .padding(.horizontal, 10).frame(height: 26)
                        .background(p.function, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            ForEach(rows, id: \.text) { row in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: row.icon)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(row.tone == .good ? p.mark : row.tone == .bad ? p.amber : p.soft)
                        .frame(width: 14)
                    Text(row.text)
                        .font(.footnote)
                        .foregroundStyle(row.tone == .bad ? p.amber : p.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(12)
        .background(p.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(p.line, lineWidth: 0.5))
        .accessibilityElement(children: .combine)
    }

    private enum Tone { case good, bad, plain }
    private struct Row { let icon: String; let text: String; let tone: Tone }

    private var rows: [Row] {
        var out: [Row] = []
        out.append(Row(icon: "cpu", text: "Model: \(Self.shortModel(receipt.model))", tone: .plain))
        if receipt.isNear {
            switch receipt.signature {
            case "verified": out.append(Row(icon: "checkmark", text: "Signature verified", tone: .good))
            case "mismatch": out.append(Row(icon: "xmark", text: "Signature did not match", tone: .bad))
            default: out.append(Row(icon: "minus", text: "Signature not available", tone: .plain))
            }
            out.append(attestationRow)
        } else {
            out.append(Row(icon: "exclamationmark.triangle", text: "OpenAI (not private): this text left NEAR AI's sealed hardware.", tone: .bad))
        }
        if let ms = receipt.ms { out.append(Row(icon: "clock", text: "Took \(Self.duration(ms))", tone: .plain)) }
        if let note, !note.isEmpty { out.append(Row(icon: "info.circle", text: note, tone: .plain)) }
        return out
    }

    private var attestationRow: Row {
        let tdx = receipt.checks["tdxQuote"]
        let gpu = receipt.checks["nvidia"]
        switch receipt.attestation {
        case "verified":
            return Row(icon: "checkmark", text: "Hardware attestation verified (Intel TDX, NVIDIA GPU)", tone: .good)
        case "partial":
            var parts: [String] = []
            if let tdx { parts.append(tdx ? "Intel TDX verified" : "Intel TDX not verified") }
            if let gpu { parts.append(gpu ? "NVIDIA GPU verified" : "NVIDIA GPU not verified") }
            let detail = parts.isEmpty ? "" : " (\(parts.joined(separator: ", ")))"
            return Row(icon: "exclamationmark", text: "Hardware attestation partly verified\(detail)", tone: .bad)
        case "failed":
            return Row(icon: "xmark", text: "Hardware attestation failed", tone: .bad)
        default:
            return Row(icon: "minus", text: "Hardware attestation not checked", tone: .plain)
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
