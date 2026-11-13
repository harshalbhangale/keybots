import Foundation

/// Glyf Keys: hold a letter and it runs what it is bound to. P starts a
/// payment, V opens the vault, C the clipboard, S a swap. Kept in the App
/// Group so the app's Keys screen and the keyboard read the same map.
enum BoundKeys {
    enum Action: String, Codable, CaseIterable, Identifiable {
        case pay, swap, vault, clipboard, check, notes

        var id: String { rawValue }

        var title: String {
            switch self {
            case .pay: "Pay"
            case .swap: "Swap"
            case .vault: "Vault"
            case .clipboard: "Clipboard"
            case .check: "Check"
            case .notes: "Notes"
            }
        }

        /// What it does, in a few words.
        var detail: String {
            switch self {
            case .pay: "Types pay, then offers your contacts"
            case .swap: "Types swap"
            case .vault: "Your NEAR account and addresses"
            case .clipboard: "What you copied"
            case .check: "Checks a copied message for scams"
            case .notes: "Your notes and shorthand"
            }
        }

        var symbol: String {
            switch self {
            case .pay: "arrow.up.right"
            case .swap: "arrow.left.arrow.right"
            case .vault: "wallet.bifold"
            case .clipboard: "doc.on.clipboard"
            case .check: "checkmark.shield"
            case .notes: "note.text"
            }
        }

        /// What the keyboard runs: words it types ("type:pay ") or one of the
        /// strip's tools it opens ("tool:wallet").
        var target: String {
            switch self {
            case .pay: "type:pay "
            case .swap: "type:swap "
            case .vault: "tool:wallet"
            case .clipboard: "tool:clipboard"
            case .check: "tool:check"
            case .notes: "tool:notes"
            }
        }
    }

    static let defaults: [String: Action] = ["p": .pay, "v": .vault, "c": .clipboard, "s": .swap]

    private static let key = "boundKeys"

    /// Letter (lowercase) → action. Nothing saved yet is the defaults; an
    /// empty map saved on purpose stays empty.
    static var current: [String: Action] {
        guard let data = Settings.store.data(forKey: key),
              let raw = try? JSONDecoder().decode([String: String].self, from: data) else { return defaults }
        // An action this build doesn't know is left out, never guessed at.
        return raw.compactMapValues(Action.init(rawValue:))
    }

    static func save(_ map: [String: Action]) {
        let raw = map.mapValues(\.rawValue)
        Settings.store.set(try? JSONEncoder().encode(raw), forKey: key)
    }

    static func reset() { Settings.store.removeObject(forKey: key) }

    /// Letters in the order they sit on the keys (Q first, M last).
    static func keyboardOrder(_ letters: some Sequence<String>) -> [String] {
        let rows = Array("qwertyuiopasdfghjklzxcvbnm").map(String.init)
        return letters.sorted { (rows.firstIndex(of: $0) ?? 99) < (rows.firstIndex(of: $1) ?? 99) }
    }
}
