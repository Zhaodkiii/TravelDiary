import Testing
import Foundation
@testable import TravelDiary

@MainActor
struct StorageManagementTests {
    private struct Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var paths: StoragePaths { StoragePaths(support: root.appendingPathComponent("Support"), caches: root.appendingPathComponent("Caches"), temporary: root.appendingPathComponent("Tmp")) }
        func write(_ url: URL, _ data: Data = Data("test-data".utf8)) throws {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        }
        func remove() { try? FileManager.default.removeItem(at: root) }
    }

    @Test func pathsRejectTraversalAndSymlinkEscapeWithoutCreatingDirectories() throws {
        let f = Fixture(); defer { f.remove() }
        #expect(!FileManager.default.fileExists(atPath: f.paths.books("a").path))
        #expect(f.paths.books("a") != f.paths.books("b"))
        #expect(throws: StorageFailure.self) { try StoragePaths.resolve("../outside", within: f.root) }
        try f.write(f.root.appendingPathComponent("outside/file"))
        let inside = f.root.appendingPathComponent("inside")
        try FileManager.default.createDirectory(at: inside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: inside.appendingPathComponent("link"), withDestinationURL: f.root.appendingPathComponent("outside"))
        #expect(throws: StorageFailure.self) { try StoragePaths.resolve("link/file", within: inside) }
    }

    @Test func scanAndCleanNeverExposeOrDeleteAnotherAccountsPrivateFiles() async throws {
        let f = Fixture(); defer { f.remove() }
        try f.write(f.paths.catalog("a"))
        try f.write(f.paths.catalog("b"), Data(repeating: 2, count: 300))
        let original = f.paths.books("a").appendingPathComponent("important-original")
        try f.write(original)
        let service = StorageService(paths: f.paths)
        await service.activate(owner: "a")
        let snapshot = try await service.scan(owner: "a")
        #expect(snapshot.totals[.otherAccounts] == 300)
        #expect(snapshot.items.count == 1)
        #expect(snapshot.items.allSatisfy { $0.title == "模板目录缓存" })
        let result = try await service.clean(snapshot: snapshot, ids: Set(snapshot.items.map(\.id)))
        #expect(result.removed == 1)
        #expect(FileManager.default.fileExists(atPath: f.paths.catalog("b").path))
        #expect(FileManager.default.fileExists(atPath: original.path))
    }

    @Test func changingAFileAfterPreviewInvalidatesItsDeletion() async throws {
        let f = Fixture(); defer { f.remove() }
        let service = StorageService(paths: f.paths)
        await service.activate(owner: "a")
        try f.write(f.paths.catalog("a"))
        let snapshot = try await service.scan(owner: "a")
        try f.write(f.paths.catalog("a"), Data("new content must survive".utf8))
        let result = try await service.clean(snapshot: snapshot, ids: Set(snapshot.items.map(\.id)))
        #expect(result.removed == 0 && result.skipped == 1)
        #expect(try Data(contentsOf: f.paths.catalog("a")) == Data("new content must survive".utf8))
    }

    @Test func leaseAcquiredAfterScanProtectsFileAtExecution() async throws {
        let f = Fixture(); defer { f.remove() }
        let activity = StorageActivity()
        let service = StorageService(paths: f.paths, activity: activity)
        await service.activate(owner: "a")
        try f.write(f.paths.catalog("a"))
        let snapshot = try await service.scan(owner: "a")
        let lease = activity.acquire(f.paths.catalog("a"))
        let result = try await service.clean(snapshot: snapshot, ids: Set(snapshot.items.map(\.id)))
        withExtendedLifetime(lease) {}
        #expect(result.removed == 0 && result.skipped == 1)
        #expect(FileManager.default.fileExists(atPath: f.paths.catalog("a").path))
    }

    @Test func accountSwitchAndReturnStillRejectsAnOldPlan() async throws {
        let f = Fixture(); defer { f.remove() }
        let service = StorageService(paths: f.paths)
        await service.activate(owner: "a"); try f.write(f.paths.catalog("a"))
        let snapshot = try await service.scan(owner: "a")
        await service.activate(owner: "b"); await service.activate(owner: "a")
        await #expect(throws: StorageFailure.self) { try await service.clean(snapshot: snapshot, ids: Set(snapshot.items.map(\.id))) }
        #expect(FileManager.default.fileExists(atPath: f.paths.catalog("a").path))
    }

    @Test func hardLinkedContentIsCountedOnceAndProtected() async throws {
        let f = Fixture(); defer { f.remove() }
        try f.write(f.paths.catalog("a"), Data(repeating: 0, count: 1024))
        try FileManager.default.linkItem(at: f.paths.catalog("a"), to: f.paths.catalog("a").deletingLastPathComponent().appendingPathComponent("second.json"))
        let service = StorageService(paths: f.paths)
        await service.activate(owner: "a")
        let snapshot = try await service.scan(owner: "a")
        #expect(snapshot.total == 1024)
        #expect(snapshot.safeBytes == 0)
    }

    @Test func exportsRequireCompletionAndRecoverableSource() async throws {
        let f = Fixture(); defer { f.remove() }
        let service = StorageService(paths: f.paths)
        await service.activate(owner: "a")
        let book = UUID()
        let directory = try StorageWorkspace.create(owner: "a", bookID: book, paths: f.paths)
        try f.write(directory.appendingPathComponent("output.pdf"))
        var snapshot = try await service.scan(owner: "a")
        #expect(snapshot.items.isEmpty)
        try StorageWorkspace.complete(directory)
        snapshot = try await service.scan(owner: "a")
        #expect(snapshot.items.isEmpty) // Completed but source absent: keep the only result.
        var source = DiaryBook(title: "Source"); source.id = book
        try f.write(f.paths.books("a").appendingPathComponent(book.uuidString).appendingPathComponent("book.json"), JSONEncoder().encode(source))
        snapshot = try await service.scan(owner: "a")
        #expect(snapshot.items.count == 1)
        #expect(snapshot.safeBytes == 0) // Newly completed exports require explicit selection.
    }

    @Test func orphanPreviewIsNeverAdvertisedAsSafelyRebuildable() async throws {
        let f = Fixture(); defer { f.remove() }
        let png = f.paths.previews("a").appendingPathComponent("\(UUID())/\(UUID())/\(UUID())/v2-light-ink-480.png")
        try f.write(png)
        let service = StorageService(paths: f.paths)
        await service.activate(owner: "a")
        let snapshot = try await service.scan(owner: "a")
        #expect(snapshot.totals[.previews] == 9)
        #expect(snapshot.items.isEmpty)
    }

    @Test func trashRestoreAndPurgePreserveIdentityAndOtherAccounts() async throws {
        let f = Fixture(); defer { f.remove() }
        let store = DiaryDocumentStore(ownerID: "a", baseDirectory: f.paths.support)
        let book = try await store.createBook(title: "原件")
        let otherStore = DiaryDocumentStore(ownerID: "b", baseDirectory: f.paths.support)
        let other = try await otherStore.createBook(title: "另一个账号")
        var page = DiaryDocument(); page.bookID = book.id
        let bookStore = DiaryDocumentStore(ownerID: "a", baseDirectory: f.paths.support, bookID: book.id)
        try await bookStore.save(page)
        let saved = try await bookStore.loadBook()
        try await store.trashBook(book.id)
        #expect(try await store.listBooks().isEmpty)
        #expect(try await store.listTrashedBooks().first?.id == book.id)
        try await store.restoreBook(book.id)
        #expect(try await bookStore.loadBook() == saved)
        #expect(try await bookStore.load(page.id).document == page)
        try await store.trashBook(book.id)
        try await store.permanentlyDeleteBook(book.id)
        #expect(try await store.listTrashedBooks().isEmpty)
        #expect(try await otherStore.listBooks().map(\.id) == [other.id])
    }

    @Test func activeEditorPreventsTrashingItsBook() async throws {
        let f = Fixture(); defer { f.remove() }
        let store = DiaryDocumentStore(ownerID: "a", baseDirectory: f.paths.support)
        let book = try await store.createBook(title: "编辑中")
        let bookStore = DiaryDocumentStore(ownerID: "a", baseDirectory: f.paths.support, bookID: book.id)
        var page = DiaryDocument(); page.bookID = book.id
        let session = DiaryEditorSession(document: page, images: [:], store: bookStore)
        await #expect(throws: StorageFailure.self) { try await store.trashBook(book.id) }
        withExtendedLifetime(session) {}
        #expect(try await store.listBooks().count == 1)
    }

    @Test func clearingAttachmentsOnlyClearsTheActiveAccount() async throws {
        let f = Fixture(); defer { f.remove() }
        let cache = FileCacheManager(baseDirectory: f.root)
        await cache.activateAccountContext(1)
        let a = try await cache.save(data: Data("a".utf8), fileUUID: "a", fileName: "a.txt")
        await cache.activateAccountContext(2)
        let b = try await cache.save(data: Data("b".utf8), fileUUID: "b", fileName: "b.txt")
        try await cache.clearAll()
        #expect(FileManager.default.fileExists(atPath: a.path))
        #expect(!FileManager.default.fileExists(atPath: b.path))
    }
    @Test func registeredPreviewRequiresItsCompleteSourceAndCanBeRebuiltAfterCleanup() async throws {
        let f = Fixture(); defer { f.remove() }
        let paths = StoragePaths(support: f.paths.support, caches: f.paths.support.appendingPathComponent("Caches"), temporary: f.paths.support.appendingPathComponent("Temporary"))
        let store = DiaryDocumentStore(ownerID: "a", baseDirectory: paths.support)
        let book = try await store.createBook(title: "Source")
        let pages = DiaryDocumentStore(ownerID: "a", baseDirectory: paths.support, bookID: book.id)
        var page = DiaryDocument(); page.bookID = book.id
        try await pages.save(page)
        let entry = try #require(try await pages.loadBook().pages.first)
        try await pages.cachePreview(Data("preview".utf8), page: entry, large: false)
        let service = StorageService(paths: paths)
        await service.activate(owner: "a")
        let snapshot = try await service.scan(owner: "a")
        let previews = snapshot.items.filter { $0.category == .previews }
        #expect(previews.count == 1)
        let result = try await service.clean(snapshot: snapshot, ids: Set(previews.map(\.id)))
        #expect(result.removed == 1)
        #expect(try await pages.cachedPreview(entry, large: false) == nil)
        #expect(try await pages.load(page.id).document == page)
    }

    @Test func automaticMaintenanceIsOptInAndOnlySelectsEligibleExpiredExports() async throws {
        let f = Fixture(); defer { f.remove() }
        let service = StorageService(paths: f.paths)
        await service.activate(owner: "a")
        let source = DiaryBook(title: "Source")
        try f.write(f.paths.books("a").appendingPathComponent(source.id.uuidString).appendingPathComponent("book.json"), JSONEncoder().encode(source))
        let directory = try StorageWorkspace.create(owner: "a", bookID: source.id, paths: f.paths)
        let output = directory.appendingPathComponent("output.pdf")
        try f.write(output)
        var record = try JSONDecoder().decode(StorageWorkspace.self, from: Data(contentsOf: directory.appendingPathComponent(StorageWorkspace.manifestName)))
        record.completedAt = Date().addingTimeInterval(-8 * 86400)
        try JSONEncoder().encode(record).write(to: directory.appendingPathComponent(StorageWorkspace.manifestName), options: .atomic)
        var snapshot = try await service.scan(owner: "a")
        #expect(try await service.maintain(snapshot: snapshot) == nil)
        #expect(FileManager.default.fileExists(atPath: output.path))
        var policy = StoragePolicy(); policy.automaticallyManageSafeFiles = true
        try await service.savePolicy(policy, owner: "a")
        snapshot = try await service.scan(owner: "a")
        let result = try await service.maintain(snapshot: snapshot)
        #expect(result?.removed == 1)
        #expect(!FileManager.default.fileExists(atPath: output.path))
        #expect(FileManager.default.fileExists(atPath: f.paths.books("a").appendingPathComponent(source.id.uuidString).appendingPathComponent("book.json").path))
    }

    @Test func exportAccessLeasePreventsDeletingPreviewedOutput() async throws {
        let f = Fixture(); defer { f.remove() }
        let service = StorageService(paths: f.paths)
        await service.activate(owner: "a")
        let source = DiaryBook(title: "Source")
        try f.write(f.paths.books("a").appendingPathComponent(source.id.uuidString).appendingPathComponent("book.json"), JSONEncoder().encode(source))
        let directory = try StorageWorkspace.create(owner: "a", bookID: source.id, paths: f.paths)
        try f.write(directory.appendingPathComponent("output.pdf"))
        try StorageWorkspace.complete(directory)
        let snapshot = try await service.scan(owner: "a")
        let item = try #require(snapshot.items.first)
        let access = try await service.exportAccess(snapshot: snapshot, id: item.id)
        let result = try await service.clean(snapshot: snapshot, ids: [item.id])
        withExtendedLifetime(access) {}
        #expect(result.skipped == 1 && result.removed == 0)
    }

}
