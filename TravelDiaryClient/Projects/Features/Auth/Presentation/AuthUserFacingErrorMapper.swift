import AuthenticationServices
import Foundation

enum AuthViewModelError: LocalizedError {
    case invalidAppleCredential
    case missingIdentityToken

    var errorDescription: String? {
        switch self {
        case .invalidAppleCredential:
            return L10n.text("auth.error.apple_credential_invalid")
        case .missingIdentityToken:
            return L10n.text("auth.error.apple_identity_token_missing")
        }
    }
}

enum AuthUserFacingErrorMapper {
    enum Scenario: Sendable {
        case appleSignIn
        case deviceSignIn
        case phoneOTPRequest
        case phoneOTPResend
        case phoneOTPLogin
    }

    static func isAppleSignInCancelled(_ error: Error) -> Bool {
        if let authError = error as? ASAuthorizationError {
            return authError.code == .canceled
        }
        let nsError = error as NSError
        return nsError.domain == ASAuthorizationError.errorDomain
            && nsError.code == ASAuthorizationError.canceled.rawValue
    }

    static func message(for error: Error, scenario: Scenario) -> String {
        if isNetworkUnavailable(error) {
            return L10n.text("auth.notification.network_unavailable")
        }

        if let credentialMessage = (error as? AuthViewModelError)?.errorDescription {
            return credentialMessage
        }

        if let networkError = error as? SupportNetworkError {
            return message(for: networkError, scenario: scenario)
        }

        return fallback(for: scenario)
    }

    private static func message(for networkError: SupportNetworkError, scenario: Scenario) -> String {
        switch networkError {
        case .transport:
            return L10n.text("auth.notification.network_unavailable")
        case .http(let statusCode, let backend, _):
            let backendMessage = BackendErrorLocalizer.message(for: backend, statusCode: statusCode)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if scenario == .deviceSignIn {
                if let mapped = deviceLoginMessage(backend: backend, statusCode: statusCode) {
                    return mapped
                }
            }
            if backendMessage.isEmpty == false, isSafeUserFacingBackendMessage(backendMessage) {
                return backendMessage
            }
            return fallback(for: scenario)
        case .cancelled, .invalidResponse, .decoding, .refreshFailed, .timeout:
            return fallback(for: scenario)
        }
    }

    static func isNetworkUnavailable(_ error: Error) -> Bool {
        if let networkError = error as? SupportNetworkError {
            switch networkError {
            case .transport, .timeout:
                return true
            default:
                return false
            }
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return true
            default:
                return false
            }
        }
        return false
    }

    /// 避免把 requestId、堆栈等技术信息直接展示给用户。
    private static func isSafeUserFacingBackendMessage(_ message: String) -> Bool {
        let lowered = message.lowercased()
        let blockedMarkers = ["requestid", "request_id", "trace", "stack", "token", "exception"]
        return blockedMarkers.contains { lowered.contains($0) } == false
    }

    private static func deviceLoginMessage(backend: BackendError?, statusCode: Int) -> String? {
        let code = backend?.code
        let msg = (backend?.msg ?? "").lowercased()
        if code == 40161 || msg.contains("device_credential_invalid") {
            return L10n.text("auth.device.credential_invalid")
        }
        if code == 42361 || msg.contains("device_credential_locked") || msg.contains("device_login_temporarily_locked") {
            return L10n.text("auth.device.login_failed")
        }
        if code == 40061 || code == 40062 || code == 40063 {
            return L10n.text("auth.device.data_recovery_warning")
        }
        if statusCode == 401 || statusCode == 403 || statusCode == 409 || statusCode == 423 || statusCode == 503 {
            return L10n.text("auth.device.login_failed")
        }
        return nil
    }

    private static func fallback(for scenario: Scenario) -> String {
        switch scenario {
        case .appleSignIn:
            return L10n.text("auth.notification.apple_sign_in_failed")
        case .deviceSignIn:
            return L10n.text("auth.device.login_failed")
        case .phoneOTPRequest:
            return L10n.text("auth.notification.otp_send_failed")
        case .phoneOTPResend:
            return L10n.text("auth.notification.otp_resend_failed")
        case .phoneOTPLogin:
            return L10n.text("auth.notification.phone_login_failed")
        }
    }
}
