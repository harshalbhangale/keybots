import SwiftUI
import UIKit

/// Tell an agent what to do, from the app. The same thing the keyboard does:
/// your own words pay and trade; someone else's are only checked.
struct CommandSheet: View {
    @Environment(AppModel.self) private var model
    let open: (Receipt) -> Void

    @State private var text = ""
    @State private var pasted = false
    @State private var running = false
    @State private var result: Receipt?
    @FocusState private var focused: Bool

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var intent: Intent? { Intent.read(text) }

    private let examples = [
        "Pay harshal.near 0.2 NEAR for dinner",
        "Swap 1 USDC to SOL",
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Picker("Whose words are these?", selection: $pasted) {
                    Text("I'm asking").tag(false)
                    Text("Someone sent me this").tag(true)
                }
                .pickerStyle(.segmented)

                field

                if let result {
                    Button { open(result) } label: { OutcomeCard(signal: result.signal, title: Plain.title(result), message: Plain.body(result)) }
                        .buttonStyle(.plain)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    Text("Tap for the details.").font(.footnote).foregroundStyle(AK.muted).padding(.horizontal, 4)
                } else if let error = model.error {
                    ErrorBanner(text: error)
                } else if trimmed.isEmpty {
                    suggestions
                } else {
                    preview
                    action
                }
            }
            .padding(.horizontal, AK.gutter)
            .padding(.top, 28)
            .padding(.bottom, 16)
            .animation(.snappy(duration: 0.25), value: result?.id)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(AK.canvas.ignoresSafeArea())
        .onAppear { focused = true }
        .onChange(of: text) { result = nil }
        .onChange(of: pasted) { result = nil }
    }

    private var field: some View {
        TextField(
            "",
            text: $text,
            prompt: Text(pasted ? "Paste the message you got" : "Pay harshal.near 0.2 NEAR for dinner").foregroundStyle(AK.faint),
            axis: .vertical
        )
        .lineLimit(1...5)
        .font(.body)
        .foregroundStyle(AK.bone)
        .focused($focused)
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .submitLabel(.done)
        .onSubmit { focused = false }
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    @ViewBuilder private var suggestions: some View {
        VStack(alignment: .leading, spacing: 10) {
            if pasted {
                Button {
                    if let s = UIPasteboard.general.string { text = s }
                } label: {
                    Label("Paste what you copied", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.glass)
                Text("AIRKEY reads it for you. It can only pay people on your allowed list; anyone else waits for you.")
                    .font(.footnote).foregroundStyle(AK.muted).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 4)
            } else {
                Text("Try").font(.footnote.weight(.semibold)).foregroundStyle(AK.muted).padding(.horizontal, 4)
                ForEach(examples, id: \.self) { e in
                    Button { text = e } label: {
                        HStack {
                            Text(e).font(.subheadline).foregroundStyle(AK.bone)
                            Spacer()
                            Image(systemName: "arrow.up.left").font(.footnote).foregroundStyle(AK.faint)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                        .background(AK.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// What the words would do, before you send them.
    @ViewBuilder private var preview: some View {
        HStack(spacing: 12) {
            Image(systemName: intent?.icon ?? (pasted ? "tray" : "questionmark"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AK.ink)
                .frame(width: 28, height: 28)
                .background(pasted ? AK.amber : intent == nil ? AK.muted : AK.accent, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(intent?.title ?? (pasted ? "Someone else's words" : "Not a payment or a trade"))
                    .font(.subheadline.weight(.semibold)).foregroundStyle(AK.bone)
                Text(note)
                    .font(.footnote).foregroundStyle(AK.muted).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .transition(.opacity)
    }

    private var note: String {
        if pasted { return "AIRKEY reads it for you. It can only pay people on your allowed list." }
        if let intent { return intent.detail ?? "Checked against your limits before anything moves." }
        return "Try “pay harshal 0.2 for dinner” or “buy $5 of near”."
    }

    /// Your own command that moves money takes a hold. Checking someone
    /// else's message is a tap: it already gets the stricter limits.
    @ViewBuilder private var action: some View {
        if running {
            HStack(spacing: 10) {
                ProgressView().tint(AK.bone)
                Text(Plain.working(pasted: pasted, swap: intent?.kind == .swap))
                    .font(.subheadline.weight(.medium)).foregroundStyle(AK.bone)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .glassEffect(.regular, in: .capsule)
        } else if let intent, !pasted {
            HoldToConfirm(label: intent.holdLabel, action: run)
        } else {
            Button(action: run) {
                Text(pasted ? "Check it" : "Send anyway")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AK.bone)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
    }

    private func run() {
        let command = trimmed
        guard !command.isEmpty, !running else { return }
        Task {
            running = true
            let r = await model.run(command, source: pasted ? "pasted" : "typed")
            running = false
            result = r
            guard let r else { return }
            let gen = UINotificationFeedbackGenerator()
            switch r.signal {
            case .allow: gen.notificationOccurred(.success)
            case .warn: gen.notificationOccurred(.warning)
            case .block: gen.notificationOccurred(.error)
            case .quote, .watch, .neutral: UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
    }
}
