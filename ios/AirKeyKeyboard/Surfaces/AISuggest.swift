import Foundation
import QuartzCore

/// The smart chip's AI side: once typing has paused, ask the server for the
/// one thing the AI could do with what's typed ("Tidy this up", "AI
/// answer", "Write it for me"). It only ever answers for exactly the text
/// it asked about, and the keyboard only shows it when no other chip and no
/// money strip has the strip: money always wins.
final class AISuggest {

    /// A suggestion landed for the text that is still in the field.
    var onReady: (() -> Void)?

    private var text = ""
    private var suggestion: AIClient.Suggestion?
    private var work: DispatchWorkItem?
    private var task: Task<Void, Never>?
    /// After a ✕ the chip rests for a while.
    private var restUntil: CFTimeInterval = 0

    /// The chip for `raw`, if one is known. When it isn't, and `allowed`,
    /// the server is asked after a pause and `onReady` says when it lands.
    func chip(for raw: String, allowed: Bool) -> AIClient.Suggestion? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard allowed, t.count >= 8, t.count <= 600, t.split(separator: " ").count >= 3,
              CACurrentMediaTime() > restUntil else {
            cancel()
            return nil
        }
        if t == text { return suggestion }
        cancel()
        text = t
        let work = DispatchWorkItem { [weak self] in
            self?.task = Task { [weak self] in
                let found = try? await AIClient().suggest(text: t)
                guard let self, self.text == t, let found else { return }
                self.suggestion = found
                self.onReady?()
            }
        }
        self.work = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: work)
        return nil
    }

    /// The chip that says `label` was tapped: what to run.
    func take(_ label: String) -> AIClient.Suggestion? {
        guard let s = suggestion, s.label == label else { return nil }
        cancel()
        return s
    }

    /// ✕ on the chip that says `label`: it rests for two minutes.
    func dismissed(_ label: String) {
        guard suggestion?.label == label else { return }
        restUntil = CACurrentMediaTime() + 120
        cancel()
    }

    func cancel() {
        work?.cancel()
        work = nil
        task?.cancel()
        task = nil
        text = ""
        suggestion = nil
    }
}
