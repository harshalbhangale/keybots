import Observation
import SwiftUI

/// One call's way to a trade: review it, hold to confirm, the leash contract
/// decides, the receipt. Nothing trades until the hold completes, and one
/// review is confirmed at most once: a second press sends nothing.
@Observable
@MainActor
final class JourneyModel {
    enum Phase: Equatable {
        case reviewing
        case review
        case sending
        case receipt
        case expired
        case failed(String)
        /// A confirm was sent but its answer was lost: the trade may or may not have gone through.
        case uncertain(String)
    }

    /// What is being reviewed: a feed post (its id) or a copied call (its text).
    let callId: String?
    let text: String?
    /// The post as the feed showed it, when the journey began from one.
    let post: KolCall?

    var phase: Phase = .reviewing
    var review: TradeReview?
    var receipt: TradeReceipt?
    /// The size picked under the card, in dollars.
    var usd = 1
    /// One line under the hold ("Already sending this trade.").
    var note: String?
    /// The clock the countdown reads; ticks once a second while a review is open.
    var now = Date()

    @ObservationIgnored private var clock: Task<Void, Never>?
    @ObservationIgnored private var asking: Task<Void, Never>?
    /// The review ids already sent: a second confirm of one never leaves the phone.
    @ObservationIgnored private var sent: Set<String> = []
    /// The last review sent: "Check status" asks the server about this one, never a new one.
    @ObservationIgnored private var lastSent: String?

    init(callId: String?, text: String?, post: KolCall? = nil) {
        self.callId = callId
        self.text = text
        self.post = post
    }

    static let sizes = [1, 2, 5]

    var secondsLeft: Int {
        guard let r = review else { return 0 }
        return max(0, Int(r.expiresAt.timeIntervalSince(now).rounded(.up)))
    }

    var confirmed: Bool { review.map { sent.contains($0.reviewId) } ?? false }

    func start() { ask() }

    func stop() {
        clock?.cancel(); clock = nil
        asking?.cancel(); asking = nil
    }

    /// A new size, or a review that ran out: ask again.
    func pick(_ size: Int) {
        guard size != usd, phase != .sending else { return }
        Haptics.layer()
        usd = size
        ask()
    }

    func again() {
        Haptics.letter()
        ask()
    }

    private func ask() {
        asking?.cancel()
        note = nil
        receipt = nil
        withAnimation(.snappy(duration: 0.2)) { phase = .reviewing }
        asking = Task {
            do {
                let r = try await JourneyAPI().review(callId: callId, text: callId == nil ? text : nil, usd: usd)
                guard !Task.isCancelled else { return }
                review = r
                now = Date()
                withAnimation(.snappy(duration: 0.2)) { phase = .review }
                tickClock()
            } catch {
                guard !Task.isCancelled else { return }
                withAnimation(.snappy(duration: 0.2)) { phase = .failed(error.localizedDescription) }
                Haptics.warning()
            }
        }
    }

    private func tickClock() {
        clock?.cancel()
        clock = Task {
            while !Task.isCancelled {
                now = Date()
                if phase == .review, secondsLeft == 0 {
                    withAnimation(.snappy(duration: 0.2)) { phase = .expired }
                    return
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    /// The hold completed (or the two-tap confirm, or VoiceOver's action).
    func confirm() {
        guard phase == .review, let r = review, !sent.contains(r.reviewId) else { return }
        sent.insert(r.reviewId)
        lastSent = r.reviewId
        note = nil
        clock?.cancel()
        withAnimation(.snappy(duration: 0.2)) { phase = .sending }
        Task {
            do {
                switch try await JourneyAPI().confirm(reviewId: r.reviewId) {
                case .receipt(let receipt):
                    self.receipt = receipt
                    withAnimation(.snappy(duration: 0.25)) { phase = .receipt }
                    if receipt.swapped { Haptics.success() } else if receipt.blocked { Haptics.error() } else { Haptics.warning() }
                case .expired:
                    withAnimation(.snappy(duration: 0.2)) { phase = .expired }
                    Haptics.warning()
                case .busy(let msg):
                    note = msg
                case .gone:
                    withAnimation(.snappy(duration: 0.2)) { phase = .uncertain(Self.lost) }
                    Haptics.warning()
                }
            } catch {
                // The answer was lost, not the trade: it may still be running or may have landed.
                withAnimation(.snappy(duration: 0.2)) { phase = .uncertain(Self.lost) }
                Haptics.warning()
            }
        }
    }

    static let lost = "The answer didn't come back, so this trade may or may not have gone through. Check its status before trading again."

    /// After a lost answer: ask about the same review. The server answers with
    /// its receipt, "still sending", or "expired" (never sent), and never sends it twice.
    func checkStatus() {
        guard let id = lastSent else { return }
        Haptics.letter()
        note = "Checking…"
        Task {
            do {
                switch try await JourneyAPI().confirm(reviewId: id) {
                case .receipt(let receipt):
                    note = nil
                    self.receipt = receipt
                    withAnimation(.snappy(duration: 0.25)) { phase = .receipt }
                case .busy:
                    note = "Still sending. Check again in a moment."
                case .expired:
                    // Expired before it was sent: nothing went out.
                    note = nil
                    withAnimation(.snappy(duration: 0.2)) { phase = .expired }
                case .gone:
                    note = "The server no longer has this trade. Check Wallet or the NEAR explorer before trading again."
                }
            } catch {
                note = "Still can't reach the AIRKEY server."
            }
        }
    }

    /// The receipt as one plain line for the chat, with its transaction.
    var receiptLine: String? {
        guard let r = receipt else { return nil }
        var line = "AIRKEY · \(Plain.scrub(r.summary))"
        if let tx = r.txURL { line += " \(tx)" }
        return line
    }
}
