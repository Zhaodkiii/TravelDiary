import Foundation

protocol AccountManagementRepository: Sendable {
    func loadAccountProfile(session: UserSession?) async throws -> AccountProfile
    func requestVerification(channel: AccountVerificationChannel, session: UserSession?) async throws -> AccountVerificationRequestContext
    func submitDeactivation(options: AccountDeactivationOptions, verification: AccountDeactivationVerification) async throws -> AccountDeactivationSubmission
    func loadIdentities(session: UserSession?) async throws -> AccountIdentityList
    func requestIdentityVerification(
        provider: AccountIdentityProvider,
        purpose: String,
        session: UserSession?
    ) async throws -> IdentityVerificationRequestResult
    func verifyIdentityVerification(
        provider: AccountIdentityProvider,
        purpose: String,
        proof: AccountIdentityReauthProof,
        session: UserSession?
    ) async throws -> VerificationTicket
    func requestTargetOTP(
        provider: AccountIdentityProvider,
        target: String,
        operation: AccountIdentityOperation,
        session: UserSession?
    ) async throws -> AccountVerificationRequestContext
    func bindIdentity(
        provider: AccountIdentityProvider,
        verificationTicket: String,
        proof: AccountIdentityBindProof,
        session: UserSession?
    ) async throws -> AccountIdentityList
    func changeIdentity(
        provider: AccountIdentityProvider,
        verificationTicket: String,
        newTarget: String,
        newOtpID: String,
        newCode: String,
        session: UserSession?
    ) async throws -> AccountIdentityList
}
