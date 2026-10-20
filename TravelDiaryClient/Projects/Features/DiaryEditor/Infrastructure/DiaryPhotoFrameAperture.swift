import UIKit

/// 从相框的封闭透明内孔恢复照片区域，外部透明背景和装饰孔洞不能成为照片蒙版。
/// 仅依赖已随作品保存的相框素材，旧作品重新打开时也能恢复；每个解码版本只识别一次。
@MainActor enum DiaryPhotoFrameAperture {
    final class Aperture {
        let source: UIImage
        let mask: UIImage
        let slot: DiaryPhotoSlot
        init(source: UIImage, mask: UIImage, slot: DiaryPhotoSlot) {
            self.source = source; self.mask = mask; self.slot = slot
        }
    }
    private static let cache: NSCache<NSString, Aperture> = {
        let value = NSCache<NSString, Aperture>(); value.totalCostLimit = 24*1024*1024; return value
    }()

    static func detect(_ image: UIImage, opening: CGRect) -> Aperture? {
        guard image.size.width > 0, image.size.height > 0, opening.width > 0, opening.height > 0 else { return nil }
        let key = "\(ObjectIdentifier(image))-\(opening)" as NSString
        if let value = cache.object(forKey: key) { return value }
        let scale = min(1, 1024/max(image.size.width, image.size.height))
        let w = max(1, Int(image.size.width*scale)), h = max(1, Int(image.size.height*scale))
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
        let cx = min(w-1, max(0, Int(opening.midX*CGFloat(w))))
        let cy = min(h-1, max(0, Int(opening.midY*CGFloat(h))))
        // 内孔中心若恰好有一小块装饰，仍可在中心附近找到透明种子。
        var seed: Int?
        let radius = max(2, Int(min(opening.width*CGFloat(w), opening.height*CGFloat(h))*0.12))
        for r in 0...radius {
            for y in max(0,cy-r)...min(h-1,cy+r) {
                for x in max(0,cx-r)...min(w-1,cx+r) where max(abs(x-cx), abs(y-cy)) == r {
                    if bytes[(y*w+x)*4+3] < 128 { seed = y*w+x; break }
                }
                if seed != nil { break }
            }
            if seed != nil { break }
        }
        guard let seed else { return nil }
        var inside = [UInt8](repeating: 0, count: w*h)
        var queue = [seed], cursor = 0
        inside[seed] = 255
        var touchesEdge = false
        while cursor < queue.count {
            let index = queue[cursor]; cursor += 1
            let x = index%w, y = index/w
            if x == 0 || y == 0 || x == w-1 || y == h-1 { touchesEdge = true }
            for next in [x > 0 ? index-1 : -1, x+1 < w ? index+1 : -1,
                         y > 0 ? index-w : -1, y+1 < h ? index+w : -1] where next >= 0 {
                if inside[next] == 0 && bytes[next*4+3] < 128 {
                    inside[next] = 255; queue.append(next)
                }
            }
        }
        let expected = opening.width*CGFloat(w)*opening.height*CGFloat(h)
        guard !touchesEdge, CGFloat(queue.count) > expected*0.40 else { return nil }
        // 向不透明框边下方压入两个像素，避免抗锯齿和缩略图采样在接缝处露底。
        var maskBytes = [UInt8](repeating: 0, count: w*h*4)
        for index in queue {
            let x = index%w, y = index/w
            if x > 0 && x+1 < w && y > 0 && y+1 < h && inside[index-1] > 0 && inside[index+1] > 0 && inside[index-w] > 0 && inside[index+w] > 0 {
                let offset = index*4
                maskBytes[offset] = 255; maskBytes[offset+1] = 255
                maskBytes[offset+2] = 255; maskBytes[offset+3] = 255
                continue
            }
            for yy in max(0,y-2)...min(h-1,y+2) {
                for xx in max(0,x-2)...min(w-1,x+2) {
                    let offset = (yy*w+xx)*4
                    maskBytes[offset] = 255; maskBytes[offset+1] = 255
                    maskBytes[offset+2] = 255; maskBytes[offset+3] = 255
                }
            }
        }
        guard let provider = CGDataProvider(data: Data(maskBytes) as CFData),
              let cg = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w*4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return nil }
        let mask = UIImage(cgImage: cg)
        // 四角决定取景和透视，精细边缘由蒙版裁剪。识别失败时保守覆盖内孔包围框。
        let slot: DiaryPhotoSlot
        if let detected = DiaryPhotoSlotDetector.detect(mask, maskAssetID: UUID()) {
            slot = DiaryPhotoSlot(corners: detected.corners, maskAssetID: nil)
        } else {
            let xs = queue.map { $0%w }, ys = queue.map { $0/w }
            let left = CGFloat(max(0,xs.min()!-3))/CGFloat(w), right = CGFloat(min(w,xs.max()!+4))/CGFloat(w)
            let top = CGFloat(max(0,ys.min()!-3))/CGFloat(h), bottom = CGFloat(min(h,ys.max()!+4))/CGFloat(h)
            slot = DiaryPhotoSlot(corners: [CGPoint(x: left,y: top), CGPoint(x: right,y: top),
                CGPoint(x: right,y: bottom), CGPoint(x: left,y: bottom)], maskAssetID: nil)
        }
        let value = Aperture(source: image, mask: mask, slot: slot)
        cache.setObject(value, forKey: key, cost: w*h*8 + (image.cgImage.map { $0.bytesPerRow*$0.height } ?? 0))
        return value
    }
}
