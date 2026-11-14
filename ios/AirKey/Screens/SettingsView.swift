import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var server = Settings.serverURL
    @State private var token = Settings.token
    @State private var name = Settings.name
    @State private var copied = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Keyboard") {
                    VStack(alignment: .leading, spacing: 8) {
                        step(1, "Open Settings › Apps › Keybots › Keyboards")
                        step(2, "Turn on Keybots")
                        step(3, "Turn on Allow Full Access, so Keybots can pay and swap for you")
                    }
                    .padding(.vertical, 4)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                }

                Section {
                    TextField("Your name", text: $name)
                } header: {
                    Text("You")
                }

                VaultSection()

                Section {
                    LabeledContent("Address") {
                        TextField("http://127.0.0.1:8787", text: $server)
                            .font(AK.mono)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                    }
                    LabeledContent("Token") {
                        SecureField("Optional", text: $token).font(AK.mono).multilineTextAlignment(.trailing)
                    }
                } header: {
                    Text("Keybots server")
                } footer: {
                    Text("The keyboard uses the same server.")
                }

                Section {
                    Text(DeviceKey.publicKey).font(AK.mono).foregroundStyle(AK.bone).textSelection(.enabled)
                    Button(copied ? "Copied" : "Copy key") {
                        UIPasteboard.general.string = DeviceKey.publicKey
                        copied = true
                    }
                } header: {
                    Text("This phone's key")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("It signs approvals after Face ID and never leaves this phone. Add it to your NEAR account once:")
                        Text("npm run add-device -- <owner> <key>").font(AK.mono)
                        if !DeviceKey.persisted {
                            Text("This build can't save the key in the Keychain, so it lasts only until the app quits.").foregroundStyle(AK.amberText)
                        }
                    }
                }

                if let state = model.state {
                    Section("Account") {
                        LabeledContent("Your account") { Text(state.owner).font(AK.mono) }
                        LabeledContent("Spend Limits contract") { Text(state.leash).font(AK.mono) }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AK.canvas.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
        .onDisappear(perform: save)
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(n)").font(.footnote.weight(.bold)).foregroundStyle(AK.ink).frame(width: 20, height: 20).background(AK.accent, in: Circle())
            Text(text).font(.subheadline).foregroundStyle(AK.bone).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func save() {
        Settings.serverURL = server.trimmingCharacters(in: .whitespaces)
        Settings.token = token
        Settings.name = name
        Task { await model.refresh() }
    }
}

/// What the keyboard's vault offers: your NEAR account, then addresses you add.
private struct VaultSection: View {
    @State private var items = Vault.items
    @State private var adding = false
    @State private var label = ""
    @State private var value = ""
    @State private var problem: String?

    var body: some View {
        Section {
            if let owner = Vault.owner {
                row("My NEAR", owner)
            }
            ForEach(items) { item in row(item.label, item.value) }
                .onDelete { at in
                    items.remove(atOffsets: at)
                    Vault.save(items)
                }
            Button("Add an address") { label = ""; value = ""; adding = true }
        } header: {
            Text("Vault")
        } footer: {
            Text("In any chat, tap the wallet in the Keybots bar to put one of these in your message. Only add things that are safe to share; keys and recovery phrases are turned away.")
        }
        .alert("Add to the vault", isPresented: $adding) {
            TextField("Name, like ETH or UPI", text: $label)
            TextField("Address or ID", text: $value)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Add", action: add)
            Button("Cancel", role: .cancel) {}
        }
        .alert("Not added", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(problem ?? "")
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        LabeledContent(label) {
            Text(value).font(AK.mono).lineLimit(1).truncationMode(.middle)
        }
    }

    private func add() {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let p = Vault.problem(with: v) { problem = p; return }
        let name = label.trimmingCharacters(in: .whitespacesAndNewlines)
        items.append(Vault.Item(label: name.isEmpty ? "Address" : name, value: v))
        Vault.save(items)
    }
}
