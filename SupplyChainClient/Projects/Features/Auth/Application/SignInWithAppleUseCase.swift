import Foundation

struct SignInWithAppleUseCase: Sendable {
    let authRepository: any AuthRepository

    func execute(payload: AppleSignInPayload) async throws -> UserSession {
        try await authRepository.signInWithApple(payload: payload)
    }
}
