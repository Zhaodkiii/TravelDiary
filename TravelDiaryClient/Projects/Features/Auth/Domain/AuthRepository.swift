import Foundation

struct AppleSignInPayload: Sendable {
    let identityToken: String
    let authorizationCode: String?
    let nonce: String?
    let userIdentifier: String
    let email: String?
    let fullName: String?
}

struct PhoneOTPRequestContext: Sendable {
    let otpID: String
    let expiresIn: Int
}

protocol AuthRepository: Sendable {
    func restoreSession() async -> UserSession?
    func signInWithApple(payload: AppleSignInPayload) async throws -> UserSession
    func signInWithDevice() async throws -> UserSession
    func requestPhoneOTP(phoneNumber: String) async throws -> PhoneOTPRequestContext
    func signInWithPhoneOTP(phoneNumber: String, verificationCode: String, otpID: String) async throws -> UserSession
    func signOut() async throws
}
