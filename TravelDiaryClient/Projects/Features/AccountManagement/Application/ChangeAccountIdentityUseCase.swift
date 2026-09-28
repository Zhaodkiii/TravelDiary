import Foundation

struct ChangeAccountIdentityUseCase: Sendable {
    private let repository: any AccountManagementRepository

    init(repository: any AccountManagementRepository) {
        self.repository = repository
    }

    func execute(
        provider: AccountIdentityProvider,
        verificationTicket: String,
        newTarget: String,
        newOtpID: String,
        newCode: String,
        session: UserSession?
    ) async throws -> AccountIdentityList {
        try await repository.changeIdentity(
            provider: provider,
            verificationTicket: verificationTicket,
            newTarget: newTarget,
            newOtpID: newOtpID,
            newCode: newCode,
            session: session
        )
    }
}
