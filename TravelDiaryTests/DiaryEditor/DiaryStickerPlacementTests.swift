import Testing
import CoreGraphics
@testable import TravelDiary

struct DiaryStickerPlacementTests {
    @Test func placesInsideVisibleRightPageAndConstrainsSize() throws {
        let visible = CGRect(x: 2400, y: 300, width: 1000, height: 1400)
        let result = try #require(DiaryStickerPlacement.plan(image: CGSize(width: 800, height: 800), canvas: CGSize(width: 4370, height: 3130), viewport: .init(rect: visible, pointsPerUnit: 0.3), sequence: 0))
        #expect(result.center.x > 2185)
        #expect(result.size.width <= 2185 * 0.3)
        let bounds = CGRect(x: result.center.x-result.size.width/2, y: result.center.y-result.size.height/2, width: result.size.width, height: result.size.height)
        #expect(visible.contains(bounds))
    }
    @Test func rejectsTooSmallVisibleArea() {
        #expect(DiaryStickerPlacement.plan(image: CGSize(width: 100,height: 100), canvas: CGSize(width: 2185,height: 3130), viewport: .init(rect: CGRect(x: 0,y: 0,width: 30,height: 30), pointsPerUnit: 1), sequence: 0) == nil)
    }
    @Test func photosAreLargerThanStickersAndTextRemainsVisible() throws {
        let canvas = CGSize(width: 4370, height: 3130)
        let viewport = DiaryStickerPlacement.Viewport(rect: CGRect(x: 0, y: 100, width: 1800, height: 2000), pointsPerUnit: 0.25)
        let image = CGSize(width: 800, height: 600)
        let sticker = try #require(DiaryStickerPlacement.plan(image: image, canvas: canvas, viewport: viewport, sequence: 0))
        let photo = try #require(DiaryStickerPlacement.plan(image: image, canvas: canvas, viewport: viewport, sequence: 0, material: .photo))
        #expect(photo.size.width > sticker.size.width)
        #expect(photo.size.height > sticker.size.height)
        let text = try #require(DiaryStickerPlacement.plan(image: CGSize(width: 650, height: 120), canvas: canvas, viewport: viewport, sequence: 0, material: .text))
        #expect(text.center.x < canvas.width / 2)
        #expect(text.size.width <= viewport.rect.width * 0.8)
    }
}
