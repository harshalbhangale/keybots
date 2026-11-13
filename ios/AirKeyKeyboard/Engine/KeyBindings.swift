import Foundation

/// What a held letter runs (Glyf Keys): the app's Keys screen first
/// (BoundKeys, in the App Group), then any menu binding the keyboard's own
/// settings still carry ("n": "surface:notes"). Read once per showing and
/// kept, because KeyboardView asks on every letter's touch.
enum KeyBindings {
    private static var cached: [String: String]?

    /// Read the map again (the keyboard came up; the app may have changed it).
    static func reload() { cached = nil }

    static func target(for letter: String) -> String? {
        if cached == nil { cached = merged() }
        return cached?[letter.lowercased()]
    }

    private static func merged() -> [String: String] {
        var out = SettingsStore.current.bindings
        for (letter, action) in BoundKeys.current { out[letter.lowercased()] = action.target }
        return out
    }

    /// "tool:wallet" → "wallet": a strip tool a held key opens.
    static func tool(in target: String) -> String? {
        target.hasPrefix("tool:") ? String(target.dropFirst("tool:".count)) : nil
    }

    /// "type:pay " → "pay ": words a held key types.
    static func words(in target: String) -> String? {
        target.hasPrefix("type:") ? String(target.dropFirst("type:".count)) : nil
    }
}
