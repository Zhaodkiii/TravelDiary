import Foundation

/// 账号登录方式（身份）管理 API。
struct SupportAccountIdentityAPI {
    let configuration: SupportBackendConfiguration

    init(configuration: SupportBackendConfiguration) {
        self.configuration = configuration
    }

    init(engine: SupportNetworkEngine) {
        self.configuration = SupportBackendConfiguration(engine: engine, logger: engine.networkLogger)
    }

    struct IdentityStatusDTO: Decodable {
        let provider: String
        let bound: Bool
        let maskedValue: String
        let modifiable: Bool
        let bindable: Bool
    }

    struct IdentityListResult: Decodable {
        let accountId: Int64
        let bundleId: String
        let identityScope: String
        let identities: [IdentityStatusDTO]
    }

    struct VerificationRequestResult: Decodable {
        let otpId: String?
        let expiresIn: Int?
        let provider: String?
        let ready: Bool?
    }

    struct VerificationTicketResult: Decodable {
        let verificationTicket: String
        let expiresIn: Int
    }

    nonisolated struct IdentityVerificationRequest: Encodable {
        let provider: String
        let purpose: String
        let bundleId: String
        let deviceId: String

        enum CodingKeys: String, CodingKey {
            case provider
            case purpose
            case bundleId = "bundle_id"
            case deviceId = "device_id"
        }
    }

    nonisolated enum IdentityVerificationProof: Encodable {
        case phone(otpId: String, code: String)
        case email(otpId: String, code: String)
        case apple(identityToken: String, authorizationCode: String?, userIdentifier: String)

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodableKey.self)
            switch self {
            case .phone(let otpId, let code):
                try container.encode(otpId, forKey: .key("otp_id"))
                try container.encode(code, forKey: .key("code"))
            case .email(let otpId, let code):
                try container.encode(otpId, forKey: .key("otp_id"))
                try container.encode(code, forKey: .key("code"))
            case .apple(let identityToken, let authorizationCode, let userIdentifier):
                try container.encode(identityToken, forKey: .key("identity_token"))
                try container.encodeIfPresent(authorizationCode, forKey: .key("authorization_code"))
                try container.encode(userIdentifier, forKey: .key("user_identifier"))
            }
        }
    }

    nonisolated struct IdentityVerificationVerifyRequest: Encodable {
        let provider: String
        let purpose: String
        let bundleId: String
        let deviceId: String
        let proof: IdentityVerificationProof

        enum CodingKeys: String, CodingKey {
            case provider
            case purpose
            case bundleId = "bundle_id"
            case deviceId = "device_id"
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(provider, forKey: .provider)
            try container.encode(purpose, forKey: .purpose)
            try container.encode(bundleId, forKey: .bundleId)
            try container.encode(deviceId, forKey: .deviceId)
            try proof.encode(to: encoder)
        }
    }

    nonisolated enum BindIdentityProof: Encodable {
        case phone(target: String, otpId: String, code: String)
        case email(target: String, otpId: String, code: String)
        case apple(identityToken: String, authorizationCode: String?, userIdentifier: String)

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodableKey.self)
            switch self {
            case .phone(let target, let otpId, let code):
                try container.encode(target, forKey: .key("target"))
                try container.encode(otpId, forKey: .key("otp_id"))
                try container.encode(code, forKey: .key("code"))
            case .email(let target, let otpId, let code):
                try container.encode(target, forKey: .key("target"))
                try container.encode(otpId, forKey: .key("otp_id"))
                try container.encode(code, forKey: .key("code"))
            case .apple(let identityToken, let authorizationCode, let userIdentifier):
                try container.encode(identityToken, forKey: .key("identity_token"))
                try container.encodeIfPresent(authorizationCode, forKey: .key("authorization_code"))
                try container.encode(userIdentifier, forKey: .key("user_identifier"))
            }
        }
    }

    nonisolated struct BindIdentityRequest: Encodable {
        let provider: String
        let verificationTicket: String
        let bundleId: String
        let deviceId: String
        let proof: BindIdentityProof

        enum CodingKeys: String, CodingKey {
            case provider
            case verificationTicket = "verification_ticket"
            case bundleId = "bundle_id"
            case deviceId = "device_id"
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(provider, forKey: .provider)
            try container.encode(verificationTicket, forKey: .verificationTicket)
            try container.encode(bundleId, forKey: .bundleId)
            try container.encode(deviceId, forKey: .deviceId)
            try proof.encode(to: encoder)
        }
    }

    nonisolated struct ChangeIdentityRequest: Encodable {
        let provider: String
        let verificationTicket: String
        let bundleId: String
        let deviceId: String
        let newTarget: String
        let newOtpId: String
        let newCode: String

        enum CodingKeys: String, CodingKey {
            case provider
            case verificationTicket = "verification_ticket"
            case bundleId = "bundle_id"
            case deviceId = "device_id"
            case newTarget = "new_target"
            case newOtpId = "new_otp_id"
            case newCode = "new_code"
        }
    }

    func listIdentities(bundleId: String) async throws -> IdentityListResult {
        let operation = CacheableSupportNetworkOperation(
            name: "AccountIdentity.List",
            apiName: "AccountIdentityAPI",
            request: .init(
                method: .get,
                path: "/api/v1/accounts/identities/",
                queryItems: [URLQueryItem(name: "bundle_id", value: bundleId)],
                body: .none,
                strategy: .init(requiresAuth: true)
            )
        )

        return try await configuration.executeDecoded(IdentityListResult.self, operation: operation)
    }

    func requestVerification(_ request: IdentityVerificationRequest) async throws -> VerificationRequestResult {
        let operation = CacheableSupportNetworkOperation(
            name: "AccountIdentity.VerificationRequest",
            apiName: "AccountIdentityAPI",
            request: .init(
                method: .post,
                path: "/api/v1/accounts/identity-verification/request/",
                body: .json(AnyEncodable(request)),
                strategy: .init(requiresAuth: true)
            )
        )

        return try await configuration.executeDecoded(VerificationRequestResult.self, operation: operation)
    }

    func verifyAndIssueTicket(_ request: IdentityVerificationVerifyRequest) async throws -> VerificationTicketResult {
        let operation = CacheableSupportNetworkOperation(
            name: "AccountIdentity.VerificationVerify",
            apiName: "AccountIdentityAPI",
            request: .init(
                method: .post,
                path: "/api/v1/accounts/identity-verification/verify/",
                body: .json(AnyEncodable(request)),
                strategy: .init(requiresAuth: true)
            )
        )

        return try await configuration.executeDecoded(VerificationTicketResult.self, operation: operation)
    }

    func bindIdentity(_ request: BindIdentityRequest) async throws -> IdentityListResult {
        let operation = CacheableSupportNetworkOperation(
            name: "AccountIdentity.Bind",
            apiName: "AccountIdentityAPI",
            request: .init(
                method: .post,
                path: "/api/v1/accounts/identities/bind/",
                body: .json(AnyEncodable(request)),
                strategy: .init(requiresAuth: true)
            )
        )

        return try await configuration.executeDecoded(IdentityListResult.self, operation: operation)
    }

    func changeIdentity(_ request: ChangeIdentityRequest) async throws -> IdentityListResult {
        let operation = CacheableSupportNetworkOperation(
            name: "AccountIdentity.Change",
            apiName: "AccountIdentityAPI",
            request: .init(
                method: .post,
                path: "/api/v1/accounts/identities/change/",
                body: .json(AnyEncodable(request)),
                strategy: .init(requiresAuth: true)
            )
        )

        return try await configuration.executeDecoded(IdentityListResult.self, operation: operation)
    }
}
