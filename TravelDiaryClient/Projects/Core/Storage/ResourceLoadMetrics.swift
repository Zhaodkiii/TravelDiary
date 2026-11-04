import Foundation
import OSLog

/// Bounded diagnostics. Identities are digests; URLs, tokens and user content are never logged.
nonisolated final class ResourceLoadMetrics: @unchecked Sendable {
    static let shared = ResourceLoadMetrics()
    struct Event: Sendable {
        let category: String
        let resource: String
        let stage: String
        let milliseconds: Double
        let bytes: Int
    }
    private let lock = NSLock()
    private var events: [Event] = []
    private let logger = OSLog(subsystem: "TravelDiary", category: "ResourceCache")
    func record(_ key: ResourceCacheKey, _ stage: String, since start: TimeInterval? = nil, bytes: Int = 0) {
        let event = Event(category: key.category, resource: String(key.id.prefix(12)), stage: stage,
            milliseconds: start.map { (ProcessInfo.processInfo.systemUptime - $0) * 1000 } ?? 0, bytes: bytes)
        lock.lock()
        if events.count >= 512 { events.removeFirst(128) }
        events.append(event)
        lock.unlock()
        os_log("category=%{public}@ id=%{public}@ stage=%{public}@ ms=%.2f bytes=%d", log: logger, type: .debug,
            event.category, event.resource, stage, event.milliseconds, bytes)
    }
    func snapshot() -> [Event] { lock.lock(); defer { lock.unlock() }; return events }
}

nonisolated struct CatalogCachePolicy: Sendable {
    var freshness: TimeInterval = 300
    var retention: TimeInterval = 7 * 24 * 3600
    static let standard = Self()
    static let reference = Self(freshness: 3600, retention: 30 * 24 * 3600)
}

nonisolated enum CatalogLoadPhase: Sendable {
    case loading, cached, refreshing, ready, offline, failed
}
