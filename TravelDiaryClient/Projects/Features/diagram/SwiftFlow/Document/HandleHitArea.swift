import CoreGraphics

nonisolated public enum HandleHitArea: Sendable, Hashable, Codable {
    case disabled
    case point(radius: CGFloat)
    case node
    case nodeBorder(width: CGFloat)
}
