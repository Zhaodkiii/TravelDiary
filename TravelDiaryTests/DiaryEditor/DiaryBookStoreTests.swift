import Testing
import Foundation
@testable import TravelDiary

@MainActor
struct DiaryBookStoreTests {
    private let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    private func store(_ book: UUID? = nil, owner: String = "owner") -> DiaryDocumentStore {
        DiaryDocumentStore(ownerID: owner, baseDirectory: folder, bookID: book)
    }
    private func page(_ book: DiaryBook) -> DiaryDocument {
        var value = DiaryDocument(); value.bookID = book.id
        value.objects[value.rootContentID]?.referenceSize = book.defaultPageSize
        return value
    }

    @Test
    func deletingBookRemovesOnlySelectedOwnersBook() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let deleted = try await store().createBook(title: "删除")
        let kept = try await store().createBook(title: "保留")
        let other = try await store(owner: "other").createBook(title: "另一个账号")
        try await store(deleted.id).save(page(deleted))
        try await store().trashBook(deleted.id)
        let books = try await store().listBooks()
        #expect(books.map(\.id) == [kept.id])
        let others = try await store(owner: "other").listBooks()
        #expect(others.map(\.id) == [other.id])
        // Repeated deletion is harmless and never targets another book.
        try await store().trashBook(deleted.id)
        #expect(!FileManager.default.fileExists(atPath: StoragePaths(support: folder, caches: folder.appendingPathComponent("Caches"), temporary: folder.appendingPathComponent("Temporary")).books("owner").appendingPathComponent(deleted.id.uuidString).path))
    }

    @Test
    func testShellIsIndependentAndPersists() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let original = try await store().createBook(title: "外壳", preset: .portrait)
        let repository = store(original.id)
        let shell = page(original)
        let content = page(original)
        try await repository.save(shell)
        try await repository.save(content)
        try await repository.setCover(content.id)
        var book = try await repository.loadBook()
        #expect(book.shell == nil)
        #expect(book.contentPages.count == 2)
        // 缺少新增字段的旧目录仍能正常解码，不推断外壳。
        let encoded = try JSONEncoder().encode(book)
        var json = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        json.removeValue(forKey: "shellPageID")
        let legacy = try JSONDecoder().decode(DiaryBook.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(legacy.shell == nil)
        try await repository.setShell(shell.id)
        book = try await store(original.id).loadBook()
        #expect(book.shell?.id == shell.id)
        #expect(book.effectiveCover?.id == content.id)
        #expect(book.contentPages.map(\.id) == [content.id])
        try await repository.setShell(nil)
        book = try await repository.loadBook()
        #expect(book.contentPages.map(\.id) == [shell.id, content.id])
        try await repository.setShell(shell.id)
        try await repository.trashPage(shell.id)
        book = try await repository.loadBook()
        #expect(book.shellPageID == nil)
        #expect(book.effectiveCover?.id == content.id)
    }

    /// 同名本、页顺序和独立图层在重建 Store 后仍能正确恢复。
    @Test
    func testBooksAndPagesSurviveReopen() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = store()
        let first = try await library.createBook(title: "旅行", preset: .portrait)
        let second = try await library.createBook(title: "旅行", preset: .square)
        #expect(first.id != second.id)
        let repository = store(first.id)
        var a = page(first)
        let b = page(first)
        a.objects[a.rootContentID]?.background = .pink
        try await repository.save(a); try await repository.save(b)
        let reopened = store(first.id)
        let book = try await reopened.loadBook()
        #expect(book.pages.map(\.id) == [a.id, b.id])
        let loaded = try await reopened.load(a.id)
        #expect(loaded.document == a)
        let empty = try await store(second.id).loadBook()
        #expect(empty.pages.isEmpty)
        let isolated = try await store(owner: "another").listBooks()
        #expect(isolated.isEmpty)
    }

    /// 旧会话不能覆盖已由另一会话提交的新版本。
    @Test
    func testStalePageSaveIsRejected() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let book = try await store().createBook(title: "冲突", preset: .portrait)
        let writer = store(book.id)
        let original = page(book)
        try await writer.save(original)
        let other = store(book.id)
        var stale = try await other.load(original.id).document
        var current = original
        current.objects[current.rootContentID]?.background = .yellow
        try await writer.save(current)
        stale.objects[stale.rootContentID]?.background = .mint
        do { try await other.save(stale); Issue.record("不应覆盖新版本") }
        catch DiaryEditorError.pageConflict { }
        let result = try await store(book.id).load(original.id)
        #expect(result.document.root.background == .yellow)
    }

    /// 排序与删除只修改目录；恢复后页内容和版本继续可编辑。
    @Test
    func testCoverReorderTrashAndRestore() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let book = try await store().createBook(title: "管理", preset: .portrait)
        let repository = store(book.id)
        let a = page(book), b = page(book)
        try await repository.save(a); try await repository.save(b)
        try await repository.setCover(a.id)
        try await repository.movePage(a.id, forward: true)
        var state = try await repository.loadBook()
        #expect(state.pages.map(\.id) == [b.id, a.id])
        #expect(state.effectiveCover?.id == a.id)
        try await repository.trashPage(a.id)
        state = try await repository.loadBook()
        #expect(state.effectiveCover?.id == b.id)
        #expect(state.trashedPages.count == 1)
        try await repository.restorePage(a.id)
        state = try await repository.loadBook()
        #expect(state.pages.map(\.id) == [b.id, a.id])
        let restored = try await repository.load(a.id)
        #expect(restored.document == a)
    }

    @Test
    func testDragOrderPersistsAndRejectsStaleOrInvalidLists() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let book = try await store().createBook(title: "拖动排序", preset: .portrait)
        let repository = store(book.id)
        let a = page(book), b = page(book), c = page(book)
        try await repository.save(a)
        try await repository.save(b)
        try await repository.save(c)
        try await repository.setCover(b.id)
        let before = try await repository.loadBook()
        try await repository.reorderPages([c.id, a.id, b.id], expectedRevision: before.catalogRevision)
        let saved = try await store(book.id).loadBook()
        #expect(saved.pages.map(\.id) == [c.id, a.id, b.id])
        #expect(saved.coverPageID == b.id)
        #expect(saved.pages.first?.revisionID == before.pages.last?.revisionID)
        do {
            try await repository.reorderPages([a.id, b.id, c.id], expectedRevision: before.catalogRevision)
            Issue.record("过期排序不应覆盖新顺序")
        } catch DiaryEditorError.pageConflict { }
        do {
            try await repository.reorderPages([a.id, a.id, c.id], expectedRevision: saved.catalogRevision)
            Issue.record("重复页面不应发布")
        } catch DiaryEditorError.invalidDocument { }
        let final = try await repository.loadBook()
        #expect(final == saved)
    }

    @Test
    func testWrongBookAndInvalidDocumentCannotPublish() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let book = try await store().createBook(title: "事务", preset: .portrait)
        let repository = store(book.id)
        var value = page(book)
        try await repository.save(value)
        let before = try await repository.loadBook()
        value.objects[value.rootContentID]?.referenceSize.width = .nan
        do { try await repository.save(value); Issue.record("无效尺寸不能提交") } catch { }
        let after = try await repository.loadBook()
        #expect(before == after)
        do { try await repository.save(DiaryDocument()); Issue.record("页面必须归属当前本") } catch { }
    }
}
