import CoreGraphics
import UIKit

nonisolated enum DiaryStickerPlacement {
    struct Viewport { let rect: CGRect; let pointsPerUnit: CGFloat }
    struct Placement { let center: CGPoint; let size: CGSize }
    enum Material { case sticker, photo, text }
    static func plan(image: CGSize, canvas: CGSize, viewport: Viewport?, sequence: Int, material: Material = .sticker) -> Placement? {
        let full = CGRect(origin: .zero, size: canvas)
        let visible = viewport?.rect.intersection(full) ?? full
        guard !visible.isNull, visible.width > 0, visible.height > 0 else { return nil }
        let isSpread = abs(canvas.width / canvas.height - 4370.0 / 3130.0) < 0.000001
        let pageWidth = isSpread ? canvas.width / 2 : canvas.width
        let sideX: CGFloat = isSpread && visible.midX > pageWidth ? pageWidth : 0
        let page = CGRect(x: sideX, y: 0, width: pageWidth, height: canvas.height)
        let unit = 1 / max(0.001, viewport?.pointsPerUnit ?? 1)
        let available = visible.intersection(page).insetBy(dx: viewport == nil ? 0 : 28 * unit, dy: viewport == nil ? 0 : 28 * unit)
        guard !available.isNull, available.width > 24 * unit, available.height > 24 * unit,
              image.width > 0, image.height > 0 else { return nil }
        let pageW: CGFloat = material == .photo ? 0.60 : (material == .text ? 0.65 : 0.30)
        let pageH: CGFloat = material == .photo ? 0.45 : (material == .text ? 0.20 : 0.25)
        let screenW: CGFloat = material == .photo ? 0.75 : (material == .text ? 0.80 : 0.45)
        let screenH: CGFloat = material == .photo ? 0.65 : (material == .text ? 0.25 : 0.40)
        let scale = min(pageWidth * pageW / image.width, canvas.height * pageH / image.height,
                        available.width * screenW / image.width, available.height * screenH / image.height)
        let size = CGSize(width: image.width * scale, height: image.height * scale)
        let offsets: [CGPoint] = [.zero, CGPoint(x: 1,y: 1), CGPoint(x: -1,y: 1), CGPoint(x: 1,y: -1), CGPoint(x: -1,y: -1)]
        let delta = offsets[sequence % offsets.count]
        let center = CGPoint(x: min(available.maxX-size.width/2, max(available.minX+size.width/2, available.midX+delta.x*16*unit)),
                             y: min(available.maxY-size.height/2, max(available.minY+size.height/2, available.midY+delta.y*16*unit)))
        return Placement(center: center, size: size)
    }
}

extension DiaryStickerPlacement {
    @MainActor static func trimmed(_ image: UIImage) -> UIImage {
        let factor = min(1, 512 / max(image.size.width, image.size.height))
        let width = max(1, Int(image.size.width * factor)), height = max(1, Int(image.size.height * factor))
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        var minX = width, minY = height, maxX = -1, maxY = -1
        bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            UIGraphicsPushContext(context)
            context.translateBy(x: 0, y: CGFloat(height)); context.scaleBy(x: 1, y: -1)
            image.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
            UIGraphicsPopContext()
            let pixels = buffer.bindMemory(to: UInt8.self)
            for y in 0..<height { for x in 0..<width where pixels[(y*width+x)*4+3] > 4 {
                minX = min(minX,x); maxX = max(maxX,x); minY = min(minY,y); maxY = max(maxY,y)
            } }
        }
        guard maxX >= minX, maxY >= minY else { return image }
        // 低分辨率检测只定位边缘；输出仍从原图绘制并保留少量抗锯齿余量。
        let left = max(0, minX - 2)
        let top = max(0, minY - 2)
        let right = min(width - 1, maxX + 2)
        let bottom = min(height - 1, maxY + 2)
        let xUnit = image.size.width / CGFloat(width)
        let yUnit = image.size.height / CGFloat(height)
        let rect = CGRect(x: CGFloat(left) * xUnit, y: CGFloat(top) * yUnit,
                          width: CGFloat(right - left + 1) * xUnit,
                          height: CGFloat(bottom - top + 1) * yUnit)
        let format = UIGraphicsImageRendererFormat(); format.scale = image.scale
        return UIGraphicsImageRenderer(size: rect.size, format: format).image { _ in
            image.draw(at: CGPoint(x: -rect.minX, y: -rect.minY))
        }
    }
}
