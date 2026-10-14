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
