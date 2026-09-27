import Foundation

nonisolated struct KnowledgeDocument: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var title: String
    var content: String
    var updatedAt: Date

    nonisolated init(
        id: String = UUID().uuidString,
        title: String,
        content: String,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.updatedAt = updatedAt
    }
}

nonisolated struct KnowledgeBase: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var name: String
    var documents: [KnowledgeDocument]
    var updatedAt: Date

    nonisolated init(
        id: String,
        name: String,
        documents: [KnowledgeDocument] = [],
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.documents = documents
        self.updatedAt = updatedAt
    }
}

nonisolated struct KnowledgeSearchHit: Equatable, Sendable {
    let knowledgeBaseID: String
    let knowledgeBaseName: String
    let documentID: String
    let title: String
    let snippet: String
    let score: Int
}

enum KnowledgeRepositoryError: Error, LocalizedError {
    case notFound(String)
    case emptyContent

    var errorDescription: String? {
        switch self {
        case .notFound(let id):
            return "未找到知识库：\(id)"
        case .emptyContent:
            return "文档内容不能为空。"
        }
    }
}
