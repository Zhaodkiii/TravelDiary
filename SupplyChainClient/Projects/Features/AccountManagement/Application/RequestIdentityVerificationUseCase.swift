import Foundation

struct RequestIdentityVerificationUseCase: Sendable {
    private let repository: any AccountManagementRepository

    init(repository: any AccountManagementRepository) {
        self.repository = repository
    }

    func execute(
        provider: AccountIdentityProvider,
        purpose: String,
        session: UserSession?
    ) async throws -> IdentityVerificationRequestResult {
        try await repository.requestIdentityVerification(provider: provider, purpose: purpose, session: session)
    }
}
