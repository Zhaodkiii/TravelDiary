import Foundation

enum AccountIdentityProvider: String, Codable, Sendable, CaseIterable {
    case phone
    case email
    case apple

    var title: String {
        switch self {
        case .phone:
            return L10n.text("account_management.identity.provider.phone", fallback: "手机号")
        case .email:
            return L10n.text("account_management.identity.provider.email", fallback: "邮箱")
        case .apple:
            return L10n.text("account_management.identity.provider.apple", fallback: "Apple 登录")
        }
    }

    var icon: String {
        switch self {
        case .phone:
            return "phone.fill"
        case .email:
            return "envelope.fill"
        case .apple:
            return "applelogo"
        }
    }

    var badgeColorName: String {
        switch self {
        case .phone:
            return "green"
        case .email:
            return "red"
        case .apple:
            return "black"
        }
    }
}

struct AccountIdentityStatus: Equatable, Sendable {
    let provider: AccountIdentityProvider
    let bound: Bool
    let maskedValue: String
    let modifiable: Bool
    let bindable: Bool
}

struct AccountIdentityList: Equatable, Sendable {
    let accountID: Int64
    let bundleID: String
    let identityScope: String
    let identities: [AccountIdentityStatus]
}

enum AccountIdentityOperation: Equatable, Sendable {
    case bind(AccountIdentityProvider)
    case change(AccountIdentityProvider)

    var targetProvider: AccountIdentityProvider {
        switch self {
        case .bind(let provider), .change(let provider):
            return provider
        }
    }

    var purpose: String {
        switch self {
        case .bind:
            return "bind_identity"
        case .change:
            return "change_identity"
        }
    }

    var targetOTPScene: String {
        switch self {
        case .bind:
            return "identity_bind"
        case .change:
            return "identity_change"
        }
    }
}

struct VerificationTicket: Equatable, Sendable {
    let ticket: String
    let expiresIn: Int
}

enum IdentityVerificationRequestResult: Equatable, Sendable {
    case otp(otpID: String, expiresIn: Int)
    case appleReady
}

enum AccountIdentityReauthProof: Equatable, Sendable {
    case phone(otpID: String, code: String)
    case email(otpID: String, code: String)
    case apple(identityToken: String, authorizationCode: String?, userIdentifier: String)
}

enum AccountIdentityBindProof: Equatable, Sendable {
    case phone(target: String, otpID: String, code: String)
    case email(target: String, otpID: String, code: String)
    case apple(identityToken: String, authorizationCode: String?, userIdentifier: String)
}

/// 发码成功后冻结的手机号快照，校验/重发必须使用同一 E.164。
struct LockedPhoneTarget: Equatable, Sendable {
    let countryCode: String
    let nationalNumber: String
    let e164: String
    let displayValue: String

    init(countryCode: String, nationalNumber: String, e164: String, displayValue: String? = nil) {
        self.countryCode = countryCode
        self.nationalNumber = nationalNumber
        self.e164 = e164
        self.displayValue = displayValue ?? "\(countryCode) \(nationalNumber)"
    }

    var maskedDisplayValue: String {
        let compact = nationalNumber.replacingOccurrences(of: " ", with: "")
        guard compact.count >= 7 else { return displayValue }
        return "\(countryCode) \(compact.prefix(3))****\(compact.suffix(2))"
    }
}

struct LockedEmailTarget: Equatable, Sendable {
    let email: String
    let displayValue: String

    init(email: String, displayValue: String? = nil) {
        self.email = email
        self.displayValue = displayValue ?? email
    }
}

enum AccountIdentityTargetSnapshot: Equatable, Sendable {
    case phone(LockedPhoneTarget)
    case email(LockedEmailTarget)

    var displayValue: String {
        switch self {
        case .phone(let phone):
            return phone.maskedDisplayValue
        case .email(let email):
            return email.displayValue
        }
    }

    var rawTarget: String {
        switch self {
        case .phone(let phone):
            return phone.e164
        case .email(let email):
            return email.email
        }
    }
}

enum AccountIdentityFlowState: Equatable {
    case idle
    case choosingReauth(AccountIdentityOperation)
    case reauthOTP(AccountIdentityOperation, AccountVerificationChannel, otpID: String?)
    case reauthApple(AccountIdentityOperation)
    case enteringTarget(AccountIdentityOperation, ticket: String)
    case targetOTP(AccountIdentityOperation, ticket: String, otpID: String, target: AccountIdentityTargetSnapshot)
    case submitting
    case completed(AccountIdentityOperation)
    case failed(String)

    var isOverlayPresented: Bool {
        switch self {
        case .idle:
            return false
        case .choosingReauth, .reauthOTP, .reauthApple, .enteringTarget, .targetOTP, .submitting, .completed, .failed:
            return true
        }
    }

    var operation: AccountIdentityOperation? {
        switch self {
        case .idle, .submitting, .completed, .failed:
            return nil
        case .choosingReauth(let operation),
             .reauthOTP(let operation, _, _),
             .reauthApple(let operation),
             .enteringTarget(let operation, _),
             .targetOTP(let operation, _, _, _):
            return operation
        }
    }
}

extension AccountIdentityProvider {
    init?(providerString: String) {
        self.init(rawValue: providerString)
    }
}

extension AccountIdentityList {
    static func from(dto: SupportAccountIdentityAPI.IdentityListResult) -> AccountIdentityList {
        AccountIdentityList(
            accountID: dto.accountId,
            bundleID: dto.bundleId,
            identityScope: dto.identityScope,
            identities: dto.identities.compactMap { item in
                guard let provider = AccountIdentityProvider(providerString: item.provider) else {
                    return nil
                }
                return AccountIdentityStatus(
                    provider: provider,
                    bound: item.bound,
                    maskedValue: item.maskedValue,
                    modifiable: item.modifiable,
                    bindable: item.bindable
                )
            }
        )
    }
}
