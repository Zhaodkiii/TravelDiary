import Foundation

/// Installation-scoped, independent of login/logout and account switching.
@MainActor
struct DiaryOnboardingPolicy {
    static let completionKey = "diary.onboarding.completed.v1"
    var defaults: UserDefaults = .standard

    var shouldPresent: Bool {
        !defaults.bool(forKey: Self.completionKey)
            && InitialGuestEntryPolicy(defaults: defaults).canAttemptAutomaticEntry
    }

    func finish() { defaults.set(true, forKey: Self.completionKey) }

    static var initialPresentation: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-diary-onboarding") { return true }
        #endif
        return Self().shouldPresent
    }
}
