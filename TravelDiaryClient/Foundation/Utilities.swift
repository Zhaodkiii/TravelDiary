import Foundation
import Security
import UIKit

enum RequestIdGenerator {
    nonisolated static func make() -> String { UUID().uuidString }
}

extension JSONDecoder {
    /// 默认全局解码器：与 SparkClient `JSONDecoder.default` 对齐。
    /// `convertFromSnakeCase` 会把服务端 `bucket_name` 转成 `bucketName` 再匹配 CodingKey。
    nonisolated static var supportDefault: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    nonisolated static var `default`: JSONDecoder { supportDefault }
}

extension JSONEncoder {
    /// 默认全局编码器：与 SparkClient `JSONEncoder.default` 对齐。
    nonisolated static var supportDefault: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    nonisolated static var `default`: JSONEncoder { supportDefault }
}

typealias SparkSystemInfo = SupportSystemInfo

@MainActor
final class SupportSystemInfo {
    static let shared = SupportSystemInfo()

    let installationDeviceID: String = SupportKeychain.getOrCreateDeviceID()

    var bundleIdentifier: String { Bundle.main.bundleIdentifier ?? "com.dreamhua.supportclient" }
    var appVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0" }
    var buildVersion: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1" }
    var platform: String { "ios" }
    var systemVersion: String { AppleDeviceInfo.systemVersion }
    var deviceModel: String { AppleDeviceInfo.modelIdentifier }
    var deviceModelName: String { AppleDeviceInfo.modelName }
    var deviceName: String { AppleDeviceInfo.deviceName }
    var screenSize: String {
        let size = UIScreen.main.bounds.size
        return "\(Int(size.width))x\(Int(size.height))"
    }
    var screenScale: Double { UIScreen.main.scale }
    var timeZone: String { TimeZone.current.identifier }
    var languageCode: String { Locale.current.language.languageCode?.identifier ?? "en" }
    var regionCode: String { Locale.current.region?.identifier ?? "" }
    var countryCode: String { Locale.current.region?.identifier ?? "" }
    var mostLikelyCountryCode: String { countryCode.uppercased() }
    var isMostLikelyMainlandChina: Bool { countryCode.uppercased() == "CN" }
    var isSimulator: Bool { AppleDeviceInfo.isSimulator }
}

enum L10n {
    nonisolated static func tr(_ key: String, fallback: String? = nil, comment: StaticString = "") -> String {
        text(key, fallback: fallback, comment: comment)
    }

    nonisolated static func text(_ key: String, fallback: String? = nil, comment: StaticString = "") -> String {
        _ = comment
        let value = Bundle.main.localizedString(forKey: key, value: nil, table: nil)
        return value == key ? (fallback ?? key) : value
    }

    nonisolated static func format(_ key: String, fallback: String? = nil, comment: StaticString = "", _ args: CVarArg...) -> String {
        String(format: text(key, fallback: fallback, comment: comment), locale: Locale.current, arguments: args)
    }
}
