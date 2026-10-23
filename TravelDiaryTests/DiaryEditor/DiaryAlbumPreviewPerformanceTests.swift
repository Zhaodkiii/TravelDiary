import Testing
import UIKit
@testable import TravelDiary

@Suite(.serialized) @MainActor
struct DiaryAlbumPreviewPerformanceTests {
    private func fixture() throws -> (URL, DiaryAlbumDraft) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 800)).image { ctx in
            UIColor.systemGreen.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 1200, height: 800))
        }
        try #require(image.jpegData(compressionQuality: 0.9)).write(to: folder.appendingPathComponent("source.image"))
        var draft = DiaryAlbumDraft()
        draft.photos = [DiaryAlbumPhoto(filename: "source.image", pixelSize: CGSize(width: 1200, height: 800), selectionOrder: 0, fingerprint: "test")]
        draft.generate()
        return (folder, draft)
    }
    @Test func repeatedAndConcurrentPageRequestsRenderOnce() async throws {
        let (folder, draft) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let service = DiaryAlbumPreviewService()
        let request = DiaryAlbumPreviewRequest(page: draft.pages[1], draft: draft, directory: folder)
        let first = Task { try await service.image(request) }
        let second = Task { try await service.image(request) }
        let a = try await first.value, b = try await second.value
        let cached = try await service.image(request)
        #expect(a === b && b === cached)
        #expect(service.renderCount == 1)
        #expect(a.cgImage?.width == 384)
        print("ALBUM_PREVIEW_RENDER_MS=\(service.totalRenderMilliseconds)")
        var changed = draft; changed.pages[1].caption = "新增文字"
        _ = try await service.image(DiaryAlbumPreviewRequest(page: changed.pages[1], draft: changed, directory: folder))
        #expect(service.renderCount == 2)
        #expect(try await service.image(request) === cached)
    }
    @Test func thumbnailRequestsCoalesceAndRespectSmallSize() async throws {
        let (folder, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("source.image")
        let before = DiaryAlbumThumbnailLoader.decodeCount
        let a = Task { await DiaryAlbumThumbnailLoader.load(url, maximumDimension: 128) }
        let b = Task { await DiaryAlbumThumbnailLoader.load(url, maximumDimension: 128) }
        let first = try #require(await a.value), second = try #require(await b.value)
        #expect(first === second)
        #expect(max(first.cgImage?.width ?? 0, first.cgImage?.height ?? 0) <= 128)
        #expect(DiaryAlbumThumbnailLoader.decodeCount - before == 1)
    }
    @Test func scrollingDefersCompositionAndOffscreenCancellationStopsWork() async throws {
        let (folder, draft) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let service = DiaryAlbumPreviewService(); service.scrolling = true
        let request = DiaryAlbumPreviewRequest(page: draft.pages[1], draft: draft, directory: folder)
        let work = Task { try await service.image(request) }
        try await Task.sleep(for: .milliseconds(120))
        #expect(service.renderCount == 0)
        work.cancel()
        await #expect(throws: CancellationError.self) { try await work.value }
        #expect(service.renderCount == 0)
        service.scrolling = false
        _ = try await service.image(request)
        #expect(service.renderCount == 1)
    }
    @Test func unrelatedPageChangesDoNotInvalidateVisiblePage() throws {
        let (folder, draft) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let before = DiaryAlbumPreviewRequest(page: draft.pages[1], draft: draft, directory: folder)
        var changed = draft; changed.pages[0].title = "修改封面"
        changed.photos.append(DiaryAlbumPhoto(filename: "other.image", pixelSize: CGSize(width: 900, height: 600), selectionOrder: 1, fingerprint: "other"))
        let after = DiaryAlbumPreviewRequest(page: changed.pages[1], draft: changed, directory: folder)
        #expect(before == after)
    }
}
