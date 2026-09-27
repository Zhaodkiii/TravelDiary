import Foundation

struct SupportOTPAPI {
    let configuration: SupportBackendConfiguration

    init(configuration: SupportBackendConfiguration) {
        self.configuration = configuration
    }

    init(engine: SupportNetworkEngine) {
        self.configuration = SupportBackendConfiguration(engine: engine, logger: engine.networkLogger)
    }

    /// 需要携带鉴权 Header 的场景：账号已登录后再次校验或修改登录方式。对齐 Spark `identityAuthScenes`。
    private static let identityAuthScenes: Set<String> = ["account_deactivation", "identity_bind", "identity_change"]

    /// 对齐 Spark `SparkOTPAPI.OTPVerifyResult`。
    struct OTPVerifyResult: Decodable, Sendable {
        let userId: Int64
        let accessToken: String
        let refreshToken: String
        let expiresIn: Int
        let tokenType: String
        let otpId: String
    }

    /// 对齐 Spark `SparkOTPAPI.PhoneOTPVerifyResult`。
    struct PhoneOTPVerifyResult: Decodable, Sendable {
        let userId: Int64
        let phoneNumber: String
        let displayName: String?
        let isPro: Bool?
        let accessToken: String
        let refreshToken: String
        let expiresIn: Int
        let tokenType: String
        let otpId: String
        let isNewUser: Bool?
        let signInMethod: String?
        let isDeviceAccount: Bool?
        let accountResolution: String?
    }

    /// - Parameters:
    ///   - scene: 业务场景，默认 `login`；`identity_bind` / `identity_change` 属于已登录账号的绑定/换绑场景，需要携带鉴权 Header。
    func requestEmailOTP(
        email: String,
        providerUID: String = "",
        bundleID: String,
        deviceID: String,
        scene: String = "login"
    ) async throws -> OTPRequestResponse {
        let body = EmailOTPRequest(email: email, providerUID: providerUID, bundleID: bundleID, deviceID: deviceID, scene: scene)
        let requiresAuth = Self.identityAuthScenes.contains(scene)
        let operation = CacheableSupportNetworkOperation(
            name: "OTP.RequestEmail",
            apiName: "OTPAPI",
            request: .init(
                method: .post,
                path: "/api/v1/otp/email/request/",
                body: .json(AnyEncodable(body)),
                strategy: .init(requiresAuth: requiresAuth)
            )
        )
        return try await configuration.executeDecoded(OTPRequestResponse.self, operation: operation)
    }

    /// 对齐 Spark：解码后写 Keychain，返回 `AuthTokens`。
    func verifyEmailOTP(
        otpID: String,
        email: String,
        code: String,
        bundleID: String,
        deviceID: String,
        deviceSecret: String = ""
    ) async throws -> AuthTokens {
        let body = EmailOTPVerifyRequest(otpID: otpID, email: email, code: code, bundleID: bundleID, deviceID: deviceID, deviceSecret: deviceSecret)
        let operation = CacheableSupportNetworkOperation(
            name: "OTP.VerifyEmail",
            apiName: "OTPAPI",
            request: .init(method: .post, path: "/api/v1/otp/email/verify/", body: .json(AnyEncodable(body)))
        )
        let result = try await configuration.executeDecoded(OTPVerifyResult.self, operation: operation)
        let tokens = AuthTokens(
            accessToken: result.accessToken,
            refreshToken: result.refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(result.expiresIn)),
            tokenType: result.tokenType
        )
        await configuration.engine.tokenStore().setTokens(tokens)
        configuration.logger.info(
            "认证解码：邮箱 OTP 登录响应解析成功 userId=\(result.userId)",
            module: .auth
        )
        return tokens
    }

    /// - Parameters:
    ///   - scene: 业务场景，默认 `login`；`account_deactivation` / `identity_bind` / `identity_change` 需要携带鉴权 Header。
    ///   - userId: 传入后视为已登录账号发码（例如账号注销前验证），会强制带鉴权 Header。
    func requestPhoneOTP(
        phoneNumber: String,
        providerUID: String = "",
        bundleID: String,
        deviceID: String,
        scene: String = "login",
        userId: Int64? = nil
    ) async throws -> OTPRequestResponse {
        let body = PhoneOTPRequest(
            phoneNumber: phoneNumber,
            providerUID: providerUID,
            bundleID: bundleID,
            deviceID: deviceID,
            scene: scene,
            userId: userId
        )
        let requiresAuth = userId != nil || Self.identityAuthScenes.contains(scene)
        let operation = CacheableSupportNetworkOperation(
            name: "OTP.RequestPhone",
            apiName: "OTPAPI",
            request: .init(
                method: .post,
                path: "/api/v1/otp/phone/request/",
                body: .json(AnyEncodable(body)),
                strategy: .init(requiresAuth: requiresAuth)
            )
        )
        return try await configuration.executeDecoded(OTPRequestResponse.self, operation: operation)
    }

    /// 对齐 Spark：解码后写 Keychain，返回 `PhoneOTPVerifyResult`。
    func verifyPhoneOTP(
        phoneNumber: String,
        otpID: String,
        code: String,
        bundleID: String,
        deviceID: String,
        deviceSecret: String = ""
    ) async throws -> PhoneOTPVerifyResult {
        let body = PhoneOTPVerifyRequest(
            otpID: otpID,
            phoneNumber: phoneNumber,
            code: code,
            bundleID: bundleID,
            deviceID: deviceID,
            deviceSecret: deviceSecret
        )
        let operation = CacheableSupportNetworkOperation(
            name: "OTP.VerifyPhone",
            apiName: "OTPAPI",
            request: .init(method: .post, path: "/api/v1/otp/phone/verify/", body: .json(AnyEncodable(body)))
        )
        let result = try await configuration.executeDecoded(PhoneOTPVerifyResult.self, operation: operation)
        let tokens = AuthTokens(
            accessToken: result.accessToken,
            refreshToken: result.refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(result.expiresIn)),
            tokenType: result.tokenType
        )
        await configuration.engine.tokenStore().setTokens(tokens)
        configuration.logger.info(
            "认证解码：手机号 OTP 登录响应解析成功 userId=\(result.userId) isPro=\(result.isPro ?? false) isNewUser=\(result.isNewUser ?? false) resolution=\(result.accountResolution ?? "-")",
            module: .auth
        )
        return result
    }


    func requestPhoneOTP(
        phoneNumber: String,
        providerUID: String = "",
        bundleId: String,
        deviceId: String,
        scene: String = "login",
        userId: Int? = nil
    ) async throws -> OTPRequestResponse {
        try await requestPhoneOTP(
            phoneNumber: phoneNumber,
            providerUID: providerUID,
            bundleID: bundleId,
            deviceID: deviceId,
            scene: scene,
            userId: userId.map { Int64($0) }
        )
    }

    func requestEmailOTP(
        email: String,
        providerUID: String = "",
        bundleId: String,
        deviceId: String,
        scene: String = "login"
    ) async throws -> OTPRequestResponse {
        try await requestEmailOTP(
            email: email,
            providerUID: providerUID,
            bundleID: bundleId,
            deviceID: deviceId,
            scene: scene
        )
    }

    func verifyPhoneOTP(
        otpId: String,
        phoneNumber: String,
        code: String,
        bundleId: String,
        deviceId: String,
        deviceSecret: String = ""
    ) async throws -> PhoneOTPVerifyResult {
        try await verifyPhoneOTP(
            phoneNumber: phoneNumber,
            otpID: otpId,
            code: code,
            bundleID: bundleId,
            deviceID: deviceId,
            deviceSecret: deviceSecret
        )
    }

}

struct PhoneOTPRequest: Encodable, Sendable {
    let phoneNumber: String
    let providerUID: String
    let bundleID: String
    let deviceID: String
    let scene: String
    let userId: Int64?
    enum CodingKeys: String, CodingKey {
        case phoneNumber = "phoneNumber"
        case providerUID = "providerUid"
        case bundleID = "bundleId"
        case deviceID = "deviceId"
        case scene
        case userId = "userId"
    }
}

struct EmailOTPRequest: Encodable, Sendable {
    let email: String
    let providerUID: String
    let bundleID: String
    let deviceID: String
    let scene: String

    enum CodingKeys: String, CodingKey {
        case email
        case providerUID = "providerUid"
        case bundleID = "bundleId"
        case deviceID = "deviceId"
        case scene
    }
}

struct PhoneOTPVerifyRequest: Encodable, Sendable {
    let otpID: String
    let phoneNumber: String
    let code: String
    let bundleID: String
    let deviceID: String
    let deviceSecret: String
    enum CodingKeys: String, CodingKey {
        case otpID = "otpId"
        case phoneNumber = "phoneNumber"
        case code
        case bundleID = "bundleId"
        case deviceID = "deviceId"
        case deviceSecret = "deviceSecret"
    }
}

struct EmailOTPVerifyRequest: Encodable, Sendable {
    let otpID: String
    let email: String
    let code: String
    let bundleID: String
    let deviceID: String
    let deviceSecret: String
    enum CodingKeys: String, CodingKey {
        case otpID = "otpId"
        case email
        case code
        case bundleID = "bundleId"
        case deviceID = "deviceId"
        case deviceSecret = "deviceSecret"
    }
}
