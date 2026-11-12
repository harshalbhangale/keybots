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

    /// What was typed through this keyboard. iOS only hands a keyboard the
    /// text back to the last sentence break ("pay harshal 0.1" arrives as "1"),
    /// so the keyboard keeps its own copy and checks it against what iOS shows.
    @ObservationIgnored private var typed = ""

    @ObservationIgnored var proxy: () -> UITextDocumentProxy? = { nil }
    @ObservationIgnored var advance: () -> Void = {}
    @ObservationIgnored var hasFullAccess: () -> Bool = { false }

    // MARK: typing

    func type(_ s: String) {
        let out = shift || capsLock ? s.uppercased() : s
        insert(out)
        if shift && !capsLock { shift = false }
        UIDevice.current.playInputClick()
        refreshContext()
    }

    func delete() {
        proxy()?.deleteBackward()
        if !typed.isEmpty { typed.removeLast() }
        UIDevice.current.playInputClick()
        refreshContext()
    }

    private func insert(_ s: String) {
        proxy()?.insertText(s)
        typed += s
    }

    func space() {
        // Double space after a word: ". " like the system keyboard.
        if let before = proxy()?.documentContextBeforeInput, before.hasSuffix(" "), let last = before.dropLast().last, last.isLetter || last.isNumber {
            proxy()?.deleteBackward()
            if !typed.isEmpty { typed.removeLast() }
            insert(". ")
        } else {
            insert(" ")
        }
        UIDevice.current.playInputClick()
        refreshContext()
    }

    func returnKey() {
        insert("\n")
        refreshContext()
    }

    func toggleShift() {
        if shift { capsLock.toggle(); shift = capsLock } else { shift = true }
    }

    /// The whole message being written: our own copy before the cursor, plus
    /// whatever iOS shows after it.
    private var fieldText: String {
        typed + (proxy()?.documentContextAfterInput ?? "")
    }

    /// Called after every keystroke and whenever the host app changes the text.
    func refreshContext() {
        let p = proxy()
        let before = p?.documentContextBeforeInput ?? ""
        // Keep our copy honest: empty when the field is (sent or cleared), and
        // replaced by what iOS shows when the two disagree (pasted, cursor moved).
        if before.isEmpty { typed = "" } else if !typed.hasSuffix(before) { typed = before }

        if layer == .letters, !capsLock {
            let sentences = (p?.autocapitalizationType ?? .sentences) == .sentences
            shift = sentences && (before.isEmpty || before.hasSuffix(". ") || before.hasSuffix("? ") || before.hasSuffix("! ") || before.hasSuffix("\n"))
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
                if source == "typed", r.signal == .allow || r.signal == .warn || r.signal == .quote { clearCommand(text) }
            } catch {
                notice = error.localizedDescription
            }
            running = nil
        }
    }

    /// The command was for the agent, not for the person in the chat: once it
    /// has run, take it out of the message box so it can't be sent by mistake.
    /// Only when the box still holds exactly what was run; a blocked command
    /// stays so it can be fixed.
    private func clearCommand(_ text: String) {
        let p = proxy()
        guard typed.trimmingCharacters(in: .whitespacesAndNewlines) == text, (p?.documentContextAfterInput ?? "").isEmpty else { return }
        for _ in 0..<typed.count { p?.deleteBackward() }
        typed = ""
        refreshContext()
    }

    /// Put the receipt into the chat, so the other person sees it too.
    func insertReceipt() {
        guard let r = result else { return }
        var line = "AIRKEY · \(r.signal.word.capitalized): \(r.message)"
        if let tx = r.tx { line += " \(tx.url)" }
        insert(line)
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
