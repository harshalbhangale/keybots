import QuartzCore
import UIKit

/// The keyboard's feel: one scheme, so every touch says what it did.
///
/// Three rules hold it together. A tap fires the moment the finger lands,
/// never on the lift. Weight follows consequence: a letter is the lightest
/// thing here, and the hold that moves money is the heaviest. And anything
/// that repeats (a held delete, a glide, the cursor) is rate-limited and
/// gets lighter as it gets faster, so it reads as texture and never as a buzz.
///
///   letter        light, crisp                          on touch-down
///   space         soft and round, a little heavier      on touch-down
///   return        medium: the firmest plain key         on touch-down
///   delete        rigid click; held, a ratchet that thins out as it speeds up
///   word delete   one firm rigid tick (a glided word or a correction taken back)
///   shift         a sharp rigid tick
///   caps lock     a second, firmer tick right behind the shift's
///   123 / ABC     the selection tick
///   glide         faint soft ticks as the trail crosses letters, at most 14 a second;
///                 a round settle when the word lands
///   cursor        a selection tick per character moved, at most 40 a second
///   popup         a tick when it opens, a selection tick on each new pick
///   key hold      a heavy press, then two soft echoes rising out of it
///   hold to pay   HoldFeel (Shared): rising ticks, a thud when it fires,
///                 then success, warning or error when the answer is back
///   chip          one soft tap when a money chip appears above the keys
///
/// Everything is a UIFeedbackGenerator made once and kept prepared: no
/// allocation per key, and no Core Haptics engine to start (or to fail) in a
/// keyboard extension. iOS plays a keyboard's haptics only with Allow Full
/// Access, and the person can turn them off in the keyboard's settings;
/// `allowed` carries both, and every call is a no-op without it.
@MainActor
enum Haptics {
    /// Full Access is on and the person wants haptics.
    static var allowed = false {
        didSet { HoldFeel.enabled = allowed }
    }

    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let soft = UIImpactFeedbackGenerator(style: .soft)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private static let selection = UISelectionFeedbackGenerator()
    private static let notice = UINotificationFeedbackGenerator()

    /// When the last glide tick and cursor tick played, to hold their rate.
    private static var glideAt: CFTimeInterval = 0
    private static var cursorAt: CFTimeInterval = 0
    /// The delete that is about to sound took a whole word.
    private static var wordDelete = false

    /// Wakes the Taptic Engine for the generators typing uses, so the first
    /// key is not late. Each tap re-prepares its own generator after it plays.
    static func warmUp() {
        guard allowed else { return }
        light.prepare()
        soft.prepare()
        rigid.prepare()
        medium.prepare()
        selection.prepare()
    }

    // MARK: Keys

    static func letter() { guard allowed else { return }; light.impactOccurred(intensity: 0.62); light.prepare() }
    static func space() { guard allowed else { return }; soft.impactOccurred(intensity: 0.9); soft.prepare() }
    static func ret() { guard allowed else { return }; medium.impactOccurred(intensity: 0.8); medium.prepare() }

    /// Delete. `repeatCount` is 0 for the press and counts up while held:
    /// each repeat is a little lighter, and once the repeat doubles its
    /// speed only every other one sounds, so the ratchet thins out instead
    /// of turning into a buzz. A delete that took a whole word is one firm tick.
    static func delete(repeatCount: Int = 0) {
        guard allowed else { wordDelete = false; return }
        defer { rigid.prepare() }
        if wordDelete {
            wordDelete = false
            rigid.impactOccurred(intensity: 1)
            return
        }
        if repeatCount > 18, repeatCount % 2 == 1 { return }
        rigid.impactOccurred(intensity: max(0.22, 0.62 - CGFloat(repeatCount) * 0.022))
    }

    /// The delete now being handled removed a whole word: its tick is the firm one.
    static func markWordDelete() { wordDelete = true }

    static func shift() { guard allowed else { return }; rigid.impactOccurred(intensity: 0.5); rigid.prepare() }

    /// Caps lock: fired on the second tap's lift, right behind that tap's
    /// own tick, so the pair reads as a double tick.
    static func capsLock() { guard allowed else { return }; rigid.impactOccurred(intensity: 0.95); rigid.prepare() }

    /// A change of layer or panel: 123, ABC, the globe, a tool on the strip.
    static func layer() { guard allowed else { return }; selection.selectionChanged(); selection.prepare() }

    /// A held key that did its second thing (return held for a new line, a menu lifting a card).
    static func modifier() { guard allowed else { return }; medium.impactOccurred(intensity: 0.75); medium.prepare() }

    // MARK: Glide typing

    /// The trail crossed onto another letter.
    static func glideTick() {
        guard allowed else { return }
        let now = CACurrentMediaTime()
        guard now - glideAt >= 0.07 else { return }
        glideAt = now
        soft.impactOccurred(intensity: 0.32)
        soft.prepare()
    }

    /// The glided word landed in the text.
    static func glideLand() { guard allowed else { return }; soft.impactOccurred(intensity: 0.95); soft.prepare() }

    // MARK: Space-bar cursor

    /// The cursor moved by a character.
    static func cursorTick() {
        guard allowed else { return }
        let now = CACurrentMediaTime()
        guard now - cursorAt >= 0.025 else { return }
        cursorAt = now
        selection.selectionChanged()
        selection.prepare()
    }

    // MARK: Long-press popups

    static func popupOpen() { guard allowed else { return }; light.impactOccurred(intensity: 0.9); light.prepare() }
    static func popupMove() { guard allowed else { return }; selection.selectionChanged(); selection.prepare() }

    // MARK: Holds and outcomes

    /// A held key that opens something: a heavy press, then two soft echoes.
    static func hold() {
        guard allowed else { return }
        heavy.impactOccurred(intensity: 1)
        later(0.08) { soft.impactOccurred(intensity: 0.7) }
        later(0.16) { soft.impactOccurred(intensity: 0.4) }
    }

    /// A money chip appeared above the keys.
    static func chip() { guard allowed else { return }; soft.impactOccurred(intensity: 0.6); soft.prepare() }

    static func success() { guard allowed else { return }; notice.notificationOccurred(.success) }
    static func warning() { guard allowed else { return }; notice.notificationOccurred(.warning) }
    static func error() { guard allowed else { return }; notice.notificationOccurred(.error) }

    private static func later(_ seconds: Double, _ body: @escaping @MainActor () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { MainActor.assumeIsolated { body() } }
    }
}
