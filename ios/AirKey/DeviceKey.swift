import CryptoKit
import Foundation
import LocalAuthentication
import Security

/// This phone's owner key: an ed25519 key made on the device, kept in the
/// Keychain (this device only), and used only after Face ID. Its public half is
/// added to the owner account once (scripts/add-device-key.mjs); after that the
/// phone signs owner actions and the server only relays them.
enum DeviceKey {
    private static let service = "tech.airkey.owner-key"
    private static let account = "device"

    /// "ed25519:<base58>", NEAR's public-key format.
    static var publicKey: String {
        "ed25519:" + Base58.encode(privateKey().publicKey.rawRepresentation)
    }

    /// Face ID (or the passcode), then an ed25519 signature over `hash`.
    static func sign(_ hash: Data, reason: String) async throws -> Data {
        try await authenticate(reason: reason)
        return try privateKey().signature(for: hash)
    }

    static func authenticate(reason: String) async throws {
        let context = LAContext()
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            let ok = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            if !ok { throw APIError(message: "Not approved.") }
            return
        }
        #if targetEnvironment(simulator)
        // The simulator has no Face ID or passcode unless you enrol one
        // (Features > Face ID > Enrolled). Allow it there so the flow can be shown.
        return
        #else
        throw APIError(message: "Set up Face ID or a passcode to approve payments.")
        #endif
    }

    private static func privateKey() -> Curve25519.Signing.PrivateKey {
        if let raw = read(), let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) { return key }
        let key = Curve25519.Signing.PrivateKey()
        write(key.rawRepresentation)
        return key
    }

    private static func read() -> Data? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
        ]
        var out: CFTypeRef?
        return SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess ? out as? Data : nil
    }

    private static func write(_ data: Data) {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: data,
        ]
        SecItemDelete(q as CFDictionary)
        SecItemAdd(q as CFDictionary, nil)
    }
}

enum Base58 {
    private static let alphabet = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")

    static func encode(_ data: Data) -> String {
        var bytes = [UInt8](data)
        var zeros = 0
        while zeros < bytes.count, bytes[zeros] == 0 { zeros += 1 }
        var out: [Character] = []
        var start = zeros
        while start < bytes.count {
            var carry = 0
            for i in start..<bytes.count {
                carry = carry * 256 + Int(bytes[i])
                bytes[i] = UInt8(carry / 58)
                carry %= 58
            }
            out.append(alphabet[carry])
            while start < bytes.count, bytes[start] == 0 { start += 1 }
        }
        return String(repeating: "1", count: zeros) + String(out.reversed())
    }
}
