import Foundation

struct LoadAccountIdentitiesUseCase: Sendable {
    private let repository: any AccountManagementRepository

    init(repository: any AccountManagementRepository) {
        self.repository = repository
    }

    func execute(session: UserSession?) async throws -> AccountIdentityList {
        try await repository.loadIdentities(session: session)
    }
}
