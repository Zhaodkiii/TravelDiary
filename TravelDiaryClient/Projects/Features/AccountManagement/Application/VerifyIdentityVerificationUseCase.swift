import Foundation

struct VerifyIdentityVerificationUseCase: Sendable {
    private let repository: any AccountManagementRepository

    init(repository: any AccountManagementRepository) {
        self.repository = repository
    }

    func execute(
        provider: AccountIdentityProvider,
        purpose: String,
        proof: AccountIdentityReauthProof,
        session: UserSession?
    ) async throws -> VerificationTicket {
        try await repository.verifyIdentityVerification(
            provider: provider,
            purpose: purpose,
            proof: proof,
            session: session
        )
    }
}
