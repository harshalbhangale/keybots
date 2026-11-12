import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var server = Settings.serverURL
    @State private var token = Settings.token
    @State private var name = Settings.name
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Settings").font(AK.title(26)).foregroundStyle(AK.bone)
                    Spacer()
                    Button("Done") { save(); dismiss() }.font(.system(size: 15, weight: .semibold)).foregroundStyle(AK.mint)
                }
                Panel {
                    Eyebrow("You")
                    field("Name", $name)
                }
                Panel {
                    Eyebrow("AIRKEY server")
                    field("Address", $server, mono: true)
                    field("Token (optional)", $token, mono: true, secure: true)
                    Text("The keyboard uses the same server.").font(.system(size: 12)).foregroundStyle(AK.faint)
                }
                Panel {
                    Eyebrow("This device")
                    Text("Your owner key lives on this phone and signs approvals after Face ID. Add it to your NEAR account once:").font(.system(size: 13)).foregroundStyle(AK.muted)
                    Text(DeviceKey.publicKey).font(AK.mono).foregroundStyle(AK.bone).textSelection(.enabled)
                    if !DeviceKey.persisted {
                        Text("This build can't save the key in the Keychain, so it lasts only until the app quits.").font(.system(size: 12)).foregroundStyle(AK.amber)
                    }
                    Button(copied ? "Copied" : "Copy key") { UIPasteboard.general.string = DeviceKey.publicKey; copied = true }
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(AK.mint)
                    Text("npm run add-device -- <owner> <key>").font(AK.mono).foregroundStyle(AK.faint)
                }
                if let owner = model.state?.owner {
                    Panel {
                        Eyebrow("Owner")
                        Text(owner).font(AK.mono).foregroundStyle(AK.bone)
                    }
                }
            }
            .padding(AK.gutter)
        }
        .background(AK.ink.ignoresSafeArea())
        .onDisappear { save() }
    }

    private func save() {
        Settings.serverURL = server
        Settings.token = token
        Settings.name = name
        Task { await model.refresh() }
    }

    private func field(_ label: String, _ value: Binding<String>, mono: Bool = false, secure: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 12)).foregroundStyle(AK.muted)
            Group {
                if secure { SecureField("", text: value) } else { TextField("", text: value) }
            }
            .font(mono ? AK.mono : .system(size: 16))
            .foregroundStyle(AK.bone)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(12)
            .background(AK.raised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}
