import Foundation
import CoreGraphics
import QuartzCore

/// Normalized corners in a stable local reference rectangle. Nil warp preserves old documents.
nonisolated struct DiaryQuadWarp: Codable, Equatable, Sendable {
    var reference: CGRect
    var topLeft = CGPoint(x: 0, y: 0)
    var topRight = CGPoint(x: 1, y: 0)
    var bottomRight = CGPoint(x: 1, y: 1)
    var bottomLeft = CGPoint(x: 0, y: 1)
    var corners: [CGPoint] {
        get { [topLeft, topRight, bottomRight, bottomLeft] }
        set { guard newValue.count == 4 else { return }; topLeft = newValue[0]; topRight = newValue[1]; bottomRight = newValue[2]; bottomLeft = newValue[3] }
    }
    var isValid: Bool {
        guard [reference.minX, reference.minY, reference.width, reference.height].allSatisfy(\.isFinite),
              reference.width > 0, reference.height > 0,
              corners.allSatisfy({ $0.x.isFinite && $0.y.isFinite && abs($0.x) <= 16 && abs($0.y) <= 16 }) else { return false }
        let p = corners
        for i in 0..<4 {
            let a = p[i], b = p[(i + 1) % 4], c = p[(i + 2) % 4]
            guard (b.x-a.x)*(c.y-b.y) - (b.y-a.y)*(c.x-b.x) > 0.0004 else { return false }
        }
        let map = projection
        let weights = reference.diaryCorners.map { map.g*$0.x + map.h*$0.y + map.i }
        return weights.allSatisfy { $0.isFinite && $0 > 0.00001 }
    }
    var projection: DiaryProjection {
        let p = corners
        let dx1 = p[1].x-p[2].x, dx2 = p[3].x-p[2].x
        let dy1 = p[1].y-p[2].y, dy2 = p[3].y-p[2].y
        let sx = p[0].x-p[1].x+p[2].x-p[3].x, sy = p[0].y-p[1].y+p[2].y-p[3].y
        let det = dx1*dy2-dx2*dy1
        let g = abs(det) > 1e-10 ? (sx*dy2-dx2*sy)/det : 0
        let h = abs(det) > 1e-10 ? (dx1*sy-sx*dy1)/det : 0
        let unit = DiaryProjection(a: p[1].x-p[0].x+g*p[1].x, b: p[1].y-p[0].y+g*p[1].y,
            c: p[3].x-p[0].x+h*p[3].x, d: p[3].y-p[0].y+h*p[3].y,
            tx: p[0].x, ty: p[0].y, g: g, h: h)
        let normalize = DiaryProjection(CGAffineTransform(a: 1/reference.width, b: 0, c: 0, d: 1/reference.height,
            tx: -reference.minX/reference.width, ty: -reference.minY/reference.height))
        let denormalize = DiaryProjection(CGAffineTransform(a: reference.width, b: 0, c: 0, d: reference.height,
            tx: reference.minX, ty: reference.minY))
        return denormalize.multiplied(by: unit).multiplied(by: normalize)
    }
}

/// Homogeneous 3x3 mapping shared by drawing, hit testing and bounds.
nonisolated struct DiaryProjection: Equatable, Sendable {
    var a: CGFloat = 1, b: CGFloat = 0, c: CGFloat = 0, d: CGFloat = 1
    var tx: CGFloat = 0, ty: CGFloat = 0, g: CGFloat = 0, h: CGFloat = 0, i: CGFloat = 1
    init(a: CGFloat = 1, b: CGFloat = 0, c: CGFloat = 0, d: CGFloat = 1,
         tx: CGFloat = 0, ty: CGFloat = 0, g: CGFloat = 0, h: CGFloat = 0, i: CGFloat = 1) {
        self.a=a; self.b=b; self.c=c; self.d=d; self.tx=tx; self.ty=ty; self.g=g; self.h=h; self.i=i
    }
    init(_ m: CGAffineTransform) { a=m.a; b=m.b; c=m.c; d=m.d; tx=m.tx; ty=m.ty }
    func point(_ p: CGPoint) -> CGPoint {
        let w = g*p.x+h*p.y+i
        guard abs(w) > 1e-10 else { return CGPoint(x: CGFloat.greatestFiniteMagnitude, y: CGFloat.greatestFiniteMagnitude) }
        return CGPoint(x: (a*p.x+c*p.y+tx)/w, y: (b*p.x+d*p.y+ty)/w)
    }
    func multiplied(by r: Self) -> Self {
        Self(a: a*r.a+c*r.b+tx*r.g, b: b*r.a+d*r.b+ty*r.g,
             c: a*r.c+c*r.d+tx*r.h, d: b*r.c+d*r.d+ty*r.h,
             tx: a*r.tx+c*r.ty+tx*r.i, ty: b*r.tx+d*r.ty+ty*r.i,
             g: g*r.a+h*r.b+i*r.g, h: g*r.c+h*r.d+i*r.h, i: g*r.tx+h*r.ty+i*r.i)
    }
    var inverse: Self {
        // Adjugate is sufficient for homogeneous coordinates (common scale cancels).
        Self(a: d*i-ty*h, b: ty*g-b*i, c: tx*h-c*i, d: a*i-tx*g,
             tx: c*ty-tx*d, ty: tx*b-a*ty, g: b*h-d*g, h: c*g-a*h, i: a*d-c*b)
    }
    func bounds(_ rect: CGRect) -> CGRect {
        let p = rect.diaryCorners.map(point)
        guard p.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return .zero }
        let xs=p.map(\.x), ys=p.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()!-xs.min()!, height: ys.max()!-ys.min()!)
    }
    var layerTransform: CATransform3D {
        var m = CATransform3DIdentity
        m.m11=a; m.m12=b; m.m14=g; m.m21=c; m.m22=d; m.m24=h
        m.m41=tx; m.m42=ty; m.m44=i
        return m
    }
}

extension DiaryTransform {
    nonisolated var projection: DiaryProjection {
        DiaryProjection(matrix).multiplied(by: warp?.projection ?? DiaryProjection())
    }
}

extension CGRect {
    nonisolated var diaryCorners: [CGPoint] {
        [CGPoint(x: minX,y: minY), CGPoint(x: maxX,y: minY), CGPoint(x: maxX,y: maxY), CGPoint(x: minX,y: maxY)]
    }
}

nonisolated enum DiaryTransformMode: String, CaseIterable, Identifiable {
    case free, skew, perspective, stretch
    var id: Self { self }
    var title: String { switch self { case .free: "自由"; case .skew: "斜切"; case .perspective: "透视"; case .stretch: "拉伸" } }
    var symbol: String { switch self { case .free: "viewfinder"; case .skew: "skew"; case .perspective: "trapezoid.and.line.vertical"; case .stretch: "arrow.up.left.and.arrow.down.right" } }

    /// Handles 0...3 are corners; 4...7 are the top/right/bottom/left midpoints.
    func moving(_ original: DiaryQuadWarp, handle: Int, delta: CGPoint) -> DiaryQuadWarp? {
        var result = original
        var p = original.corners
        if self == .free && handle < 4 {
            p[handle].x += delta.x; p[handle].y += delta.y
        } else if self == .perspective && handle < 4 {
            if abs(delta.x*original.reference.width) >= abs(delta.y*original.reference.height) {
                let pair = handle == 0 ? 1 : handle == 1 ? 0 : handle == 2 ? 3 : 2
                p[handle].x += delta.x; p[pair].x -= delta.x
            } else {
                let pair = handle == 0 ? 3 : handle == 3 ? 0 : handle == 1 ? 2 : 1
                p[handle].y += delta.y; p[pair].y -= delta.y
            }
        } else if self == .skew && handle >= 4 {
            let edge = handle-4, next=(edge+1)%4
            let x=p[next].x-p[edge].x, y=p[next].y-p[edge].y
            // Convert to physical coordinates so non-square objects shear along their edge.
            let vx=x*original.reference.width, vy=y*original.reference.height
            let amount=(delta.x*original.reference.width*vx+delta.y*original.reference.height*vy)/max(1e-8,vx*vx+vy*vy)
            for n in [edge,next] { p[n].x += x*amount; p[n].y += y*amount }
        } else if self == .stretch {
            let rect = CGRect(x: p.map(\.x).min()!, y: p.map(\.y).min()!,
                width: p.map(\.x).max()!-p.map(\.x).min()!, height: p.map(\.y).max()!-p.map(\.y).min()!)
            let left = [0,3,7].contains(handle), right = [1,2,5].contains(handle)
            let top = [0,1,4].contains(handle), bottom = [2,3,6].contains(handle)
            let sx = left ? 1-delta.x/rect.width : right ? 1+delta.x/rect.width : 1
            let sy = top ? 1-delta.y/rect.height : bottom ? 1+delta.y/rect.height : 1
            guard sx > 0.02, sy > 0.02 else { return nil }
            let anchor=CGPoint(x: left ? rect.maxX : rect.minX, y: top ? rect.maxY : rect.minY)
            p = p.map { CGPoint(x: anchor.x+($0.x-anchor.x)*sx, y: anchor.y+($0.y-anchor.y)*sy) }
        } else { return nil }
        result.corners=p
        return result.isValid ? result : nil
    }
}
