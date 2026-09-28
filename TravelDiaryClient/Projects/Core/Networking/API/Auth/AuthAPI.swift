import Foundation

struct SupportAuthAPI {
    let configuration: SupportBackendConfiguration

    init(configuration: SupportBackendConfiguration) {
        self.configuration = configuration
    }

    init(engine: SupportNetworkEngine) {
        self.configuration = SupportBackendConfiguration(engine: engine, logger: engine.networkLogger)
    }

    /// 密码登录响应（仅 token + userId），对齐 Spark `SparkAuthAPI.LoginResult`。
    struct LoginResult: Decodable, Sendable {
        let userId: Int64
        let accessToken: String
        let refreshToken: String
        let expiresIn: Int
        let tokenType: String
    }

    /// Apple / 设备登录成功后的账号上下文，对齐 Spark `SparkAuthAPI.AuthenticatedUserContext`。
    struct AuthenticatedUserContext: Sendable {
        let userId: Int64
        let email: String?
        let displayName: String?
        let isPro: Bool
        let isNewUser: Bool
        let signInMethod: String?
        let isDeviceAccount: Bool
        let accountResolution: AccountResolution?
        let tokens: AuthTokens
    }

    /// Apple 登录响应，对齐 Spark `SparkAuthAPI.AppleLoginResult`。
    struct AppleLoginResult: Decodable, Sendable {
        let userId: Int64
        let accessToken: String
        let refreshToken: String
        let expiresIn: Int
        let tokenType: String
        let email: String?
        let displayName: String?
        let isPro: Bool?
        let isNewUser: Bool?
        let signInMethod: String?
        let isDeviceAccount: Bool?
        let accountResolution: String?
    }

    /// 设备登录响应，对齐 Spark `SparkAuthAPI.DeviceLoginResult`。
    struct DeviceLoginResult: Decodable, Sendable {
        let userId: Int64
        let accessToken: String
        let refreshToken: String
        let expiresIn: Int
        let tokenType: String
        let email: String?
        let displayName: String?
        let isPro: Bool?
        let isNewUser: Bool?
        let signInMethod: String?
        let isDeviceAccount: Bool?
        let accountResolution: String?
    }

    /// 冷启动刷新当前账号会话（含最新 `is_pro`），对齐 Spark `SparkAuthAPI.CurrentSessionResult`。
    struct CurrentSessionResult: Decodable, Sendable {
        let userId: Int64
        let email: String?
        let displayName: String?
        let isPro: Bool?
        let isNewUser: Bool?
        let signInMethod: String?
        let isDeviceAccount: Bool?
    }

    func appleLogin(_ request: AppleLoginRequest) async throws -> AuthenticatedUserContext {
        let operation = CacheableSupportNetworkOperation(
            name: "Auth.AppleLogin",
            apiName: "AuthAPI",
            request: .init(method: .post, path: "/api/v1/auth/apple/login/", body: .json(AnyEncodable(request)))
        )
        configuration.logger.debug("认证解码：开始解析 Apple 登录响应为 AppleLoginResult", module: .auth)
        let result = try await configuration.executeDecoded(AppleLoginResult.self, operation: operation)
        configuration.logger.info(
            "认证解码：Apple 登录响应解析成功 userId=\(result.userId) email=\(result.email ?? "-") isPro=\(result.isPro ?? false) isNewUser=\(result.isNewUser ?? false) resolution=\(result.accountResolution ?? "-")",
            module: .auth
        )
        let tokens = AuthTokens(
            accessToken: result.accessToken,
            refreshToken: result.refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(result.expiresIn)),
            tokenType: result.tokenType
        )
        await configuration.engine.tokenStore().setTokens(tokens)
        return AuthenticatedUserContext(
            userId: result.userId,
            email: result.email,
            displayName: result.displayName,
            isPro: result.isPro ?? false,
            isNewUser: result.isNewUser ?? false,
            signInMethod: result.signInMethod ?? "apple",
            isDeviceAccount: result.isDeviceAccount ?? false,
            accountResolution: AccountResolution(rawValue: result.accountResolution ?? ""),
            tokens: tokens
        )
    }

    /// 游客模式设备账号登录，对齐 Spark `SparkAuthAPI.loginWithDevice`。
    func deviceLogin(_ request: DeviceLoginRequest) async throws -> AuthenticatedUserContext {
        let operation = CacheableSupportNetworkOperation(
            name: "Auth.DeviceLogin",
            apiName: "AuthAPI",
            request: .init(method: .post, path: "/api/v1/auth/device/login/", body: .json(AnyEncodable(request)))
        )
        configuration.logger.debug("认证解码：开始解析设备登录响应为 DeviceLoginResult", module: .auth)
        let result = try await configuration.executeDecoded(DeviceLoginResult.self, operation: operation)
        configuration.logger.info(
            "认证解码：设备登录响应解析成功 userId=\(result.userId) resolution=\(result.accountResolution ?? "-")",
            module: .auth
        )
        let tokens = AuthTokens(
            accessToken: result.accessToken,
            refreshToken: result.refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(result.expiresIn)),
            tokenType: result.tokenType
        )
        await configuration.engine.tokenStore().setTokens(tokens)
        return AuthenticatedUserContext(
            userId: result.userId,
            email: result.email,
            displayName: result.displayName,
            isPro: result.isPro ?? false,
            isNewUser: result.isNewUser ?? false,
            signInMethod: result.signInMethod ?? "device",
            isDeviceAccount: result.isDeviceAccount ?? true,
            accountResolution: AccountResolution(rawValue: result.accountResolution ?? ""),
            tokens: tokens
        )
    }

    /// 密码登录：对齐 Spark 解码 `LoginResult` 并写 Keychain；返回完整 `LoginResult` 以便构造无 token 的 `UserSession`。
    func passwordLogin(_ request: PasswordLoginRequest) async throws -> LoginResult {
        let operation = CacheableSupportNetworkOperation(
            name: "Auth.PasswordLogin",
            apiName: "AuthAPI",
            request: .init(method: .post, path: "/api/v1/auth/password/login/", body: .json(AnyEncodable(request)))
        )
        configuration.logger.debug("认证解码：开始解析密码登录响应为 LoginResult", module: .auth)
        let result = try await configuration.executeDecoded(LoginResult.self, operation: operation)
        configuration.logger.info(
            "认证解码：密码登录响应解析成功 userId=\(result.userId) tokenType=\(result.tokenType) expiresIn=\(result.expiresIn)",
            module: .auth
        )
        let tokens = AuthTokens(
            accessToken: result.accessToken,
            refreshToken: result.refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(result.expiresIn)),
            tokenType: result.tokenType
        )
        await configuration.engine.tokenStore().setTokens(tokens)
        return result
    }

    func currentSession() async throws -> CurrentSessionResult {
        let operation = CacheableSupportNetworkOperation(
            name: "Auth.CurrentSession",
            apiName: "AuthAPI",
            request: .init(method: .get, path: "/api/v1/auth/session/", strategy: .init(requiresAuth: true))
        )
        let result = try await configuration.executeDecoded(CurrentSessionResult.self, operation: operation)
        configuration.logger.info(
            "认证解码：当前会话刷新成功 userId=\(result.userId) isPro=\(result.isPro ?? false) isDeviceAccount=\(result.isDeviceAccount ?? false)",
            module: .auth
        )
        return result
    }

    func logout() async throws {
        let operation = CacheableSupportNetworkOperation(
            name: "Auth.Logout",
            apiName: "AuthAPI",
            request: .init(method: .post, path: "/api/v1/auth/logout/", strategy: .init(requiresAuth: true))
        )
        let _: EmptyResponse = try await configuration.executeDecoded(EmptyResponse.self, operation: operation)
        configuration.logger.info("认证：服务端登出成功", module: .auth)
    }

    // MARK: - Spark-compatible method names (Auth Feature / AccountManagement)

    func loginWithApple(
        identityToken: String,
        authorizationCode: String?,
        nonce: String?,
        user: String,
        email: String?,
        fullName: String?,
        bundleId: String = "",
        deviceId: String = "",
        deviceSecret: String = ""
    ) async throws -> AuthenticatedUserContext {
        try await appleLogin(
            AppleLoginRequest(
                identityToken: identityToken,
                authorizationCode: authorizationCode,
                nonce: nonce,
                user: user,
                email: email,
                fullName: fullName,
                bundleID: bundleId,
                deviceID: deviceId,
                deviceSecret: deviceSecret
            )
        )
    }

    func loginWithDevice(
        bundleId: String,
        deviceId: String,
        deviceSecret: String
    ) async throws -> AuthenticatedUserContext {
        try await deviceLogin(
            DeviceLoginRequest(bundleID: bundleId, deviceID: deviceId, deviceSecret: deviceSecret)
        )
    }

    func fetchCurrentSession() async throws -> CurrentSessionResult {
        try await currentSession()
    }

}

struct PasswordLoginRequest: Encodable, Sendable {
    let identifier: String
    let password: String
    let bundleID: String
    let deviceID: String

    enum CodingKeys: String, CodingKey {
        case identifier
        case password
        case bundleID = "bundleId"
        case deviceID = "deviceId"
    }
}

struct AppleLoginRequest: Encodable, Sendable {
    let identityToken: String
    let authorizationCode: String?
    let nonce: String?
    let user: String
    let email: String?
    let fullName: String?
    let bundleID: String
    let deviceID: String
    let deviceSecret: String

    enum CodingKeys: String, CodingKey {
        case identityToken = "identityToken"
        case authorizationCode = "authorizationCode"
        case nonce
        case user
        case email
        case fullName = "fullName"
        case bundleID = "bundleId"
        case deviceID = "deviceId"
        case deviceSecret = "deviceSecret"
    }
}

/// 游客模式设备账号登录请求，对齐 Spark `loginWithDevice` 参数。
struct DeviceLoginRequest: Encodable, Sendable {
    let bundleID: String
    let deviceID: String
    let deviceSecret: String

    enum CodingKeys: String, CodingKey {
        case bundleID = "bundleId"
        case deviceID = "deviceId"
        case deviceSecret = "deviceSecret"
    }
}

