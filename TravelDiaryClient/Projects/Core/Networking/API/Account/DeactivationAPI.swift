import Foundation

struct SupportDeactivationAPI {
    let configuration: SupportBackendConfiguration

    init(configuration: SupportBackendConfiguration) {
        self.configuration = configuration
    }

    init(engine: SupportNetworkEngine) {
        self.configuration = SupportBackendConfiguration(engine: engine, logger: engine.networkLogger)
    }

    func submit(_ request: AccountDeactivationSubmitRequest) async throws -> AccountDeactivationSubmissionResponse {
        let operation = CacheableSupportNetworkOperation(
            name: "Deactivation.Request",
            apiName: "DeactivationAPI",
            request: .init(
                method: .post,
                path: "/api/v1/deactivation/",
                body: .json(AnyEncodable(request)),
                strategy: .init(requiresAuth: true)
            )
        )
        return try await configuration.executeDecoded(AccountDeactivationSubmissionResponse.self, operation: operation)
    }
}

struct AccountDeactivationSubmitRequest: Codable, Sendable {
    let reason: String?
    let immediateDeactivation: Bool
    let countdownHours: Int?
    let dataRetentionDays: Int
    let anonymizePersonalData: Bool
    let deleteRelatedData: Bool
    let verification: AccountDeactivationVerificationPayload?

    enum CodingKeys: String, CodingKey {
        case reason
        case immediateDeactivation = "immediateDeactivation"
        case countdownHours = "countdownHours"
        case dataRetentionDays = "dataRetentionDays"
        case anonymizePersonalData = "anonymizePersonalData"
        case deleteRelatedData = "deleteRelatedData"
        case verification
    }
}

struct AccountDeactivationVerificationPayload: Codable, Sendable {
    let type: String
    let identityToken: String?
    let authorizationCode: String?
    let userIdentifier: String?
    let otpID: String?
    let code: String?

    enum CodingKeys: String, CodingKey {
        case type
        case identityToken = "identityToken"
        case authorizationCode = "authorizationCode"
        case userIdentifier = "userIdentifier"
        case otpID = "otpId"
        case code
    }
}

struct AccountDeactivationSubmissionResponse: Decodable, Sendable {
    let deactivationID: Int
    let state: String
    let scheduledAt: String?
    let immediateDeactivation: Bool?
    let countdownHours: Int?

    enum CodingKeys: String, CodingKey {
        case deactivationID = "deactivationId"
        case state
        case scheduledAt = "scheduledAt"
        case immediateDeactivation = "immediateDeactivation"
        case countdownHours = "countdownHours"
    }
}

struct OTPRequestResponse: Decodable, Sendable {
    let otpID: String
    let expiresIn: Int?

    /// Spark-compatible alias.
    var otpId: String { otpID }

    enum CodingKeys: String, CodingKey {
        case otpID = "otpId"
        case expiresIn = "expiresIn"
    }
}
