import Observation
import SwiftUI
import UIKit

/// What the Wallet and Calls panels ask of the keyboard. They never type or
/// send by themselves: each of these is the keyboard's own doing.
@MainActor
struct MoneyActions {
    var fullAccess: () -> Bool
    /// Closes the panel and puts `text` in the message, for the strip to read.
    var insert: (String) -> Void
    /// Closes the panel and puts a receipt line in the chat.
    var share: (String) -> Void
    /// Opens a link in Safari; false when iOS wouldn't (the link is copied instead).
    var open: (URL, @escaping (Bool) -> Void) -> Void
}

/// The leash as the Wallet panel shows it: read from the AIRKEY server, and
/// only read. Like Kall's wallet it retries every 4 seconds until the first
/// read lands, then refreshes every 20 while the panel is open.
@Observable
@MainActor
final class WalletModel {
    var state: LeashState?
    var receipts: [Receipt] = []
    var orders: [Order] = []
    /// Dollar prices from NEAR Intents, by symbol.
    var prices: [String: Double] = [:]
    var problem: String?
    /// The order being cancelled.
    var cancelling: String?
    var note: String?

    @ObservationIgnored private var watching: Task<Void, Never>?

    func start() {
        guard watching == nil else { return }
        watching = Task { [weak self] in
            while !Task.isCancelled {
                await self?.load()
                guard let self else { return }
                try? await Task.sleep(for: .seconds(self.state == nil ? 4 : 20))
            }
        }
    }

    /// The panel closed: no timers, nothing kept.
    func stop() {
        watching?.cancel()
        watching = nil
    }

    func retry() {
        problem = nil
        Task { await load() }
    }

    func load() async {
        let api = API()
        async let r = try? await api.receipts(limit: 10)
        async let o = try? await api.orders()
        do {
            let state = try await api.state()
            guard !Task.isCancelled else { return }
            self.state = state
            problem = nil
            Fmt.roleNames = state.roleNames
            Contacts.save(state.contacts)
        } catch {
            // A failed read keeps the last good one.
            if state == nil, !Task.isCancelled { problem = error.localizedDescription }
        }
        let (receipts, orders) = await (r, o)
        guard !Task.isCancelled else { return }
        if let receipts { self.receipts = receipts }
        if let orders { self.orders = orders }
        await loadPrices()
    }

    private func loadPrices() async {
        let symbols = ["NEAR"] + (state?.holdings ?? []).map { $0.symbol.uppercased() }
        await withTaskGroup(of: (String, Double?).self) { group in
            for symbol in Set(symbols) {
                group.addTask { (symbol, try? await API().price(symbol).usd) }
            }
            for await (symbol, usd) in group {
                if let usd { prices[symbol] = usd }
            }
        }
    }

    func cancel(_ order: Order) {
        guard cancelling == nil else { return }
        cancelling = order.id
        Task {
            do {
                try await API().cancelOrder(order.id)
                orders.removeAll { $0.id == order.id }
                Haptics.success()
            } catch {
                note = error.localizedDescription
                Haptics.error()
            }
            cancelling = nil
        }
    }

    // MARK: What the panel shows

    var watchingOrders: [Order] { orders.filter { $0.status == "watching" } }

    /// "≈ $2.16" for an amount of a token, when its price is known.
    func usd(_ amount: String, _ symbol: String) -> String? {
        guard let price = prices[symbol.uppercased()], let n = Double(amount) else { return nil }
        return "≈ " + Fmt.usd(n * price)
    }

    /// People you can pay by name: your contacts, without the ones the leash blocks.
    var payees: [String] {
        guard let state else { return Contacts.names.filter { !$0.contains(".") }.sorted() }
        let blocked = Set(state.blocklist.map(\.account))
        return state.contacts.filter { !$0.key.contains(".") && !blocked.contains($0.value) }.keys.sorted()
    }
}

/// Words the money panels share.
enum MoneyText {
    /// The server's words, in plain ones: no "leash", no rule codes.
    /// "Blocked by the leash (R3): drain.near is blocked: reported by …" reads
    /// "Blocked: drain.near is on your blocked list."
    static func plain(_ message: String) -> String {
        var s = message
        let swaps: [(String, String)] = [
            (#"Blocked by the leash \([^)]*\): (\S+) is blocked\b.*"#, "Blocked: $1 is on your blocked list."),
            (#"Blocked by the leash \([^)]*\): "#, "Blocked: "),
            (#"Blocked by the leash: "#, "Blocked: "),
            (#"The leash would block this: "#, "Over your limits: "),
            (#" ?\(R\d+\)"#, ""),
            (#"It's in the leash\."#, "It's in your wallet."),
            (#"the leash keeps the NEAR"#, "the NEAR stays in your wallet"),
            (#"through the leash"#, "from your wallet"),
            (#"by the leash"#, "by your limits"),
            (#"refunds the leash"#, "refunds your wallet"),
            (#"The leash"#, "Your wallet"),
            (#"the leash"#, "your wallet"),
        ]
        for (pattern, with) in swaps {
            s = s.replacingOccurrences(of: pattern, with: with, options: .regularExpression)
        }
        return s
    }

    /// A receipt as one line for the chat, the way the strip's Share writes it.
    static func receiptLine(message: String, signal: Signal, tx: Receipt.Tx?) -> String {
        let message = plain(message)
        let word = signal.word.capitalized
        let says = signal == .allow || message.lowercased().hasPrefix(word.lowercased().trimmingCharacters(in: .punctuationCharacters))
        var line = says ? "AIRKEY · \(message)" : "AIRKEY · \(word): \(message)"
        if let tx { line += " \(tx.url)" }
        return line
    }
}

/// The panels' colours: the strip's own, plus a "good" and "bad" that read on
/// light and dark keys alike (lime as text only works on dark).
struct MoneyPalette {
    let dark: Bool
    var text: Color { dark ? .white : Color(white: 0.07) }
    var soft: Color { text.opacity(0.55) }
    var faint: Color { text.opacity(0.32) }
    var fill: Color { dark ? .white.opacity(0.10) : .black.opacity(0.06) }
    var line: Color { text.opacity(0.08) }
    var good: Color { dark ? AK.accent : Color(hex: 0x3F7A0A) }
    var bad: Color { dark ? AK.red : Color(hex: 0xD92D2F) }
    var warn: Color { dark ? AK.amber : Color(hex: 0xB86E00) }

    func color(_ signal: Signal) -> Color {
        switch signal {
        case .allow: good
        case .warn: warn
        case .block: bad
        default: soft
        }
    }
}

/// Buttons dip under the finger, like keys.
struct MoneyPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// The row of sections at the top of a panel. The one that's open is lime.
struct MoneyTabs<Tab: Hashable>: View {
    let tabs: [(tab: Tab, label: String)]
    @Binding var selection: Tab
    let palette: MoneyPalette

    var body: some View {
        HStack(spacing: 6) {
            ForEach(tabs, id: \.tab) { item in
                let on = item.tab == selection
                Button {
                    guard !on else { return }
                    Haptics.layer()
                    withAnimation(.snappy(duration: 0.2)) { selection = item.tab }
                } label: {
                    Text(item.label)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(on ? AK.ink : palette.text)
                        .lineLimit(1)
                        .padding(.horizontal, 11)
                        .frame(height: 28)
                        .background(on ? AK.accent : palette.fill, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(MoneyPress())
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

/// One quiet line (or two) in the middle of an empty panel.
struct MoneyEmpty: View {
    let text: String
    let palette: MoneyPalette
    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(palette.soft)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The Wallet or the Calls panel over the keys: SwiftUI in a host that is
/// built when the panel opens and let go when it closes, timers and all.
final class MoneyPanel: UIView {
    enum Kind { case wallet, calls }

    private let host: UIHostingController<AnyView>
    private let stop: () -> Void
    /// Calls is showing a review: it takes the whole keyboard, strip and all.
    private(set) var full = false
    /// Called when `full` changes, so the keyboard lays itself out again.
    var onFull: ((Bool) -> Void)?

    /// `review`: a copied call's text, opened straight on its review.
    init(kind: Kind, actions: MoneyActions, dark: Bool, review: String? = nil) {
        let scheme: ColorScheme = dark ? .dark : .light
        var calls: CallsModel?
        switch kind {
        case .wallet:
            let model = WalletModel()
            host = UIHostingController(rootView: AnyView(WalletView(model: model, actions: actions).environment(\.colorScheme, scheme)))
            stop = { model.stop() }
        case .calls:
            let model = CallsModel()
            host = UIHostingController(rootView: AnyView(CallsView(model: model, actions: actions).environment(\.colorScheme, scheme)))
            stop = { model.stop(); model.journey?.stop() }
            calls = model
        }
        super.init(frame: .zero)
        if let calls {
            calls.onFull = { [weak self] on in
                guard let self, self.full != on else { return }
                self.full = on
                self.onFull?(on)
            }
            if let review { calls.review(text: review) }
        }
        host.view.backgroundColor = .clear
        host.sizingOptions = []
        host.safeAreaRegions = []
        addSubview(host.view)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        host.view.frame = bounds
    }

    func attach(to parent: UIViewController) {
        parent.addChild(host)
        host.didMove(toParent: parent)
    }

    /// Stops the refresh and takes the panel out, so nothing of it stays in memory.
    func close() {
        stop()
        host.willMove(toParent: nil)
        host.view.removeFromSuperview()
        host.removeFromParent()
        removeFromSuperview()
    }
}
