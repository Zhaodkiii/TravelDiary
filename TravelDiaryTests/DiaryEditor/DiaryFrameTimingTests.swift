import Testing
import UIKit
@testable import TravelDiary

@MainActor struct DiaryFrameTimingTests {
    @Test func measureCurrentImportFrame() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DiaryDocumentStore(ownerID: "frame-timing", baseDirectory: root)
        for ratio in [4.0/3, 3.0/4, 16.0/9] {
            for run in 0..<6 {
                let start = CFAbsoluteTimeGetCurrent()
                let item = DiaryPhotoFrameCatalog.select(for: [CGSize(width: 4000, height: 4000/ratio)])[0]
                let image = try #require(item.image)
                let rendered = CFAbsoluteTimeGetCurrent()
                let aperture = DiaryPhotoFrameAperture.detect(image, opening: item.opening)
                #expect(aperture != nil)
                let detected = CFAbsoluteTimeGetCurrent()
                let bytes = try #require(image.pngData())
                let encoded = CFAbsoluteTimeGetCurrent()
                let (asset, decoded) = try await store.importImage(bytes, documentID: UUID())
                let end = CFAbsoluteTimeGetCurrent()
                let bound = DiaryEditorSession.photoFrame(item, asset: asset, photo: DiaryLayer.photo(asset: asset, center: .zero))
                let boundAt = CFAbsoluteTimeGetCurrent()
                #expect(DiaryPhotoFrameAperture.detect(decoded, opening: item.opening) != nil)
                let decodedAt = CFAbsoluteTimeGetCurrent()
                #expect(DiaryPhotoFrameAperture.detect(decoded, opening: item.opening) != nil)
                let cachedAt = CFAbsoluteTimeGetCurrent()
                print(String(format: "FRAME_EXTRA ratio=%.3f run=%d bind=%.2f decodedDetect=%.2f cachedDetect=%.2f totalThroughFirstUse=%.2f ms", ratio, run, (boundAt-end)*1000, (decodedAt-boundAt)*1000, (cachedAt-decodedAt)*1000, (decodedAt-start)*1000))
                #expect(bound.frameTargetID != nil)
                print(String(format: "FRAME_TIMING ratio=%.3f run=%d pixels=%.0fx%.0f render=%.2f detect=%.2f png=%.2f import=%.2f total=%.2f ms bytes=%d", ratio, run, image.size.width, image.size.height, (rendered-start)*1000, (detected-rendered)*1000, (encoded-detected)*1000, (end-encoded)*1000, (end-start)*1000, bytes.count))
            }
        }
    }
}
