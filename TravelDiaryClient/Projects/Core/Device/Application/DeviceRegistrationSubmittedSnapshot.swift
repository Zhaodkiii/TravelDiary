import Foundation

/// 设备登记去重摘要（Support 精简版，不依赖 Spark 医疗/推送状态机）。
struct DeviceRegistrationSubmittedSnapshot: Codable, Equatable, Sendable {
    var accountID: Int?
    var isAuthenticated: Bool
    var bundleID: String
    var deviceID: String
    var countryCode: String
    var regionCode: String
    var notificationsEnabled: Bool?
    var pushTokenHash: String?
    var authorizationStatusRaw: Int?
}
