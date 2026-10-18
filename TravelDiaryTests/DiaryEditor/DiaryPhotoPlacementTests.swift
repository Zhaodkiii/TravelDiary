import Testing
import UIKit
@testable import TravelDiary

@MainActor
struct DiaryPhotoPlacementTests {
    @Test func bakedRotationIsDetectedAndPersistsAcrossReplacement() throws {
        let f = UIGraphicsImageRendererFormat(); f.scale = 1; f.opaque = false
        let image = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 240), format: f).image { renderer in
            let ctx = renderer.cgContext
            ctx.translateBy(x: 100, y: 120); ctx.rotate(by: 0.12)
            UIColor.red.setFill(); ctx.fill(CGRect(x: -70, y: -90, width: 140, height: 180))
        }
        let geometry = try #require(DiaryPhotoPlacementDetector.detect(image))
        #expect(abs(geometry.radians - 0.12) < 0.015)
        #expect(abs(geometry.center.x - 0.5) < 0.02)
        var document = DiaryDocument()
        let asset = DiaryAsset(id: UUID(), path: "assets/a.png", pixelSize: image.size)
        document.assets[asset.id] = asset
        let layer = DiaryLayer.photo(asset: asset, center: .zero)
        document.objects[document.rootContentID]?.layers.append(layer)
        document.replacePhoto(layer.id, with: asset, placement: geometry)
        document.replacePhoto(layer.id, with: asset)
        let reopened = try JSONDecoder().decode(DiaryDocument.self, from: JSONEncoder().encode(document))
        #expect(reopened.layer(layer.id)?.photoPlacement == geometry)
    }

    @Test func suppliedCafePhotoHasBakedRotation() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let path = root.appendingPathComponent("TravelDiaryTests/Fixtures/DiaryPresets.bundle/美食系列/上海手帐本/咖啡工坊的铜色空间.diarypreset/assets/443396d073a9d52c804027fc9f176331b88aed6ea3bdc8a383ffc40d69edce88.png")
        let image = try #require(UIImage(contentsOfFile: path.path))
        let placement = try #require(DiaryPhotoPlacementDetector.detect(image))
        #expect(abs(placement.radians) > 0.02)
    }
}
