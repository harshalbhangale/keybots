import UIKit

/// What autocorrect must never touch, because it could be money or a name:
/// your contacts, NEAR accounts (anything with a dot in it), token symbols,
/// $tickers, numbers, AIRKEY's own command words, and words you taught the
/// keyboard by undoing a correction. After "pay" or "send" the next word is
/// a name or an account, so it is left alone and the strip offers your
/// contacts; after "to", a word that starts like a contact is.
enum Protections {
    /// Words that are part of AIRKEY's own commands; never "fixed".
    static let commandWords: Set<String> = [
        "pay", "send", "give", "transfer", "tip", "swap", "buy", "sell", "near", "usdc", "usdt",
        "airkey", "leash", "memo", "re",
    ]
    /// After these words the next one is a name or an account.
    static let payVerbs: Set<String> = ["pay", "send", "give", "transfer", "tip"]
    /// After these it may be a name ("send 2 to harshal"), or any word
    /// ("going to bed"): only what starts like a contact counts as one.
    static let maybeName: Set<String> = ["to"]

    /// True for a word autocorrect must leave exactly as typed.
    static func isProtected(_ word: String, after previous: String?) -> Bool {
        let lower = word.lowercased()
        guard !lower.isEmpty else { return true }
        // Money and addresses: $near, 0.5, harshal.near, @handle, #tag, a_b.
        if word.contains(where: { !$0.isLetter && $0 != "'" && $0 != "’" }) { return true }
        // iPhone, NEAR, USDC: capitals past the first letter were typed on purpose.
        if word.dropFirst().contains(where: \.isUppercase) { return true }
        if let previous, payVerbs.contains(previous.lowercased()) { return true }
        if let previous, maybeName.contains(previous.lowercased()), lower.count >= 2,
           Contacts.names.contains(where: { $0.hasPrefix(lower) }) { return true }
        return commandWords.contains(lower)
            || Contacts.names.contains(lower)
            || Tokens.known.contains(word.uppercased())
            || learned.contains(lower)
    }

    /// Whether the run being typed (everything since the last space) is an
    /// account or an amount: a dot inside it ("harshal.ne", "0.2") or a $.
    /// iOS and the word tracker split a word at a dot, so the part after it
    /// would otherwise look like a word of its own.
    static func insideAccount(before: String?) -> Bool {
        guard let before, !before.isEmpty else { return false }
        let run = before.split(omittingEmptySubsequences: false, whereSeparator: { $0.isWhitespace }).last ?? ""
        if run.hasPrefix("$") { return true }
        guard let dot = run.firstIndex(of: ".") else { return false }
        // A dot with something after it: "harshal.ne", "0.25". A dot at the
        // very end is a full stop until more is typed.
        return run.index(after: dot) < run.endIndex
    }

    /// After "pay" or "send": the contacts whose names start with what has
    /// been typed of the next word (all of them, before a letter is typed).
    /// After "to", only once what is typed matches a contact.
    static func contacts(typed word: String, after previous: String?) -> [String] {
        guard let previous else { return [] }
        let before = previous.lowercased()
        guard payVerbs.contains(before) || (maybeName.contains(before) && word.count >= 2) else { return [] }
        let lower = word.lowercased()
        return Contacts.names
            .filter { $0.hasPrefix(lower) && $0 != lower && !$0.contains(".") }
            .sorted()
    }

    // MARK: Learned words

    private static let learnedKey = "learnedWords"
    static var learned: Set<String> { Set(Settings.store.stringArray(forKey: learnedKey) ?? []) }

    /// Remember a word so it's never corrected again (on undo).
    static func learn(_ word: String) {
        let lower = word.lowercased()
        guard lower.count > 1, !lower.contains(" ") else { return }
        var words = Settings.store.stringArray(forKey: learnedKey) ?? []
        guard !words.contains(lower) else { return }
        words.append(lower)
        Settings.store.set(Array(words.suffix(500)), forKey: learnedKey)
    }
}

/// The paste guard: an address that lands in the message all at once (pasted
/// or dropped in, not typed letter by letter) and isn't yours, in your vault
/// or one of your contacts' gets a warning. Address poisoning slips in a
/// lookalike that shares the first and last few characters with one you've
/// used, so the warning shows both ends and asks for every character.
enum PasteGuard {
    private static let patterns: [NSRegularExpression] = [
        // NEAR names (harshal.near, pay.airkey-harshal.testnet), not inside a link.
        #"(?<![\w.@/-])(?:[a-z0-9_-]+\.)+(?:near|testnet)(?![\w.-])"#,
        // NEAR implicit accounts.
        #"(?<![\w/])[0-9a-f]{64}(?!\w)"#,
        // EVM.
        #"(?<![\w/])0x[a-fA-F0-9]{40}(?!\w)"#,
        // Solana and other base58.
        #"(?<![\w/])[1-9A-HJ-NP-Za-km-z]{32,44}(?!\w)"#,
    ].compactMap { try? NSRegularExpression(pattern: $0) }

    static func addresses(in text: String) -> [String] {
        let range = NSRange(text.startIndex..., in: text)
        var found: [String] = []
        for p in patterns {
            for m in p.matches(in: text, range: range) {
                guard let r = Range(m.range, in: text) else { continue }
                let a = String(text[r])
                if !found.contains(a) { found.append(a) }
            }
        }
        return found
    }

    /// Yours, your vault's and your contacts', lower case.
    static var known: Set<String> {
        var k = Set(Vault.all.map { $0.value.lowercased() })
        k.formUnion(Contacts.accounts)
        return k
    }

    /// The first address in `new` that wasn't in `old`, arrived in one go,
    /// and isn't known. A typed address grows a letter at a time, so it never
    /// shows up whole in one change.
    static func stranger(old: String, new: String, known: Set<String>) -> String? {
        let before = Set(addresses(in: old))
        let grew = new.count - old.count
        for a in addresses(in: new) where !before.contains(a) && !known.contains(a.lowercased()) {
            if grew >= a.count - 2 { return a }
        }
        return nil
    }

    /// "0x1234…cdef": both ends, where lookalikes try to match.
    static func short(_ a: String) -> String { a.count > 16 ? "\(a.prefix(6))…\(a.suffix(4))" : a }
}
