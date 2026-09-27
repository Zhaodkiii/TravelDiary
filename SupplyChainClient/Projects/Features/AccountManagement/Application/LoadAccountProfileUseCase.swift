import Foundation

struct LoadAccountProfileUseCase: Sendable {
    private let repository: any AccountManagementRepository

    init(repository: any AccountManagementRepository) {
        self.repository = repository
    }

    func execute(session: UserSession?) async throws -> AccountProfile {
        try await repository.loadAccountProfile(session: session)
    }
}

