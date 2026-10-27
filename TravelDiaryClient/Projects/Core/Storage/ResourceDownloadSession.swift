import Foundation

/// Binary resources have one disk owner. Disable the independent HTTP cache to avoid duplicate
/// image/attachment bytes outside the configured resource budget. Cookies are not shared across accounts.
nonisolated enum ResourceDownloadSession {
    static let shared: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        return URLSession(configuration: configuration)
    }()
}
