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
                        step(1, "Open Settings › Apps › AIRKEY › Keyboards")
                        step(2, "Turn on AIRKEY")
                        step(3, "Turn on Allow Full Access, so agents can reach the server")
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
                    Text("AIRKEY server")
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
                            Text("This build can't save the key in the Keychain, so it lasts only until the app quits.").foregroundStyle(AK.amber)
                        }
                    }
                }

                if let state = model.state {
                    Section("Account") {
                        LabeledContent("Owner") { Text(state.owner).font(AK.mono) }
                        LabeledContent("Leash") { Text(state.leash).font(AK.mono) }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AK.ink.ignoresSafeArea())
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
            Text("\(n)").font(.footnote.weight(.bold)).foregroundStyle(AK.ink).frame(width: 20, height: 20).background(AK.mint, in: Circle())
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
