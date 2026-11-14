import SwiftUI

/// Hold keys: which letters run something when held in the keyboard, and
/// what. Saved to the App Group as it changes (BoundKeys); the keyboard
/// reads it the next time it comes up.
struct KeysView: View {
    @State private var map = BoundKeys.current

    private var letters: [String] { BoundKeys.keyboardOrder(map.keys) }
    private var free: [String] { Self.alphabet.filter { map[$0] == nil } }
    private static let alphabet = "abcdefghijklmnopqrstuvwxyz".map(String.init)

    var body: some View {
        Screen {
            Masthead(eyebrow: "AIRKEY · HOLD KEYS", title: "KEYS")
            Text("Hold a letter in any chat to run it. A small dot marks each one.")
                .font(.subheadline)
                .foregroundStyle(AK.muted)
                .fixedSize(horizontal: false, vertical: true)
            Card(padding: 0, spacing: 0) {
                if letters.isEmpty {
                    Text("No letters bound.")
                        .font(.subheadline)
                        .foregroundStyle(AK.muted)
                        .padding(16)
                }
                ForEach(Array(letters.enumerated()), id: \.element) { i, letter in
                    if i > 0 { Rectangle().fill(AK.hairline).frame(height: 1).padding(.leading, 70) }
                    if let action = map[letter] { row(letter, action) }
                }
            }
            VStack(spacing: 10) {
                if !free.isEmpty {
                    Menu {
                        ForEach(free, id: \.self) { letter in
                            Menu(letter.uppercased()) {
                                ForEach(BoundKeys.Action.allCases) { action in
                                    Button(action.title, systemImage: action.symbol) { set(letter, action) }
                                }
                            }
                        }
                    } label: {
                        Text("ADD A KEY")
                    }
                    .buttonStyle(.bigSecondary)
                }
                if map != BoundKeys.defaults {
                    Button("Reset to P, V, C, S") {
                        BoundKeys.reset()
                        withAnimation(.snappy) { map = BoundKeys.current }
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AK.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                }
            }
            Text("A held letter runs its action instead of showing its accents.")
                .font(.footnote)
                .foregroundStyle(AK.faint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: map)
    }

    private func row(_ letter: String, _ action: BoundKeys.Action) -> some View {
        HStack(spacing: 14) {
            KeyCap(letter: letter)
            VStack(alignment: .leading, spacing: 2) {
                Text(action.title).font(.subheadline.weight(.semibold)).foregroundStyle(AK.bone)
                Text(action.detail).font(.footnote).foregroundStyle(AK.muted).lineLimit(1).minimumScaleFactor(0.85)
            }
            Spacer(minLength: 8)
            Menu {
                Picker(action.title, selection: Binding(get: { action }, set: { set(letter, $0) })) {
                    ForEach(BoundKeys.Action.allCases) { a in
                        Label(a.title, systemImage: a.symbol).tag(a)
                    }
                }
                Divider()
                Button("Unbind \(letter.uppercased())", systemImage: "minus.circle", role: .destructive) { set(letter, nil) }
            } label: {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AK.muted)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Change \(letter.uppercased())")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .transition(.opacity)
    }

    private func set(_ letter: String, _ action: BoundKeys.Action?) {
        withAnimation(.snappy) { map[letter] = action }
        BoundKeys.save(map)
    }
}

/// A letter as it sits on the keyboard: a key with the small lime dot of a
/// bound key in its corner.
struct KeyCap: View {
    let letter: String
    var size: CGFloat = 40

    var body: some View {
        Text(letter.uppercased())
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(AK.bone)
            .frame(width: size, height: size * 1.1)
            .background(AK.raised, in: RoundedRectangle(cornerRadius: size * 0.2, style: .continuous))
            .overlay(alignment: .topTrailing) {
                Circle().fill(AK.accent).frame(width: 5, height: 5).padding(size * 0.14)
            }
            .accessibilityHidden(true)
    }
}

/// The Keyboard tab's way in: what the held letters do, at a glance.
struct KeysLink: View {
    @State private var map = BoundKeys.current

    var body: some View {
        HStack(spacing: 12) {
            KeyCap(letter: ordered.first ?? "p", size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text("Hold a letter").font(.subheadline.weight(.semibold)).foregroundStyle(AK.bone)
                Text(summary).font(.footnote).foregroundStyle(AK.muted).lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(AK.faint)
        }
        .contentShape(Rectangle())
        .onAppear { map = BoundKeys.current }
    }

    private var ordered: [String] { BoundKeys.keyboardOrder(map.keys) }

    /// "P Pay · S Swap · C Clipboard · V Vault"
    private var summary: String {
        guard !map.isEmpty else { return "None bound yet" }
        return ordered.compactMap { l in map[l].map { "\(l.uppercased()) \($0.title)" } }.joined(separator: " · ")
    }
}
