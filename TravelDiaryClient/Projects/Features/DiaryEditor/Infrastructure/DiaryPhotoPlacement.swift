import UIKit

/// PSD 导出的照片可能已经把旋转烘焙在 PNG 内；以透明轮廓的最小包围矩形恢复内部摆放。
/// 参数相对于图片完整像素框归一化，外部图层变换仍独立保留。
nonisolated struct DiaryPhotoPlacement: Codable, Equatable, Sendable {
    var center: CGPoint
    var size: CGSize
    var radians: CGFloat
}

@MainActor
enum DiaryPhotoPlacementDetector {
    static func detect(_ image: UIImage) -> DiaryPhotoPlacement? {
        let scale = min(1, 512 / max(image.size.width, image.size.height))
        let w = max(1, Int(image.size.width * scale)), h = max(1, Int(image.size.height * scale))
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let success = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: 1, y: -1)
            UIGraphicsPushContext(ctx); image.draw(in: CGRect(x: 0, y: 0, width: w, height: h)); UIGraphicsPopContext()
            return true
        }
        guard success else { return nil }
        var points: [CGPoint] = []
        var count = 0
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
        func cross(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> CGFloat {
            (b.x-a.x)*(c.y-a.y)-(b.y-a.y)*(c.x-a.x)
        }
        func half(_ values: [CGPoint]) -> [CGPoint] {
            var hull: [CGPoint] = []
            for p in values {
                while hull.count >= 2 && cross(hull[hull.count-2], hull[hull.count-1], p) <= 0 { hull.removeLast() }
                hull.append(p)
            }
            return hull
        }
        let hull = Array(half(points).dropLast()) + Array(half(points.reversed()).dropLast())
        guard hull.count >= 3 else { return nil }
        var area = CGFloat.greatestFiniteMagnitude
        var best: DiaryPhotoPlacement?
        for i in hull.indices {
            let a = hull[i], b = hull[(i+1)%hull.count]
            var angle = atan2(b.y-a.y, b.x-a.x)
            // 选择最接近水平的边作为图片横轴，防止长边带来额外 90°旋转。
            while angle > .pi/4 { angle -= .pi/2 }
            while angle < -.pi/4 { angle += .pi/2 }
            let c = cos(angle), s = sin(angle)
            let xs = hull.map { $0.x*c+$0.y*s }, ys = hull.map { -$0.x*s+$0.y*c }
            let loX = xs.min()!, hiX = xs.max()!, loY = ys.min()!, hiY = ys.max()!
            let candidate = (hiX-loX)*(hiY-loY)
            if candidate < area {
                area = candidate
                let x = (loX+hiX)/2, y = (loY+hiY)/2
                best = DiaryPhotoPlacement(center: CGPoint(x: (x*c-y*s)/CGFloat(w), y: (x*s+y*c)/CGFloat(h)),
                    size: CGSize(width: (hiX-loX)/CGFloat(w), height: (hiY-loY)/CGFloat(h)), radians: angle)
            }
        }
        // 不把不规则贴纸/抠图人物误判成倾斜矩形；仅接受近似实心照片轮廓。
        guard CGFloat(count)/area > 0.90, let best, abs(best.radians) > .pi/360 else { return nil }
        return best
    }
}
