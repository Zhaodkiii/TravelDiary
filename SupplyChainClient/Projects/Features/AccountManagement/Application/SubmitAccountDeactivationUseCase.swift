import Foundation

struct SubmitAccountDeactivationUseCase: Sendable {
    private let repository: any AccountManagementRepository

    init(repository: any AccountManagementRepository) {
        self.repository = repository
    }

    func execute(options: AccountDeactivationOptions, verification: AccountDeactivationVerification) async throws -> AccountDeactivationSubmission {
        try await repository.submitDeactivation(options: options, verification: verification)
    }
}

