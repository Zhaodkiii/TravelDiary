import Foundation

nonisolated private struct KnowledgeStorePayload: Codable, Sendable {
    var bases: [KnowledgeBase]
}

nonisolated private enum KnowledgeFileStore {
    nonisolated static func load(accountID: Int64, fileManager: FileManager = .default) throws -> KnowledgeStorePayload {
        let url = storeURL(accountID: accountID, fileManager: fileManager)
        guard fileManager.fileExists(atPath: url.path) else {
            return KnowledgeStorePayload(bases: JSONFileKnowledgeRepository.defaultBases())
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(KnowledgeStorePayload.self, from: data)
    }

    nonisolated static func save(_ payload: KnowledgeStorePayload, accountID: Int64, fileManager: FileManager = .default) throws {
        let url = storeURL(accountID: accountID, fileManager: fileManager)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        try data.write(to: url, options: .atomic)
    }

    nonisolated private static func storeURL(accountID: Int64, fileManager: FileManager) -> URL {
        return StoragePaths.system.business("Knowledge", owner: String(accountID))
            .appending(path: "knowledge_bases.json")
    }
}

final class JSONFileKnowledgeRepository: KnowledgeRepository, @unchecked Sendable {
    static let shared = JSONFileKnowledgeRepository()

    func listBases(accountID: Int64) async throws -> [KnowledgeBase] {
        try KnowledgeFileStore.load(accountID: accountID).bases.sorted { $0.name < $1.name }
    }

    func loadBase(id: String, accountID: Int64) async throws -> KnowledgeBase? {
        try KnowledgeFileStore.load(accountID: accountID).bases.first { $0.id == id }
    }

    func saveBase(_ base: KnowledgeBase, accountID: Int64) async throws {
        var store = try KnowledgeFileStore.load(accountID: accountID)
        if let index = store.bases.firstIndex(where: { $0.id == base.id }) {
            store.bases[index] = base
        } else {
            store.bases.append(base)
        }
        try KnowledgeFileStore.save(store, accountID: accountID)
    }

    func deleteBase(id: String, accountID: Int64) async throws {
        var store = try KnowledgeFileStore.load(accountID: accountID)
        store.bases.removeAll { $0.id == id }
        try KnowledgeFileStore.save(store, accountID: accountID)
    }

    func allBaseIDs(accountID: Int64) async throws -> [String] {
        try KnowledgeFileStore.load(accountID: accountID).bases.map(\.id)
    }

    nonisolated static func defaultBases() -> [KnowledgeBase] {
        [
            KnowledgeBase(
                id: "default",
                name: "默认知识库",
                documents: [
                    KnowledgeDocument(
                        title: "DeepTutor 本地模式",
                        content: """
                        DeepTutor 本地模式在 iOS 设备上直接运行 AI 对话，无需连接 DeepTutorSerevr。
                        支持联网搜索、本地知识检索、记忆读写与 Persona 注入。
                        知识检索当前使用关键词匹配，后续可升级为向量检索。
                        """
                    ),
                ]
            ),
        ]
    }
}
