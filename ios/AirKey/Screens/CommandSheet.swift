import SwiftUI
import UIKit

/// Tell an agent what to do, from the app. The same thing the keyboard does:
/// your own words go to the Payment Agent, someone else's to the Inbox Agent.
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
                    Button { open(result) } label: { OutcomeCard(signal: result.signal, message: result.message) }
                        .buttonStyle(.plain)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    Text("Tap for the full receipt.").font(.footnote).foregroundStyle(AK.muted).padding(.horizontal, 4)
                } else if let error = model.error {
                    ErrorBanner(text: error)
                } else if trimmed.isEmpty {
                    suggestions
                } else if let intent {
                    preview(intent)
                }
            }
            .padding(.horizontal, AK.gutter)
            .padding(.top, 28)
            .padding(.bottom, 16)
            .animation(.snappy(duration: 0.25), value: result?.id)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(AK.ink.ignoresSafeArea())
        .onAppear { focused = true }
        .onChange(of: text) { result = nil }
        .onChange(of: pasted) { result = nil }
    }

    private var field: some View {
        HStack(alignment: .bottom, spacing: 10) {
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
            .submitLabel(.go)
            .onSubmit(run)

            Button(action: run) {
                Group {
                    if running { ProgressView().tint(AK.ink) } else { Image(systemName: "arrow.up").font(.system(size: 16, weight: .bold)) }
                }
                .foregroundStyle(AK.ink)
                .frame(width: 34, height: 34)
                .background(trimmed.isEmpty ? AK.raised : AK.accent, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(trimmed.isEmpty || running)
            .accessibilityLabel("Run")
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
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
                Text("The Inbox Agent reads it. It can only pay people on your allowlist; anyone else waits for you.")
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
    private func preview(_ intent: Intent) -> some View {
        HStack(spacing: 12) {
            Image(systemName: intent.icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(AK.ink)
                .frame(width: 28, height: 28)
                .background(pasted ? AK.amber : AK.accent, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(intent.title).font(.subheadline.weight(.semibold)).foregroundStyle(AK.bone)
                Text(pasted ? "The Inbox Agent will ask the leash" : (intent.detail ?? "The leash checks it before anything moves"))
                    .font(.footnote).foregroundStyle(AK.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .transition(.opacity)
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
            case .quote, .neutral: UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
    }
}
