import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class AppModel {
    var state: LeashState?
    var receipts: [Receipt] = []
    /// Trades still waiting for their price.
    var watching: [Order] = []
    var error: String?
    var loading = false
    /// Set while an owner action is waiting for Face ID or the chain.
    var busy: String?
    var lastOwnerTx: Submitted?

    var api: API { API() }

    /// The colour of what's going on: red while everything is stopped, amber
    /// while something waits for the owner, lime otherwise.
    var mood: Color {
        guard let state else { return AK.accent }
        if state.paused { return AK.red }
        return state.pending.isEmpty ? AK.accent : AK.amber
    }

    func refresh() async {
        loading = true
        defer { loading = false }
        do {
            async let s = api.state()
            async let r = api.receipts()
            (state, receipts) = try await (s, r)
            error = nil
            if let state {
                Fmt.roleNames = state.roleNames
                Contacts.save(state.contacts)
                Vault.saveOwner(state.owner)
            }
            watching = ((try? await api.orders()) ?? []).filter { $0.status == "watching" }
            if Tokens.stale, let symbols = try? await api.tokens() { Tokens.save(symbols) }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func run(_ text: String, source: String) async -> Receipt? {
        error = nil
        do {
            let r = try await api.command(text, source: source)
            await refresh()
            return r
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    /// Owner action: the server builds it, Face ID unlocks the device key, the phone signs, the server relays.
    func owner(_ method: String, _ args: [String: any Sendable], reason: String) async {
        busy = method
        error = nil
        defer { busy = nil }
        do {
            let prepared = try await api.prepare(method: method, args: args, publicKey: DeviceKey.publicKey)
            guard let hash = Data(base64Encoded: prepared.hash) else { throw APIError(message: "Bad transaction from the server.") }
            let sig = try await DeviceKey.sign(hash, reason: reason)
            lastOwnerTx = try await api.submit(tx: prepared.tx, signature: sig.base64EncodedString())
            await refresh()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func cancel(_ order: Order) async {
        do {
            try await api.cancelOrder(order.id)
            await refresh()
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: today's numbers, from the receipts

    var today: [Receipt] {
        receipts.filter { r in r.date.map { Calendar.current.isDateInToday($0) } ?? false }
    }

    var paidToday: String {
        var total = Decimal(0)
        for r in today where r.outcome == "paid" {
            if let s = r.interpretation.action.amountNear, let d = Decimal(string: s) { total += d }
        }
        return "\(NSDecimalNumber(decimal: total).stringValue) NEAR"
    }

    var approvalsToday: Int { today.filter { $0.outcome == "approval" }.count }
    var blockedToday: Int { today.filter { $0.outcome == "blocked" }.count }

    func receipts(for agent: String) -> [Receipt] { receipts.filter { $0.agent?.account == agent } }
}
