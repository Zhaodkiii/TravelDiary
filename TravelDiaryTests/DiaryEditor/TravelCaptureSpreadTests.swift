import Testing
import Foundation
import UIKit
@testable import TravelDiary

@MainActor
struct TravelCaptureSpreadTests {
    @Test func spreadPagesRemainIndependentAfterReopening() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = DiaryDocumentStore(ownerID: "spread-test", baseDirectory: directory)
        let book = try await library.createBook(title: "随记", preset: .spread)
        let store = DiaryDocumentStore(ownerID: "spread-test", baseDirectory: directory, bookID: book.id)
        for _ in 0..<3 {
            var document = DiaryDocument()
            document.bookID = book.id
            document.objects[document.rootContentID]?.referenceSize = DiaryPagePreset.spread.size
            try await store.save(document)
        }
        let reopened = try await store.loadBook()
        #expect(reopened.defaultPageSize == CGSize(width: 4370, height: 3130))
        #expect(reopened.readingSpreads.count == 3)
        #expect(reopened.readingSpreads.allSatisfy { $0.compactMap { $0 }.count == 1 })
        for page in reopened.pages {
            let loaded = try await store.load(page.id)
            #expect(loaded.document.root.referenceSize == reopened.defaultPageSize)
        }
    }
    @Test func captureSessionCanSaveAndStillDetectRealConflicts() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = DiaryDocumentStore(ownerID: "capture-session", baseDirectory: directory)
        let book = try await library.createBook(title: "随记", preset: .spread)
        let original = DiaryDocumentStore(ownerID: "capture-session", baseDirectory: directory, bookID: book.id)
        var document = DiaryDocument()
        document.bookID = book.id
        document.objects[document.rootContentID]?.referenceSize = book.defaultPageSize
        try await original.save(document)
        // 使用与新入口完全相同的加载路径，首次保存和重复保存都应成功。
        let session = try await TravelCaptureSessionLoader.open(pageID: document.id,
            store: DiaryDocumentStore(ownerID: "capture-session", baseDirectory: directory, bookID: book.id))
        try await session.save()
        session.setBackground(DiaryColor(red: 1, green: 1, blue: 1, alpha: 1))
        try await session.save()
        // 另一会话写入后仍应拒绝过期保存，不能通过移除版本保护解决问题。
        let other = try await TravelCaptureSessionLoader.open(pageID: document.id,
            store: DiaryDocumentStore(ownerID: "capture-session", baseDirectory: directory, bookID: book.id))
        try await other.save()
        do {
            try await session.save()
            Issue.record("过期会话不应覆盖其他会话的修改")
        } catch { #expect(error is DiaryEditorError) }
    }
}
