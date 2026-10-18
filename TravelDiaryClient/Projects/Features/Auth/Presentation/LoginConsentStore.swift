import Foundation

/// 仅代表登录提示的接受记录，不把旧健康产品的布尔值视为当前协议同意。
@MainActor
struct LoginConsentStore {
    static let noticeVersion = "traveldiary-notice-2026-10-18"
    var defaults: UserDefaults = .standard
    var isAccepted: Bool {
        defaults.string(forKey: "auth.login.legal.accepted_version") == Self.noticeVersion
            && defaults.double(forKey: "auth.login.legal.accepted_at") > 0
    }
    func accept(at date: Date = Date()) {
        defaults.set(date.timeIntervalSince1970, forKey: "auth.login.legal.accepted_at")
        defaults.set(Self.noticeVersion, forKey: "auth.login.legal.accepted_version")
    }
    func revoke() {
        defaults.removeObject(forKey: "auth.login.legal.accepted_version")
        defaults.removeObject(forKey: "auth.login.legal.accepted_at")
        defaults.removeObject(forKey: "auth.login.initial_legal_prompt_accepted")
    }
}
