import Foundation

struct AccountProfile: Equatable, Sendable {
    let accountID: Int64
    let displayName: String
    let contact: String
    let signInMethod: UserSession.SignInMethod
    let signedInAt: Date
    let isPro: Bool

    var email: String? {
        contact.contains("@") ? contact : nil
    }

    var phoneNumber: String? {
        signInMethod == .phone ? contact : nil
    }

    var signInMethodDescription: String {
        switch signInMethod {
        case .apple:
            return L10n.text("account_management.sign_in.apple", fallback: "Apple 登录")
        case .phone:
            return L10n.text("account_management.sign_in.phone", fallback: "手机号验证码")
        case .email:
            return L10n.text("account_management.sign_in.email", fallback: "邮箱验证码")
        case .google:
            return L10n.text("account_management.sign_in.google", fallback: "Google 登录")
        case .device:
            return L10n.text("account_management.sign_in.device", fallback: "游客模式")
        }
    }
}

enum AccountVerificationChannel: Equatable, Sendable {
    case apple
    case phone(String)
    case email(String)

    var title: String {
        switch self {
        case .apple:
            return L10n.text("account_management.verify.apple", fallback: "Apple 登录验证")
        case .phone:
            return L10n.text("account_management.verify.phone", fallback: "手机短信验证")
        case .email:
            return L10n.text("account_management.verify.email", fallback: "邮箱验证")
        }
    }

    var target: String {
        switch self {
        case .apple:
            return L10n.text("account_management.target.apple_id", fallback: "Apple ID")
        case .phone(let value), .email(let value):
            return value
        }
    }
}

enum AccountDeactivationVerification: Equatable, Sendable {
    case apple(identityToken: String, authorizationCode: String?, userIdentifier: String)
    case phone(otpID: String, code: String)
    case email(otpID: String, code: String)
}

struct AccountDeactivationOptions: Equatable, Sendable {
    var reason: String = ""
    var immediateDeactivation: Bool = true
    var countdownHours: Int = 24
    var dataRetentionDays: Int = 30
    var anonymizePersonalData: Bool = true
    var deleteRelatedData: Bool = true
}

struct AccountDeactivationSubmission: Equatable, Sendable {
    let deactivationID: Int
    let state: String
    let scheduledAt: String?
    let immediateDeactivation: Bool?
    let countdownHours: Int?
}

struct AccountVerificationRequestContext: Equatable, Sendable {
    let channel: AccountVerificationChannel
    let otpID: String
    let expiresIn: Int
}

enum AccountManagementError: LocalizedError {
    case missingSession
    case unsupportedVerificationChannel
    case missingVerificationProof
    case invalidAppleCredential

    var errorDescription: String? {
        switch self {
        case .missingSession:
            return L10n.text("account_management.error.missing_session", fallback: "当前登录会话不可用")
        case .unsupportedVerificationChannel:
            return L10n.text("account_management.error.unsupported_channel", fallback: "当前验证方式暂不可用")
        case .missingVerificationProof:
            return L10n.text("account_management.error.missing_proof", fallback: "请先完成身份验证")
        case .invalidAppleCredential:
            return L10n.text("account_management.error.invalid_apple", fallback: "Apple 身份验证凭证无效")
        }
    }
}

