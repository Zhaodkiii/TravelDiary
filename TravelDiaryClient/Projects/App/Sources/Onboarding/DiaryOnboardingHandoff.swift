/// Keep the demonstration visible until the mounted entry route can be used.
/// Authentication errors and offline routes are also usable destinations: they
/// expose recovery controls instead of trapping the user behind the guide.
struct DiaryOnboardingHandoff {
    private(set) var finishRequested = false
    private(set) var entryReady = false
    var canDismiss: Bool { finishRequested && entryReady }

    mutating func requestFinish() { finishRequested = true }
    mutating func updateReadiness(_ ready: Bool) { entryReady = ready }
}
