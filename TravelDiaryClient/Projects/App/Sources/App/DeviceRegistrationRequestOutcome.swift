import Foundation

/// 设备登记入口的明确结果。
enum DeviceRegistrationRequestOutcome: Sendable, Equatable {
    /// 本次已真实调用 `/device/register/` 并成功。
    case submitted
    /// 同一冷启动/引导周期内已成功提交过，允许跳过重复网络请求。
    case skippedSameLaunchSubmission
    /// 未成功提交，可进入有限重试。
    case failedRetryable
    /// 鉴权/设备会话失效，应中止后续账号级引导并强制退出。
    case authSessionInvalidated

    /// 是否允许进入 AI / OSS 等账号级引导。
    var allowsAccountBootstrap: Bool {
        switch self {
        case .submitted, .skippedSameLaunchSubmission:
            return true
        case .failedRetryable, .authSessionInvalidated:
            return false
        }
    }

    var logLabel: String {
        switch self {
        case .submitted: return "submitted"
        case .skippedSameLaunchSubmission: return "skipped_same_launch_submission"
        case .failedRetryable: return "failed_retryable"
        case .authSessionInvalidated: return "auth_session_invalidated"
        }
    }
}

/// 引导级设备登记有限重试策略。
enum DeviceRegistrationBootstrapRetryPolicy: Sendable {
    static let maxAttempts = 3
    static let backoffNanoseconds: [UInt64] = [0, 300_000_000, 600_000_000]

    static func backoffBeforeAttempt(_ attemptIndex: Int) -> UInt64 {
        guard attemptIndex > 0, attemptIndex < backoffNanoseconds.count else { return 0 }
        return backoffNanoseconds[attemptIndex]
    }
}
