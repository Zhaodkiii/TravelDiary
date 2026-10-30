import Foundation
import SQLite3

/// Stable identity is independent of a signed download URL. Scope is captured by each operation.
nonisolated struct ResourceCacheKey: Hashable, Sendable {
    let scope: String
    let category: String
    let identity: String
    var id: String { StoragePaths.digest(scope + "\n" + category + "\n" + identity) }
    static func account(_ owner: String, category: String, identity: String) -> Self {
        Self(scope: StoragePaths.scopeKey(owner), category: category, identity: identity)
    }
}

nonisolated struct ResourceCacheEntry: Sendable {
    let id: String
    let scope: String
    let category: String
    let url: URL
    let bytes: Int64
    let accessedAt: Date
}

/// Single disk budget for rebuildable data. SQLite and file mutations share one lock, including
/// synchronous legacy providers. Call from a worker for large reads. User originals never enter here.
nonisolated final class ResourceCache: @unchecked Sendable {
    static let shared = ResourceCache()
    let paths: StoragePaths
    private let lock = NSRecursiveLock()
    private let sessionLock = NSLock()
    private let activity: StorageActivity
    private var database: OpaquePointer?
    private var attemptedOpen = false
    private var limit: Int64
    private var touched: [String: TimeInterval] = [:]
    private var lastFlush = Date.distantPast
    private var maintenanceScheduled = false
    private var revision: UInt64 = 0
    private var scopeRevisions: [String: UInt64] = [:]
    private var categoryRevisions: [String: UInt64] = [:]
    private var scopedCategoryRevisions: [String: UInt64] = [:]
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    var root: URL { paths.cache("Resources") }
    var generation: UInt64 { sessionLock.withLock { revision } }
    func generation(for key: ResourceCacheKey) -> String {
        sessionLock.withLock { "\(revision):\(scopeRevisions[key.scope, default: 0]):\(categoryRevisions[key.category, default: 0]):\(scopedCategoryRevisions[key.scope + "|" + key.category, default: 0])" }
    }
    var capacity: Int64 { locked { limit } }

    init(paths: StoragePaths = .system, activity: StorageActivity = .shared, limit: Int64? = nil) {
        self.paths = paths; self.activity = activity
        let stored = (try? Data(contentsOf: paths.control.appendingPathComponent("policy.json")))
            .flatMap { try? JSONDecoder().decode(StoragePolicy.self, from: $0) }
        self.limit = max(0, limit ?? stored?.previewLimit ?? StoragePolicy().previewLimit)
        if FileManager.default.fileExists(atPath: root.appendingPathComponent("index.sqlite").path) { openIfNeeded() }
    }
    private func openIfNeeded() {
        guard !attemptedOpen else { return }
        attemptedOpen = true
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let dbURL = root.appendingPathComponent("index.sqlite")
        if sqlite3_open_v2(dbURL.path, &database, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK {
            sqlite3_busy_timeout(database, 2000)
            var healthy = false
            if let check = statement("PRAGMA quick_check") {
                healthy = sqlite3_step(check) == SQLITE_ROW && string(check, 0) == "ok"
                sqlite3_finalize(check)
            }
            if !healthy {
                sqlite3_close(database); database = nil
                for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: dbURL.path + suffix) }
                guard sqlite3_open_v2(dbURL.path, &database, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
                    if let database { sqlite3_close(database) }; database = nil; return
                }
            }
            execute("PRAGMA journal_mode=WAL")
            execute("CREATE TABLE IF NOT EXISTS entries (id TEXT PRIMARY KEY, scope TEXT NOT NULL, category TEXT NOT NULL, path TEXT UNIQUE NOT NULL, bytes INTEGER NOT NULL, accessed REAL NOT NULL, expires REAL)")
            execute("CREATE INDEX IF NOT EXISTS cache_lru ON entries(accessed)")
            reconcile()
            trim()
        } else {
            if let database { sqlite3_close(database) }
            database = nil // Cache failure never prevents browsing or saving a user document.
        }
    }
    deinit { if let database { sqlite3_close(database) } }

    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock(); defer { lock.unlock() }; return try body()
    }
    private func execute(_ sql: String, _ values: [String] = []) {
        guard let statement = statement(sql, values) else { return }
        defer { sqlite3_finalize(statement) }; sqlite3_step(statement)
    }
    private func statement(_ sql: String, _ values: [String] = []) -> OpaquePointer? {
        guard let database else { return nil }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return nil }
        for (index, value) in values.enumerated() { sqlite3_bind_text(stmt, Int32(index + 1), value, -1, transient) }
        return stmt
    }
    private func string(_ stmt: OpaquePointer, _ index: Int32) -> String {
        sqlite3_column_text(stmt, index).map { String(cString: $0) } ?? ""
    }
    func entries() -> [ResourceCacheEntry] {
        locked {
            guard let stmt = statement("SELECT id,scope,category,path,bytes,accessed FROM entries ORDER BY accessed,id") else { return [] }
            defer { sqlite3_finalize(stmt) }
            var result: [ResourceCacheEntry] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = string(stmt, 0)
                result.append(ResourceCacheEntry(id: id, scope: string(stmt, 1), category: string(stmt, 2),
                    url: URL(fileURLWithPath: string(stmt, 3)), bytes: sqlite3_column_int64(stmt, 4),
                    accessedAt: Date(timeIntervalSince1970: touched[id] ?? sqlite3_column_double(stmt, 5))))
            }
            return result
        }
    }
    var totalBytes: Int64 { locked {
        guard let stmt = statement("SELECT COALESCE(SUM(bytes),0) FROM entries") else { return 0 }
        defer { sqlite3_finalize(stmt) }; guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return sqlite3_column_int64(stmt, 0)
    } }
    func entry(at url: URL) -> ResourceCacheEntry? { locked { entry(where: "path", value: url.standardizedFileURL.path) } }
    private func entry(where column: String, value: String) -> ResourceCacheEntry? {
        guard let stmt = statement("SELECT id,scope,category,path,bytes,accessed FROM entries WHERE " + column + "=?", [value]) else { return nil }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        let id = string(stmt, 0)
        return ResourceCacheEntry(id: id, scope: string(stmt, 1), category: string(stmt, 2), url: URL(fileURLWithPath: string(stmt, 3)),
            bytes: sqlite3_column_int64(stmt, 4), accessedAt: Date(timeIntervalSince1970: touched[id] ?? sqlite3_column_double(stmt, 5)))
    }

    private func fileURL(_ key: ResourceCacheKey) -> URL? {
        guard let stmt = statement("SELECT path,expires FROM entries WHERE id=?", [key.id]) else { return nil }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        if sqlite3_column_type(stmt, 1) != SQLITE_NULL, sqlite3_column_double(stmt, 1) <= Date().timeIntervalSince1970 { return nil }
        let url = URL(fileURLWithPath: string(stmt, 0))
        guard isSafe(url), FileManager.default.fileExists(atPath: url.path) else {
            execute("DELETE FROM entries WHERE id=?", [key.id]); return nil
        }
        touch(id: key.id)
        return url
    }
    func data(for key: ResourceCacheKey) -> Data? {
        locked {
            guard let url = fileURL(key) else { return nil }
            let lease = activity.acquire(url); defer { withExtendedLifetime(lease) {} }
            return try? Data(contentsOf: url)
        }
    }
    func touch(_ key: ResourceCacheKey) { locked { if fileURL(key) != nil { touch(id: key.id) } } }
    func touch(url: URL) { locked { if let entry = entry(at: url) { touch(id: entry.id) } } }
    private func touch(id: String) {
        touched[id] = Date().timeIntervalSince1970
        if Date().timeIntervalSince(lastFlush) > 5 || touched.count >= 64 { flushAccesses() }
    }
    func flushAccesses() {
        locked {
            execute("BEGIN IMMEDIATE")
            for (id, time) in touched { execute("UPDATE entries SET accessed=? WHERE id=?", [String(time), id]) }
            execute("COMMIT"); touched.removeAll(); lastFlush = Date()
        }
    }

    /// Returns nil when the cache is full/protected or unavailable. The caller still owns the data.
    @discardableResult
    func store(_ data: Data, for key: ResourceCacheKey, expiresAt: Date? = nil, expectedGeneration: String? = nil) -> URL? {
        locked {
            openIfNeeded()
            guard database != nil, expectedGeneration == nil || expectedGeneration == generation(for: key),
                  Int64(data.count) <= limit, limit > 0 else { return nil }
            let old = entry(where: "id", value: key.id)
            trim(incoming: Int64(data.count), excluding: old.map { [$0.id] } ?? [])
            guard totalBytes + Int64(data.count) <= limit else { return nil }
            let url = root.appendingPathComponent("Files/\(StoragePaths.digest(key.scope))/\(UUID().uuidString).cache")
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url, options: .atomic)
                guard upsert(key, url: url, bytes: Int64(data.count), expiresAt: expiresAt) else {
                    try? FileManager.default.removeItem(at: url); return nil
                }
                if let old, old.url != url { try? activity.exclusively(old.url) { try FileManager.default.removeItem(at: old.url) } }
                return url
            } catch { return nil }
        }
    }

    /// Adopt only a provider-confirmed rebuildable file. This allows incremental legacy migration
    /// without duplicating bytes. Upload staging files must not be registered until acknowledged.
    func register(_ url: URL, for key: ResourceCacheKey) {
        locked {
            guard isSafe(url), let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return }
            openIfNeeded()
            _ = upsert(key, url: url, bytes: Int64(size), expiresAt: nil)
            trim(excluding: [key.id])
            if totalBytes > limit { scheduleMaintenance() }
        }
    }
    private func upsert(_ key: ResourceCacheKey, url: URL, bytes: Int64, expiresAt: Date?) -> Bool {
        guard let stmt = statement("INSERT OR REPLACE INTO entries(id,scope,category,path,bytes,accessed,expires) VALUES(?,?,?,?,?,?,?)",
            [key.id, key.scope, key.category, url.path, String(bytes), String(Date().timeIntervalSince1970)]) else { return false }
        defer { sqlite3_finalize(stmt) }
        if let expiresAt { sqlite3_bind_double(stmt, 7, expiresAt.timeIntervalSince1970) } else { sqlite3_bind_null(stmt, 7) }
        touched[key.id] = nil
        return sqlite3_step(stmt) == SQLITE_DONE
    }
    func setCapacity(_ bytes: Int64) { locked { limit = max(0, bytes); trim(); if totalBytes > limit { scheduleMaintenance() } } }
    func maintain() { locked { flushAccesses(); reconcile(); trim(); if totalBytes > limit { scheduleMaintenance() } } }
    private func scheduleMaintenance() {
        guard !maintenanceScheduled else { return }
        maintenanceScheduled = true
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.locked { self?.maintenanceScheduled = false; self?.maintain() }
        }
    }
    func invalidateSession(scope: String?) {
        locked { sessionLock.withLock { if let scope { scopeRevisions[scope, default: 0] &+= 1 } }; flushAccesses(); trim() }
    }
    func clear(scope: String? = nil, category: String? = nil) {
        locked {
            sessionLock.withLock {
                if let scope, let category { scopedCategoryRevisions[scope + "|" + category, default: 0] &+= 1 }
                else if let scope { scopeRevisions[scope, default: 0] &+= 1 }
                else if let category { categoryRevisions[category, default: 0] &+= 1 }
                else { revision &+= 1 }
            }
            for entry in entries() where (scope == nil || entry.scope == scope) && (category == nil || entry.category == category) {
                _ = remove(id: entry.id)
            }
        }
    }
    @discardableResult func remove(id: String, expectedBytes: Int64? = nil, expectedModified: Date? = nil, expectedFileNumber: UInt64? = nil) -> Bool {
        locked {
            guard let entry = entry(where: "id", value: id), isSafe(entry.url) else { return false }
            do {
                try activity.exclusively(entry.url) {
                    let attributes = try? FileManager.default.attributesOfItem(atPath: entry.url.path)
                    guard expectedBytes == nil || (attributes?[.size] as? NSNumber)?.int64Value == expectedBytes,
                          expectedModified == nil || attributes?[.modificationDate] as? Date == expectedModified,
                          expectedFileNumber == nil || (attributes?[.systemFileNumber] as? NSNumber)?.uint64Value == expectedFileNumber else { throw StorageFailure.stalePlan }
                    guard (attributes?[.referenceCount] as? NSNumber)?.intValue ?? 1 <= 1 else { throw StorageFailure.inUse }
                    if FileManager.default.fileExists(atPath: entry.url.path) { try FileManager.default.removeItem(at: entry.url) }
                    execute("DELETE FROM entries WHERE id=?", [id]); touched[id] = nil
                }
                return true
            } catch { return false }
        }
    }
    func forget(url: URL) { locked { execute("DELETE FROM entries WHERE path=?", [url.path]) } }
    private func trim(incoming: Int64 = 0, excluding: Set<String> = []) {
        flushAccesses()
        var remaining = totalBytes
        guard remaining + incoming > limit else { return }
        let target = max(0, limit - limit / 10 - incoming)
        for entry in entries().sorted(by: { $0.accessedAt < $1.accessedAt }) where remaining > target && !excluding.contains(entry.id) {
            if remove(id: entry.id) { remaining -= entry.bytes }
        }
    }
    private func isSafe(_ url: URL) -> Bool {
        guard StoragePaths.contains(url, in: paths.cacheRoot),
              StoragePaths.contains(url.resolvingSymlinksInPath(), in: paths.cacheRoot),
              (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else { return false }
        return url.pathExtension != "sqlite" && !url.lastPathComponent.hasPrefix("index.sqlite")
    }
    private func reconcile() {
        for entry in entries() where !isSafe(entry.url) || !FileManager.default.fileExists(atPath: entry.url.path) {
            execute("DELETE FROM entries WHERE id=?", [entry.id])
        }
        let known = Set(entries().map { $0.url.path })
        let files = root.appendingPathComponent("Files")
        if let enumerator = FileManager.default.enumerator(at: files, includingPropertiesForKeys: [.contentModificationDateKey, .isSymbolicLinkKey]) {
            for case let url as URL in enumerator where url.pathExtension == "cache" && !known.contains(url.path) && isSafe(url) {
                // Only our UUID-named expendable objects; no guessing at legacy ownership.
                try? activity.exclusively(url) { try FileManager.default.removeItem(at: url) }
            }
        }
    }
}
