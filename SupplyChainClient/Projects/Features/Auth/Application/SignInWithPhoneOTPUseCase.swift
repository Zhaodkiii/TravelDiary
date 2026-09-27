import Foundation

struct SignInWithPhoneOTPUseCase: Sendable {
    let authRepository: any AuthRepository

    func execute(phoneNumber: String, verificationCode: String, otpID: String) async throws -> UserSession {
        try await authRepository.signInWithPhoneOTP(
            phoneNumber: phoneNumber,
            verificationCode: verificationCode,
            otpID: otpID
        )
    }
}
