import Foundation

/// Small JSON files in the App Group container (`group.tech.airkey.shared`),
/// under bridge/. The keyboard keeps its settings, clipboard history, notes,
/// learned words and cached rates here, so the app can read them too.
enum AppGroupStore {
    static let groupID = Settings.group

    /// Looked up once: the container's location never changes while the
    /// process lives, and asking the system for it on every read is costly.
    static let containerURL: URL? =
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)

    /// bridge/ subdirectory inside the group container; created on first use.
    static let bridgeDir: URL? = {
        guard let base = containerURL else { return nil }
        let dir = base.appendingPathComponent("bridge", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    @discardableResult
    static func writeJSON(_ payload: [String: Any], name: String) -> Bool {
        guard let dir = bridgeDir,
              JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        else { return false }
        do {
            try data.write(to: dir.appendingPathComponent(name), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    static func readJSON(name: String) -> [String: Any]? {
        guard let dir = bridgeDir,
              let data = try? Data(contentsOf: dir.appendingPathComponent(name))
        else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
