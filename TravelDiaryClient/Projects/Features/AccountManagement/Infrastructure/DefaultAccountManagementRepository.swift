import Foundation

final class DefaultAccountManagementRepository: AccountManagementRepository {
    private let backend: SupportBackend

    init(backend: SupportBackend) {
        self.backend = backend
    }

    private var bundleId: String {
        Bundle.main.bundleIdentifier ?? "TravelDiary"
    }

    private var deviceId: String {
        SupportKeychain.getOrCreateDeviceID()
    }

    func loadAccountProfile(session: UserSession?) async throws -> AccountProfile {
        guard let session else {
            throw AccountManagementError.missingSession
        }
        return AccountProfile(
            accountID: session.accountID,
            displayName: session.displayName,
            contact: session.email,
            signInMethod: session.signInMethod,
            signedInAt: session.signedInAt,
            isPro: session.isPro
        )
    }

    func loadIdentities(session: UserSession?) async throws -> AccountIdentityList {
        guard session != nil else {
            throw AccountManagementError.missingSession
        }
        let result = try await backend.accountIdentity.listIdentities(bundleId: bundleId)
        return AccountIdentityList.from(dto: result)
    }

    func requestVerification(channel: AccountVerificationChannel, session: UserSession?) async throws -> AccountVerificationRequestContext {
        switch channel {
        case .phone(let phoneNumber):
            guard let session else {
                throw AccountManagementError.missingSession
            }
            let result = try await backend.otp.requestPhoneOTP(
                phoneNumber: phoneNumber,
                bundleId: bundleId,
                deviceId: deviceId,
                scene: "account_deactivation",
                userId: Int(session.accountID)
            )
            return AccountVerificationRequestContext(
                channel: channel,
                otpID: result.otpId,
                expiresIn: result.expiresIn ?? 300
            )
        case .email(let email):
            let result = try await backend.otp.requestEmailOTP(
                email: email,
                bundleId: bundleId,
                deviceId: deviceId,
                scene: "login"
            )
            return AccountVerificationRequestContext(
                channel: channel,
                otpID: result.otpId,
                expiresIn: result.expiresIn ?? 300
            )
        case .apple:
            throw AccountManagementError.unsupportedVerificationChannel
        }
    }

    func requestIdentityVerification(
        provider: AccountIdentityProvider,
        purpose: String,
        session: UserSession?
    ) async throws -> IdentityVerificationRequestResult {
        guard session != nil else {
            throw AccountManagementError.missingSession
        }

        let request = SupportAccountIdentityAPI.IdentityVerificationRequest(
            provider: provider.rawValue,
            purpose: purpose,
            bundleId: bundleId,
            deviceId: deviceId
        )
        let result = try await backend.accountIdentity.requestVerification(request)

        if result.ready == true {
            return .appleReady
        }
        guard let otpID = result.otpId, let expiresIn = result.expiresIn else {
            throw AccountManagementError.unsupportedVerificationChannel
        }
        return .otp(otpID: otpID, expiresIn: expiresIn)
    }

    func verifyIdentityVerification(
        provider: AccountIdentityProvider,
        purpose: String,
        proof: AccountIdentityReauthProof,
        session: UserSession?
    ) async throws -> VerificationTicket {
        guard session != nil else {
            throw AccountManagementError.missingSession
        }

        let apiProof: SupportAccountIdentityAPI.IdentityVerificationProof
        switch proof {
        case .phone(let otpID, let code):
            apiProof = .phone(otpId: otpID, code: code)
        case .email(let otpID, let code):
            apiProof = .email(otpId: otpID, code: code)
        case .apple(let identityToken, let authorizationCode, let userIdentifier):
            apiProof = .apple(
                identityToken: identityToken,
                authorizationCode: authorizationCode,
                userIdentifier: userIdentifier
            )
        }

        let request = SupportAccountIdentityAPI.IdentityVerificationVerifyRequest(
            provider: provider.rawValue,
            purpose: purpose,
            bundleId: bundleId,
            deviceId: deviceId,
            proof: apiProof
        )
        let result = try await backend.accountIdentity.verifyAndIssueTicket(request)
        return VerificationTicket(ticket: result.verificationTicket, expiresIn: result.expiresIn)
    }

    func requestTargetOTP(
        provider: AccountIdentityProvider,
        target: String,
        operation: AccountIdentityOperation,
        session: UserSession?
    ) async throws -> AccountVerificationRequestContext {
        guard let session else {
            throw AccountManagementError.missingSession
        }

        let scene = operation.targetOTPScene
        switch provider {
        case .phone:
            let result = try await backend.otp.requestPhoneOTP(
                phoneNumber: target,
                bundleId: bundleId,
                deviceId: deviceId,
                scene: scene,
                userId: Int(session.accountID)
            )
            return AccountVerificationRequestContext(
                channel: .phone(target),
                otpID: result.otpId,
                expiresIn: result.expiresIn ?? 300
            )
        case .email:
            let result = try await backend.otp.requestEmailOTP(
                email: target,
                bundleId: bundleId,
                deviceId: deviceId,
                scene: scene
            )
            return AccountVerificationRequestContext(
                channel: .email(target),
                otpID: result.otpId,
                expiresIn: result.expiresIn ?? 300
            )
        case .apple:
            throw AccountManagementError.unsupportedVerificationChannel
        }
    }

    func bindIdentity(
        provider: AccountIdentityProvider,
        verificationTicket: String,
        proof: AccountIdentityBindProof,
        session: UserSession?
    ) async throws -> AccountIdentityList {
        guard session != nil else {
            throw AccountManagementError.missingSession
        }

        let apiProof: SupportAccountIdentityAPI.BindIdentityProof
        switch proof {
        case .phone(let target, let otpID, let code):
            apiProof = .phone(target: target, otpId: otpID, code: code)
        case .email(let target, let otpID, let code):
            apiProof = .email(target: target, otpId: otpID, code: code)
        case .apple(let identityToken, let authorizationCode, let userIdentifier):
            apiProof = .apple(
                identityToken: identityToken,
                authorizationCode: authorizationCode,
                userIdentifier: userIdentifier
            )
        }

        let request = SupportAccountIdentityAPI.BindIdentityRequest(
            provider: provider.rawValue,
            verificationTicket: verificationTicket,
            bundleId: bundleId,
            deviceId: deviceId,
            proof: apiProof
        )
        let result = try await backend.accountIdentity.bindIdentity(request)
        return AccountIdentityList.from(dto: result)
    }

    func changeIdentity(
        provider: AccountIdentityProvider,
        verificationTicket: String,
        newTarget: String,
        newOtpID: String,
        newCode: String,
        session: UserSession?
    ) async throws -> AccountIdentityList {
        guard session != nil else {
            throw AccountManagementError.missingSession
        }

        let request = SupportAccountIdentityAPI.ChangeIdentityRequest(
            provider: provider.rawValue,
            verificationTicket: verificationTicket,
            bundleId: bundleId,
            deviceId: deviceId,
            newTarget: newTarget,
            newOtpId: newOtpID,
            newCode: newCode
        )
        let result = try await backend.accountIdentity.changeIdentity(request)
        return AccountIdentityList.from(dto: result)
    }

    func submitDeactivation(options: AccountDeactivationOptions, verification: AccountDeactivationVerification) async throws -> AccountDeactivationSubmission {
        let apiVerification: AccountDeactivationVerificationPayload
        switch verification {
        case .apple(let identityToken, let authorizationCode, let userIdentifier):
            apiVerification = AccountDeactivationVerificationPayload(
                type: "apple",
                identityToken: identityToken,
                authorizationCode: authorizationCode,
                userIdentifier: userIdentifier,
                otpID: nil,
                code: nil
            )
        case .phone(let otpId, let code):
            apiVerification = AccountDeactivationVerificationPayload(
                type: "phone",
                identityToken: nil,
                authorizationCode: nil,
                userIdentifier: nil,
                otpID: otpId,
                code: code
            )
        case .email(let otpId, let code):
            apiVerification = AccountDeactivationVerificationPayload(
                type: "email",
                identityToken: nil,
                authorizationCode: nil,
                userIdentifier: nil,
                otpID: otpId,
                code: code
            )
        }

        let request = AccountDeactivationSubmitRequest(
            reason: options.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : options.reason,
            immediateDeactivation: options.immediateDeactivation,
            countdownHours: options.immediateDeactivation ? nil : options.countdownHours,
            dataRetentionDays: options.dataRetentionDays,
            anonymizePersonalData: options.anonymizePersonalData,
            deleteRelatedData: options.deleteRelatedData,
            verification: apiVerification
        )
        let result = try await backend.deactivation.submit(request)
        return AccountDeactivationSubmission(
            deactivationID: result.deactivationID,
            state: result.state,
            scheduledAt: result.scheduledAt,
            immediateDeactivation: result.immediateDeactivation,
            countdownHours: result.countdownHours
        )
    }
}
