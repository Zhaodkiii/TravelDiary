import Foundation
import UserNotifications

@MainActor
final class PushAdapter: NSObject, UNUserNotificationCenterDelegate {
    nonisolated override init() {
        super.init()
    }

    func requestAuthorizationIfNotDetermined() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            return (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        }
        return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }
}
