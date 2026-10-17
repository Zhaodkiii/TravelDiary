import Foundation

/// 访问记录是设备状态，不写入作品目录，也不推进作品更新时间。
@MainActor
struct DiaryBookAccessStore {
    struct Record: Codable, Equatable {
        let bookID: UUID
        let pageID: UUID
        let openedAt: Date
    }
    let ownerID: String
    var defaults: UserDefaults = .standard
    private var key: String { "DiaryBookAccess.v1." + Data(ownerID.utf8).base64EncodedString() }
    var records: [Record] {
        guard let data = defaults.data(forKey: key),
              let value = try? JSONDecoder().decode([Record].self, from: data) else { return [] }
        return value.sorted { $0.openedAt > $1.openedAt }
    }
    func record(bookID: UUID, pageID: UUID, at date: Date = Date()) {
        var updated = records.filter { $0.bookID != bookID }
        updated.insert(Record(bookID: bookID, pageID: pageID, openedAt: date), at: 0)
        save(updated)
    }
    func remove(_ bookID: UUID) { save(records.filter { $0.bookID != bookID }) }
    func latest(in books: [DiaryBook]) -> Record? {
        let ids = Set(books.map(\.id))
        return records.first { ids.contains($0.bookID) }
    }
    private func save(_ records: [Record]) {
        if let data = try? JSONEncoder().encode(records) { defaults.set(data, forKey: key) }
    }
    static func resumePage(in book: DiaryBook, preferred: UUID?) -> DiaryPageEntry? {
        book.contentPages.first { $0.id == preferred } ?? book.contentPages.first
    }
}

nonisolated enum DiaryShelfSort: String, CaseIterable, Identifiable {
    case updated, created, title
    var id: Self { self }
    var label: String {
        switch self { case .updated: "最近修改"; case .created: "最近创建"; case .title: "名称" }
    }
    func apply(to books: [DiaryBook], search: String) -> [DiaryBook] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return books.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }.sorted { a, b in
            switch self {
            case .updated: if a.updatedAt != b.updatedAt { return a.updatedAt > b.updatedAt }
            case .created: if a.createdAt != b.createdAt { return a.createdAt > b.createdAt }
            case .title:
                let order = a.title.localizedStandardCompare(b.title)
                if order != .orderedSame { return order == .orderedAscending }
            }
            return a.id.uuidString < b.id.uuidString
        }
    }
}
