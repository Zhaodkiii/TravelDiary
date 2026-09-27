import Foundation

struct RestoreSessionUseCase: Sendable {
    let authRepository: any AuthRepository

    func execute() async -> UserSession? {
        await authRepository.restoreSession()
    }
}
