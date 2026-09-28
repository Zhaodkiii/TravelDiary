import CoreGraphics

extension CGSize {
    nonisolated var secondCameraEditor_largerAxis: CGFloat { Swift.max(width, height) }
    nonisolated var secondCameraEditor_smallerAxis: CGFloat { Swift.min(width, height) }

    nonisolated static func secondCameraEditor_square(_ edge: CGFloat) -> CGSize {
        CGSize(width: edge, height: edge)
    }
}

extension CGFloat {
    nonisolated func secondCameraEditor_squareRoot() -> CGFloat { sqrt(self) }
}

extension CGPoint {
    nonisolated func secondCameraEditor_fuzzyEquals(_ other: CGPoint, tolerance: CGFloat = 0.001) -> Bool {
        abs(x - other.x) < tolerance && abs(y - other.y) < tolerance
    }
}
