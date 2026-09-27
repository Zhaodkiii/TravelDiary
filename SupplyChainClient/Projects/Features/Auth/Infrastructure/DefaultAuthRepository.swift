import Foundation
import UIKit

enum AuthFeatureError: LocalizedError {
    case missingAppleUserIdentifier
    case deviceCredentialUnavailable

    var errorDescription: String? {
        switch self {
        case .missingAppleUserIdentifier:
            return L10n.text("auth.error.apple_user_identifier_missing")
        case .deviceCredentialUnavailable:
            return L10n.text("auth.device.credential_invalid")
        }
    }
}

/// 认证仓储：
/// 负责桥接远端认证、会话快照存储与本地首屏数据初始化。
final class DefaultAuthRepository: AuthRepository {
    private let backend: SupportBackend
    private let snapshotStore: SessionSnapshotStore
    private let logger: Logger

    init(
        backend: SupportBackend,
        snapshotStore: SessionSnapshotStore = SessionSnapshotStore(),
        logger: Logger = ConsoleLogger()
    ) {
        self.backend = backend
        self.snapshotStore = snapshotStore
        self.logger = logger
    }

    func restoreSession() async -> UserSession? {
        guard let cachedSession = await snapshotStore.load() else {
            await logMissingSnapshotWithTokenHint(context: "restoreSession")
            return nil
        }

        do {
            _ = try await backend.tokenProvider().authorizationHeaderValue()
            logger.info("会话恢复：认证令牌已就绪，开始拉取服务端最新 UserSession", module: .auth)
        } catch let authError as AuthTokenProviderError {
            switch authError {
            case .refreshTemporarilyUnavailable:
                logger.warning("会话恢复时 token 刷新暂不可用（降级保留会话）：\(authError.localizedDescription)", module: .auth)
                return cachedSession
            case .missingTokens, .invalidRefreshResponse:
                logger.warning(
                    "会话恢复：令牌刷新明确失败，清空本地会话 error=\(authError.localizedDescription)",
                    module: .auth
                )
                await backend.tokenProvider().clearTokens()
                backend.deviceCache.clearAuthenticatedDeviceState()
                await snapshotStore.clear()
                SupportAuthSessionInvalidation.postIfNeeded(
                    statusCode: 401,
                    backendCode: nil,
                    message: "token_not_valid",
                    source: "DefaultAuthRepository.restoreSession"
                )
                return nil
            case .refreshFailed(let message, let code):
                logger.warning(
                    "会话恢复：令牌刷新明确失败，清空本地会话 msg=\(message)",
                    module: .auth
                )
                await backend.tokenProvider().clearTokens()
                backend.deviceCache.clearAuthenticatedDeviceState()
                await snapshotStore.clear()
                SupportAuthSessionInvalidation.postIfNeeded(
                    statusCode: 401,
                    backendCode: code,
                    message: message,
                    source: "DefaultAuthRepository.restoreSession"
                )
                return nil
            }
        } catch {
            logger.warning("会话恢复时 token 预热失败（降级保留会话）：\(error.localizedDescription)", module: .auth)
            return cachedSession
        }

        do {
            let remote = try await backend.auth.fetchCurrentSession()
            let latestSession = mergeCurrentSession(remote, into: cachedSession)
            try await snapshotStore.save(latestSession)
            if latestSession.isPro != cachedSession.isPro {
                logger.info(
                    "会话恢复：Pro 状态已更新 accountID=\(latestSession.accountID) cached=\(cachedSession.isPro) latest=\(latestSession.isPro)",
                    module: .auth
                )
            }
            logger.info(
                "会话恢复成功：已使用服务端最新 UserSession accountID=\(latestSession.accountID) isPro=\(latestSession.isPro)",
                module: .auth
            )
            return latestSession
        } catch {
            if shouldSignOutOnSessionRefreshFailure(error) {
                logger.warning(
                    "会话恢复：服务端鉴权失效，清空本地会话 error=\(error.localizedDescription)",
                    module: .auth
                )
                await backend.tokenProvider().clearTokens()
                backend.deviceCache.clearAuthenticatedDeviceState()
                await snapshotStore.clear()
                return nil
            }

            logger.warning(
                "会话恢复：拉取最新 UserSession 失败，使用 SessionSnapshotStore 兜底 cachedIsPro=\(cachedSession.isPro) error=\(error.localizedDescription)",
                module: .auth
            )
            return cachedSession
        }
    }

    func signInWithApple(payload: AppleSignInPayload) async throws -> UserSession {
        let userIdentifier = payload.userIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard userIdentifier.isEmpty == false else {
            throw AuthFeatureError.missingAppleUserIdentifier
        }

        let bundleId = Bundle.main.bundleIdentifier ?? "SupplyChainClient"
        let deviceId = try SupportKeychain.getOrCreatePersistentDeviceID()
        let deviceSecret = SupportKeychain.loadDeviceSecret() ?? ""

        let context: SupportAuthAPI.AuthenticatedUserContext
        do {
            context = try await backend.auth.loginWithApple(
                identityToken: payload.identityToken,
                authorizationCode: payload.authorizationCode,
                nonce: payload.nonce,
                user: userIdentifier,
                email: payload.email,
                fullName: payload.fullName,
                bundleId: bundleId,
                deviceId: deviceId,
                deviceSecret: deviceSecret
            )
        } catch let error as SupportNetworkError where Self.isUnregisteredDeviceCredential(error) {
            // Keychain 可能保留了旧安装/旧服务端环境的 secret；服务端明确表示
            // 当前设备凭证不存在时，Apple 正式账号登录可以不依赖游客凭证。
            SupportKeychain.deleteDeviceSecret()
            logger.warning(
                "认证仓储：Apple 登录发现本地 device_secret 未在服务端登记，清除后使用无设备凭证重试",
                module: .auth
            )
            context = try await backend.auth.loginWithApple(
                identityToken: payload.identityToken,
                authorizationCode: payload.authorizationCode,
                nonce: payload.nonce,
                user: userIdentifier,
                email: payload.email,
                fullName: payload.fullName,
                bundleId: bundleId,
                deviceId: deviceId,
                deviceSecret: ""
            )
        }
        logger.info(
            "认证仓储：Apple 登录远端上下文已返回 userId=\(context.userId) email=\(context.email ?? "-") isPro=\(context.isPro) isNewUser=\(context.isNewUser)",
            module: .auth
        )

        let normalizedEmail = (payload.email ?? context.email ?? "apple_\(userIdentifier)@privaterelay.appleid.com")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let displayName = {
            let preferred = payload.fullName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if preferred.isEmpty == false { return preferred }
            let backendName = context.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if backendName.isEmpty == false { return backendName }
            return L10n.text("auth.apple.default_display_name")
        }()

        let signedInAt = Date()
        let session = UserSession(
            accountID: Int64(context.userId),
            email: normalizedEmail,
            displayName: displayName,
            signedInAt: signedInAt,
            signInMethod: parseSignInMethod(context.signInMethod) ?? .apple,
            isPro: context.isPro,
            isNewUser: context.isNewUser,
            isDeviceAccount: context.isDeviceAccount
        )

        try await snapshotStore.save(session)
        backend.deviceCache.cacheLastLoggedInAccountID(session.accountID)
        await verifySnapshotAfterSave(expectedAccountID: session.accountID, signInMethod: "apple")
        logger.info(
            "用户已通过 Apple 登录，session 已保存 accountID=\(session.accountID) resolution=\(context.accountResolution?.rawValue ?? "-")",
            module: .auth
        )
        return session
    }

    func signInWithDevice() async throws -> UserSession {
        let bundleId = Bundle.main.bundleIdentifier ?? "SupplyChainClient"
        let deviceId: String
        do {
            deviceId = try SupportKeychain.getOrCreatePersistentDeviceID()
        } catch {
            throw AuthFeatureError.deviceCredentialUnavailable
        }
        let deviceSecret: String
        do {
            deviceSecret = try SupportKeychain.getOrCreateDeviceSecret()
        } catch {
            throw AuthFeatureError.deviceCredentialUnavailable
        }

        let context = try await backend.auth.loginWithDevice(
            bundleId: bundleId,
            deviceId: deviceId,
            deviceSecret: deviceSecret
        )
        logger.info(
            "认证仓储：设备登录远端上下文已返回 userId=\(context.userId) resolution=\(context.accountResolution?.rawValue ?? "-")",
            module: .auth
        )

        let session = UserSession(
            accountID: Int64(context.userId),
            email: (context.email ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            displayName: (context.displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            signedInAt: Date(),
            signInMethod: .device,
            isPro: context.isPro,
            isNewUser: context.isNewUser,
            isDeviceAccount: context.isDeviceAccount
        )

        try await snapshotStore.save(session)
        backend.deviceCache.cacheLastLoggedInAccountID(session.accountID)
        await verifySnapshotAfterSave(expectedAccountID: session.accountID, signInMethod: "device")
        logger.info("用户已通过设备账户登录，session 已保存 accountID=\(session.accountID)", module: .auth)
        return session
    }

    func requestPhoneOTP(phoneNumber: String) async throws -> PhoneOTPRequestContext {
        let bundleId = Bundle.main.bundleIdentifier ?? "SupplyChainClient"
        let deviceId = try SupportKeychain.getOrCreatePersistentDeviceID()
        let result = try await backend.otp.requestPhoneOTP(
            phoneNumber: phoneNumber,
            bundleId: bundleId,
            deviceId: deviceId
        )
        return PhoneOTPRequestContext(
            otpID: result.otpId,
            expiresIn: result.expiresIn ?? 300
        )
    }

    func signInWithPhoneOTP(phoneNumber: String, verificationCode: String, otpID: String) async throws -> UserSession {
        let bundleId = Bundle.main.bundleIdentifier ?? "SupplyChainClient"
        let deviceId = try SupportKeychain.getOrCreatePersistentDeviceID()
        let deviceSecret = SupportKeychain.loadDeviceSecret() ?? ""

        let result = try await backend.otp.verifyPhoneOTP(
            otpId: otpID,
            phoneNumber: phoneNumber,
            code: verificationCode,
            bundleId: bundleId,
            deviceId: deviceId,
            deviceSecret: deviceSecret
        )
        logger.info(
            "认证仓储：手机号 OTP 远端响应已返回 userId=\(result.userId) phone=\(result.phoneNumber) isPro=\(result.isPro ?? false) isNewUser=\(result.isNewUser ?? false)",
            module: .auth
        )

        let normalizedPhone = result.phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = result.displayName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? (result.displayName ?? normalizedPhone)
            : normalizedPhone
        let signedInAt = Date()
        let session = UserSession(
            accountID: Int64(result.userId),
            email: normalizedPhone,
            displayName: displayName,
            signedInAt: signedInAt,
            signInMethod: parseSignInMethod(result.signInMethod) ?? .phone,
            isPro: result.isPro ?? false,
            isNewUser: result.isNewUser ?? false,
            isDeviceAccount: result.isDeviceAccount ?? false
        )

        try await snapshotStore.save(session)
        backend.deviceCache.cacheLastLoggedInAccountID(session.accountID)
        await verifySnapshotAfterSave(expectedAccountID: session.accountID, signInMethod: "phone")
        logger.info(
            "用户已通过手机号验证码登录，session 已保存 accountID=\(session.accountID) resolution=\(result.accountResolution ?? "-")",
            module: .auth
        )
        return session
    }

    func signOut() async throws {
        logger.info("认证仓储：开始登出，将通知服务端并清除 Keychain token 与 SessionSnapshot", module: .auth)
        do {
            try await backend.auth.logout()
        } catch {
            logger.warning("认证仓储：服务端登出失败（继续清理本地会话）：\(error.localizedDescription)", module: .auth)
        }
        await backend.tokenProvider().clearTokens()
        backend.deviceCache.clearAuthenticatedDeviceState()
        await snapshotStore.clear()
        logger.info("用户已登出（保留 lastLoggedInAccountID）", module: .auth)
    }

    /// 登录/刷新写快照后立即读回，便于发现 save 失败或读写时序问题。
    private func verifySnapshotAfterSave(expectedAccountID: Int64, signInMethod: String) async {
        guard let persisted = await snapshotStore.load() else {
            logger.error(
                "认证仓储：\(signInMethod) 登录 save 后快照仍不可读 accountID=\(expectedAccountID)（AppSessionStore 若已 signedIn 将产生分裂）",
                module: .auth
            )
            return
        }
        guard persisted.accountID == expectedAccountID else {
            logger.error(
                "认证仓储：\(signInMethod) 登录 save 后快照 accountID=\(persisted.accountID) 与预期 \(expectedAccountID) 不一致",
                module: .auth
            )
            return
        }
    }

    /// 无 UserDefaults 会话但 Keychain 仍有 token 时打 warning，便于定位「能调鉴权 API 但解析不到 accountID」。
    private func logMissingSnapshotWithTokenHint(context: String) async {
        do {
            _ = try await backend.tokenProvider().authorizationHeaderValue()
            logger.warning(
                "认证仓储：\(context) 无可用 SessionSnapshot，但 Keychain 中仍有 access token（鉴权与 accountID 可能分裂）",
                module: .auth
            )
        } catch {
            logger.debug(
                "认证仓储：\(context) 无可用 SessionSnapshot，且无可用 access token",
                module: .auth
            )
        }
    }

    private func mergeCurrentSession(
        _ remote: SupportAuthAPI.CurrentSessionResult,
        into cached: UserSession
    ) -> UserSession {
        let accountID = Int64(remote.userId)
        let email = (remote.email ?? cached.email).trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedEmail = email.isEmpty ? cached.email : email

        let remoteDisplayName = remote.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let displayName = remoteDisplayName.isEmpty ? cached.displayName : remoteDisplayName

        let signInMethod = parseSignInMethod(remote.signInMethod) ?? cached.signInMethod

        return UserSession(
            accountID: accountID,
            email: resolvedEmail,
            displayName: displayName,
            signedInAt: cached.signedInAt,
            signInMethod: signInMethod,
            isPro: remote.isPro ?? false,
            isNewUser: remote.isNewUser ?? cached.isNewUser,
            isDeviceAccount: remote.isDeviceAccount ?? cached.isDeviceAccount
        )
    }

    private static func isUnregisteredDeviceCredential(_ error: SupportNetworkError) -> Bool {
        guard case .http(let statusCode, let backend, _) = error else { return false }
        guard statusCode == 401 else { return false }
        return backend?.code == 40162 || backend?.msg == "device_credential_not_registered"
    }

    private func parseSignInMethod(_ raw: String?) -> UserSession.SignInMethod? {
        guard let raw else { return nil }
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "device":
            return .device
        case "apple":
            return .apple
        case "google":
            return .google
        case "phone":
            return .phone
        case "email":
            return .email
        default:
            return nil
        }
    }

    private func shouldSignOutOnSessionRefreshFailure(_ error: Error) -> Bool {
        if let authError = error as? AuthTokenProviderError {
            switch authError {
            case .refreshFailed, .missingTokens, .invalidRefreshResponse:
                return true
            case .refreshTemporarilyUnavailable:
                return false
            }
        }

        if let networkError = error as? SupportNetworkError {
            switch networkError {
            case .refreshFailed:
                return true
            case .http(let statusCode, let backend, _):
                let backendCode = backend?.code
                let message = backend?.msg ?? ""
                return SupportAuthSessionInvalidation.shouldInvalidate(
                    statusCode: statusCode,
                    backendCode: backendCode,
                    message: message
                )
            case .cancelled, .transport, .invalidResponse, .decoding, .timeout:
                return false
            }
        }

        return false
    }
}
