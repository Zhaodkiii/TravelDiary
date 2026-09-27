import Foundation

enum AccountDeactivationFlowState: Equatable {
    case idle
    case chooseVerification
    case enteringOTP(AccountVerificationChannel, otpID: String)
    case appleReauth
    case finalConfirmation(AccountDeactivationVerification)
    case submitting
    case completed(AccountDeactivationSubmission)
    case failed(String)

    var isOverlayPresented: Bool {
        switch self {
        case .idle, .completed:
            return false
        case .chooseVerification, .enteringOTP, .appleReauth, .finalConfirmation, .submitting, .failed:
            return true
        }
    }
}

