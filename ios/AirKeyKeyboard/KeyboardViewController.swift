import SwiftUI
import UIKit

/// Hosts the SwiftUI keyboard. The keyboard never holds a key and never signs:
/// it sends your words to the AIRKEY server, whose agents ask the leash.
final class KeyboardViewController: UIInputViewController {
    private var host: UIHostingController<KeyboardView>?
    private let model = KeyboardModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        model.proxy = { [weak self] in self?.textDocumentProxy }
        model.advance = { [weak self] in self?.advanceToNextInputMode() }
        model.hasFullAccess = { [weak self] in self?.hasFullAccess ?? false }
        let host = UIHostingController(rootView: KeyboardView(model: model))
        host.view.backgroundColor = .clear
        host.sizingOptions = [.intrinsicContentSize]
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
        self.host = host
        model.needsGlobe = needsInputModeSwitchKey
        watch()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        model.needsGlobe = needsInputModeSwitchKey
    }

    override func textDidChange(_ textInput: UITextInput?) {
        model.refreshContext()
    }

    override func selectionDidChange(_ textInput: UITextInput?) {
        model.refreshContext()
    }

    // Some apps change the text without telling the keyboard (a paste from the
    // menu, a message sent). Look again a few times a second while it's on screen.
    private var watcher: Task<Void, Never>?

    private func watch() {
        guard watcher == nil else { return }
        watcher = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(400))
                guard let self else { return }
                if self.view.window != nil { self.model.refreshContext() }
            }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        model.refreshContext()
        model.refreshTokens()
        watch()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        watcher?.cancel()
        watcher = nil
    }
}
