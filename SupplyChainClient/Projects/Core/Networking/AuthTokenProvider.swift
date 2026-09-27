import Foundation
import Security

nonisolated struct AuthTokens: Sendable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var tokenType: String
}

nonisolated enum AuthTokenProviderError: Error, LocalizedError, Sendable {
    case missingTokens
    case refreshFailed(message: String, code: Int?)
    case refreshTemporarilyUnavailable
    case invalidRefreshResponse

    var errorDescription: String? {
        switch self {
        case .missingTokens:
            return "当前未登录或认证信息缺失，请先登录后再重试。"
        case .refreshFailed:
            return "登录状态已过期，令牌刷新失败，请重新登录。"
        case .refreshTemporarilyUnavailable:
            return "当前网络或服务暂不可用，稍后将自动重试令牌刷新。"
        case .invalidRefreshResponse:
            return "服务端返回了无效的令牌刷新结果，请稍后重试。"
        }
    }
}

/// 兼容多种刷新成功 JSON：`access`/`refresh` 与 `access_token`/`refresh_token`/`token_type`。
nonisolated private struct TokenRefreshSuccessEnvelope: Decodable, Sendable {
    let access: String?
    let refresh: String?
    let accessToken: String?
    let refreshToken: String?
    let tokenType: String?


    nonisolated func resolvedTokens(fallbackRefreshToken: String) -> (access: String, refresh: String, tokenType: String)? {
        let accessString = access ?? accessToken
        guard let accessString else { return nil }
        let refreshString = refresh ?? refreshToken ?? fallbackRefreshToken
        let rawType = (tokenType ?? "Bearer").trimmingCharacters(in: .whitespacesAndNewlines)
        let type = rawType.isEmpty ? "Bearer" : rawType
        return (accessString, refreshString, type)
    }
}

/// Owns access/refresh tokens and performs refresh de-duping.
actor AuthTokenProvider {
    private let keychainService: String
    private let transport: SupportNetworkTransport
    private let baseURL: URL
    private let logger: Logger

    private let refreshPath: String = "/api/v1/auth/token/refresh/"

    private var cachedTokens: AuthTokens?
    private var refreshTask: Task<AuthTokens, Error>?

    init(
        transport: SupportNetworkTransport,
        baseURL: URL,
        keychainService: String = "SupplyChainClient.Auth",
        logger: Logger = ConsoleLogger()
    ) {
        self.transport = transport
        self.baseURL = baseURL
        self.keychainService = keychainService
        self.logger = logger
    }

    func setTokens(_ tokens: AuthTokens) {
        cachedTokens = tokens
        saveToKeychain(tokens)
    }

    func clearTokens() {
        let hadKeychainAccess = keychainGet("accessToken") != nil
        cachedTokens = nil
        keychainDelete("accessToken")
        keychainDelete("refreshToken")
        keychainDelete("expiresAt")
        keychainDelete("tokenType")
        logger.debug("AuthTokenProvider：已清除 Keychain 令牌 hadAccess=\(hadKeychainAccess)", module: .auth)
    }

    func authorizationHeaderValue() async throws -> String {
        let tokens = try await validTokens()
        return "\(tokens.tokenType) \(tokens.accessToken)"
    }

    /// Forces a refresh even if current access token is not yet near `expiresAt`.
    /// Used when the server rejects the token (e.g. 401).
    func forceRefreshTokens() async throws -> AuthTokens {
        cachedTokens = nil
        return try await refreshTokensDeDuplicated()
    }

    // MARK: - Refresh / Validity

    private func validTokens() async throws -> AuthTokens {
        if let tokens = cachedTokens {
            if shouldRefresh(tokens: tokens) == false {
                return tokens
            }
            do {
                return try await refreshTokensDeDuplicated()
            } catch AuthTokenProviderError.refreshTemporarilyUnavailable {
                logger.warning("令牌刷新暂不可用，回退使用本地 access token。", module: .auth)
                return tokens
            }
        } else if let tokens = loadFromKeychain() {
            cachedTokens = tokens
            if shouldRefresh(tokens: tokens) == false {
                return tokens
            }
            do {
                return try await refreshTokensDeDuplicated()
            } catch AuthTokenProviderError.refreshTemporarilyUnavailable {
                logger.warning("从 Keychain 恢复后刷新暂不可用，回退使用本地 access token。", module: .auth)
                return tokens
            }
        }

        return try await refreshTokensDeDuplicated()
    }

    private func shouldRefresh(tokens: AuthTokens) -> Bool {
        // Refresh slightly before actual expiry to avoid edge races.
        let skew: TimeInterval = 30
        return Date().addingTimeInterval(skew) >= tokens.expiresAt
    }

    private func refreshTokensDeDuplicated() async throws -> AuthTokens {
        if let existing = refreshTask {
            return try await existing.value
        }

        guard loadRefreshToken() != nil else {
            logger.warning("刷新令牌不存在，无法发起 token refresh。", module: .auth)
            clearTokens()
            throw AuthTokenProviderError.missingTokens
        }

        let task = Task<AuthTokens, Error> {
            try await self.performRefresh()
        }
        refreshTask = task
        defer {
            // Only the creator reaches this defer; concurrent callers awaited `refreshTask`.
            refreshTask = nil
        }
        return try await task.value
    }

    private func performRefresh() async throws -> AuthTokens {
        guard let refreshToken = loadRefreshToken() else {
            logger.warning("刷新令牌读取失败，判定为未登录态。", module: .auth)
            clearTokens()
            throw AuthTokenProviderError.missingTokens
        }

        var urlRequest = URLRequest(url: url(for: refreshPath))
        urlRequest.httpMethod = SupportHTTPMethod.post.rawValue
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(RequestIdGenerator.make(), forHTTPHeaderField: "X-Request-ID")

        let (deviceId, bundleId) = await MainActor.run { () -> (String, String) in
            let systemInfo = SupportSystemInfo.shared
            return (systemInfo.installationDeviceID, systemInfo.bundleIdentifier)
        }
        let payload: [String: String] = [
            "refresh": refreshToken,
            "refresh_token": refreshToken,
            "device_id": deviceId,
            "bundle_id": bundleId,
        ]
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        logger.info(SupportNetworkingStrings.Auth.refreshing(), module: .auth)

        let response = try await transport.send(urlRequest)

        // Success: SimpleJWT 风格 { "access","refresh" } 或网关/账户服务常用 { "access_token","refresh_token","token_type" }。
        if (200...299).contains(response.httpResponse.statusCode) {
            do {
                let decoder = JSONDecoder.default
                let envelope = try decoder.decode(TokenRefreshSuccessEnvelope.self, from: response.data)
                guard let triple = envelope.resolvedTokens(fallbackRefreshToken: refreshToken) else {
                    logger.error("令牌刷新响应解析失败：缺少 access/access_token 字段。", module: .auth)
                    throw AuthTokenProviderError.invalidRefreshResponse
                }

                let claims = try JWTExpParser.parseClaims(triple.access)

                let tokens = AuthTokens(
                    accessToken: triple.access,
                    refreshToken: triple.refresh,
                    expiresAt: claims.expDate,
                    tokenType: triple.tokenType
                )
                cachedTokens = tokens
                saveToKeychain(tokens)
                logger.info(SupportNetworkingStrings.Auth.refreshSucceeded(), module: .auth)
                return tokens
            } catch let error as AuthTokenProviderError {
                throw error
            } catch {
                logger.error("令牌刷新响应解析失败：\(error.localizedDescription)", module: .auth)
                throw AuthTokenProviderError.invalidRefreshResponse
            }
        }

        // Error shape fallback: { "code":..., "msg":..., "data":... }
        let statusCode = response.httpResponse.statusCode
        let backendError: BackendError?
        do {
            let decoded = try JSONDecoder.default.decode(BackendError.self, from: response.data)
            backendError = decoded
            logger.error("令牌刷新 HTTP 错误：code=\(decoded.code) msg=\(decoded.msg)", module: .auth)
        } catch {
            backendError = nil
            logger.error("令牌刷新 HTTP 错误：status=\(statusCode)，响应体无法解析为 BackendError", module: .auth)
        }

        // 仅在响应体可解析且业务码/msg 明确为鉴权失效时清理 token；仅凭 HTTP 状态或网关/HTML 错误页时保留本地登录态。
        if let backend = backendError, isDefinitiveRefreshAuthFailure(backend) {
            clearTokens()
            logger.error(SupportNetworkingStrings.Auth.refreshFailed(), module: .auth)
            SupportAuthSessionInvalidation.postIfNeeded(
                statusCode: statusCode,
                backendCode: backend.code,
                message: backend.msg,
                source: "AuthTokenProvider.performRefresh"
            )
            throw AuthTokenProviderError.refreshFailed(message: backend.msg, code: backend.code)
        } else {
            if let backend = backendError {
                logger.warning(
                    "令牌刷新失败：HTTP \(statusCode) code=\(backend.code) msg=\(backend.msg)，未判定为明确鉴权失效，保留本地 token。",
                    module: .auth
                )
            } else {
                logger.warning("令牌刷新临时失败（HTTP \(statusCode)），保留本地 token。", module: .auth)
            }
            throw AuthTokenProviderError.refreshTemporarilyUnavailable
        }
    }

    /// 刷新接口返回的 JSON 是否明确表示「刷新令牌已不可用」，可安全清理本地凭证。
    private func isDefinitiveRefreshAuthFailure(_ backend: BackendError) -> Bool {
        if (40100...40199).contains(backend.code) || (40300...40399).contains(backend.code) {
            return true
        }
        let normalized = backend.msg.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let definitiveMessages = [
            "token_not_valid",
            "device_session_revoked",
            "device_session_replaced",
            "device_session_not_found",
            "device_mismatch",
        ]
        if definitiveMessages.contains(normalized) {
            return true
        }
        return false
    }

    private func url(for path: String) -> URL {
        // Absolute paths must preserve a trailing slash: split(separator: "/") drops the
        // final empty segment, which would turn ".../refresh/" into ".../refresh" and
        // trigger Django APPEND_SLASH → 301; URLSession then retries as GET → 405.
        if path.hasPrefix("/"), let resolved = URL(string: path, relativeTo: baseURL) {
            return resolved.absoluteURL
        }
        var url = baseURL
        for segment in path.split(separator: "/") where segment.isEmpty == false {
            url.appendPathComponent(String(segment))
        }
        return url
    }

    // MARK: - Keychain

    private func loadAccessToken() -> String? {
        keychainGet("accessToken")
    }

    private func loadRefreshToken() -> String? {
        keychainGet("refreshToken")
    }

    private func loadFromKeychain() -> AuthTokens? {
        guard
            let accessToken = keychainGet("accessToken"),
            let refreshToken = keychainGet("refreshToken"),
            let tokenType = keychainGet("tokenType"),
            let expiresAtSeconds = keychainGet("expiresAt"),
            let seconds = Double(expiresAtSeconds)
        else { return nil }

        return AuthTokens(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date(timeIntervalSince1970: seconds),
            tokenType: tokenType
        )
    }

    private func saveToKeychain(_ tokens: AuthTokens) {
        keychainSet(tokens.accessToken, "accessToken")
        keychainSet(tokens.refreshToken, "refreshToken")
        keychainSet(String(tokens.expiresAt.timeIntervalSince1970), "expiresAt")
        keychainSet(tokens.tokenType, "tokenType")
    }

    private func keychainSet(_ value: String, _ key: String) {
        guard let data = value.data(using: .utf8) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
        ]

        let deleteStatus = SecItemDelete(query as CFDictionary)
        if deleteStatus != errSecSuccess && deleteStatus != errSecItemNotFound {
            logger.warning("Keychain 删除旧 token 失败，key=\(key) status=\(deleteStatus)", module: .auth)
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus != errSecSuccess {
            logger.error("Keychain 持久化 token 失败，key=\(key) status=\(addStatus)", module: .auth)
        } else {
            logger.debug("Keychain 持久化 token 成功，key=\(key)", module: .auth)
        }
    }

    private func keychainGet(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func keychainDelete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
