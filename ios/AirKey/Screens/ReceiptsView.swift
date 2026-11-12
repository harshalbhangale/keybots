import SwiftUI

struct ReceiptsView: View {
    @Environment(AppModel.self) private var model
    @State private var open: Receipt?

    var body: some View {
        Screen(title: "Receipts", subtitle: "Every command: what you said, how it was read, who acted, and what the leash decided.") {
            if let error = model.error { ErrorBanner(text: error) }
            if model.receipts.isEmpty {
                Text(model.loading ? "Loading…" : "No receipts yet. Run a command from Home or the keyboard.").font(AK.body).foregroundStyle(AK.muted)
            }
            ForEach(model.receipts) { r in
                Button { open = r } label: { ReceiptRow(r: r) }.buttonStyle(.plain)
            }
        }
        .sheet(item: $open) { r in ReceiptDetail(r: r).presentationDetents([.large]) }
    }
}

struct ReceiptRow: View {
    let r: Receipt
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2).fill(r.signal.color).frame(width: 3)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(r.signal.word).font(.system(size: 11, weight: .heavy).width(.expanded)).foregroundStyle(r.signal.color)
                    Pill(text: r.input.source, color: r.input.source == "typed" ? AK.bone : AK.amber)
                    Spacer()
                    Text(Fmt.time(r.date)).font(.system(size: 12)).foregroundStyle(AK.faint)
                }
                Text(r.message).font(.system(size: 15, weight: .medium)).foregroundStyle(AK.bone).fixedSize(horizontal: false, vertical: true)
                Text("“\(r.input.text)”").font(.system(size: 13)).foregroundStyle(AK.muted).lineLimit(2)
            }
        }
        .padding(14)
        .background(AK.surface, in: RoundedRectangle(cornerRadius: AK.radius, style: .continuous))
    }
}

/// The full receipt, in the order things happened.
struct ReceiptDetail: View {
    let r: Receipt
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Wordmark(size: 14)
                    Spacer()
                    Button("Done") { dismiss() }.font(.system(size: 15, weight: .semibold)).foregroundStyle(AK.mint)
                }
                OutcomeChip(signal: r.signal, message: r.message)

                step("1", "You said") {
                    Text("“\(r.input.text)”").font(.system(size: 15)).foregroundStyle(AK.bone)
                    KeyValue(key: "Source", value: r.input.source == "typed" ? "Typed by you (trusted)" : "From someone else (untrusted)")
                }
                step("2", "How it was read") {
                    KeyValue(key: "Reader", value: r.interpretation.reader == "rules" ? "Rules (no AI)" : "NEAR AI Cloud")
                    let a = r.interpretation.action
                    KeyValue(key: "Action", value: a.kind)
                    if let to = a.receiver { KeyValue(key: "Receiver", value: to, mono: true) }
                    if let amt = a.amountNear { KeyValue(key: "Amount", value: "\(amt) NEAR") }
                    if let memo = a.memo { KeyValue(key: "For", value: memo) }
                    if let ai = r.interpretation.ai {
                        KeyValue(key: "Model", value: ai.model, mono: true)
                        KeyValue(key: "Reply signature", value: ai.signature.status, color: ai.signature.status == "verified" ? AK.mint : AK.amber)
                        KeyValue(key: "TEE attestation", value: ai.attestation, color: AK.amber)
                    }
                }
                if let agent = r.agent {
                    step("3", "Who acted") {
                        KeyValue(key: "Agent", value: Fmt.agentName(agent.tier))
                        KeyValue(key: "Account", value: agent.account, mono: true)
                        if let rcv = r.receiver { KeyValue(key: "Paying", value: rcv.account, mono: true) }
                    }
                }
                if let sw = r.swap {
                    step("4", "Swap on NEAR Intents") {
                        tokenRow("Pay", sw.from)
                        tokenRow("Get", sw.to)
                        if let q = sw.quote {
                            Hairline()
                            KeyValue(key: "You send", value: "\(q.amountInFormatted) \(sw.from.asked.uppercased())" + (q.amountInUsd.flatMap(Double.init).map { String(format: " (~$%.2f)", $0) } ?? ""))
                            KeyValue(key: "You get", value: "\(q.amountOutFormatted) \(sw.to.asked.uppercased())" + (q.amountOutUsd.flatMap(Double.init).map { String(format: " (~$%.2f)", $0) } ?? ""))
                            if let t = q.timeEstimate { KeyValue(key: "Settles in", value: "~\(Int(t))s") }
                            KeyValue(key: "Mode", value: "Dry run: nothing sent", color: AK.amber)
                        }
                        if let l = sw.leash {
                            Hairline()
                            KeyValue(key: "Worth", value: "\(l.valueNear) NEAR")
                            KeyValue(key: "Leash cap", value: "\(Fmt.near(l.perPaymentCap)) per payment · \(Fmt.near(l.leftToday)) left today")
                            KeyValue(key: "Within the leash", value: l.within ? "Yes" : "No", color: l.within ? AK.mint : AK.red)
                        }
                    }
                }
                if let c = r.checks {
                    step("4", "Checks before asking") {
                        KeyValue(key: "Verdict", value: c.verdict, color: c.verdict == "allow" ? AK.mint : c.verdict == "warn" ? AK.amber : AK.red)
                        ForEach(c.reasons, id: \.self) { Text("· \($0)").font(.system(size: 13)).foregroundStyle(AK.muted) }
                    }
                }
                if let d = r.decision {
                    step("5", "The leash decided") {
                        KeyValue(key: "Decision", value: d.status, color: r.signal.color)
                        if let rule = d.rule { KeyValue(key: "Rule", value: rule, mono: true) }
                        Text(d.reason).font(.system(size: 13)).foregroundStyle(AK.muted)
                        if let tx = r.tx, let url = URL(string: tx.url) {
                            Link(destination: url) { Text("\(tx.hash.prefix(14))… on NEAR ↗").font(AK.mono).foregroundStyle(AK.mint) }
                        }
                    }
                }
            }
            .padding(AK.gutter)
        }
        .background(AK.ink.ignoresSafeArea())
    }

    private func tokenRow(_ label: String, _ t: Receipt.TokenCheck) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label).font(.system(size: 14)).foregroundStyle(AK.muted)
                Spacer()
                Text(t.token.map { "\($0.symbol) on \($0.blockchain)" } ?? t.asked.uppercased()).font(.system(size: 14, weight: .medium)).foregroundStyle(AK.bone)
                Image(systemName: t.verified ? "checkmark.seal.fill" : "xmark.octagon.fill").foregroundStyle(t.verified ? AK.mint : AK.red)
            }
            Text(t.reason).font(.system(size: 11, design: .monospaced)).foregroundStyle(AK.faint).lineLimit(2).truncationMode(.middle)
        }
    }

    private func step<C: View>(_ n: String, _ title: String, @ViewBuilder _ content: () -> C) -> some View {
        Panel {
            HStack(spacing: 8) {
                Text(n).font(.system(size: 11, weight: .bold).monospacedDigit()).foregroundStyle(AK.ink).frame(width: 18, height: 18).background(AK.bone, in: Circle())
                Eyebrow(title, color: AK.bone)
            }
            content()
        }
    }
}
