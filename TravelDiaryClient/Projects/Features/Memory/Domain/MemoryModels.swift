import Foundation

struct MemoryRecord: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var title: String
    var content: String
    var pinned: Bool
    var createdAt: Date
    var updatedAt: Date

    nonisolated init(
        id: UUID = UUID(),
        title: String,
        content: String,
        pinned: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.pinned = pinned
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct MemoryPreferences: Codable, Equatable, Sendable {
    var isEnabled: Bool
    var allowToolWrite: Bool
    var allowCrossThreadRecall: Bool
    var maxRecallCount: Int

    nonisolated init(
        isEnabled: Bool = true,
        allowToolWrite: Bool = true,
        allowCrossThreadRecall: Bool = true,
        maxRecallCount: Int = 5
    ) {
        self.isEnabled = isEnabled
        self.allowToolWrite = allowToolWrite
        self.allowCrossThreadRecall = allowCrossThreadRecall
        self.maxRecallCount = max(1, min(maxRecallCount, 20))
    }

    nonisolated static let `default` = MemoryPreferences()
}

struct MemorySearchResult: Equatable, Sendable {
    var record: MemoryRecord
    var score: Int
}

enum MemoryRepositoryError: Error, LocalizedError {
    case notSignedIn
    case emptyContent

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "当前未登录，无法访问记忆档案。"
        case .emptyContent:
            return "记忆内容不能为空。"
        }
    }
}
