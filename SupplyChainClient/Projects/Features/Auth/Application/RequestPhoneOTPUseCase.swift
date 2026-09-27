import Foundation

struct RequestPhoneOTPUseCase: Sendable {
    let authRepository: any AuthRepository

    func execute(phoneNumber: String) async throws -> PhoneOTPRequestContext {
        try await authRepository.requestPhoneOTP(phoneNumber: phoneNumber)
    }
}
