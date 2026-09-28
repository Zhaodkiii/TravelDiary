import Foundation

struct BindAccountIdentityUseCase: Sendable {
    private let repository: any AccountManagementRepository

    init(repository: any AccountManagementRepository) {
        self.repository = repository
    }

    func execute(
        provider: AccountIdentityProvider,
        verificationTicket: String,
        proof: AccountIdentityBindProof,
        session: UserSession?
    ) async throws -> AccountIdentityList {
        try await repository.bindIdentity(
            provider: provider,
            verificationTicket: verificationTicket,
            proof: proof,
            session: session
        )
    }
}
