import UIKit

/// Autocorrect and word suggestions, worked out on the phone with Apple's own
/// spell checker. Anything that could be money or a name is left exactly as
/// typed: contacts, NEAR accounts, token symbols, $tickers, numbers, and words
/// you've taught it by undoing a correction.
@MainActor
final class Words {
    struct Suggestion: Equatable, Hashable {
        enum Kind { case typed, correction, word, contact }
        let text: String
        let kind: Kind
    }

    private let checker = UITextChecker()
    private let language = UITextChecker.availableLanguages.first { $0.hasPrefix("en_US") }
        ?? UITextChecker.availableLanguages.first { $0.hasPrefix("en") } ?? "en_US"
    /// Text replacements from iOS Settings ("omw" → "On my way!"), lowercased input → output.
    private var replacements: [String: String] = [:]
    /// Names iOS knows about (your contacts' names), lowercased.
    private var lexicon: Set<String> = []

    /// Words that are part of AIRKEY's own commands; never "fixed".
    private static let commandWords: Set<String> = [
        "pay", "send", "give", "transfer", "tip", "swap", "buy", "sell", "near", "usdc", "usdt",
        "airkey", "leash", "memo", "re",
    ]
    /// After these words the next one is a name or an account.
    private static let nameBefore: Set<String> = ["pay", "send", "give", "transfer", "tip", "to"]
    /// Common words that need an apostrophe or a capital and are too short for the checker.
    private static let fixed: [String: String] = [
        "i": "I", "im": "I'm", "ive": "I've", "dont": "don't", "cant": "can't",
        "wont": "won't", "didnt": "didn't", "doesnt": "doesn't", "isnt": "isn't", "wasnt": "wasn't",
        "arent": "aren't", "couldnt": "couldn't", "shouldnt": "shouldn't", "wouldnt": "wouldn't",
        "thats": "that's", "whats": "what's", "theyre": "they're", "youre": "you're", "hes": "he's",
        "shes": "she's", "theres": "there's",
    ]

    /// Read the text replacements and names iOS hands a keyboard, as
    /// (what you type, what goes in) pairs.
    func load(_ entries: [(input: String, output: String)]) {
        for e in entries {
            let input = e.input.lowercased()
            if e.output.lowercased() == input {
                lexicon.insert(input)
            } else if !input.contains(" ") {
                replacements[input] = e.output
            }
        }
    }

    // MARK: rules

    /// True for anything autocorrect must not touch.
    func isProtected(_ word: String, after previous: String? = nil) -> Bool {
        let lower = word.lowercased()
        if lower.count < 2 && Self.fixed[lower] == nil { return true }
        // Money and addresses: $near, 0.5, harshal.near, @handle, #tag, a_b, x-y.
        if word.contains(where: { !$0.isLetter && $0 != "'" }) { return true }
        // iPhone, NEAR, USDC: capitals past the first letter mean it was typed on purpose.
        if word.dropFirst().contains(where: \.isUppercase) { return true }
        if let previous, Self.nameBefore.contains(previous.lowercased()) { return true }
        return Self.commandWords.contains(lower)
            || Contacts.names.contains(lower)
            || Tokens.known.contains(word.uppercased())
            || Self.learned.contains(lower)
            || lexicon.contains(lower)
    }

    /// The word autocorrect would put in place of this one, or nil to leave it.
    func correction(for word: String, after previous: String? = nil) -> String? {
        let lower = word.lowercased()
        if let r = replacements[lower] { return r }
        if Self.learned.contains(lower) { return nil }
        if let f = Self.fixed[lower] { return matchCase(f, like: word, keepCapitals: f.first?.isUppercase == true) }
        guard !isProtected(word, after: previous), isMisspelled(word) else { return nil }
        let limit = lower.count <= 4 ? 1 : 2
        guard let best = guesses(word).first(where: { Self.distance(lower, $0.lowercased()) <= limit && !$0.contains(" ") }) else { return nil }
        return matchCase(best, like: word)
    }

    /// Up to three choices for the bar while a word is being typed.
    func suggestions(for word: String, after previous: String?) -> [Suggestion] {
        guard !word.isEmpty else { return [] }
        let lower = word.lowercased()
        var out: [Suggestion] = []
        func add(_ text: String, _ kind: Suggestion.Kind) {
            guard out.count < 3, !out.contains(where: { $0.text.lowercased() == text.lowercased() }) else { return }
            out.append(Suggestion(text: text, kind: kind))
        }

        // After "pay" or "to", offer the people in your contacts.
        if let previous, Self.nameBefore.contains(previous.lowercased()) {
            let names = Contacts.names.filter { $0.hasPrefix(lower) && $0 != lower && !$0.contains(".") }.sorted()
            if !names.isEmpty {
                add(word, .typed)
                for n in names { add(n, .contact) }
                return out
            }
        }
        guard !word.contains(where: { !$0.isLetter && $0 != "'" }) else { return [] }

        let fix = correction(for: word, after: previous)
        add(word, .typed)
        if let fix { add(fix, .correction) }
        for c in completions(word) where c.lowercased() != lower { add(matchCase(c, like: word), .word) }
        if isMisspelled(word) { for g in guesses(word) { add(matchCase(g, like: word), .word) } }
        // A lone "typed" slot says nothing new.
        return out.count > 1 ? out : []
    }

    // MARK: learning

    private static let learnedKey = "learnedWords"
    static var learned: Set<String> { Set(Settings.store.stringArray(forKey: learnedKey) ?? []) }

    /// Remember a word so it's never corrected again (on undo, or picked as typed).
    static func learn(_ word: String) {
        let lower = word.lowercased()
        guard lower.count > 1, !lower.contains(" ") else { return }
        var words = Settings.store.stringArray(forKey: learnedKey) ?? []
        guard !words.contains(lower) else { return }
        words.append(lower)
        Settings.store.set(Array(words.suffix(500)), forKey: learnedKey)
        UITextChecker.learnWord(lower)
    }

    // MARK: spell checker

    private func isMisspelled(_ word: String) -> Bool {
        let r = checker.rangeOfMisspelledWord(in: word, range: NSRange(location: 0, length: (word as NSString).length), startingAt: 0, wrap: false, language: language)
        return r.location != NSNotFound
    }

    private func guesses(_ word: String) -> [String] {
        checker.guesses(forWordRange: NSRange(location: 0, length: (word as NSString).length), in: word, language: language) ?? []
    }

    private func completions(_ word: String) -> [String] {
        checker.completions(forPartialWordRange: NSRange(location: 0, length: (word as NSString).length), in: word, language: language) ?? []
    }

    /// "Teh" → "The", "teh" → "the".
    private func matchCase(_ s: String, like word: String, keepCapitals: Bool = false) -> String {
        guard !keepCapitals else { return s }
        if word.first?.isUppercase == true { return s.prefix(1).uppercased() + s.dropFirst() }
        return s
    }

    /// Edits between two words, counting a swap of neighbours as one ("teh" → "the").
    static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var d = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { d[i][0] = i }
        for j in 0...b.count { d[0][j] = j }
        for i in 1...a.count {
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    d[i][j] = min(d[i][j], d[i - 2][j - 2] + 1)
                }
            }
        }
        return d[a.count][b.count]
    }
}
