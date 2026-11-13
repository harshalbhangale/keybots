import UIKit

/// The keyboard's feel. Each kind of key has its own tap, fired the moment a
/// finger lands, from generators kept warm so there's no lag. iOS lets a
/// keyboard play haptics only with Allow Full Access, and the person can turn
/// them off in Settings; `allowed` carries both, and every call is a no-op
/// without it.
///
///   letters    a light, crisp tick
///   space      a softer, rounder thump
///   delete     a firm click; held, a quick ratchet that gets lighter
///   shift      a medium click; caps lock adds a second click
///   123 / ABC  the selection tick
///   hold       a heavy press, then two soft echoes rising out of it
@MainActor
enum Haptics {
    /// Full Access is on and the person wants haptics.
    static var allowed = false

    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let soft = UIImpactFeedbackGenerator(style: .soft)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private static let selection = UISelectionFeedbackGenerator()
    private static let notice = UINotificationFeedbackGenerator()

    static func warmUp() {
        guard allowed else { return }
        light.prepare()
        soft.prepare()
        rigid.prepare()
        selection.prepare()
    }

    static func letter() { guard allowed else { return }; light.impactOccurred(intensity: 0.6); light.prepare() }
    static func space() { guard allowed else { return }; soft.impactOccurred(intensity: 0.85); soft.prepare() }
    static func delete(repeatCount: Int = 0) {
        guard allowed else { return }
        rigid.impactOccurred(intensity: max(0.3, 0.6 - CGFloat(repeatCount) * 0.03))
        rigid.prepare()
    }
    static func modifier() { guard allowed else { return }; medium.impactOccurred(intensity: 0.75); medium.prepare() }
    static func capsLock() {
        guard allowed else { return }
        later(0.06) { rigid.impactOccurred(intensity: 0.9) }
    }
    static func layer() { guard allowed else { return }; selection.selectionChanged(); selection.prepare() }

    /// A hold that runs something: a heavy press, then two soft echoes.
    static func hold() {
        guard allowed else { return }
        heavy.impactOccurred(intensity: 1)
        later(0.08) { soft.impactOccurred(intensity: 0.7) }
        later(0.16) { soft.impactOccurred(intensity: 0.4) }
    }

    static func success() { guard allowed else { return }; notice.notificationOccurred(.success) }
    static func warning() { guard allowed else { return }; notice.notificationOccurred(.warning) }
    static func error() { guard allowed else { return }; notice.notificationOccurred(.error) }

    private static func later(_ seconds: Double, _ body: @escaping @MainActor () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { MainActor.assumeIsolated { body() } }
    }
}
