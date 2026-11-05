import UIKit

/// Seeded paper surfaces shared by photo borders and stronger torn text decorations.
nonisolated enum DiaryPaperRenderer {
    private struct Random {
        var state: UInt64
        mutating func unit() -> CGFloat {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat(state >> 32) / CGFloat(UInt32.max)
        }
    }
    static func path(rect: CGRect, roughness: CGFloat, seed: Int, decoration: Bool) -> UIBezierPath {
        var random = Random(state: UInt64(bitPattern: Int64(seed)))
        let amplitude = min(decoration ? 14 : 10, min(rect.width, rect.height) * (decoration ? 0.045 : 0.018)) * roughness
        let corners = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                       CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)].map {
            CGPoint(x: $0.x + (random.unit() - 0.5) * amplitude, y: $0.y + (random.unit() - 0.5) * amplitude)
        }
        let path = UIBezierPath()
        for edge in 0..<4 {
            let a = corners[edge], b = corners[(edge + 1) % 4]
            let length = max(1, hypot(b.x-a.x, b.y-a.y))
            let count = min(1600, max(12, Int(length / 1.5)))
            var broad: CGFloat = 0, medium: CGFloat = 0
            var broadTarget = random.unit() - 0.5, mediumTarget = random.unit() - 0.5
            for i in 0..<count {
                if i % 45 == 0 { broadTarget = random.unit() - 0.5 }
                if i % 9 == 0 { mediumTarget = random.unit() - 0.5 }
                broad += (broadTarget - broad) * 0.09
                medium += (mediumTarget - medium) * 0.4
                let t = CGFloat(i) / CGFloat(count)
                let fade = min(1, min(t, 1-t) * 20)
                let d = (broad * 1.8 + medium * 0.8 + (random.unit()-0.5) * 0.45) * amplitude * fade
                let point = CGPoint(x: a.x + (b.x-a.x)*t - (b.y-a.y)/length*d,
                                    y: a.y + (b.y-a.y)*t + (b.x-a.x)/length*d)
                if edge == 0 && i == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
        }
        path.close(); return path
    }
    static func draw(_ path: UIBezierPath, rect: CGRect, color: UIColor, shadow: CGFloat, seed: Int, in ctx: CGContext) {
        let scale = min(1, min(rect.width, rect.height) / 400)
        let warm = UIColor(red: 0.25, green: 0.20, blue: 0.15, alpha: 1)
        // Wide lifted-paper shadow plus tight contact shadow, independent of paper texture.
        for (offset, blur, alpha) in [(CGFloat(7), CGFloat(17), CGFloat(0.20)), (2, 3, 0.24)] {
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: scale * offset * 0.25, height: scale * offset),
                          blur: scale * blur, color: warm.withAlphaComponent(alpha * shadow).cgColor)
            color.setFill(); path.fill(); ctx.restoreGState()
        }
        // Small corner lift is mostly covered by the paper; only its soft lower edge remains.
        if shadow > 0 {
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: 5 * scale), blur: 9 * scale,
                          color: warm.withAlphaComponent(0.14 * shadow).cgColor)
            warm.withAlphaComponent(0.12 * shadow).setFill()
            let corner = CGRect(x: rect.maxX - rect.width * 0.22, y: rect.maxY - 4 * scale,
                                width: rect.width * 0.18, height: 3 * scale)
            ctx.fillEllipse(in: corner)
            ctx.restoreGState()
        }
        ctx.saveGState(); path.addClip()
        color.setFill(); path.fill()
        var random = Random(state: UInt64(bitPattern: Int64(seed)) &+ 173)
        let count = min(24000, max(200, Int(rect.width * rect.height / 55)))
        ctx.setLineWidth(max(0.3, scale * 0.55))
        for _ in 0..<count {
            let x = rect.minX + random.unit()*rect.width, y = rect.minY + random.unit()*rect.height
            let light = random.unit() > 0.45
            ctx.setStrokeColor((light ? UIColor.white : warm).withAlphaComponent(light ? 0.16 : 0.045).cgColor)
            ctx.move(to: CGPoint(x: x, y: y))
            ctx.addLine(to: CGPoint(x: x + (1 + random.unit()*4)*scale, y: y + (random.unit()-0.5)*2*scale)); ctx.strokePath()
        }
        // The pale torn core sits over a thin warm thickness edge.
        ctx.translateBy(x: 0, y: scale * 1.2)
        warm.withAlphaComponent(0.14).setStroke(); path.lineWidth = scale * 3; path.stroke()
        ctx.translateBy(x: 0, y: -scale * 1.8)
        UIColor.white.withAlphaComponent(0.65).setStroke(); path.lineWidth = scale * 2; path.stroke()
        ctx.restoreGState()
    }
}
