import Foundation

/// Things you share often (your NEAR account, an EVM address, a UPI ID),
/// kept in the App Group so the keyboard can put one in a chat with a tap.
/// Only things that are safe to share: the vault turns away anything that
/// looks like a private key or a recovery phrase.
enum Vault {
    struct Item: Codable, Identifiable, Hashable {
        var id = UUID()
        var label: String
        var value: String
    }

    private static let key = "vaultItems"
    private static let ownerKey = "ownerAccount"
    private static let ownerID = UUID(uuidString: "00000000-0000-0000-0000-00000000a1c0")!

    /// Your NEAR account, from the server's state.
    static var owner: String? { Settings.store.string(forKey: ownerKey) }
    static func saveOwner(_ account: String) { Settings.store.set(account, forKey: ownerKey) }

    /// What you added yourself, in the order you added it.
    static var items: [Item] {
        guard let data = Settings.store.data(forKey: key), let list = try? JSONDecoder().decode([Item].self, from: data) else { return [] }
        return list
    }

    static func save(_ items: [Item], sync: Bool = true) {
        Settings.store.set(try? JSONEncoder().encode(items), forKey: key)
        // Free signing has no App Group, so the keyboard reads the vault from the server.
        if sync { Task { try? await API().saveVault(items) } }
    }

    /// Fetch the vault the app saved on the server, and keep it here.
    static func pull() async {
        guard let list = try? await API().vault() else { return }
        save(list, sync: false)
    }

    /// Everything the keyboard offers: your NEAR account first, then what you saved.
    static var all: [Item] {
        (owner.map { [Item(id: ownerID, label: "My NEAR", value: $0)] } ?? []) + items
    }

    /// Why a value can't go in the vault, or nil when it can.
    static func problem(with value: String) -> String? {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if v.isEmpty { return "Add the address or ID to share." }
        let words = v.split(whereSeparator: \.isWhitespace)
        if words.count >= 12, words.allSatisfy({ $0.allSatisfy(\.isLetter) }) {
            return "That looks like a recovery phrase. Never put one in a keyboard."
        }
        // NEAR keys are "ed25519:<base58>"; a secret one is much longer than a public one.
        if let r = v.range(of: "ed25519:"), v[r.upperBound...].count > 60 {
            return "That looks like a private key. Only add things that are safe to share."
        }
        let hex = v.hasPrefix("0x") ? String(v.dropFirst(2)) : v
        if hex.count == 64, hex.allSatisfy(\.isHexDigit) {
            return "That looks like a private key. Only add things that are safe to share."
        }
        return nil
    }
}
