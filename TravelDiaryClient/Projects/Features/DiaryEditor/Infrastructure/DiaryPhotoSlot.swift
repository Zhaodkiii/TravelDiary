import UIKit
import CoreImage

/// 独立于当前照片的槽位。四角按左上、右上、右下、左下排列，使用素材框的归一化坐标。
/// 蒙版引用首次识别时的素材，仅使用其 alpha；后续换图不会重新识别或覆盖槽位。
nonisolated struct DiaryPhotoSlot: Codable, Equatable, Sendable {
    nonisolated enum Fill: String, Codable, CaseIterable, Sendable { case cover, stretch }
    var corners: [CGPoint]
    var maskAssetID: UUID?
    var fill: Fill = .cover

    var isValid: Bool {
        guard corners.count == 4, corners.allSatisfy({ $0.x.isFinite && $0.y.isFinite && (-1...2).contains($0.x) && (-1...2).contains($0.y) }) else { return false }
        return corners.indices.allSatisfy { i in
            Self.cross(corners[i], corners[(i+1)%4], corners[(i+2)%4]) > 0.00001
        }
    }
    static func rectangle(_ placement: DiaryPhotoPlacement, size: CGSize, maskAssetID: UUID?) -> DiaryPhotoSlot {
        let c = cos(placement.radians), s = sin(placement.radians)
        let points = [CGPoint(x: -0.5, y: -0.5), CGPoint(x: 0.5, y: -0.5),
                      CGPoint(x: 0.5, y: 0.5), CGPoint(x: -0.5, y: 0.5)].map { p in
            let x = p.x*placement.size.width*size.width, y = p.y*placement.size.height*size.height
            return CGPoint(x: placement.center.x+(x*c-y*s)/size.width,
                           y: placement.center.y+(x*s+y*c)/size.height)
        }
        return DiaryPhotoSlot(corners: points, maskAssetID: maskAssetID)
    }

    static func cross(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> CGFloat {
        (b.x-a.x)*(c.y-a.y) - (b.y-a.y)*(c.x-a.x)
    }
}

nonisolated enum DiaryPhotoSlotDetector {
    /// 仅接受接近实心四边形的透明照片，拒绝人物抠图、圆形和不透明照片。
    static func detect(_ image: UIImage, maskAssetID: UUID) -> DiaryPhotoSlot? {
        let ratio = min(1, 768 / max(image.size.width, image.size.height))
        let w = max(1, Int(image.size.width * ratio)), h = max(1, Int(image.size.height * ratio))
        var bytes = [UInt8](repeating: 0, count: w*h*4)
        let success = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                bytesPerRow: w*4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: 1, y: -1)
            UIGraphicsPushContext(ctx); image.draw(in: CGRect(x: 0, y: 0, width: w, height: h)); UIGraphicsPopContext()
            return true
        }
        guard success else { return nil }
        var points: [CGPoint] = [], count = 0
        for y in 0..<h {
            var left: Int?, right: Int?
            for x in 0..<w where bytes[(y*w+x)*4+3] >= 128 {
                if left == nil { left = x }; right = x; count += 1
            }
            if let left, let right {
                points += [CGPoint(x: left, y: y), CGPoint(x: right+1, y: y),
                           CGPoint(x: left, y: y+1), CGPoint(x: right+1, y: y+1)]
            }
        }
        guard count > w*h/10, count < w*h*99/100 else { return nil }
        points.sort { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
        func half(_ values: [CGPoint]) -> [CGPoint] {
            var hull: [CGPoint] = []
            for p in values {
                while hull.count >= 2 && DiaryPhotoSlot.cross(hull[hull.count-2], hull[hull.count-1], p) <= 0 { hull.removeLast() }
                hull.append(p)
            }
            return hull
        }
        let hull = Array(half(points).dropLast()) + Array(half(points.reversed()).dropLast())
        guard hull.count >= 4 else { return nil }
        func area(_ polygon: [CGPoint]) -> CGFloat {
            abs(polygon.indices.reduce(CGFloat.zero) { result, i in
                let a = polygon[i], b = polygon[(i+1)%polygon.count]
                return result + a.x*b.y-b.x*a.y
            }) / 2
        }
        var quad = hull
        while quad.count > 4 {
            let index = quad.indices.min { a, b in
                abs(DiaryPhotoSlot.cross(quad[(a+quad.count-1)%quad.count], quad[a], quad[(a+1)%quad.count])) <
                abs(DiaryPhotoSlot.cross(quad[(b+quad.count-1)%quad.count], quad[b], quad[(b+1)%quad.count]))
            }!
            quad.remove(at: index)
        }
        let hullArea = area(hull), quadArea = area(quad)
        guard CGFloat(count)/hullArea > 0.94, quadArea/hullArea > 0.90 else { return nil }
        // 最靠近左上方的顶点作为起点，保持照片横轴方向。
        let first = quad.indices.min { quad[$0].x/CGFloat(w)+quad[$0].y/CGFloat(h) < quad[$1].x/CGFloat(w)+quad[$1].y/CGFloat(h) }!
        quad = (0..<4).map { quad[(first+$0)%4] }
        // 将拟合四边形扩到覆盖轻微弯曲边缘；最终可见范围由原始 alpha 精确裁剪。
        let center = quad.reduce(CGPoint.zero) { CGPoint(x: $0.x+$1.x/4, y: $0.y+$1.y/4) }
        var expansion: CGFloat = 1
        for i in 0..<4 {
            let a = quad[i], b = quad[(i+1)%4]
            let denominator = DiaryPhotoSlot.cross(a, b, center)
            guard denominator > 0 else { return nil }
            for p in hull { expansion = max(expansion, 1 - DiaryPhotoSlot.cross(a, b, p)/denominator) }
        }
        guard expansion < 1.12 else { return nil }
        let corners = quad.map { CGPoint(x: (center.x+($0.x-center.x)*expansion)/CGFloat(w),
                                         y: (center.y+($0.y-center.y)*expansion)/CGFloat(h)) }
        let slot = DiaryPhotoSlot(corners: corners, maskAssetID: maskAssetID)
        return slot.isValid ? slot : nil
    }
}

/// 画布、命中、缩略图和导出统一调用，Core Image 只处理本地槽位，外部图层矩阵仍由页面渲染器负责。
@MainActor enum DiaryPhotoSlotRenderer {
    private static let context = CIContext(options: [.cacheIntermediates: false])
    private final class CachedImage {
        let source: UIImage
        let mask: UIImage?
        let result: UIImage
        init(source: UIImage, mask: UIImage?, result: UIImage) {
            self.source = source; self.mask = mask; self.result = result
        }
    }
    private static let cache: NSCache<NSString, CachedImage> = {
        let value = NSCache<NSString, CachedImage>(); value.totalCostLimit = 32*1024*1024; return value
    }()

    static func image(_ source: UIImage, mask: UIImage?, slot: DiaryPhotoSlot, size: CGSize, crop: DiaryCrop, pixelScale: CGFloat = 1) -> UIImage? {
        guard slot.isValid, size.width > 0, size.height > 0, slot.maskAssetID == nil || mask != nil else { return nil }
        var hash = Hasher()
        hash.combine(ObjectIdentifier(source)); hash.combine(mask.map(ObjectIdentifier.init))
        hash.combine(try? JSONEncoder().encode(slot)); hash.combine(try? JSONEncoder().encode(crop))
        hash.combine(size.width); hash.combine(size.height); hash.combine(pixelScale)
        let key = String(hash.finalize()) as NSString
        if let image = cache.object(forKey: key) { return image.result }
        let edge = min(4096, max(max(source.size.width, source.size.height), max(mask?.size.width ?? 0, mask?.size.height ?? 0)))
        let scale = min(max(0.1, pixelScale), edge / max(size.width, size.height))
        let outputSize = CGSize(width: max(1, ceil(size.width*scale)), height: max(1, ceil(size.height*scale)))
        let corners = slot.corners.map { CGPoint(x: $0.x*outputSize.width, y: $0.y*outputSize.height) }
        func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x-b.x, a.y-b.y) }
        let rectSize = CGSize(width: max(1, (distance(corners[0], corners[1])+distance(corners[3], corners[2]))/2),
                              height: max(1, (distance(corners[0], corners[3])+distance(corners[1], corners[2]))/2))
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = false
        let prepared = UIGraphicsImageRenderer(size: rectSize, format: format).image { _ in
            source.draw(in: slot.fill == .stretch ? CGRect(origin: .zero, size: rectSize) : crop.imageRect(source: source.size, frame: rectSize))
        }
        guard let input = CIImage(image: prepared) else { return nil }
        func vector(_ p: CGPoint) -> CIVector { CIVector(x: p.x, y: outputSize.height-p.y) }
        var output = input.applyingFilter("CIPerspectiveTransform", parameters: [
            "inputTopLeft": vector(corners[0]), "inputTopRight": vector(corners[1]),
            "inputBottomRight": vector(corners[2]), "inputBottomLeft": vector(corners[3])
        ])
        let bounds = CGRect(origin: .zero, size: outputSize)
        if let mask {
            let normalized = UIGraphicsImageRenderer(size: outputSize, format: format).image { _ in mask.draw(in: bounds) }
            guard let alpha = CIImage(image: normalized) else { return nil }
            output = output.applyingFilter("CIBlendWithAlphaMask", parameters: [
                kCIInputBackgroundImageKey: CIImage(color: .clear).cropped(to: bounds), kCIInputMaskImageKey: alpha
            ])
        }
        guard let cg = context.createCGImage(output, from: bounds) else { return nil }
        let image = UIImage(cgImage: cg)
        let cost = cg.bytesPerRow*cg.height + (source.cgImage.map { $0.bytesPerRow*$0.height } ?? 0)
            + (mask?.cgImage.map { $0.bytesPerRow*$0.height } ?? 0)
        cache.setObject(CachedImage(source: source, mask: mask, result: image), forKey: key, cost: cost)
        return image
    }
}
