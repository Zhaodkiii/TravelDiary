import Foundation

struct LoadMemoryArchiveUseCase: Sendable {
    let repository: any MemoryRepository

    func execute(query: String? = nil) async throws -> [MemoryRecord] {
        try await repository.list(query: query)
    }
}

struct SaveMemoryUseCase: Sendable {
    let repository: any MemoryRepository

    func execute(title: String? = nil, content: String, pinned: Bool = false) async throws -> MemoryRecord {
        try await repository.save(title: title, content: content, pinned: pinned)
    }
}

struct RetrieveMemoryUseCase: Sendable {
    let repository: any MemoryRepository

    func execute(keyword: String, limit: Int? = nil) async throws -> [MemorySearchResult] {
        let preferences = await repository.loadPreferences()
        guard preferences.isEnabled, preferences.allowCrossThreadRecall else { return [] }
        return try await repository.retrieve(keyword: keyword, limit: limit ?? preferences.maxRecallCount)
    }
}

struct UpdateMemoryUseCase: Sendable {
    let repository: any MemoryRepository

    func execute(id: UUID, title: String?, content: String, pinned: Bool?) async throws -> MemoryRecord {
        try await repository.update(id: id, title: title, content: content, pinned: pinned)
    }

    func execute(originalContentOrTitle: String, updatedContent: String) async throws -> MemoryRecord? {
        try await repository.updateMatching(originalContentOrTitle: originalContentOrTitle, updatedContent: updatedContent)
    }
}

struct DeleteMemoryUseCase: Sendable {
    let repository: any MemoryRepository

    func execute(id: UUID) async throws {
        try await repository.delete(id: id)
    }

    func deleteAll() async throws {
        try await repository.deleteAll()
    }
}

struct MemoryPreferencesUseCase: Sendable {
    let repository: any MemoryRepository

    func load() async -> MemoryPreferences {
        await repository.loadPreferences()
    }

    func save(_ preferences: MemoryPreferences) async throws {
        try await repository.savePreferences(preferences)
    }
}
