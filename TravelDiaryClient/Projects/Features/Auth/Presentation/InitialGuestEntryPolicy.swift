import Foundation

/// 安装内的首次进入记录，独立于账号会话；退出登录不能清除此标记。
@MainActor
struct InitialGuestEntryPolicy {
    var defaults: UserDefaults = .standard
    private let key = "auth.initial_entry.guest_attempt_consumed.v1"

    var canAttemptAutomaticEntry: Bool { !defaults.bool(forKey: key) }

    /// 请求前消费资格，首次失败或中断后也不在下次启动自动重试。
    func consumeAutomaticEntryIfNeeded() -> Bool {
        guard canAttemptAutomaticEntry else { return false }
        defaults.set(true, forKey: key)
        return true
    }

    /// 已恢复或登录过账号的用户属于后续进入，不再提供首次自动游客登录。
    func markExistingSession() { defaults.set(true, forKey: key) }
}
