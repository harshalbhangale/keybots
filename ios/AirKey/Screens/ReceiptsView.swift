import SwiftUI

/// Everything the agents were asked to do, newest first, by day.
struct ActivityView: View {
    @Environment(AppModel.self) private var model
    let open: (Receipt) -> Void

    /// Receipts grouped by day, keeping the server's newest-first order.
    private var days: [(day: String, receipts: [Receipt])] {
        var out: [(day: String, receipts: [Receipt])] = []
        for r in model.receipts {
            let d = Fmt.day(r.date)
            if out.last?.day == d { out[out.count - 1].receipts.append(r) } else { out.append((d, [r])) }
        }
        return out
    }

    var body: some View {
        Screen(tint: model.mood) {
            Masthead(eyebrow: "AIRKEY · EVERYTHING YOUR AGENTS DID", title: "ACTIVITY")
            if model.receipts.isEmpty {
                Panel {
                    Text(model.loading ? "Loading…" : "Nothing yet").font(.subheadline.weight(.medium)).foregroundStyle(AK.bone)
                    Text("Everything you ask for gets a receipt here: what was said, how it was read, and what happened.")
                        .font(.subheadline).foregroundStyle(AK.muted).fixedSize(horizontal: false, vertical: true)
                }
            }
            ForEach(days, id: \.day) { group in
                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(group.day)
                    ReceiptGroup(receipts: group.receipts, open: open)
                }
            }
        }
        .toolbarVisibility(.hidden, for: .navigationBar)
    }
}

/// One receipt, told in the order things happened.
struct ReceiptDetail: View {
    let r: Receipt
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    OutcomeCard(signal: r.signal, title: Plain.title(r), message: Plain.body(r))
                    VStack(alignment: .leading, spacing: 0) {
                        said
                        read
                        if r.agent != nil { acted }
                        if let sw = r.swap, r.order == nil { swap(sw) }
                        if let o = r.order { order(o) }
                        if let c = r.checks { checks(c) }
                        details
                    }
                }
                .padding(.horizontal, AK.gutter)
                .padding(.vertical, 12)
            }
            .scrollIndicators(.hidden)
            .background { Ambient(tint: r.signal.plain ? AK.accent : r.signal.color) }
            .navigationTitle("Receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
                if let tx = r.tx, let url = URL(string: tx.url) {
                    ToolbarItem(placement: .topBarLeading) { ShareLink(item: url) }
                }
            }
        }
    }

    private var said: some View {
        Step(title: r.input.source == "typed" ? "You typed" : "You copied") {
            Text("“\(r.input.text)”").font(.body).foregroundStyle(AK.bone).fixedSize(horizontal: false, vertical: true)
            Text(r.input.source == "typed" ? "Your own words." : "Not your words, so the stricter limits apply.")
                .font(.footnote).foregroundStyle(r.input.source == "typed" ? AK.muted : AK.amber)
        }
    }

    private var read: some View {
        let a = r.interpretation.action
        return Step(title: "How it was read") {
            KeyValue(key: "Read by", value: Self.readerName(r.interpretation.reader), color: r.interpretation.reader == "openai" ? AK.amber : AK.bone)
            if a.kind == "pay" {
                if let amt = a.amountNear { KeyValue(key: "Pay", value: "\(amt) NEAR") }
                if let to = a.receiver { KeyValue(key: "To", value: to, mono: true) }
                if let memo = a.memo { KeyValue(key: "For", value: memo) }
            } else if a.kind == "watch" {
                KeyValue(key: "Order", value: a.command ?? "")
            } else if a.kind == "swap" {
                KeyValue(key: "Swap", value: "\(a.amount ?? "") \(a.from ?? "") to \(a.to ?? "")")
            } else if let reason = a.reason {
                Text(reason).font(.subheadline).foregroundStyle(AK.muted).fixedSize(horizontal: false, vertical: true)
            }
            if let ai = r.interpretation.ai {
                KeyValue(key: "Model", value: ai.model, mono: true)
                KeyValue(key: "Reply signature", value: r.interpretation.reader == "openai" ? "Not signed" : ai.signature.status, color: ai.signature.status == "verified" ? AK.accent : AK.amber)
                KeyValue(key: "Attestation", value: ai.attestation, color: AK.amber)
            }
        }
    }

    private var acted: some View {
        Step(title: "Who acted") {
            if let agent = r.agent {
                KeyValue(key: "Agent", value: Fmt.agentName(account: agent.account), color: agent.tier == "trusted" ? AK.accent : AK.amber)
                KeyValue(key: "Acting on", value: Plain.tier(agent.tier))
                KeyValue(key: "Its account", value: agent.account, mono: true)
            }
            if let rcv = r.receiver {
                if Plain.name(rcv.account) != rcv.account { KeyValue(key: "Paying", value: Plain.name(rcv.account)) }
                KeyValue(key: Plain.name(rcv.account) != rcv.account ? "Their account" : "Paying", value: rcv.account, mono: true)
            }
        }
    }

    private func swap(_ sw: Receipt.Swap) -> some View {
        Step(title: "Swap on \(sw.executed?.venue ?? "NEAR Intents")") {
            tokenRow("You pay", sw.from)
            tokenRow("You get", sw.to)
            if let x = sw.executed {
                Hairline()
                KeyValue(key: "Swapped on", value: x.venue)
                KeyValue(key: "Paid", value: "\(x.amountIn) NEAR from your AIRKEY balance")
                if let out = x.amountOut { KeyValue(key: "Got", value: "\(out) \(x.symbolOut), in your AIRKEY balance", color: AK.accent) }
                KeyValue(key: "Result", value: x.ok ? "Done on NEAR" : "Not filled, nothing lost", color: x.ok ? AK.accent : AK.amber)
            } else if let q = sw.quote {
                Hairline()
                KeyValue(key: "Send", value: "\(q.amountInFormatted) \(sw.from.asked.uppercased())" + usd(q.amountInUsd))
                KeyValue(key: "Receive", value: "\(q.amountOutFormatted) \(sw.to.asked.uppercased())" + usd(q.amountOutUsd))
                if let t = q.timeEstimate { KeyValue(key: "Settles in", value: "about \(Int(t)) s") }
                KeyValue(key: "Result", value: "A price only, nothing sent", color: AK.amber)
            }
            if let l = sw.leash {
                Hairline()
                KeyValue(key: "Worth", value: "\(l.valueNear) NEAR")
                KeyValue(key: "Your limit", value: "\(Fmt.near(l.perPaymentCap)) a trade · \(Fmt.near(l.leftToday)) left today")
                KeyValue(key: "Within your limits", value: l.within ? "Yes" : "No", color: l.within ? AK.accent : AK.red)
            }
        }
    }

    private func order(_ o: Receipt.OrderRef) -> some View {
        Step(title: "Left watching the price") {
            KeyValue(key: "Watching", value: o.symbol)
            KeyValue(key: "Runs when it's", value: "\(o.direction) \(Fmt.usd(o.price))")
            KeyValue(key: "Price then", value: Fmt.usd(o.priceThen))
            KeyValue(key: "Then", value: o.command)
            Text("When the price gets there, the trade runs like one you typed: same token checks, same limits, its own receipt. Cancel it from Wallet.")
                .font(.footnote).foregroundStyle(AK.muted).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func checks(_ c: Receipt.Checks) -> some View {
        Step(title: "Checks on who is being paid") {
            KeyValue(
                key: "Verdict",
                value: c.verdict == "allow" ? "Looks fine" : c.verdict == "warn" ? "Ask you first" : "Stop",
                color: c.verdict == "allow" ? AK.accent : c.verdict == "warn" ? AK.amber : AK.red
            )
            ForEach(c.reasons, id: \.self) { reason in
                Text(Plain.check(reason)).font(.footnote).foregroundStyle(AK.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The technical record, as the server and the contract wrote it: the
    /// full message, the rule that decided, and the transaction.
    private var details: some View {
        Step(title: "Details", last: true, color: r.signal.color) {
            if let d = r.decision {
                KeyValue(key: "The contract said", value: d.status.capitalized, color: r.signal.color)
                if let rule = d.rule { KeyValue(key: "Rule", value: rule, mono: true) }
                Text(d.reason).font(.footnote).foregroundStyle(AK.muted).fixedSize(horizontal: false, vertical: true)
            }
            Text(r.message).font(.footnote.monospaced()).foregroundStyle(AK.muted).fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if let tx = r.tx, let url = URL(string: tx.url) {
                Link(destination: url) {
                    Label("See the transaction on NEAR", systemImage: "arrow.up.right").font(.subheadline.weight(.semibold)).foregroundStyle(AK.accent)
                }
                .padding(.top, 2)
            }
        }
    }

    /// The reader that actually answered, named plainly.
    static func readerName(_ reader: String) -> String {
        switch reader {
        case "rules": "Fixed rules, no AI"
        case "near-ai-cloud": "NEAR AI Cloud, private"
        case "openai": "OpenAI, not private"
        default: reader
        }
    }

    private func usd(_ s: String?) -> String {
        s.flatMap(Double.init).map { String(format: " (~$%.2f)", $0) } ?? ""
    }

    private func tokenRow(_ label: String, _ t: Receipt.TokenCheck) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label).font(.subheadline).foregroundStyle(AK.muted)
                Spacer()
                Text(t.token.map { "\($0.symbol) on \($0.blockchain)" } ?? t.asked.uppercased()).font(.subheadline.weight(.medium)).foregroundStyle(AK.bone)
                Image(systemName: t.verified ? "checkmark.seal.fill" : "xmark.octagon.fill").foregroundStyle(t.verified ? AK.accent : AK.red)
            }
            if !t.verified {
                Text(t.reason).font(.footnote).foregroundStyle(AK.red.opacity(0.9)).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// One step on the receipt's timeline: a dot on a rail, a title, and the facts.
private struct Step<Content: View>: View {
    let title: String
    var last = false
    var color: Color = AK.faint
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                Circle().fill(color).frame(width: 9, height: 9).padding(.top, 5)
                if !last { Rectangle().fill(AK.line).frame(width: 1).frame(maxHeight: .infinity) }
            }
            .frame(width: 9)
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(AK.muted)
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, last ? 0 : 26)
        }
    }
}
