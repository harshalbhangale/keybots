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
            if model.receipts.isEmpty {
                Panel {
                    Text(model.loading ? "Loading…" : "Nothing yet").font(.subheadline.weight(.medium)).foregroundStyle(AK.bone)
                    Text("Every command gets a receipt here: what was said, how it was read, and what the leash decided.")
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
        .navigationTitle("Activity")
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
                    OutcomeCard(signal: r.signal, message: r.message)
                    VStack(alignment: .leading, spacing: 0) {
                        said
                        read
                        if r.agent != nil { acted }
                        if let sw = r.swap, r.order == nil { swap(sw) }
                        if let o = r.order { order(o) }
                        if let c = r.checks { checks(c) }
                        if let d = r.decision { decided(d) }
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
        Step(title: r.input.source == "typed" ? "You typed" : "Someone sent") {
            Text("“\(r.input.text)”").font(.body).foregroundStyle(AK.bone).fixedSize(horizontal: false, vertical: true)
            Text(r.input.source == "typed" ? "Your own words, so it's trusted." : "Not your words, so it's treated as untrusted.")
                .font(.footnote).foregroundStyle(r.input.source == "typed" ? AK.muted : AK.amber)
        }
    }

    private var read: some View {
        let a = r.interpretation.action
        return Step(title: "How it was read") {
            KeyValue(key: "Read by", value: r.interpretation.reader == "rules" ? "Fixed rules, no AI" : "NEAR AI Cloud")
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
                KeyValue(key: "Reply signature", value: ai.signature.status, color: ai.signature.status == "verified" ? AK.accent : AK.amber)
                KeyValue(key: "Attestation", value: ai.attestation, color: AK.amber)
            }
        }
    }

    private var acted: some View {
        Step(title: "Who acted") {
            if let agent = r.agent {
                KeyValue(key: Fmt.agentName(account: agent.account), value: agent.tier == "trusted" ? "Trusted" : "Untrusted", color: agent.tier == "trusted" ? AK.accent : AK.amber)
                KeyValue(key: "Account", value: agent.account, mono: true)
            }
            if let rcv = r.receiver { KeyValue(key: "Paying", value: rcv.account, mono: true) }
        }
    }

    private func swap(_ sw: Receipt.Swap) -> some View {
        Step(title: "Swap on NEAR Intents") {
            tokenRow("You pay", sw.from)
            tokenRow("You get", sw.to)
            if let q = sw.quote {
                Hairline()
                KeyValue(key: "Send", value: "\(q.amountInFormatted) \(sw.from.asked.uppercased())" + usd(q.amountInUsd))
                KeyValue(key: "Receive", value: "\(q.amountOutFormatted) \(sw.to.asked.uppercased())" + usd(q.amountOutUsd))
                if let t = q.timeEstimate { KeyValue(key: "Settles in", value: "about \(Int(t)) s") }
                KeyValue(key: "Mode", value: "Quote only, nothing sent", color: AK.amber)
            }
            if let l = sw.leash {
                Hairline()
                KeyValue(key: "Worth", value: "\(l.valueNear) NEAR")
                KeyValue(key: "Leash allows", value: "\(Fmt.near(l.perPaymentCap)) a payment · \(Fmt.near(l.leftToday)) left today")
                KeyValue(key: "Within the leash", value: l.within ? "Yes" : "No", color: l.within ? AK.accent : AK.red)
            }
        }
    }

    private func order(_ o: Receipt.OrderRef) -> some View {
        Step(title: "Left with the Trading Agent", last: true) {
            KeyValue(key: "Watching", value: o.symbol)
            KeyValue(key: "Runs when it's", value: "\(o.direction) \(Fmt.usd(o.price))")
            KeyValue(key: "Price then", value: Fmt.usd(o.priceThen))
            KeyValue(key: "Then", value: o.command)
            Text("When the price crosses, the trade runs like one you typed: same token checks, same caps, its own receipt. Cancel it from Home.")
                .font(.footnote).foregroundStyle(AK.muted).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func checks(_ c: Receipt.Checks) -> some View {
        Step(title: "Checks before asking the leash") {
            KeyValue(
                key: "Verdict",
                value: c.verdict == "allow" ? "Looks fine" : c.verdict == "warn" ? "Ask the owner" : "Stop",
                color: c.verdict == "allow" ? AK.accent : c.verdict == "warn" ? AK.amber : AK.red
            )
            ForEach(c.reasons, id: \.self) { reason in
                Text(reason).font(.footnote).foregroundStyle(AK.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func decided(_ d: Receipt.Decision) -> some View {
        Step(title: "The leash decided", last: true, color: r.signal.color) {
            KeyValue(key: "Decision", value: d.status.capitalized, color: r.signal.color)
            if let rule = d.rule { KeyValue(key: "Rule", value: rule, mono: true) }
            Text(d.reason).font(.footnote).foregroundStyle(AK.muted).fixedSize(horizontal: false, vertical: true)
            if let tx = r.tx, let url = URL(string: tx.url) {
                Link(destination: url) {
                    Label("See it on NEAR", systemImage: "arrow.up.right").font(.subheadline.weight(.semibold)).foregroundStyle(AK.accent)
                }
                .padding(.top, 2)
            }
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
