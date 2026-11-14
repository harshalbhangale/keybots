import Foundation
import Observation

/// The people you follow and what their calls traded for you, as the
/// keyboard's Calls › Following and the app's Wallet show it. Read every 15
/// seconds while it's on screen. Nothing here trades by itself: rules are
/// saved on the server, which trades a new call only within them, and
/// "trade their latest call" is a hold in the views.
@Observable
@MainActor
final class FollowsModel {
    /// nil until the first read lands.
    var follows: [Follow]?
    /// Newest first.
    var trades: [AutoTrade] = []
    /// Callers Keybots tracks, for "Add someone".
    var callers: [Caller] = []
    var problem: String?
    /// One plain line about the last thing that happened.
    var notice: String?
    /// Trades that just came in, drawn with a short highlight.
    var fresh: Set<String> = []
    /// Goes up each time a new trade lands for you: the views play success on it.
    var landed = 0
    /// The handle being added or saved.
    var saving: String?
    /// The handle whose latest call is being traded.
    var checking: String?

    @ObservationIgnored private var watching: Task<Void, Never>?
    /// Trade ids already shown; nil before the first read, so the history isn't "new".
    @ObservationIgnored private var seen: Set<String>?

    func start() {
        guard watching == nil else { return }
        watching = Task { [weak self] in
            await self?.loadCallers()
            while !Task.isCancelled {
                await self?.load()
                guard let self else { return }
                try? await Task.sleep(for: .seconds(self.follows == nil ? 4 : 15))
            }
        }
    }

    func stop() {
        watching?.cancel()
        watching = nil
    }

    func retry() {
        problem = nil
        Task { await load() }
    }

    func load() async {
        do {
            let list = try await API().follows()
            guard !Task.isCancelled else { return }
            // A rule being saved keeps what you just set until the server has it.
            if let saving, let mine = follows?.first(where: { $0.id == saving.lowercased() }) {
                follows = list.follows.map { $0.id == mine.id ? mine : $0 }
            } else {
                follows = list.follows
            }
            ingest(list.trades)
            problem = nil
        } catch {
            if follows == nil, !Task.isCancelled { problem = error.localizedDescription }
        }
    }

    func loadCallers() async {
        if let list = try? await API().kols() { callers = list }
    }

    /// Who to suggest: tracked callers you don't follow yet, most hits first.
    var suggestions: [Caller] {
        let mine = Set((follows ?? []).map(\.id))
        return callers.filter { !mine.contains($0.id) }
            .sorted { $0.record.hits != $1.record.hits ? $0.record.hits > $1.record.hits : $0.record.misses < $1.record.misses }
            .prefix(8).map { $0 }
    }

    func follow(_ handle: String) -> Follow? { follows?.first { $0.id == Follow.clean(handle).lowercased() } }

    // MARK: Changes

    /// Follow someone with the default rules (auto off until you turn it on).
    @discardableResult
    func add(_ raw: String) async -> Bool {
        let handle = Follow.clean(raw)
        guard Follow.valid(handle) else {
            notice = "That isn't an X handle. Try one like @CryptoKaleo."
            return false
        }
        if follow(handle) != nil {
            notice = "You already follow @\(handle)."
            return false
        }
        saving = handle
        defer { saving = nil }
        do {
            let f = try await API().follow(handle: handle, rules: FollowRules())
            follows = (follows ?? []) + [f]
            notice = nil
            return true
        } catch {
            notice = error.localizedDescription
            return false
        }
    }

    /// Save one person's rules. The change shows at once and goes back if the server says no.
    @discardableResult
    func save(_ handle: String, _ rules: FollowRules) async -> Bool {
        guard let i = follows?.firstIndex(where: { $0.id == handle.lowercased() }) else { return false }
        let before = follows![i]
        follows![i].apply(rules)
        // Turning auto back on is what clears a pause on the server.
        if rules.auto { follows![i].pausedReason = nil }
        saving = handle
        defer { saving = nil }
        do {
            let f = try await API().follow(handle: handle, rules: rules)
            if let j = follows?.firstIndex(where: { $0.id == f.id }) { follows![j] = f }
            notice = nil
            return true
        } catch {
            if let j = follows?.firstIndex(where: { $0.id == before.id }) { follows![j] = before }
            notice = error.localizedDescription
            return false
        }
    }

    func setAuto(_ handle: String, _ on: Bool) async {
        guard var rules = follow(handle)?.rules else { return }
        rules.auto = on
        await save(handle, rules)
    }

    @discardableResult
    func unfollow(_ handle: String) async -> Bool {
        let before = follows
        follows?.removeAll { $0.id == handle.lowercased() }
        do {
            try await API().unfollow(handle: handle)
            notice = nil
            return true
        } catch {
            follows = before
            notice = error.localizedDescription
            return false
        }
    }

    /// The hold on "Trade their latest call now": the server reads their
    /// latest call and trades it within your rules, or says why not. The
    /// answer's first row comes back for the view's haptic.
    func tradeLatest(_ handle: String) async -> AutoTrade? {
        guard checking == nil else { return nil }
        checking = handle
        defer { checking = nil }
        do {
            let rows = try await API().checkFollow(handle: handle, latest: true)
            seen = (seen ?? []).union(rows.map(\.id))
            trades = rows + trades.filter { row in !rows.contains { $0.id == row.id } }
            fresh.formUnion(rows.map(\.id))
            fade(rows.map(\.id))
            notice = rows.first?.message ?? "No new call from @\(Follow.clean(handle)) to trade."
            await load()
            return rows.first
        } catch {
            notice = error.localizedDescription
            return nil
        }
    }

    // MARK: Trades

    private func ingest(_ rows: [AutoTrade]) {
        let ids = Set(rows.map(\.id))
        if let seen {
            let new = rows.filter { !seen.contains($0.id) }
            if !new.isEmpty {
                fresh.formUnion(new.map(\.id))
                if new.contains(where: \.traded) { landed += 1 }
                fade(new.map(\.id))
            }
        }
        seen = (seen ?? []).union(ids)
        trades = rows
    }

    /// The highlight goes after a few seconds.
    private func fade(_ ids: [String]) {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            self?.fresh.subtract(ids)
        }
    }
}
