import Foundation

/// Shared by synchronous file providers and async tasks. The lock covers check AND mutation.
nonisolated final class StorageActivity: @unchecked Sendable {
    static let shared = StorageActivity()
    private let lock = NSRecursiveLock()
    private var readers: [UUID: URL] = [:]

    func acquire(_ url: URL) -> Lease {
        lock.lock(); defer { lock.unlock() }
        let id = UUID()
        readers[id] = url.standardizedFileURL
        return Lease(id: id, registry: self)
    }
    func isInUse(_ url: URL) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return readers.values.contains { StoragePaths.contains($0, in: url) || StoragePaths.contains(url, in: $0) }
    }
    func exclusively<T>(_ url: URL, _ action: () throws -> T) throws -> T {
        lock.lock(); defer { lock.unlock() }
        guard !isInUse(url) else { throw StorageFailure.inUse }
        return try action()
    }
    private func release(_ id: UUID) {
        lock.lock(); defer { lock.unlock() }; readers.removeValue(forKey: id)
    }
    final class Lease: @unchecked Sendable {
        private let id: UUID
        private let registry: StorageActivity
        fileprivate init(id: UUID, registry: StorageActivity) { self.id = id; self.registry = registry }
        deinit { registry.release(id) }
    }
}

/// Per-task output folders carry ownership and a completion marker. Unknown/unfinished folders are protected.
nonisolated struct StorageWorkspace: Codable, Sendable {
    let id: UUID
    let owner: String
    let bookID: UUID
    let createdAt: Date
    var completedAt: Date?
    static let manifestName = ".storage-workspace.json"

    static func create(owner: String, bookID: UUID, parent: URL? = nil, paths: StoragePaths = .system) throws -> URL {
        let value = StorageWorkspace(id: UUID(), owner: owner, bookID: bookID, createdAt: Date())
        let url = (parent ?? paths.workspaces).appendingPathComponent(value.id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        do { try JSONEncoder().encode(value).write(to: url.appendingPathComponent(manifestName), options: .atomic) }
        catch { try? FileManager.default.removeItem(at: url); throw error }
        return url
    }
    static func complete(_ directory: URL) throws {
        let url = directory.appendingPathComponent(manifestName)
        var value = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        value.completedAt = Date()
        try JSONEncoder().encode(value).write(to: url, options: .atomic)
    }
}
