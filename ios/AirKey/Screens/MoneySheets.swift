import CoreImage.CIFilterBuiltins
import SwiftUI

/// Deposit, Withdraw and Send: money into and out of Spend Limits, in plain words.
struct MoneyButtons: View {
    @Environment(AppModel.self) private var model
    @State private var sheet: Kind?

    enum Kind: String, Identifiable { case deposit, withdraw, send; var id: String { rawValue } }

    var body: some View {
        HStack(spacing: 10) {
            button("Deposit", "arrow.down.circle", .deposit)
            button("Withdraw", "arrow.up.circle", .withdraw)
            button("Send", "paperplane", .send)
        }
        .sheet(item: $sheet) { kind in
            Group {
                switch kind {
                case .deposit: DepositSheet()
                case .withdraw: WithdrawSheet()
                case .send: SendSheet()
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private func button(_ title: String, _ icon: String, _ kind: Kind) -> some View {
        Button { sheet = kind } label: {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.title3)
                Text(title).font(.footnote.weight(.medium))
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(AK.surface, in: RoundedRectangle(cornerRadius: AK.radius, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(AK.bone)
        .disabled(model.state == nil)
    }
}

/// The Spend Limits address, to copy or scan. Anyone can send NEAR to it.
struct DepositSheet: View {
    @Environment(AppModel.self) private var model
    @State private var copied = false

    private var address: String { model.state?.leash ?? "" }
    private var testnet: Bool { model.state?.explorer.contains("testnet") ?? true }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                if let qr = Self.qr(address) {
                    Image(uiImage: qr).interpolation(.none).resizable().scaledToFit()
                        .frame(width: 180, height: 180)
                        .padding(12).background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .accessibilityLabel("QR code for \(address)")
                }
                Text(address).font(.body.monospaced()).foregroundStyle(AK.bone).textSelection(.enabled)
                Button(copied ? "Copied" : "Copy address") {
                    UIPasteboard.general.string = address
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    copied = true
                }
                .buttonStyle(BigButtonStyle(primary: true, height: 46))
                Text(testnet
                     ? "Send testnet NEAR to this address from any NEAR wallet or a testnet faucet. It goes straight into Spend Limits, where your agents can spend it within their limits."
                     : "Send NEAR to this address from any NEAR wallet. This is real NEAR: it goes into Spend Limits, where your agents can spend it within their limits.")
                    .font(.footnote).foregroundStyle(AK.muted).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, AK.gutter).padding(.top, 8)
            .navigationTitle("Deposit").navigationBarTitleDisplayMode(.inline)
        }
    }

    static func qr(_ text: String) -> UIImage? {
        guard !text.isEmpty else { return nil }
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(text.utf8)
        f.correctionLevel = "M"
        guard let out = f.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cg = CIContext().createCGImage(out, from: out.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// NEAR back from Spend Limits to you, signed after Face ID.
struct WithdrawSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""

    private var yocto: String? { Fmt.yocto(near: amount).flatMap { $0 == "0" ? nil : $0 } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Amount") {
                        TextField("0.1", text: $amount).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                    if let s = model.state {
                        LabeledContent("Available", value: Fmt.near(s.available))
                        LabeledContent("To", value: s.owner).font(.subheadline.monospaced())
                    }
                } footer: {
                    Text("Only to you, the owner. Signed on this phone after Face ID; Spend Limits sends it.")
                }
            }
            .navigationTitle("Withdraw").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Withdraw") {
                        guard let y = yocto else { return }
                        Task {
                            await model.owner("withdraw", ["amount": y], reason: "Withdraw \(amount) NEAR to you")
                            if model.error == nil { dismiss() }
                        }
                    }
                    .disabled(yocto == nil || model.busy != nil)
                }
            }
        }
    }
}

/// Pay someone through the Pay Agent, after seeing exactly who gets what.
struct SendSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var to = ""
    @State private var amount = ""
    @State private var sending = false
    @State private var result: Receipt?

    private var receiver: String { to.trimmingCharacters(in: .whitespaces).lowercased() }
    private var ready: Bool { !receiver.isEmpty && Fmt.yocto(near: amount).map { $0 != "0" } == true }
    private var payAgent: LeashState.AgentEntry? {
        model.state.flatMap { s in s.shownAgents.first { $0.account == s.active?.trusted } }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("name.near or a contact", text: $to)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    LabeledContent("Amount") {
                        TextField("0.1", text: $amount).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                }
                if ready {
                    Section("You're about to") {
                        Text("Pay \(amount) NEAR to \(receiver)").font(.headline)
                        LabeledContent("Paid by", value: "Pay Agent, from Spend Limits")
                        if let a = payAgent {
                            LabeledContent("Its limits", value: "\(Fmt.near(a.agent.per_payment_cap)) a payment · \(Fmt.near(a.agent.daily_cap)) a day")
                        }
                        Text("Spend Limits checks it on chain first: Stop everything, the blocked list and the limits.")
                            .font(.footnote).foregroundStyle(AK.muted)
                    }
                }
                if let r = result {
                    Section("Result") {
                        Label(Plain.title(r), systemImage: r.signal.icon).foregroundStyle(r.signal.text)
                        Text(Plain.body(r)).font(.footnote).foregroundStyle(AK.muted)
                    }
                }
            }
            .navigationTitle("Send").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(result == nil ? "Cancel" : "Done") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(sending ? "Sending…" : "Send") {
                        sending = true
                        Task {
                            result = await model.run("pay \(receiver) \(amount)", source: "typed")
                            sending = false
                        }
                    }
                    .disabled(!ready || sending || result != nil)
                }
            }
        }
    }
}
