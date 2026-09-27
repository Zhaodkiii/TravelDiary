import Foundation

struct SignOutUseCase: Sendable {
    let authRepository: any AuthRepository

    func execute() async throws {
        try await authRepository.signOut()
    }
}
