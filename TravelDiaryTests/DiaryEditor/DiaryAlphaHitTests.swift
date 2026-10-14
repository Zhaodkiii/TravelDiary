import Testing
import UIKit
@testable import TravelDiary

@MainActor
struct DiaryAlphaHitTests {
    private func fixture(_ image: UIImage) -> (DiaryDocument, DiaryLayer, [UUID: UIImage]) {
        var document = DiaryDocument()
        let asset = DiaryAsset(id: UUID(), path: "assets/test.png", pixelSize: image.size)
        document.assets[asset.id] = asset
        let layer = DiaryLayer(name: "透明相框", kind: .sticker,
            transform: DiaryTransform(position: .zero, pivot: .zero), size: image.size, assetID: asset.id)
        return (document, layer, [asset.id: image])
    }

    @Test func transparentHoleAndTopOriginAndReplacement() {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = false
        let image = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100), format: format).image { _ in
            UIColor.red.setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: 100, height: 10))
        }
        let (document, layer, images) = fixture(image)
        func hit(_ p: CGPoint, _ images: [UUID: UIImage]) -> Bool {
            DiaryLayerHitTester.contains(p, layer: layer, document: document, siblings: [layer], images: images)
        }
        #expect(hit(CGPoint(x: 50, y: 5), images))
        #expect(!hit(CGPoint(x: 50, y: 95), images))
        #expect(!hit(CGPoint(x: 50, y: 50), images))
        let replacement = UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            UIColor.blue.setFill(); UIRectFill(CGRect(origin: .zero, size: image.size))
        }
        #expect(hit(CGPoint(x: 50, y: 50), [layer.assetID!: replacement]))
    }

    @Test func suppliedFramesHaveSelectablePixelsAndTransparentPixels() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let assets = root.appendingPathComponent("TravelDiaryClient/Projects/App/Resources/DiaryPresets.bundle/美食系列/上海手帐本/咖啡工坊的铜色空间.diarypreset/assets")
        for name in ["20a2b42edeac0c5b97d41ea9c15693ecc4a65eef08042ccbfffe4d30e95774ec", "443396d073a9d52c804027fc9f176331b88aed6ea3bdc8a383ffc40d69edce88"] {
            let image = try #require(UIImage(contentsOfFile: assets.appendingPathComponent(name + ".png").path))
            let (document, layer, images) = fixture(image)
            var selected = 0, transparent = 0
            for x in stride(from: 0.025, to: 1.0, by: 0.05) {
                for y in stride(from: 0.025, to: 1.0, by: 0.05) {
                    let hit = DiaryLayerHitTester.contains(CGPoint(x: image.size.width * x, y: image.size.height * y),
                        layer: layer, document: document, siblings: [layer], images: images)
                    if hit { selected += 1 } else { transparent += 1 }
                }
            }
            #expect(selected > 0); #expect(transparent > 0)
        }
    }
}
