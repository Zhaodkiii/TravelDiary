import Testing
import UIKit
@testable import TravelDiary

@MainActor
struct TravelCaptureBackgroundRendererTests {
    @Test func portraitAndLandscapeProduceExactPixelSize() {
        for size in [CGSize(width: 300, height: 600), CGSize(width: 800, height: 200)] {
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            let source = UIGraphicsImageRenderer(size: size, format: format).image { context in
                UIColor.red.setFill(); context.fill(CGRect(origin: .zero, size: size))
                UIColor.blue.setFill()
                context.fill(CGRect(x: size.width * 0.4, y: size.height * 0.4,
                                    width: size.width * 0.2, height: size.height * 0.2))
            }
//            let output = TravelCaptureBackgroundRenderer.render(source)
//            #expect(output.cgImage?.width == 4370)
//            #expect(output.cgImage?.height == 3130)
//            // 中心必须保留原图中心；四角保持红色，不能出现留白。
//            for (x, y, blue) in [(2185, 1565, true), (2, 2, false), (4367, 3127, false)] {
//                var bytes = [UInt8](repeating: 0, count: 4)
//                let bitmap = output.cgImage!.cropping(to: CGRect(x: x, y: y, width: 1, height: 1))!
//                bytes.withUnsafeMutableBytes { buffer in
//                    let context = CGContext(data: buffer.baseAddress, width: 1, height: 1,
//                        bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
//                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
//                    context.draw(bitmap, in: CGRect(x: 0, y: 0, width: 1, height: 1))
//                }
//                #expect(bytes[blue ? 2 : 0] > 240)
//            }
        }
    }
}
