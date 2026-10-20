import Foundation
import UIKit
import UserNotifications
import Combine

nonisolated struct CustomPushPayload: Sendable {
    let request: String; let event: String; let action: String
    init?(_ payload: [AnyHashable: Any]) {
        guard payload["schema_version"] as? Int == 1,
              let id = payload["request_id"] as? String, UUID(uuidString: id) != nil,
              let event = payload["event_id"] as? String, UUID(uuidString: event) != nil,
              let action = payload["action"] as? String,
              ["open_customization","open_customization_info","open_customization_delivery"].contains(action) else { return nil }
        self.request = id; self.event = event; self.action = action
    }
}

@MainActor
final class PushAdapter: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = PushAdapter()
    @Published private(set) var token: String?
    @Published private(set) var notificationsEnabled: Bool?
    @Published private(set) var registrationError: String?
    private weak var sessions: AppSessionStore?
    private weak var devices: DeviceRegistrationCoordinator?
    private var subscription: AnyCancellable?
    private var client: (any NotificationClient)?
    private let pendingKey = "custom-push-pending-v1"
    nonisolated override init() { super.init() }
    func configure(sessions: AppSessionStore, devices: DeviceRegistrationCoordinator, client: any NotificationClient) {
        self.sessions = sessions; self.devices = devices; self.client = client
        UNUserNotificationCenter.current().delegate = self
        subscription = sessions.$state.sink { [weak self] _ in Task { await self?.refreshRegistration() } }
        if let item = UserDefaults.standard.dictionary(forKey: pendingKey), let id = item["request"] as? String,
           let expiry = item["expiry"] as? Double, expiry > Date().timeIntervalSince1970 { CustomizationService.shared.routeID = id }
    }
    func refreshRegistration() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationsEnabled = [.authorized,.provisional,.ephemeral].contains(settings.authorizationStatus)
        if notificationsEnabled == true { UIApplication.shared.registerForRemoteNotifications() }
        await submitSnapshot()
    }
    func registered(_ data: Data) {
        let value = data.map { String(format: "%02x", $0) }.joined()
        guard value != token else { return }; token = value; registrationError = nil
        Task { await submitSnapshot() }
    }
    func failedRegistration() { registrationError = "系统通知注册暂时失败，进入前台后会重试" }
    private func submitSnapshot() async {
        guard let sessions, case let .signedIn(session) = sessions.state else { return }
        _ = await devices?.requestRegisterWithLimitedRetry(reason: .pushStateChanged,session: session)
    }
    func requestAuthorizationIfNotDetermined(openSettingsIfDenied: Bool = false) async -> Bool {
        let center = UNUserNotificationCenter.current(); let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined { _ = try? await center.requestAuthorization(options: [.alert,.badge,.sound]) }
        else if settings.authorizationStatus == .denied && openSettingsIfDenied { if let url = URL(string: UIApplication.openSettingsURLString) { await UIApplication.shared.open(url) } }
        await refreshRegistration(); return notificationsEnabled == true
    }
    func clearPrivateState() { UserDefaults.standard.removeObject(forKey: pendingKey) }
    func routeConsumed() { clearPrivateState() }
    private func handle(_ payload: CustomPushPayload, clicked: Bool) async {
        let id = payload.request; let event = payload.event
        let service = CustomizationService.shared
        if clicked {
            UserDefaults.standard.set(["request":id,"expiry":Date().addingTimeInterval(86400).timeIntervalSince1970],forKey: pendingKey)
            service.routeID = id; return
        }
        guard let owner = service.owner, (try? await service.detail(id,owner: owner)) != nil else { return }
        await service.refreshUnread(owner: owner)
        service.refreshSequence += 1
        if service.visibleRequestID == id { return }
        let key = "custom-push-seen-" + owner
        var seen = UserDefaults.standard.stringArray(forKey: key) ?? []
        guard !seen.contains(event) else { return }; seen.append(event); UserDefaults.standard.set(Array(seen.suffix(500)),forKey: key)
        client?.publish(NotificationIntent(title: "专属定制",message: "你的定制有新的更新，点击查看",level: .info,presentation: .banner,
            dedupeKey: "custom-"+event,source: "customization.push",onTap: { CustomizationService.shared.routeID = id }))
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let payload = notification.request.content.userInfo
        // Exactly one foreground presentation channel. Other scenes retain system behavior.
        if (payload["scene_key"] as? String)?.hasPrefix("diary.customization.") == true {
            completionHandler([])
            if let value = CustomPushPayload(payload) { Task { @MainActor in await self.handle(value,clicked: false) } }
        } else { completionHandler([.banner,.sound]) }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let payload = response.notification.request.content.userInfo
        completionHandler()
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
        if let value = CustomPushPayload(payload) { Task { @MainActor in await self.handle(value,clicked: true) } }
    }
}

final class RemotePushAppDelegateBridge: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = PushAdapter.shared; return true
    }
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) { PushAdapter.shared.registered(deviceToken) }
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) { PushAdapter.shared.failedRegistration() }
}
