import AuthenticationServices
import Combine
import CryptoKit
import Foundation
import Security

/// 登录流程中的账号切换协调：用协议注入替代 async closure，避免 iOS 16 回部署时
/// `nonisolated(nonsending)` 元数据在 ObservableObject 反射阶段崩溃。
@MainActor
protocol LoginAccountSwitchHandling: AnyObject {
    func beginLoginAccountSwitch(suspendedAccountID: Int64?) async
    func endLoginAccountSwitch(commit: Bool, currentSignedInAccountID: Int64?) async
}

@MainActor
/// 登录场景状态管理：串联输入校验、用例调用与会话状态更新。
final class LoginViewModel: ObservableObject {
    @Published var isLoading = false

    private let signInWithAppleUseCase: SignInWithAppleUseCase
    private let signInWithDeviceUseCase: SignInWithDeviceUseCase
    private let requestPhoneOTPUseCase: RequestPhoneOTPUseCase
    private let signInWithPhoneOTPUseCase: SignInWithPhoneOTPUseCase
    private let sessionStore: AppSessionStore
    private let notificationClient: any NotificationClient
    private let accountSwitchHandler: (any LoginAccountSwitchHandling)?
    private let logger: Logger = ConsoleLogger()
    private var currentNonce: String?

    private let notificationSource = "auth.login"

    init(
        signInWithAppleUseCase: SignInWithAppleUseCase,
        signInWithDeviceUseCase: SignInWithDeviceUseCase,
        requestPhoneOTPUseCase: RequestPhoneOTPUseCase,
        signInWithPhoneOTPUseCase: SignInWithPhoneOTPUseCase,
        sessionStore: AppSessionStore,
        notificationClient: any NotificationClient,
        accountSwitchHandler: (any LoginAccountSwitchHandling)? = nil
    ) {
        self.signInWithAppleUseCase = signInWithAppleUseCase
        self.signInWithDeviceUseCase = signInWithDeviceUseCase
        self.requestPhoneOTPUseCase = requestPhoneOTPUseCase
        self.signInWithPhoneOTPUseCase = signInWithPhoneOTPUseCase
        self.sessionStore = sessionStore
        self.notificationClient = notificationClient
        self.accountSwitchHandler = accountSwitchHandler
    }

    private var currentAccountID: Int64? {
        if case .signedIn(let session) = sessionStore.state {
            return session.accountID
        }
        return nil
    }

    private func prepareAccountSwitchIfNeeded() async -> Int64? {
        guard case .signedIn(let session) = sessionStore.state else { return nil }
        await accountSwitchHandler?.beginLoginAccountSwitch(suspendedAccountID: session.accountID)
        return session.accountID
    }

    private func finishAccountSwitch(commit: Bool) async {
        await accountSwitchHandler?.endLoginAccountSwitch(
            commit: commit,
            currentSignedInAccountID: currentAccountID
        )
    }

    private func commitAuthenticatedSession(_ session: UserSession, previousAccountID: Int64?) async {
        let isSameAccount = previousAccountID.map { $0 == session.accountID } ?? false
        sessionStore.setAuthenticated(session)
        await finishAccountSwitch(commit: true)
        if isSameAccount, previousAccountID != nil, session.isDeviceAccount == false {
            notificationClient.success(
                L10n.text("auth.device.upgrade_success"),
                source: notificationSource
            )
        } else {
            notificationClient.success(
                L10n.text("auth.notification.sign_in_success"),
                source: notificationSource
            )
        }
    }

    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonceString()
        currentNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)
    }

    func signInWithDevice() async {
        guard isLoading == false else { return }
        isLoading = true
        defer { isLoading = false }

        var accountSwitchStarted = false
        do {
            let previousAccountID = await prepareAccountSwitchIfNeeded()
            accountSwitchStarted = previousAccountID != nil
            let session = try await signInWithDeviceUseCase.execute()
            accountSwitchStarted = false
            logger.info(
                "登录流程：设备登录成功 accountID=\(session.accountID) isDeviceAccount=\(session.isDeviceAccount)",
                module: .auth
            )
            await commitAuthenticatedSession(session, previousAccountID: previousAccountID)
        } catch {
            if accountSwitchStarted {
                await finishAccountSwitch(commit: false)
            }
            let message = AuthUserFacingErrorMapper.message(for: error, scenario: .deviceSignIn)
            logger.error("登录流程：设备登录失败 error=\(message)", module: .auth)
            notifyFailure(message: message, error: error)
        }
    }

    func signInWithApple(result: Result<ASAuthorization, Error>) async {
        guard isLoading == false else { return }
        isLoading = true
        defer { isLoading = false }

        var accountSwitchStarted = false
        do {
            let authorization = try result.get()
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                throw AuthViewModelError.invalidAppleCredential
            }

            let payload = try makePayload(from: credential)
            logger.info("登录流程：Apple credential 已生成 payload，开始执行登录用例", module: .auth)
            let previousAccountID = await prepareAccountSwitchIfNeeded()
            accountSwitchStarted = previousAccountID != nil
            let session = try await signInWithAppleUseCase.execute(payload: payload)
            accountSwitchStarted = false
            logger.info(
                "登录流程：Apple 登录成功 accountID=\(session.accountID) isDeviceAccount=\(session.isDeviceAccount)",
                module: .auth
            )
            await commitAuthenticatedSession(session, previousAccountID: previousAccountID)
        } catch {
            if accountSwitchStarted {
                await finishAccountSwitch(commit: false)
            }
            if AuthUserFacingErrorMapper.isAppleSignInCancelled(error) {
                logger.info("登录流程：用户取消 Apple 登录", module: .auth)
                notificationClient.info(
                    L10n.text("auth.notification.apple_sign_in_cancelled"),
                    source: notificationSource
                )
                return
            }

            let message = AuthUserFacingErrorMapper.message(for: error, scenario: .appleSignIn)
            logger.error("登录流程：Apple 登录失败 error=\(message)", module: .auth)
            notifyFailure(message: message, error: error)
        }
    }

    func sendOTP(phoneNumber: String, isResend: Bool = false) async -> PhoneOTPRequestContext? {
        let scenario: AuthUserFacingErrorMapper.Scenario = isResend ? .phoneOTPResend : .phoneOTPRequest

        do {
            let context = try await requestPhoneOTPUseCase.execute(phoneNumber: phoneNumber)
            let successMessage = isResend
                ? L10n.text("auth.notification.otp_resent")
                : L10n.text("auth.notification.otp_sent")
            notificationClient.success(successMessage, source: notificationSource)
            return context
        } catch {
            let message = AuthUserFacingErrorMapper.message(for: error, scenario: scenario)
            logger.error("登录流程：验证码\(isResend ? "重发" : "发送")失败 error=\(message)", module: .auth)
            notifyFailure(message: message, error: error)
            return nil
        }
    }

    func phoneLogin(phoneNumber: String, verificationCode: String, otpId: String) async {
        guard isLoading == false else { return }
        isLoading = true
        defer { isLoading = false }

        var accountSwitchStarted = false
        do {
            let previousAccountID = await prepareAccountSwitchIfNeeded()
            accountSwitchStarted = previousAccountID != nil
            let session = try await signInWithPhoneOTPUseCase.execute(
                phoneNumber: phoneNumber,
                verificationCode: verificationCode,
                otpID: otpId
            )
            accountSwitchStarted = false
            logger.info(
                "登录流程：手机号登录成功 accountID=\(session.accountID) isDeviceAccount=\(session.isDeviceAccount)",
                module: .auth
            )
            await commitAuthenticatedSession(session, previousAccountID: previousAccountID)
        } catch {
            if accountSwitchStarted {
                await finishAccountSwitch(commit: false)
            }
            let message = AuthUserFacingErrorMapper.message(for: error, scenario: .phoneOTPLogin)
            logger.error("登录流程：手机号登录失败 error=\(message)", module: .auth)
            notifyFailure(message: message, error: error)
        }
    }

    private func notifyFailure(message: String, error: Error) {
        if AuthUserFacingErrorMapper.isNetworkUnavailable(error) {
            notificationClient.warning(message, source: notificationSource)
        } else {
            notificationClient.error(message, source: notificationSource)
        }
    }

    private func makePayload(from credential: ASAuthorizationAppleIDCredential) throws -> AppleSignInPayload {
        guard
            let identityTokenData = credential.identityToken,
            let identityToken = String(data: identityTokenData, encoding: .utf8),
            identityToken.isEmpty == false
        else {
            throw AuthViewModelError.missingIdentityToken
        }

        let authorizationCode: String?
        if let codeData = credential.authorizationCode {
            authorizationCode = String(data: codeData, encoding: .utf8)
        } else {
            authorizationCode = nil
        }

        return AppleSignInPayload(
            identityToken: identityToken,
            authorizationCode: authorizationCode,
            nonce: currentNonce,
            userIdentifier: credential.user,
            email: credential.email,
            fullName: Self.displayName(from: credential.fullName)
        )
    }

    private static func displayName(from fullName: PersonNameComponents?) -> String? {
        guard let fullName else { return nil }
        let value = PersonNameComponentsFormatter().string(from: fullName).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        result.reserveCapacity(length)
        var remainingLength = length

        while remainingLength > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
            if status != errSecSuccess {
                return UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(length).lowercased()
            }

            randoms.forEach { random in
                if remainingLength == 0 {
                    return
                }
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
