import UIKit
import CoreImage

/// UIKit coordinates are top-down; Core Image vectors use bottom-up coordinates.
@MainActor
enum DiaryWarpRenderer {
    private static let context = CIContext(options: [.cacheIntermediates: false])
    static func draw(_ image: UIImage, rect: CGRect, warp: DiaryQuadWarp?, in cg: CGContext) {
        guard let warp else { image.draw(in: rect); return }
        guard let source = image.cgImage, warp.isValid, rect.width > 0, rect.height > 0 else { return }
        let sx=CGFloat(source.width)/rect.width, sy=CGFloat(source.height)/rect.height
        let map=warp.projection
        let corners=rect.diaryCorners.map(map.point)
        guard corners.allSatisfy({ $0.x.isFinite && $0.y.isFinite && abs($0.x) < 1e7 && abs($0.y) < 1e7 }) else { return }
        func vector(_ p: CGPoint) -> CIVector { CIVector(x: (p.x-rect.minX)*sx, y: (rect.maxY-p.y)*sy) }
        let output=CIImage(cgImage: source).applyingFilter("CIPerspectiveTransform", parameters: [
            "inputTopLeft": vector(corners[0]), "inputTopRight": vector(corners[1]),
            "inputBottomRight": vector(corners[2]), "inputBottomLeft": vector(corners[3])])
        let extent=output.extent.integral
        guard extent.width.isFinite, extent.height.isFinite, extent.width > 0, extent.height > 0,
              extent.width*extent.height <= 64*1024*1024,
              let result=context.createCGImage(output, from: extent) else { return }
        let target=CGRect(x: rect.minX+extent.minX/sx, y: rect.maxY-extent.maxY/sy,
                          width: extent.width/sx, height: extent.height/sy)
        UIImage(cgImage: result).draw(in: target)
    }
}
