import Foundation

/// Installation-scoped, independent of login/logout and account switching.
@MainActor
struct DiaryOnboardingPolicy {
    static let completionKey = "diary.onboarding.completed.v1"
    private static let startedKey = "diary.onboarding.started.v1"
    var defaults: UserDefaults = .standard

    var shouldPresent: Bool {
        !defaults.bool(forKey: Self.completionKey)
            && (defaults.bool(forKey: Self.startedKey)
                || InitialGuestEntryPolicy(defaults: defaults).canAttemptAutomaticEntry)
    }

    // Automatic login consumes guest eligibility while the guide is still on screen.
    // Remember that the guide started so an interrupted demonstration can resume.
    func begin() { defaults.set(true, forKey: Self.startedKey) }

    func finish() { defaults.set(true, forKey: Self.completionKey) }

    static var initialPresentation: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-diary-onboarding") { return true }
        #endif
        let policy = Self()
        let shouldPresent = policy.shouldPresent
        if shouldPresent { policy.begin() }
        return shouldPresent
    }
}
