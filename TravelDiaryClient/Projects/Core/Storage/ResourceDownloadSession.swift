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

/// Shared FIFO admission for preview traffic. A cancelled waiter never starts a download.
actor PreviewDownloadGate {
    static let shared = PreviewDownloadGate()
    private var running = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []
    func data(session: URLSession, url: URL, key: ResourceCacheKey) async throws -> (Data, URLResponse) {
        let start = ProcessInfo.processInfo.systemUptime
        if running >= 4 { await withCheckedContinuation { waiting.append($0) } }
        else { running += 1 }
        defer {
            if waiting.isEmpty { running -= 1 }
            else { waiting.removeFirst().resume() }
        }
        try Task.checkCancellation()
        ResourceLoadMetrics.shared.record(key, "image.queue", since: start)
        return try await session.data(from: url)
    }
}
