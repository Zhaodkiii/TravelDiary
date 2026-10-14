import UIKit

/// 矩形粗筛 + 图层自身 Alpha 精确命中。透明洞继续穿透到当前编辑层级的下一层。
/// 对象掩码包含内部可见图层和笔画，但命中返回的仍是对象本身，不跨级选择子层。
@MainActor
enum DiaryLayerHitTester {
    private final class Mask {
        let bytes: [UInt8]
        let width: Int
        let height: Int
        init(bytes: [UInt8], width: Int, height: Int) {
            self.bytes = bytes; self.width = width; self.height = height
        }
    }
    private static let cache: NSCache<NSString, Mask> = {
        let value = NSCache<NSString, Mask>()
        value.totalCostLimit = 24 * 1024 * 1024
        return value
    }()
    /// 排除几乎不可见的阴影/抗锯齿像素，保留正常半透明素材。
    private static let alphaThreshold: UInt8 = 10

    static func contains(_ point: CGPoint, layer: DiaryLayer, document: DiaryDocument,
                         siblings: [DiaryLayer], images: [UUID: UIImage]) -> Bool {
        let rect = DiaryPageRenderer.bounds(layer, document: document, siblings: siblings)
        guard rect.width > 0, rect.height > 0, rect.contains(point) else { return false }
        let fingerprint = DiaryPageRenderer.hitFingerprint(layer, document: document, siblings: siblings, images: images)
        let key = "\(document.id)-\(layer.id)-\(fingerprint)-\(rect)" as NSString
        let mask: Mask
        if let cached = cache.object(forKey: key) { mask = cached }
        else {
            guard let generated = makeMask(layer, rect: rect, document: document, siblings: siblings, images: images) else {
                // 无法分配掩码时不以整个矩形拦住下层；仍可通过图层列表选择。
                return false
            }
            mask = generated
            cache.setObject(mask, forKey: key, cost: mask.bytes.count)
        }
        let x = min(mask.width - 1, max(0, Int((point.x - rect.minX) / rect.width * CGFloat(mask.width))))
        let y = min(mask.height - 1, max(0, Int((point.y - rect.minY) / rect.height * CGFloat(mask.height))))
        return mask.bytes[y * mask.width + x] >= alphaThreshold
    }

    private static func makeMask(_ layer: DiaryLayer, rect: CGRect, document: DiaryDocument,
                                 siblings: [DiaryLayer], images: [UUID: UIImage]) -> Mask? {
        // 单层最长边最多 2048，每个像素只缓存 1 字节 Alpha；拖动/缩放/旋转复用同一份。
        let scale = min(2, 2048 / max(rect.width, rect.height))
        let width = max(1, Int(ceil(rect.width * scale)))
        let height = max(1, Int(ceil(rect.height * scale)))
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let rendered = pixels.withUnsafeMutableBytes { storage -> Bool in
            guard let context = CGContext(data: storage.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            // 显式转为 UIKit 顶部原点，确保屏幕点击和缓冲区行索引方向一致。
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: CGFloat(width) / rect.width, y: -CGFloat(height) / rect.height)
            context.translateBy(x: -rect.minX, y: -rect.minY)
            context.clip(to: rect)
            UIGraphicsPushContext(context)
            DiaryPageRenderer.drawHitLayer(layer, document: document, siblings: siblings, images: images, in: context)
            UIGraphicsPopContext()
            return true
        }
        guard rendered else { return nil }
        let alpha = stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] }
        return Mask(bytes: alpha, width: width, height: height)
    }
}
