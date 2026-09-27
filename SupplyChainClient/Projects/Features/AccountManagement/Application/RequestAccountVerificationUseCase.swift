import Foundation

struct RequestAccountVerificationUseCase: Sendable {
    private let repository: any AccountManagementRepository

    init(repository: any AccountManagementRepository) {
        self.repository = repository
    }

    func execute(channel: AccountVerificationChannel, session: UserSession?) async throws -> AccountVerificationRequestContext {
        try await repository.requestVerification(channel: channel, session: session)
    }
}
