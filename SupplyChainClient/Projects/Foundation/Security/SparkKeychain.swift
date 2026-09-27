import Foundation
import Security

/// 安装级设备 ID / 设备登录密钥（对齐 Spark `SparkKeychain` 路径；service 使用 SupplyChainClient）。
enum SparkKeychain {
    /// 设备登录凭证读写失败（例如 Keychain 拒绝写入），必须拒绝降级为内存态 secret。
    enum DeviceCredentialError: Error {
        case deviceCredentialUnavailable
    }

    nonisolated(unsafe) private static let service = "com.dreamhua.supportclient"
    nonisolated(unsafe) private static let deviceIDAccount = "device_unique_id"
    nonisolated(unsafe) private static let deviceSecretAccount = "device_login_secret"

    nonisolated static func getOrCreateDeviceID() -> String {
        if let existing = load(account: deviceIDAccount) { return existing }
        let newID = UUID().uuidString
        try? save(newID, account: deviceIDAccount)
        return newID
    }

    /// 认证场景必须使用可持久化的安装标识，禁止降级为内存 UUID。
    nonisolated static func getOrCreatePersistentDeviceID() throws -> String {
        if let existing = load(account: deviceIDAccount), existing.isEmpty == false {
            return existing
        }
        let newID = UUID().uuidString
        do {
            try save(newID, account: deviceIDAccount)
            return newID
        } catch {
            throw DeviceCredentialError.deviceCredentialUnavailable
        }
    }

    /// 读取或创建游客模式设备登录密钥（`device_secret`）。保存失败时拒绝返回仅存在于内存的临时 secret。
    nonisolated static func getOrCreateDeviceSecret() throws -> String {
        if let existing = load(account: deviceSecretAccount), existing.isEmpty == false {
            return existing
        }
        let secret = try generateDeviceSecret()
        do {
            try save(secret, account: deviceSecretAccount)
        } catch {
            throw DeviceCredentialError.deviceCredentialUnavailable
        }
        return secret
    }

    nonisolated static func loadDeviceSecret() -> String? {
        load(account: deviceSecretAccount)
    }

    nonisolated static func replaceDeviceSecret(_ secret: String) throws {
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw DeviceCredentialError.deviceCredentialUnavailable
        }
        try save(trimmed, account: deviceSecretAccount)
    }

    nonisolated static func deleteDeviceSecret() {
        delete(account: deviceSecretAccount)
    }

    nonisolated private static func generateDeviceSecret() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw DeviceCredentialError.deviceCredentialUnavailable
        }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    nonisolated static func save(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    nonisolated static func load(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    nonisolated static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

typealias SupportKeychain = SparkKeychain
