import Testing
import UIKit
@testable import TravelDiary

@MainActor
struct StickerImageProcessorTests {
    @Test func finishedStickerPreservesTransparentPaddingAndDoesNotClipBorder() throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let input = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 80), format: format).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 100, height: 80))
        }
        for style in ["原样", "白边", "彩边", "虚线"] {
            let output = StickerImageProcessor.render(input, style: style, color: .white, thickness: 3)
            #expect(output.size.width > input.size.width)
            #expect(output.size.height > input.size.height)
            let png = try #require(output.pngData())
            let cg = try #require(UIImage(data: png)?.cgImage)
            #expect(cg.alphaInfo != .none)
            var pixel = [UInt8](repeating: 0, count: 4)
            let context = try #require(CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
            #expect(pixel[3] == 0)
        }
    }
}
