import Foundation

/// The rates behind the money chip ("$13 = ₹1,246"), straight from the ECB's
/// daily rates (Frankfurter, free and keyless), kept in the App Group so a
/// fresh keyboard process has yesterday's table before its first request
/// lands. Asked for once an hour, and only with Full Access. Token prices
/// are AIRKEY's agents' ("$near"), from the AIRKEY server.
final class RatesStore {
    static let shared = RatesStore()

    private(set) var fiat: [String: Double] = [:]
    private var fiatAt: Date?
    private var inFlight = false

    private static let file = "rates.json"
    private static let fiatTTL: TimeInterval = 60 * 60
    static let frankfurter = URL(string: "https://api.frankfurter.dev/v1/latest?base=USD")!

    private init() {
        if let saved = AppGroupStore.readJSON(name: Self.file) {
            fiat = (saved["fiat"] as? [String: Double]) ?? [:]
            if let at = saved["fiatAt"] as? Double { fiatAt = Date(timeIntervalSince1970: at) }
        }
    }

    /// The currency money converts into: the one chosen in Settings;
    /// otherwise where the phone is.
    var local: String {
        if let chosen = SettingsStore.current.moneyCurrency?.uppercased(),
           chosen != "AUTO", chosen.count == 3 { return chosen }
        if let region = SettingsStore.current.region?.uppercased(),
           let code = Self.regionCurrency[region] { return code }
        if let code = Locale.current.currency?.identifier { return code }
        return "USD"
    }

    private static let regionCurrency: [String: String] = [
        "IN": "INR", "US": "USD", "GB": "GBP", "JP": "JPY", "SG": "SGD", "AU": "AUD",
        "CA": "CAD", "AE": "AED", "CH": "CHF", "CN": "CNY", "HK": "HKD", "KR": "KRW",
        "DE": "EUR", "FR": "EUR", "ES": "EUR", "IT": "EUR", "NL": "EUR", "IE": "EUR",
        "PT": "EUR", "AT": "EUR", "BE": "EUR", "FI": "EUR", "GR": "EUR",
    ]

    func snapshot() -> Smart.RatesSnapshot {
        Smart.RatesSnapshot(fiat: fiat, local: local)
    }

    /// Fetches the dollar table when it is missing or stale; `then` runs on
    /// the main queue once something new is in hand.
    func ensureFiat(then: @escaping () -> Void) {
        if let at = fiatAt, Date().timeIntervalSince(at) < Self.fiatTTL, !fiat.isEmpty { return }
        guard !inFlight else { return }
        inFlight = true
        var req = URLRequest(url: Self.frankfurter)
        req.timeoutInterval = 6
        URLSession.shared.dataTask(with: req) { [weak self] data, response, _ in
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
            let obj = ok ? data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } : nil
            var rates = (obj?["rates"] as? [String: Any])?.compactMapValues { ($0 as? NSNumber)?.doubleValue }.filter { $0.value > 0 } ?? [:]
            if !rates.isEmpty { rates["USD"] = 1 }
            DispatchQueue.main.async {
                guard let self else { return }
                self.inFlight = false
                guard !rates.isEmpty else { return }
                self.fiat = rates
                self.fiatAt = Date()
                _ = AppGroupStore.writeJSON(["fiat": rates, "fiatAt": Date().timeIntervalSince1970],
                                            name: Self.file)
                then()
            }
        }.resume()
    }
}
