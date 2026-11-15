import Foundation

/// 仅恢复未登记的可选凭证。游客升级不得降级成创建另一个正式账号。
enum PhoneOTPDeviceCredentialRecovery {
    static func verify<Result>(
        deviceSecret: String,
        protectsGuestAccount: Bool,
        operation: (String) async throws -> Result
    ) async throws -> Result {
        do {
            return try await operation(deviceSecret)
        } catch let error as SupportNetworkError {
            guard !deviceSecret.isEmpty, !protectsGuestAccount,
                  case .http(let status, let backend, _) = error,
                  status == 401,
                  backend?.code == 40162,
                  backend?.msg == "device_credential_not_registered" else {
                throw error
            }
            try Task.checkCancellation()
            // 后端事务会回滚失败验证的 OTP used_at。只重试一次，不删除
            // Keychain 密钥：该密钥可能仍用于另一服务环境的游客账号。
            return try await operation("")
        }
    }
}
