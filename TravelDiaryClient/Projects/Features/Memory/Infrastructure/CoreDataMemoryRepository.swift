import CoreData
import Foundation

/// 基于 `MemoryRecordEntity` 的账号隔离记忆仓储，替代进程内 `InMemoryMemoryRepository`。
actor CoreDataMemoryRepository: MemoryRepository {
    private let coreDataStack: CoreDataStack
    private let ownerAccountID: Int64
    private let searchEngine = MemorySearchEngine()

    init(coreDataStack: CoreDataStack, ownerAccountID: Int64) {
        self.coreDataStack = coreDataStack
        self.ownerAccountID = ownerAccountID
    }

    func loadPreferences() async -> MemoryPreferences {
        .default
    }

    func savePreferences(_ preferences: MemoryPreferences) async throws {
        // 偏好仍由 UserDefaults / 设置页管理；Core Data 仓储仅负责记录。
    }

    func list(query: String?) async throws -> [MemoryRecord] {
        let records = try await fetchAllRecords()
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
            title: title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? title!
                : String(trimmed.prefix(20)),
            content: trimmed,
            pinned: pinned
        )
        try await upsert(record)
        return record
    }

    func update(id: UUID, title: String?, content: String, pinned: Bool?) async throws -> MemoryRecord {
        var record = try await requireRecord(id: id)
        record.title = title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? title!
            : String(content.prefix(20))
        record.content = content
        if let pinned {
            record.pinned = pinned
        }
        record.updatedAt = Date()
        try await upsert(record)
        return record
    }

    func updateMatching(originalContentOrTitle: String, updatedContent: String) async throws -> MemoryRecord? {
        let records = try await fetchAllRecords()
        guard let match = records.first(where: {
            $0.content == originalContentOrTitle || $0.title == originalContentOrTitle
        }) else {
            return nil
        }
        return try await update(id: match.id, title: match.title, content: updatedContent, pinned: nil)
    }

    func delete(id: UUID) async throws {
        try await coreDataStack.performBackgroundTask { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: "MemoryRecordEntity")
            request.fetchLimit = 1
            request.predicate = Self.recordPredicate(id: id, ownerAccountID: self.ownerAccountID)
            if let object = try context.fetch(request).first {
                context.delete(object)
            }
        }
    }

    func deleteAll() async throws {
        try await coreDataStack.performBackgroundTask { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: "MemoryRecordEntity")
            request.predicate = NSPredicate(format: "ownerAccountID == %lld", self.ownerAccountID)
            for object in try context.fetch(request) {
                context.delete(object)
            }
        }
    }

    func retrieve(keyword: String, limit: Int) async throws -> [MemorySearchResult] {
        let records = try await fetchAllRecords()
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return sorted(records).prefix(limit).map { MemorySearchResult(record: $0, score: $0.pinned ? 2 : 1) }
        }
        return searchEngine.search(records: records, keyword: trimmed, limit: limit)
    }

    // MARK: - Private

    private func fetchAllRecords() async throws -> [MemoryRecord] {
        try await coreDataStack.performBackgroundTask { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: "MemoryRecordEntity")
            request.predicate = NSPredicate(format: "ownerAccountID == %lld", self.ownerAccountID)
            return try context.fetch(request).compactMap(Self.mapRecord)
        }
    }

    private func requireRecord(id: UUID) async throws -> MemoryRecord {
        guard let record = try await fetchAllRecords().first(where: { $0.id == id }) else {
            throw MemoryRepositoryError.emptyContent
        }
        return record
    }

    private func upsert(_ record: MemoryRecord) async throws {
        try await coreDataStack.performBackgroundTask { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: "MemoryRecordEntity")
            request.fetchLimit = 1
            request.predicate = Self.recordPredicate(id: record.id, ownerAccountID: self.ownerAccountID)
            let object = (try context.fetch(request).first)
                ?? NSEntityDescription.insertNewObject(forEntityName: "MemoryRecordEntity", into: context)
            object.setValue(record.id, forKey: "id")
            object.setValue(self.ownerAccountID, forKey: "ownerAccountID")
            object.setValue(record.title, forKey: "title")
            object.setValue(record.content, forKey: "content")
            object.setValue(record.pinned, forKey: "pinned")
            object.setValue(record.createdAt, forKey: "createdAt")
            object.setValue(record.updatedAt, forKey: "updatedAt")
        }
    }

    private func sorted(_ input: [MemoryRecord]) -> [MemoryRecord] {
        input.sorted {
            if $0.pinned != $1.pinned { return $0.pinned && !$1.pinned }
            return $0.updatedAt > $1.updatedAt
        }
    }

    private static nonisolated func recordPredicate(id: UUID, ownerAccountID: Int64) -> NSPredicate {
        NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "ownerAccountID == %lld", ownerAccountID),
            NSPredicate(format: "id == %@", id as CVarArg),
        ])
    }

    private static nonisolated func mapRecord(_ object: NSManagedObject) -> MemoryRecord? {
        guard let id = object.value(forKey: "id") as? UUID,
              let title = object.value(forKey: "title") as? String,
              let content = object.value(forKey: "content") as? String,
              let createdAt = object.value(forKey: "createdAt") as? Date,
              let updatedAt = object.value(forKey: "updatedAt") as? Date
        else { return nil }
        let pinned = object.value(forKey: "pinned") as? Bool ?? false
        return MemoryRecord(
            id: id,
            title: title,
            content: content,
            pinned: pinned,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
