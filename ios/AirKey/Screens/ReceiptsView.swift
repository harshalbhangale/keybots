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
            Masthead(eyebrow: "", title: "Activity")
            if let pending = model.state?.pending, !pending.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle("Waiting for you", trailing: "\(pending.count)")
                    ForEach(pending) { ApprovalCard(pending: $0, tagged: false) }
                }
            }
            if model.receipts.isEmpty {
                Panel {
                    Text(model.loading ? "Loading…" : "Nothing yet").font(.headline).foregroundStyle(AK.bone)
                    Text("Everything you ask for gets a receipt here: what was said, how it was read, and what happened.")
                        .font(.subheadline).foregroundStyle(AK.muted).fixedSize(horizontal: false, vertical: true)
                }
            }
            ForEach(days, id: \.day) { group in
                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle(group.day)
                    ReceiptGroup(receipts: group.receipts, open: open)
                }
            }
        }
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
                    verdict
                    VStack(alignment: .leading, spacing: 0) {
                        said
                        read
                        if r.agent != nil { acted }
                        if let sw = r.swap, r.order == nil { swap(sw) }
                        if let o = r.order { order(o) }
                        if let c = r.checks { checks(c) }
                        details
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AK.surface, in: RoundedRectangle(cornerRadius: AK.radius, style: .continuous))
                }
                .padding(.horizontal, AK.gutter)
                .padding(.vertical, 12)
            }
            .scrollIndicators(.hidden)
            .background { Ambient() }
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

    /// Who made the call: the contract on chain, or the server before anything was sent.
    private var decider: String? {
        if r.decision != nil { return "Decided by Spend Limits, on NEAR" }
        switch r.outcome {
        case "quoted": return "A price only. Nothing was sent."
        case "watching": return "Waiting for the price. Nothing sent yet."
        default: return "Stopped by the Keybots server. Nothing reached Spend Limits."
        }
    }

    /// The amount at stake, for the big number: "2 NEAR".
    private var bigAmount: String? {
        let a = r.interpretation.action
        if a.kind == "pay", let n = a.amountNear { return "\(n) NEAR" }
        if a.kind == "swap", let n = a.amount, let from = a.from { return "\(n) \(from.uppercased())" }
        return nil
    }

    /// Who it went to, or what a swap became: ("To", "free-near-drop.testnet").
    private var counterpart: (word: String, name: String)? {
        let a = r.interpretation.action
        if a.kind == "swap", let to = a.to { return ("For", to.uppercased()) }
        if let rc = r.receiver { return ("To", Plain.name(rc.account)) }
        if let to = a.receiver { return ("To", to) }
        return nil
    }

    /// The verdict, who decided, and the transaction, before anything else.
    private var verdict: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let amount = bigAmount {
                // One big number: the status above it, the account under it.
                VStack(alignment: .leading, spacing: 4) {
                    Label(Plain.title(r), systemImage: r.signal.icon)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(r.signal.text)
                    Text(amount)
                        .font(AK.number(40))
                        .foregroundStyle(AK.bone)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    if let to = counterpart {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(to.word).font(.subheadline).foregroundStyle(AK.muted)
                            Text(to.name).font(.footnote.monospaced()).foregroundStyle(AK.bone)
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            } else {
                HStack(alignment: .top, spacing: 14) {
                    SignalBadge(signal: r.signal, size: 40)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Plain.title(r)).font(.title2.weight(.semibold)).foregroundStyle(AK.bone)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(Plain.body(r)).font(.subheadline).foregroundStyle(AK.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
            if let decider {
                Hairline()
                Label(decider, systemImage: r.decision != nil ? "checkmark.shield" : "server.rack")
                    .font(.subheadline)
                    .foregroundStyle(AK.bone)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let tx = r.tx, let url = URL(string: tx.url) {
                Link(destination: url) {
                    HStack {
                        Text("See the transaction on NEAR")
                        Spacer(minLength: 8)
                        Image(systemName: "arrow.up.right")
                    }
                }
                .buttonStyle(BigButtonStyle(primary: false, height: 46))
                .accessibilityHint("Opens the NEAR explorer")
            }
        }
        .padding(16)
        .background(AK.surface, in: RoundedRectangle(cornerRadius: AK.radius, style: .continuous))
    }

    private var said: some View {
        Step(title: r.input.source == "typed" ? "You typed" : "You copied") {
            Text("“\(r.input.text)”").font(.body).foregroundStyle(AK.bone).fixedSize(horizontal: false, vertical: true)
            Text(r.input.source == "typed" ? "Your own words." : "Not your words, so the stricter limits apply.")
                .font(.footnote).foregroundStyle(r.input.source == "typed" ? AK.muted : AK.amberText)
        }
    }

    private var read: some View {
        let a = r.interpretation.action
        return Step(title: "How it was read") {
            KeyValue(key: "Read by", value: Self.readerName(r.interpretation.reader), color: r.interpretation.reader == "openai" ? AK.amberText : AK.bone)
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
                let checked = r.interpretation.reader != "openai" && ai.signature.status == "verified" && ai.attestation == "verified"
                Label(checked ? "Checked: the reading came from a private, verified model" : "Not checked: this reading isn't from a verified private model",
                      systemImage: checked ? "checkmark.seal" : "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(checked ? AK.bone : AK.amberText)
                    .fixedSize(horizontal: false, vertical: true)
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 8) {
                        KeyValue(key: "Model", value: ai.model)
                        KeyValue(key: "Answer signed", value: r.interpretation.reader == "openai" ? "No" : Self.sentence(ai.signature.status), color: ai.signature.status == "verified" ? AK.accentText : AK.amberText)
                        KeyValue(key: "Private hardware", value: Self.sentence(ai.attestation), color: ai.attestation == "verified" ? AK.accentText : AK.amberText)
                    }
                    .padding(.top, 8)
                } label: {
                    Text("How it was checked").font(.subheadline).foregroundStyle(AK.muted)
                }
                .tint(AK.muted)
            }
        }
    }

    private var acted: some View {
        Step(title: "Who acted") {
            if let agent = r.agent {
                KeyValue(key: "Agent", value: Fmt.agentName(account: agent.account), color: AK.bone)
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
                KeyValue(key: "Paid", value: "\(x.amountIn) NEAR from your Keybots balance")
                if let out = x.amountOut { KeyValue(key: "Got", value: "\(out) \(x.symbolOut), in your Keybots balance", color: AK.accentText) }
                KeyValue(key: "Result", value: x.ok ? "Done on NEAR" : "Not filled, nothing lost", color: x.ok ? AK.accentText : AK.amberText)
            } else if let q = sw.quote {
                Hairline()
                KeyValue(key: "Send", value: "\(q.amountInFormatted) \(sw.from.asked.uppercased())" + usd(q.amountInUsd))
                KeyValue(key: "Receive", value: "\(q.amountOutFormatted) \(sw.to.asked.uppercased())" + usd(q.amountOutUsd))
                if let t = q.timeEstimate { KeyValue(key: "Settles in", value: "about \(Int(t)) s") }
                KeyValue(key: "Result", value: "A price only, nothing sent", color: AK.amberText)
            }
            if let l = sw.leash {
                Hairline()
                KeyValue(key: "Worth", value: "\(l.valueNear) NEAR")
                KeyValue(key: "Your limit", value: "\(Fmt.near(l.perPaymentCap)) a trade · \(Fmt.near(l.leftToday)) left today")
                KeyValue(key: "Within Spend Limits", value: l.within ? "Yes" : "No", color: l.within ? AK.accentText : AK.redText)
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
                color: c.verdict == "allow" ? AK.accentText : c.verdict == "warn" ? AK.amberText : AK.redText
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
                HStack(alignment: .firstTextBaseline) {
                    Text("Spend Limits said").font(.subheadline).foregroundStyle(AK.muted)
                    if let rule = d.rule {
                        Text(rule).font(.caption2.monospaced()).foregroundStyle(AK.faint)
                            .accessibilityLabel("rule \(rule)")
                    }
                    Spacer(minLength: 16)
                    Text(d.status.capitalized).font(.subheadline.weight(.medium)).foregroundStyle(r.signal.text)
                }
                Text(Plain.rule(d.rule) ?? Plain.scrub(d.reason)).font(.footnote).foregroundStyle(AK.muted).fixedSize(horizontal: false, vertical: true)
            }
            Text(Plain.scrub(r.message)).font(.footnote).foregroundStyle(AK.muted).fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if let agent = r.agent {
                KeyValue(key: "Agent", value: Fmt.agentName(account: agent.account))
            }
            KeyValue(key: "When", value: Fmt.when(r.date))
            if let tx = r.tx {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Transaction").font(.subheadline).foregroundStyle(AK.muted)
                    Spacer(minLength: 8)
                    Button {
                        UIPasteboard.general.string = tx.hash
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc").font(.footnote.weight(.medium))
                    }
                    .foregroundStyle(AK.accentText)
                    .accessibilityLabel("Copy the transaction hash")
                }
                Text(tx.hash).font(.footnote.monospaced()).foregroundStyle(AK.bone)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// "verified" -> "Verified".
    static func sentence(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }

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
                Image(systemName: t.verified ? "checkmark.seal.fill" : "xmark.octagon.fill").foregroundStyle(t.verified ? AK.accentText : AK.redText)
            }
            if !t.verified {
                Text(t.reason).font(.footnote).foregroundStyle(AK.redText).fixedSize(horizontal: false, vertical: true)
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
