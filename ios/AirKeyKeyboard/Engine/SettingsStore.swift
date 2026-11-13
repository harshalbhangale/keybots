import Foundation

/// The keyboard's own settings (typing, feel, look, the strip), kept as a
/// JSON file in the App Group so they survive the keyboard process and the
/// app can read them. Changed from the keyboard's Settings screen.
struct KeyboardSettings: Codable, Equatable {
    /// Bumped when defaults change; load() migrates older files additively.
    var schemaVersion: Int? = 1
    var haptics: Bool = true
    var keyClicks: Bool = true
    var numberRow: Bool = false
    /// The letters' layout (LetterLayout): "qwerty", "qwertz", "azerty" or
    /// "colemak"; nil, or an id this build doesn't know, is QWERTY.
    var keyLayout: String? = nil
    /// A comma key left of the space bar, and a period key right of it, on
    /// the letters of a text field. Nil reads as off.
    var commaKey: Bool? = nil
    var periodKey: Bool? = nil
    var autocorrect: Bool = true
    var autocapitalize: Bool = true
    var periodShortcut: Bool = true
    var candidates: Bool = true
    /// Vocabulary packs switched on (ids from packs.json). Nil until picked:
    /// phones set to India start with Hinglish.
    var vocabPacks: [String]? = nil
    /// Learn words from typing (on device). Off = nothing new is learned.
    var vocabLearning: Bool? = true
    /// off | left | right
    var oneHanded: String = "off"
    /// Tool ids on the strip, in order; missing ids are appended on load.
    var toolbarOrder: [String] = Toolbar.defaultOrder
    /// The menu's tile order, as the person arranged it (nil = default).
    var menuOrder: [String]? = nil
    var toolbarHidden: [String] = []
    /// Key letter (lowercase) → what holding it opens ("surface:notes").
    var bindings: [String: String] = KeyboardSettings.defaultBindings
    /// Whether a correction is applied on the space, or only offered in the
    /// strip. Off is the "don't change my words" setting.
    var autocorrectApply: Bool? = true
    /// Glide typing: a finger sliding over the letters types the word.
    var glideTyping: Bool? = true
    /// Key style: "glass" (Liquid Glass keys, the default) | "site" (flat
    /// solid keys) | "classic" | "glow".
    var keyTheme: String? = "glass"
    /// A keyboard theme's id from KeyboardThemes ("typewriter", …); "" or
    /// missing is the plain look.
    var skin: String? = ""
    /// Whether a theme with a sound pack plays it (nil reads as on).
    var skinSound: Bool? = true
    /// Borders around keys.
    var keyBorders: Bool? = false
    /// 0…0.6 dim for painted themes.
    var themeBrightness: Double? = 0
    /// The currency the strip converts money into ("INR", "USD", …), or
    /// "auto" to follow where the phone is.
    var moneyCurrency: String? = "auto"
    /// Keep what you copy in the keyboard's clipboard history.
    var clipboardHistory: Bool? = true
    /// Take every copy into the clipboard, rather than waiting to be handed
    /// one by the Paste button. Each read raises iOS's "Allow Paste?" until
    /// the person allows pasting from other apps in Settings.
    var clipboardCaptureAll: Bool? = false
    /// Recent screenshots in the clipboard, beside what you copied (needs
    /// photo library access, which only an app can ask for).
    var clipboardScreenshots: Bool? = false
    /// Two-letter region, for dates, numbers and money; nil follows the phone.
    var region: String?

    /// Hold N to open your notes and details. Nothing else is bound: a held
    /// letter shows its accents.
    static let defaultBindings: [String: String] = [
        "n": "surface:notes",
    ]

    enum Toolbar {
        /// The strip: AIRKEY's wallet and copied-text check first, then the
        /// tools the keys cannot reach. The emoji key is in the bottom row.
        static let defaultOrder = ["wallet", "check", "clipboard", "notes"]

        /// Tools that were renamed, so a saved strip keeps its place.
        static let retired: [String: String] = ["vault": "notes"]

        /// The tool a saved id stands for now.
        static func canonical(_ id: String) -> String { retired[id] ?? id }
    }

    /// The tools on the strip, in its order.
    var stripTools: [String] {
        var out: [String] = []
        for id in toolbarOrder where !toolbarHidden.contains(id) {
            let tool = Toolbar.canonical(id)
            if !out.contains(tool) { out.append(tool) }
        }
        return out
    }
}

enum SettingsStore {
    static let fileName = "keyboard-settings.json"
    static let changedNote = Notification.Name("airkey.settings.changed")

    private static var cached: KeyboardSettings?

    static var current: KeyboardSettings {
        if let cached { return cached }
        let loaded = load()
        cached = loaded
        return loaded
    }

    static func load() -> KeyboardSettings {
        guard let dir = AppGroupStore.bridgeDir,
              let data = try? Data(contentsOf: dir.appendingPathComponent(fileName)),
              let s = try? JSONDecoder().decode(KeyboardSettings.self, from: data)
        else { return KeyboardSettings() }
        return migrated(s)
    }

    /// Additive migrations: new strip tools appear even for old files.
    static func migrated(_ old: KeyboardSettings) -> KeyboardSettings {
        var s = old
        for id in KeyboardSettings.Toolbar.defaultOrder where !s.toolbarOrder.contains(id) {
            s.toolbarOrder.append(id)
        }
        s.toolbarOrder = s.toolbarOrder.map(KeyboardSettings.Toolbar.canonical)
        return s
    }

    static func save(_ s: KeyboardSettings) {
        cached = s
        guard let dir = AppGroupStore.bridgeDir,
              let data = try? JSONEncoder().encode(s) else { return }
        let url = dir.appendingPathComponent(fileName)
        try? data.write(to: url, options: .atomic)
        // Our own write is not "someone else changed it".
        loadedStamp = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        NotificationCenter.default.post(name: changedNote, object: nil)
    }

    static func update(_ mutate: (inout KeyboardSettings) -> Void) {
        reloadIfChanged()
        var s = current
        mutate(&s)
        save(s)
    }

    /// Re-read from disk next time.
    static func invalidate() { cached = nil }

    private static var loadedStamp: Date?

    /// Re-reads the file when it changed since the last read: a stat, not a
    /// decode, so it is cheap enough to ask on every text change.
    @discardableResult
    static func reloadIfChanged() -> Bool {
        guard let dir = AppGroupStore.bridgeDir else { return false }
        let path = dir.appendingPathComponent(fileName).path
        let stamp = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
        guard stamp != loadedStamp else { return false }
        loadedStamp = stamp
        cached = nil
        NotificationCenter.default.post(name: changedNote, object: nil)
        return true
    }
}
