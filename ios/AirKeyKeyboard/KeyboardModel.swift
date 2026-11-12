import Observation
import UIKit

@Observable
@MainActor
final class KeyboardModel {
    enum Layer { case letters, numbers, symbols }

    var layer: Layer = .letters
    var shift = false
    var capsLock = false
    var needsGlobe = true
    var returnLabel = "return"
    /// What the words in the field would do, read as you type.
    var intent: Intent?
    var running: String?  // "typed" or "pasted" while waiting
    var result: Receipt?
    var notice: String?

    @ObservationIgnored var proxy: () -> UITextDocumentProxy? = { nil }
    @ObservationIgnored var advance: () -> Void = {}
    @ObservationIgnored var hasFullAccess: () -> Bool = { false }

    // MARK: typing

    func type(_ s: String) {
        let out = shift || capsLock ? s.uppercased() : s
        proxy()?.insertText(out)
        if shift && !capsLock { shift = false }
        UIDevice.current.playInputClick()
        refreshContext()
    }

    func delete() {
        proxy()?.deleteBackward()
        UIDevice.current.playInputClick()
        refreshContext()
    }

    func space() {
        // Double space after a word: ". " like the system keyboard.
        if let before = proxy()?.documentContextBeforeInput, before.hasSuffix(" "), let last = before.dropLast().last, last.isLetter || last.isNumber {
            proxy()?.deleteBackward()
            proxy()?.insertText(". ")
        } else {
            proxy()?.insertText(" ")
        }
        UIDevice.current.playInputClick()
        refreshContext()
    }

    func returnKey() {
        proxy()?.insertText("\n")
        refreshContext()
    }

    func toggleShift() {
        if shift { capsLock.toggle(); shift = capsLock } else { shift = true }
    }

    /// The text in the field, as far as the host app lets a keyboard see it.
    private var fieldText: String {
        let p = proxy()
        return (p?.documentContextBeforeInput ?? "") + (p?.documentContextAfterInput ?? "")
    }

    /// Called after every keystroke and whenever the host app changes the text.
    func refreshContext() {
        let before = proxy()?.documentContextBeforeInput ?? ""
        if layer == .letters, !capsLock {
            shift = before.isEmpty || before.hasSuffix(". ") || before.hasSuffix("? ") || before.hasSuffix("! ") || before.hasSuffix("\n")
        }
        intent = Intent.read(fieldText)
        returnLabel = switch proxy()?.returnKeyType {
        case .send: "send"
        case .go: "go"
        case .search, .google, .yahoo: "search"
        case .done: "done"
        case .next: "next"
        case .join: "join"
        default: "return"
        }
    }

    // MARK: agents

    /// The text in the field: what you typed. Goes to the trusted Payment Agent.
    func runTyped() {
        let text = fieldText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { notice = "Type something first, like “pay harshal 0.2 for dinner”."; return }
        send(text, source: "typed")
    }

    /// What's on the clipboard: someone else's words. Goes to the untrusted Inbox Agent.
    func runPasted() {
        guard hasFullAccess() else { notice = "Turn on Allow Full Access for AIRKEY to check what you copied."; return }
        guard let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            notice = "Copy a message first, then tap Check."
            return
        }
        send(text, source: "pasted")
    }

    private func send(_ text: String, source: String) {
        guard hasFullAccess() else { notice = "Turn on Allow Full Access for AIRKEY so your agents can reach the server."; return }
        notice = nil
        result = nil
        running = source
        Task {
            do {
                let r = try await API().command(text, source: source)
                result = r
                feedback(for: r.signal)
            } catch {
                notice = error.localizedDescription
            }
            running = nil
        }
    }

    /// Put the receipt into the chat, so the other person sees it too.
    func insertReceipt() {
        guard let r = result else { return }
        var line = "AIRKEY · \(r.signal.word.capitalized): \(r.message)"
        if let tx = r.tx { line += " \(tx.url)" }
        proxy()?.insertText(line)
        result = nil
        refreshContext()
    }

    func dismissResult() { result = nil; notice = nil }

    private func feedback(for signal: Signal) {
        let gen = UINotificationFeedbackGenerator()
        switch signal {
        case .allow: gen.notificationOccurred(.success)
        case .warn: gen.notificationOccurred(.warning)
        case .block: gen.notificationOccurred(.error)
        case .quote: UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .neutral: break
        }
    }
}
