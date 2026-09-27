import Foundation

protocol MemoryRepository: Sendable {
    func loadPreferences() async -> MemoryPreferences
    func savePreferences(_ preferences: MemoryPreferences) async throws

    func list(query: String?) async throws -> [MemoryRecord]
    func save(title: String?, content: String, pinned: Bool) async throws -> MemoryRecord
    func update(id: UUID, title: String?, content: String, pinned: Bool?) async throws -> MemoryRecord
    func updateMatching(originalContentOrTitle: String, updatedContent: String) async throws -> MemoryRecord?
    func delete(id: UUID) async throws
    func deleteAll() async throws
    func retrieve(keyword: String, limit: Int) async throws -> [MemorySearchResult]
}

