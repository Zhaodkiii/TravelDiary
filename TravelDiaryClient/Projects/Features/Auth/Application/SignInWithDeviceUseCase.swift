import Foundation

struct SignInWithDeviceUseCase: Sendable {
    let authRepository: any AuthRepository

    func execute() async throws -> UserSession {
        try await authRepository.signInWithDevice()
    }
}
