import Testing
import Foundation
import ImageIO
@testable import TravelDiary

@MainActor
struct DiaryCoverLifecycleTests {
    @Test func completedPageGetsOneEditableCoverAtPrintResolution() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let catalog = DiaryDocumentStore(ownerID: "default-cover", baseDirectory: folder)
        let created = try await catalog.createBook(title: "旅行随记", preset: .spread)
        let store = DiaryDocumentStore(ownerID: "default-cover", baseDirectory: folder, bookID: created.id)
        let draft = try await store.prepareCoverDraft().document
        var body = DiaryDocument()
        body.bookID = created.id
        body.objects[body.rootContentID]?.referenceSize = DiaryPagePreset.spread.size
        body.objects[body.rootContentID]?.background = .pink
        try await store.save(body, addDefaultCover: true)
        var book = try await store.loadBook()
        var cover = try #require(book.effectiveCover)
        let coverID = cover.id
        #expect(cover.size == DiaryBook.coverSize)
        #expect(book.pages.first?.id == coverID)
        #expect(book.bodyPages.map(\.id) == [body.id])
        #expect(book.bodyPageCount == 2)
        #expect(book.coverDraft?.id == draft.id)
        try await store.save(body, addDefaultCover: true)
        #expect(try await store.loadBook().effectiveCover?.id == coverID)

        try await store.renameBook("新居初记")
        cover = try #require(try await store.loadBook().effectiveCover)
        var loaded = try await store.load(coverID).document
        let titleID = try #require(cover.defaultCover?.boundTitleLayerID)
        #expect(loaded.layer(titleID)?.text == "新居初记")
        loaded.update(titleID) { $0.text = "我自己的标题" }
        try await store.save(loaded)
        cover = try #require(try await store.loadBook().effectiveCover)
        try await store.applyDefaultCover(.watercolor, expectedCover: cover)
        book = try await store.loadBook()
        #expect(book.effectiveCover?.id == coverID)
        #expect(book.effectiveCover?.defaultCover?.style == .watercolor)
        #expect(try await store.load(coverID).document.layer(titleID)?.text == "我自己的标题")

        let result = try await DiaryBookImageExporter.export(book: book, store: store, mode: .pages([coverID]),
            outputDirectory: folder) { _, _ in }
        let url = try #require(result.urls.first)
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let metadata = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect((metadata[kCGImagePropertyPixelWidth] as? Int) == 2185)
        #expect((metadata[kCGImagePropertyPixelHeight] as? Int) == 3130)
        #expect((metadata[kCGImagePropertyDPIWidth] as? Int) == 300)
        #expect((metadata[kCGImagePropertyDPIHeight] as? Int) == 300)

        try await store.setCover(nil)
        try await store.save(body, addDefaultCover: true)
        #expect(try await store.loadBook().effectiveCover == nil)
    }

    @Test func draftPublishReplaceRemoveAndRestoreKeepBodyIntact() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = DiaryDocumentStore(ownerID: "cover", baseDirectory: folder)
        let original = try await library.createBook(title: "封面", preset: .spread)
        let store = DiaryDocumentStore(ownerID: "cover", baseDirectory: folder, bookID: original.id)
        var body = DiaryDocument(); body.bookID = original.id
        body.objects[body.rootContentID]?.referenceSize = DiaryPagePreset.spread.size
        try await store.save(body)
        var book = try await store.loadBook()
        #expect(book.effectiveCover == nil)
        #expect(book.readingSpreads[0].allSatisfy { $0 == nil })
        #expect(book.exportSpreads.count == 1 && book.bodyPageCount == 2)
        do { try await store.setCover(body.id); Issue.record("跨页不能作为封面") }
        catch DiaryEditorError.invalidDocument { }
        do { try await store.copyAsCover(body.id); Issue.record("跨页不能复制为封面") }
        catch DiaryEditorError.invalidDocument { }

        var draft = try await store.prepareCoverDraft().document
        #expect(draft.root.referenceSize == DiaryBook.coverSize)
        draft.objects[draft.rootContentID]?.background = .pink
        try await store.save(draft)
        let reopened = DiaryDocumentStore(ownerID: "cover", baseDirectory: folder, bookID: original.id)
        #expect(try await reopened.prepareCoverDraft().document == draft)
        book = try await reopened.loadBook()
        #expect(book.pages.map(\.id) == [body.id] && book.effectiveCover == nil)
        #expect(book.exportSpreads.count == 1)
        try await reopened.finishCoverDraft(draft.id, replacing: nil)
        book = try await reopened.loadBook()
        #expect(book.pages.map(\.id) == [draft.id, body.id])
        #expect(book.coverDraft == nil && book.effectiveCover?.id == draft.id)
        #expect(book.readingSpreads[0][0] == nil && book.readingSpreads[0][1]?.id == draft.id)
        #expect(book.defaultPageSize == DiaryPagePreset.spread.size)
        #expect(book.bodyPageCount == 2 && book.pageLabel(book.pages[1]) == "第 1–2 页")
        let replacement = try await reopened.prepareCoverDraft().document
        do { try await reopened.finishCoverDraft(replacement.id, replacing: nil); Issue.record("过期替换不能覆盖封面") }
        catch DiaryEditorError.pageConflict { }
        try await reopened.finishCoverDraft(replacement.id, replacing: draft.id)
        book = try await reopened.loadBook()
        #expect(book.pages.map(\.id) == [replacement.id, body.id])
        #expect(book.trashedPages.map(\.id) == [draft.id])
        try await reopened.setCover(nil)
        book = try await reopened.loadBook()
        #expect(book.effectiveCover == nil && book.pages.map(\.id) == [body.id])
        try await reopened.restorePage(draft.id)
        book = try await reopened.loadBook()
        #expect(book.effectiveCover == nil)
        #expect(try await reopened.load(body.id).document == body)
    }

    @Test func copiedCoverRetainsSourceAndDraftDiscardDoesNotCreatePage() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = DiaryDocumentStore(ownerID: "copy", baseDirectory: folder)
        let original = try await library.createBook(title: "复制", preset: .portrait)
        let store = DiaryDocumentStore(ownerID: "copy", baseDirectory: folder, bookID: original.id)
        var source = DiaryDocument(); source.bookID = original.id
        source.objects[source.rootContentID]?.referenceSize = original.defaultPageSize
        source.objects[source.rootContentID]?.background = .pink
        try await store.save(source)
        let draft = try await store.prepareCoverDraft()
        try await store.discardCoverDraft(draft.document.id)
        #expect(try await store.loadBook().pages.count == 1)
        try await store.copyAsCover(source.id)
        let book = try await store.loadBook()
        let cover = try #require(book.effectiveCover)
        #expect(cover.id != source.id && book.pages.first?.id == cover.id)
        #expect(book.bodyPages.map(\.id) == [source.id])
        let copied = try await store.load(cover.id)
        #expect(copied.document.root == source.root)
        #expect(try await store.load(source.id).document == source)
    }
}
