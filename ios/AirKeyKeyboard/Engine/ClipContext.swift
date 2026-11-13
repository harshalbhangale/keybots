import UIKit

/// Whether a copy is fresh enough to offer in the strip, and whether it was
/// already used or put away: kept by the pasteboard's change count, so the
/// copy itself is never read to decide.
enum ClipContext {
    /// The clipboard panel's "just copied" card. The strip's chip is shorter
    /// lived (StripPolicy.pasteFresh).
    static let freshFor: TimeInterval = 10 * 60
    private static let file = "clip-context.json"

    static func isFresh(now: Date = Date(), within: TimeInterval = freshFor) -> Bool {
        let board = UIPasteboard.general
        let cc = board.changeCount
        var state = AppGroupStore.readJSON(name: file) ?? [:]
        if (state["done"] as? Int) == cc { return false }
        if (state["cc"] as? Int) != cc {
            // A copy we haven't seen before starts its clock now.
            state = ["cc": cc, "seen": now.timeIntervalSince1970, "done": state["done"] ?? -1]
            AppGroupStore.writeJSON(state, name: file)
        }
        let seen = (state["seen"] as? Double) ?? now.timeIntervalSince1970
        return now.timeIntervalSince1970 - seen < within && board.hasStrings
    }

    /// Dismissed or used: never offer this copy again.
    static func markDone() {
        var state = AppGroupStore.readJSON(name: file) ?? [:]
        state["done"] = UIPasteboard.general.changeCount
        AppGroupStore.writeJSON(state, name: file)
    }
}
