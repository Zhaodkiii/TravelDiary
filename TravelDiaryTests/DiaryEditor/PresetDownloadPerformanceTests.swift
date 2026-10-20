import Testing
import Foundation
import Combine
@testable import TravelDiary

@MainActor
struct PresetDownloadPerformanceTests {
    private func fixture(_ root: URL, status: String = "ready") throws -> PresetDownloadJob {
        let data = Data("""
        {"format":"TravelDiary.PresetBook","schemaVersion":1,"layerSchemaVersion":1,
        "templateBookID":"test-book","packageVersion":1,"title":"Test","seriesID":"test",
        "pageSize":{"width":1,"height":1},"coverPageID":"p",
        "pages":[{"id":"p","title":"Page","path":"page.json"}],
        "objectTable":{},"assetTable":{},"requiredCapabilities":[],
        "files":[{"path":"page.json","byteCount":2,"sha256":"unused"}]}
        """.utf8)
        var job = PresetDownloadJob(id: UUID(), owner: "owner", planID: "plan", title: "Test",
            manifestData: data, wholeBook: true, targetID: nil, afterPageID: nil, expectedRevision: nil)
        job.status = status
        let folder = root.appendingPathComponent(job.id.uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: folder.appendingPathComponent("page.json"))
        try JSONEncoder().encode([job]).write(to: root.appendingPathComponent("jobs.json"))
        return job
    }

    @Test func downloadCompletionKeepsOpenReaderWhileNextOpeningUsesCache() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let book = RemotePresetBook(id: "test-book", title: "Test", series: "test", version: 1,
                                    page_count: 1, cover_url: "https://example.test/thumb")
        let item = PresetLibraryItem(id: book.id, local: nil, remote: book)
        let opened = PresetReaderPresentation(item: item, cachedPackage: nil)
        guard case .remote(let initial) = opened.source else {
            Issue.record("An uncached preset must open the remote reader"); return
        }
        #expect(initial.id == book.id)

        // Publishing a complete cache updates catalog availability while a reader is open.
        _ = try fixture(root)
        let manager = PresetDownloadManager(directory: root)
        await manager.waitUntilRestored()
        #expect(manager.availability.hasDownloadedPage(bookID: book.id, version: book.version, pageID: "p"))
        let cached = try #require(manager.completeCachedPackage(for: book))
        guard case .remote(let retained) = opened.source else {
            Issue.record("Download completion must not replace the reader owning the import sheet"); return
        }
        #expect(retained.id == initial.id && retained.version == initial.version)

        let reopened = PresetReaderPresentation(item: item, cachedPackage: cached)
        guard case .local(let local) = reopened.source else {
            Issue.record("A new presentation should use the available offline cache"); return
        }
        #expect(local.id == book.id && local.manifest.packageVersion == book.version)
        let preparation = try await manager.prepareImport(book: book, pageIDs: ["p"], wholeBook: true, ownerID: "owner")
        #expect(preparation.downloadID == nil)
        #expect(manager.jobs.first?.status == "ready")
        #expect(manager.jobs.first?.resultID == nil)
    }

    @Test func restoreBuildsIndexAndQueriesDoNotRescanDisk() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let job = try fixture(root)
        let manager = PresetDownloadManager(directory: root)
        await manager.waitUntilRestored()
        #expect(manager.availability.downloadedPageIDs(bookID: "test-book", version: 1) == ["p"])
        // The UI reads a snapshot even if an external actor changes the filesystem.
        try FileManager.default.removeItem(at: root.appendingPathComponent(job.id.uuidString))
        #expect(manager.preparedPackage(job.id) != nil)
        #expect(manager.availability.hasDownloadedPage(bookID: "test-book", version: 1, pageID: "p"))
        let restarted = PresetDownloadManager(directory: root)
        await restarted.waitUntilRestored()
        #expect(restarted.preparedPackage(job.id) == nil)
        #expect(restarted.jobs.first?.status == "paused")
        #expect(restarted.availability.downloadedPageIDs(bookID: "test-book", version: 1).isEmpty)
    }

    @Test func preparingDownloadedPageNeedsNoNetworkEngine() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try fixture(root)
        let manager = PresetDownloadManager(directory: root)
        let book = RemotePresetBook(id: "test-book", title: "Test", series: "test", version: 1,
                                    page_count: 1, cover_url: "https://example.test/thumb")
        // prepareImport must await restoration and return before attempting any HTTP request.
        let prepared = try await manager.prepareImport(book: book, pageIDs: ["p"],
                                                       wholeBook: false, ownerID: "owner")
        #expect(prepared.downloadID == nil)
        #expect(prepared.package.manifest.templateBookID == book.id)
        #expect(prepared.package.manifest.pages.map(\.id) == ["p"])
    }

    @Test func unrelatedJobsDoNotNotifySheetOrCatalog() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let job = try fixture(root, status: "paused")
        let manager = PresetDownloadManager(directory: root)
        await manager.waitUntilRestored()
        let observation = PresetDownloadObservation()
        observation.bind(UUID(), manager: manager)
        var sheetEvents = 0, catalogEvents = 0
        let a = observation.$job.dropFirst().sink { _ in sheetEvents += 1 }
        let b = manager.availability.$pages.dropFirst().sink { _ in catalogEvents += 1 }
        manager.cancel(job.id)
        #expect(sheetEvents == 0)
        #expect(catalogEvents == 0)
        withExtendedLifetime((a, b)) {}
        // Allow the immediate save to be submitted before removing the fixture.
        await Task.yield()
    }
    @Test func offlinePinAndReaderLeaseProtectDownloadRemoval() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let job = try fixture(root)
        let manager = PresetDownloadManager(directory: root)
        await manager.waitUntilRestored()
        manager.activate(owner: "owner")
        try manager.setPinned(true, id: job.id, ownerID: "owner")
        #expect(throws: DiaryEditorError.self) { try manager.removeDownloads([job.id], ownerID: "owner") }
        try manager.setPinned(false, id: job.id, ownerID: "owner")
        do {
            let lease = StorageActivity.shared.acquire(root.appendingPathComponent(job.id.uuidString))
            #expect(throws: StorageFailure.self) { try manager.removeDownloads([job.id], ownerID: "owner") }
            withExtendedLifetime(lease) {}
        }
        try manager.removeDownloads([job.id], ownerID: "owner")
        #expect(manager.jobs.isEmpty)
        #expect(manager.availability.pages.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(job.id.uuidString).path))
    }

}
