import Foundation

nonisolated private struct MasteryStorePayload: Codable, Sendable {
    var paths: [MasteryProgress]
}

nonisolated private enum MasteryFileStore {
    nonisolated static func load(accountID: Int64, fileManager: FileManager = .default) throws -> MasteryStorePayload {
        let url = storeURL(accountID: accountID, fileManager: fileManager)
        guard fileManager.fileExists(atPath: url.path) else {
            return MasteryStorePayload(paths: [])
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(MasteryStorePayload.self, from: data)
    }

    nonisolated static func save(_ payload: MasteryStorePayload, accountID: Int64, fileManager: FileManager = .default) throws {
        let url = storeURL(accountID: accountID, fileManager: fileManager)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        try data.write(to: url, options: .atomic)
    }

    nonisolated private static func storeURL(accountID: Int64, fileManager: FileManager) -> URL {
        return StoragePaths.system.business("Mastery", owner: String(accountID))
            .appending(path: "mastery.json")
    }
}

/// 按账号将掌握度路径持久化到 Application Support 下的 JSON 文件。
final class JSONFileMasteryProgressRepository: MasteryProgressRepository, @unchecked Sendable {
    static let shared = JSONFileMasteryProgressRepository()

    func load(pathID: String, accountID: Int64) async throws -> MasteryProgress? {
        let trimmed = pathID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MasteryRepositoryError.invalidPathID }
        let store = try MasteryFileStore.load(accountID: accountID)
        return store.paths.first { $0.pathID == trimmed }
    }

    func save(_ progress: MasteryProgress, accountID: Int64) async throws {
        guard !progress.pathID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MasteryRepositoryError.invalidPathID
        }
        var store = try MasteryFileStore.load(accountID: accountID)
        if let index = store.paths.firstIndex(where: { $0.pathID == progress.pathID }) {
            store.paths[index] = progress
        } else {
            store.paths.append(progress)
        }
        try MasteryFileStore.save(store, accountID: accountID)
    }
}
