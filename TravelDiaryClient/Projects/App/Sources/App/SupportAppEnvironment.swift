typealias AppEnvironment = SupportAppEnvironment

import Foundation

enum SupportAppEnvironment: String, CaseIterable, Sendable {
    case debug
    case staging
    case production

    static let current: SupportAppEnvironment = {
        #if DEBUG
        return .debug
        #elseif STAGING
        return .staging
        #else
        return .production
        #endif
    }()

    var apiBaseURL: URL {
        switch self {
        case .debug:
            return URL(string: "http://39.106.39.110:22026")!
//            return URL(string: "https://diary.dreamwhale.top")!
        case .staging, .production:
            return URL(string: "https://diary.dreamwhale.top")!
        }
    }

    var siteBaseURL: URL {
        switch self {
        case .debug:
            return URL(string: "https://www.dreamwhale.top")!
        case .staging, .production:
            return URL(string: "https://www.dreamwhale.top")!
        }
    }

    var privacyPolicyURL: URL { siteBaseURL.appending(path: "legal/privacy/") }
    var termsOfServiceURL: URL { siteBaseURL.appending(path: "legal/terms/") }

    var logLevel: LogLevel {
        switch self {
        case .debug, .staging: return .verbose
        case .production: return .error
        }
    }

    var subsystem: String {
        switch self {
        case .debug: return "TravelDiary.Debug"
        case .staging: return "TravelDiary.Staging"
        case .production: return "TravelDiary"
        }
    }

    var ocrConfiguration: OCRConfiguration {
        switch self {
        case .debug:
            return OCRConfiguration(
                enableAliyunOCR: false,
                enableLocalServerOCR: false
            )
        case .staging, .production:
            return OCRConfiguration(
                enableAliyunOCR: true,
                enableLocalServerOCR: false
            )
        }
    }

}
