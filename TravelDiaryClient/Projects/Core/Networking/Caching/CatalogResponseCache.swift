import Foundation

/// Read-only catalog policy. Freshness and disk retention are deliberately separate:
/// stale data can render immediately while a conditional request refreshes it.
@MainActor
final class CatalogResponseCache {
    static let shared = CatalogResponseCache()
    nonisolated struct Snapshot: Codable, Sendable {
        let data: Data
        let validatedAt: Date
        var needsRefresh: Bool? = nil
    }
    private struct Pending {
        let id: UUID
        let task: Task<Data, Error>
    }
    private let cache: ResourceCache
    private let now: () -> Date
    private var pending: [String: Pending] = [:]
    private var revisions: [String: UUID] = [:]
    static let freshness: TimeInterval = 300
    static let retention: TimeInterval = 7 * 24 * 3600

    init(cache: ResourceCache = .shared, now: @escaping () -> Date = Date.init) {
        self.cache = cache; self.now = now
    }
    static func identity(_ path: String) -> String {
        guard var parts = URLComponents(string: path) else { return path }
        parts.queryItems = parts.queryItems?.sorted { ($0.name, $0.value ?? "") < ($1.name, $1.value ?? "") }
        return parts.string ?? path
    }
    private func key(owner: String, domain: String, path: String) -> ResourceCacheKey {
        .account(owner, category: "catalog-" + domain, identity: Self.identity(path))
    }
    /// Mutations invalidate only the affected account/domain, including in-flight writes.
    func invalidate(owner: String, domain: String) {
        let group = owner + "|" + domain
        revisions[group] = UUID()
        cache.clear(scope: StoragePaths.scopeKey(owner), category: "catalog-" + domain)
    }
    /// Keep visible content after non-authoritative mutations (for example favorites).
    /// Rights changes must still use invalidate, never this method.
    func markStale(owner: String, domain: String) async {
        let group = owner + "|" + domain
        revisions[group] = UUID()
        let scope = StoragePaths.scopeKey(owner)
        await Task.detached { [cache] in
            cache.transform(scope: scope, category: "catalog-" + domain) { data in
                guard var snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return nil }
                snapshot.needsRefresh = true
                return try? JSONEncoder().encode(snapshot)
            }
        }.value
    }
    func load(owner: String, domain: String, path: String, forceRefresh: Bool = false,
              onCached: ((Data) -> Void)? = nil, onOffline: (() -> Void)? = nil,
              policy: CatalogCachePolicy = .standard, onPhase: ((CatalogLoadPhase) -> Void)? = nil,
              fetch: @escaping @MainActor () async throws -> Data) async throws -> Data {
        let key = key(owner: owner, domain: domain, path: path)
        let group = owner + "|" + domain
        let revision = revisions[group]
        let generation = cache.generation(for: key)
        let started = ProcessInfo.processInfo.systemUptime
        defer { ResourceLoadMetrics.shared.record(key, "catalog.load.finished", since: started) }
        onPhase?(.loading)
        let snapshot = await Task.detached { [cache] in
            cache.data(for: key).flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) }
        }.value
        try Task.checkCancellation()
        guard revision == revisions[group], generation == cache.generation(for: key) else { throw CancellationError() }
        let usable = snapshot.flatMap { now().timeIntervalSince($0.validatedAt) < policy.retention ? $0 : nil }
        if let usable {
            ResourceLoadMetrics.shared.record(key, "catalog.disk.hit", since: started, bytes: usable.data.count)
            onPhase?(.cached)
            onCached?(usable.data)
            if !forceRefresh, now().timeIntervalSince(usable.validatedAt) < policy.freshness, usable.needsRefresh != true { onPhase?(.ready); return usable.data }
        }
        if usable == nil { ResourceLoadMetrics.shared.record(key, snapshot == nil ? "catalog.miss" : "catalog.expired", since: started) }
        onPhase?(.refreshing)
        let pendingKey = key.id + ":" + generation + ":" + (revision?.uuidString ?? "initial")
        let work: Pending
        if let existing = pending[pendingKey] { work = existing; ResourceLoadMetrics.shared.record(key, "catalog.coalesced") }
        else {
            work = Pending(id: UUID(), task: Task { [self] in
                let networkStart = ProcessInfo.processInfo.systemUptime
                let data = try await fetch()
                ResourceLoadMetrics.shared.record(key, "catalog.fetch", since: networkStart, bytes: data.count)
                try Task.checkCancellation()
                guard revision == revisions[group], generation == cache.generation(for: key) else { throw CancellationError() }
                let envelope = try JSONEncoder().encode(Snapshot(data: data, validatedAt: now()))
                _ = await Task.detached { [cache] in
                    cache.store(envelope, for: key, expectedGeneration: generation)
                }.value
                return data
            })
            pending[pendingKey] = work
        }
        defer { if pending[pendingKey]?.id == work.id { pending[pendingKey] = nil } }
        do {
            let data = try await work.task.value
            try Task.checkCancellation()
            guard revision == revisions[group], generation == cache.generation(for: key) else { throw CancellationError() }
            onPhase?(.ready)
            return data
        } catch {
            try Task.checkCancellation()
            guard revision == revisions[group], generation == cache.generation(for: key) else { throw CancellationError() }
            // Never mask authorization failures, invalid JSON or server errors with stale rights.
            let connectionError: URLError?
            if case let SupportNetworkError.transport(underlying) = error { connectionError = underlying }
            else { connectionError = error as? URLError }
            if let error = connectionError,
               [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost].contains(error.code),
               let usable { onOffline?(); onPhase?(.offline); ResourceLoadMetrics.shared.record(key, "catalog.offline"); return usable.data }
            onPhase?(.failed)
            throw error
        }
    }
}

/// Cancellation is control flow (tab changes, navigation or invalidation), never a user error.
nonisolated enum CatalogLoadError {
    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let error = error as? URLError, error.code == .cancelled { return true }
        if let error = error as? SupportNetworkError {
            switch error {
            case .cancelled: return true
            case .transport(let underlying): return underlying.code == .cancelled
            default: break
            }
        }
        return false
    }
}
