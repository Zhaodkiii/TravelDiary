import Foundation

actor InMemoryMemoryRepository: MemoryRepository {
    private var records: [MemoryRecord] = []
    private var preferences: MemoryPreferences = .default
    private let searchEngine = MemorySearchEngine()

    func loadPreferences() async -> MemoryPreferences {
        preferences
    }

    func savePreferences(_ preferences: MemoryPreferences) async throws {
        self.preferences = preferences
    }

    func list(query: String?) async throws -> [MemoryRecord] {
        let trimmed = query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard trimmed.isEmpty == false else {
            return sorted(records)
        }
        return searchEngine.search(records: records, keyword: trimmed, limit: records.count).map(\.record)
    }

    func save(title: String?, content: String, pinned: Bool) async throws -> MemoryRecord {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { throw MemoryRepositoryError.emptyContent }
        let record = MemoryRecord(
            title: title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? title! : String(trimmed.prefix(20)),
            content: trimmed,
            pinned: pinned
        )
        records.append(record)
        return record
    }

    func update(id: UUID, title: String?, content: String, pinned: Bool?) async throws -> MemoryRecord {
        guard let index = records.firstIndex(where: { $0.id == id }) else {
            throw MemoryRepositoryError.emptyContent
        }
        records[index].title = title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? title! : String(content.prefix(20))
        records[index].content = content
        if let pinned {
            records[index].pinned = pinned
        }
        records[index].updatedAt = Date()
        return records[index]
    }

    func updateMatching(originalContentOrTitle: String, updatedContent: String) async throws -> MemoryRecord? {
        guard let index = records.firstIndex(where: { $0.content == originalContentOrTitle || $0.title == originalContentOrTitle }) else {
            return nil
        }
        records[index].content = updatedContent
        records[index].updatedAt = Date()
        return records[index]
    }

    func delete(id: UUID) async throws {
        records.removeAll { $0.id == id }
    }

    func deleteAll() async throws {
        records.removeAll()
    }

    func retrieve(keyword: String, limit: Int) async throws -> [MemorySearchResult] {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return sorted(records).prefix(limit).map { MemorySearchResult(record: $0, score: $0.pinned ? 2 : 1) }
        }
        return searchEngine.search(records: records, keyword: trimmed, limit: limit)
    }

    private func sorted(_ input: [MemoryRecord]) -> [MemoryRecord] {
        input.sorted {
            if $0.pinned != $1.pinned { return $0.pinned && !$1.pinned }
            return $0.updatedAt > $1.updatedAt
        }
    }
}

