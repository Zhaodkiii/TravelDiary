import Foundation

/// Keep validator and body in one cache object: eviction can never leave a dangling ETag.
nonisolated struct ResourceETagCache {
    struct Envelope: Codable, Sendable {
        let record: ETagCacheRecord
        let body: Data
    }
    let baseDirectory: URL
    var enabled: Bool { StoragePaths.contains(baseDirectory, in: StoragePaths.system.cacheRoot) }
    private func key(_ identity: String) -> ResourceCacheKey {
        // The upstream identity includes the Authorization fingerprint. No account response is
        // addressable with another account's request, including after a session switch.
        ResourceCacheKey(scope: "shared", category: "network-responses", identity: baseDirectory.path + ":" + identity)
    }
    func read(_ identity: String) -> Envelope? {
        guard enabled else { return nil }
        let key = key(identity)
        if let data = ResourceCache.shared.data(for: key), let value = try? JSONDecoder().decode(Envelope.self, from: data) { return value }
        let metadata = baseDirectory.appendingPathComponent(identity + ".meta.json")
        let bytes = baseDirectory.appendingPathComponent(identity + ".body")
        guard let data = try? Data(contentsOf: metadata), let record = try? JSONDecoder.default.decode(ETagCacheRecord.self, from: data),
              let body = try? Data(contentsOf: bytes) else { return nil }
        let value = Envelope(record: record, body: body)
        if let encoded = try? JSONEncoder().encode(value), ResourceCache.shared.store(encoded, for: key) != nil {
            try? FileManager.default.removeItem(at: metadata); try? FileManager.default.removeItem(at: bytes)
        }
        return value
    }
    func store(record: ETagCacheRecord, body: Data, identity: String) throws {
        let data = try JSONEncoder().encode(Envelope(record: record, body: body))
        ResourceCache.shared.store(data, for: key(identity))
    }
    func remove(_ identity: String) { ResourceCache.shared.remove(id: key(identity).id) }
}
