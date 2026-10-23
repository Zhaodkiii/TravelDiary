import CoreGraphics
import Foundation

/// 选框外保留 44 点操作热区；框内按较紧的圆形／短条命中，给文字留出选择空间。
nonisolated enum DiaryCanvasHandleHitRegion {
    static func contains(_ offset: CGPoint, edgeAngle: CGFloat? = nil, allowsExpansion: Bool = false) -> Bool {
        guard let angle = edgeAngle else { return hypot(offset.x, offset.y) <= (allowsExpansion ? 22 : 16) }
        let x = offset.x * cos(angle) + offset.y * sin(angle)
        let y = -offset.x * sin(angle) + offset.y * cos(angle)
        return abs(x) <= (allowsExpansion ? 22 : 14) && abs(y) <= (allowsExpansion ? 18 : 8)
    }
}
