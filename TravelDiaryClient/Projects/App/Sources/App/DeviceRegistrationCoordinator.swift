import UIKit

enum DeviceRegistrationReason: String, Sendable {
    case pushStateChanged
    case guestColdLaunch
    case signedInColdLaunch
    case signedInForeground
}

@MainActor
final class DeviceRegistrationCoordinator {
    private let backend: SupportBackend
    private let logger: Logger
    private var lastRegisteredKey: String?
    private var isSubmissionSuspended = false

    init(backend: SupportBackend, logger: Logger) {
        self.backend = backend
        self.logger = logger
    }

    func reset() {
        lastRegisteredKey = nil
        isSubmissionSuspended = false
    }

    func suspendPendingSubmissions() {
        isSubmissionSuspended = true
        logger.info("设备登记已暂停：鉴权失效处理中", module: .device)
    }

    func registerGuestDevice(reason: DeviceRegistrationReason) async {
        _ = await requestRegister(
            userID: nil,
            accountID: nil,
            authenticated: false,
            reason: reason
        )
    }

    @discardableResult
    func requestRegisterWithLimitedRetry(
        reason: DeviceRegistrationReason,
        session: UserSession,
        maxAttempts: Int = DeviceRegistrationBootstrapRetryPolicy.maxAttempts
    ) async -> DeviceRegistrationRequestOutcome {
        let attempts = max(1, maxAttempts)
        var lastOutcome: DeviceRegistrationRequestOutcome = .failedRetryable

        for attemptIndex in 0 ..< attempts {
            let backoff = DeviceRegistrationBootstrapRetryPolicy.backoffBeforeAttempt(attemptIndex)
            if backoff > 0 {
                logger.info(
                    "设备登记重试 backoffMs=\(backoff / 1_000_000) attempt=\(attemptIndex + 1)/\(attempts)",
                    module: .device
                )
                try? await Task.sleep(nanoseconds: backoff)
            }

            lastOutcome = await requestRegister(
                userID: session.userID,
                accountID: session.accountID,
                authenticated: true,
                reason: reason
            )
            switch lastOutcome {
            case .submitted, .skippedSameLaunchSubmission, .authSessionInvalidated:
                return lastOutcome
            case .failedRetryable:
                logger.warning(
                    "设备登记重试失败 attempt=\(attemptIndex + 1)/\(attempts) reason=\(reason.rawValue)",
                    module: .device
                )
            }
        }

        logger.warning(
            "设备登记重试已用尽 attempts=\(attempts) reason=\(reason.rawValue)",
            module: .device
        )
        return lastOutcome
    }

    private func requestRegister(
        userID: Int64?,
        accountID: Int64?,
        authenticated: Bool,
        reason: DeviceRegistrationReason
    ) async -> DeviceRegistrationRequestOutcome {
        if isSubmissionSuspended {
            logger.warning(
                "设备登记阶段失败 outcome=failed_retryable error=submission_suspended",
                module: .device
            )
            return .failedRetryable
        }

        let info = SupportSystemInfo.shared
        let key = "\(authenticated)-\(userID ?? 0)-\(info.installationDeviceID)-\(PushAdapter.shared.token ?? "unknown")-\(String(describing: PushAdapter.shared.notificationsEnabled))"
        if key == lastRegisteredKey, reason != .signedInForeground {
            logger.info(
                "设备登记阶段跳过 outcome=skipped_same_launch_submission reason=\(reason.rawValue) accountID=\(accountID.map(String.init) ?? "-")",
                module: .device
            )
            return .skippedSameLaunchSubmission
        }

        logger.info(
            "设备登记阶段开始 reason=\(reason.rawValue) accountID=\(accountID.map(String.init) ?? "-")",
            module: .device
        )

        let request = DeviceRegistrationRequest(
            deviceID: info.installationDeviceID,
            userID: userID,
            pushToken: PushAdapter.shared.token,
            notificationsEnabled: PushAdapter.shared.notificationsEnabled,
            appVersion: info.appVersion,
            buildVersion: info.buildVersion,
            bundleIdentifier: info.bundleIdentifier,
            bundleID: info.bundleIdentifier,
            platform: "ios",
            systemVersion: info.systemVersion,
            deviceModel: info.deviceModel,
            deviceModelName: info.deviceModelName,
            deviceName: info.deviceName,
            screenSize: info.screenSize,
            screenScale: info.screenScale,
            timeZone: TimeZone.current.identifier,
            languageCode: Locale.current.language.languageCode?.identifier ?? "",
            regionCode: Locale.current.region?.identifier ?? "",
            countryCode: Locale.current.region?.identifier ?? "",
            isSimulator: info.isSimulator
        )

        logger.info(
            "设备登记提交 reasons=[\(reason.rawValue)] includesPushToken=\(PushAdapter.shared.token != nil) authenticated=\(authenticated)",
            module: .device
        )

        do {
            let response = try await backend.device.register(request, authenticated: authenticated)
            lastRegisteredKey = key
            logger.info(
                "设备登记成功 id=\(response.deviceID ?? info.installationDeviceID) created=\(response.registered.map(String.init(describing:)) ?? "-")",
                module: .device
            )
            logger.info(
                "设备登记阶段完成 outcome=submitted reason=\(reason.rawValue) accountID=\(accountID.map(String.init) ?? "-")",
                module: .device
            )
            return .submitted
        } catch {
            if SupportCancellationClassifier.isCancellation(error) {
                let cancelReason = SupportCancellationClassifier.reason(for: error)
                logger.warning(
                    "设备登记阶段取消 reason=\(reason.rawValue) accountID=\(accountID.map(String.init) ?? "-") cancelledBy=\(cancelReason) phase=signedInDeviceRegistration",
                    module: .device
                )
                return .failedRetryable
            }

            if isAuthSessionInvalidation(error) {
                suspendPendingSubmissions()
                logger.warning(
                    "设备登记阶段失败 outcome=auth_session_invalidated reason=\(reason.rawValue) accountID=\(accountID.map(String.init) ?? "-") error=\(error.localizedDescription)",
                    module: .device
                )
                return .authSessionInvalidated
            }

            logger.error(
                "设备登记失败 outcome=failed_retryable reason=\(reason.rawValue) accountID=\(accountID.map(String.init) ?? "-") error=\(error.localizedDescription)",
                module: .device
            )
            return .failedRetryable
        }
    }

    private func isAuthSessionInvalidation(_ error: Error) -> Bool {
        if let networkError = error as? SupportNetworkError {
            switch networkError {
            case .refreshFailed(let backend, _):
                return SupportAuthSessionInvalidation.shouldInvalidate(
                    statusCode: 401,
                    backendCode: backend?.code,
                    message: backend?.msg ?? networkError.localizedDescription
                )
            case .http(let statusCode, let backend, _):
                return SupportAuthSessionInvalidation.shouldInvalidate(
                    statusCode: statusCode,
                    backendCode: backend?.code,
                    message: backend?.msg ?? ""
                )
            default:
                break
            }
        }
        if let providerError = error as? AuthTokenProviderError {
            switch providerError {
            case .missingTokens, .refreshFailed:
                return true
            case .refreshTemporarilyUnavailable, .invalidRefreshResponse:
                return false
            }
        }
        return false
    }
}
