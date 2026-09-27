import UIKit

extension UIEdgeInsets {
    nonisolated init(top: CGFloat, leading: CGFloat, bottom: CGFloat, trailing: CGFloat) {
        let isRTL = SecondCameraEditorCurrentAppContextIfAvailable()?.isRTL
            ?? (UIApplication.shared.userInterfaceLayoutDirection == .rightToLeft)
        self.init(
            top: top,
            left: isRTL ? trailing : leading,
            bottom: bottom,
            right: isRTL ? leading : trailing
        )
    }

    nonisolated init(margin: CGFloat) {
        self.init(top: margin, left: margin, bottom: margin, right: margin)
    }

    nonisolated init(hMargin: CGFloat, vMargin: CGFloat) {
        self.init(top: vMargin, left: hMargin, bottom: vMargin, right: hMargin)
    }

    nonisolated func inverted() -> UIEdgeInsets {
        UIEdgeInsets(top: -top, left: -left, bottom: -bottom, right: -right)
    }

    var leading: CGFloat {
        get {
            let isRTL = SecondCameraEditorCurrentAppContextIfAvailable()?.isRTL
                ?? (UIApplication.shared.userInterfaceLayoutDirection == .rightToLeft)
            return isRTL ? right : left
        }
        set {
            let isRTL = SecondCameraEditorCurrentAppContextIfAvailable()?.isRTL
                ?? (UIApplication.shared.userInterfaceLayoutDirection == .rightToLeft)
            if isRTL {
                right = newValue
            } else {
                left = newValue
            }
        }
    }

    var trailing: CGFloat {
        get {
            let isRTL = SecondCameraEditorCurrentAppContextIfAvailable()?.isRTL
                ?? (UIApplication.shared.userInterfaceLayoutDirection == .rightToLeft)
            return isRTL ? left : right
        }
        set {
            let isRTL = SecondCameraEditorCurrentAppContextIfAvailable()?.isRTL
                ?? (UIApplication.shared.userInterfaceLayoutDirection == .rightToLeft)
            if isRTL {
                left = newValue
            } else {
                right = newValue
            }
        }
    }

    var isNonEmpty: Bool {
        left != 0 || right != 0 || top != 0 || bottom != 0
    }
}

extension NSDirectionalEdgeInsets {
    init(margin: CGFloat) {
        self.init(top: margin, leading: margin, bottom: margin, trailing: margin)
    }

    init(hMargin: CGFloat, vMargin: CGFloat) {
        self.init(top: vMargin, leading: hMargin, bottom: vMargin, trailing: hMargin)
    }
}

extension CGRect {
    nonisolated var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }

    nonisolated var topLeft: CGPoint { origin }
    nonisolated var topRight: CGPoint { CGPoint(x: maxX, y: minY) }
    nonisolated var bottomLeft: CGPoint { CGPoint(x: minX, y: maxY) }
    nonisolated var bottomRight: CGPoint { CGPoint(x: maxX, y: maxY) }
}

extension CGPoint {
    nonisolated func clamp(_ rect: CGRect) -> CGPoint {
        CGPoint(
            x: CGFloat.secondCameraEditor_clamp(x, min: rect.minX, max: rect.maxX),
            y: CGFloat.secondCameraEditor_clamp(y, min: rect.minY, max: rect.maxY)
        )
    }

    nonisolated func toUnitCoordinates(viewBounds: CGRect, shouldClamp: Bool) -> CGPoint {
        CGPoint(
            x: (x - viewBounds.origin.x).secondCameraEditor_inverseLerp(0, viewBounds.width, shouldClamp: shouldClamp),
            y: (y - viewBounds.origin.y).secondCameraEditor_inverseLerp(0, viewBounds.height, shouldClamp: shouldClamp)
        )
    }

    nonisolated func toUnitCoordinates(viewSize: CGSize, shouldClamp: Bool) -> CGPoint {
        toUnitCoordinates(viewBounds: CGRect(origin: .zero, size: viewSize), shouldClamp: shouldClamp)
    }

    nonisolated func fromUnitCoordinates(viewBounds: CGRect) -> CGPoint {
        CGPoint(
            x: viewBounds.origin.x + x.secondCameraEditor_lerp(0, viewBounds.size.width),
            y: viewBounds.origin.y + y.secondCameraEditor_lerp(0, viewBounds.size.height)
        )
    }

    nonisolated func fromUnitCoordinates(viewSize: CGSize) -> CGPoint {
        fromUnitCoordinates(viewBounds: CGRect(origin: .zero, size: viewSize))
    }

    nonisolated func inverse() -> CGPoint {
        CGPoint(x: -x, y: -y)
    }

    nonisolated func plus(_ value: CGPoint) -> CGPoint {
        CGPoint(x: x + value.x, y: y + value.y)
    }

    nonisolated func minus(_ value: CGPoint) -> CGPoint {
        CGPoint.secondCameraEditor_subtract(self, value)
    }

    nonisolated func times(_ value: CGFloat) -> CGPoint {
        CGPoint(x: x * value, y: y * value)
    }

    nonisolated func min(_ value: CGPoint) -> CGPoint {
        CGPoint(x: Swift.min(x, value.x), y: Swift.min(y, value.y))
    }

    nonisolated func max(_ value: CGPoint) -> CGPoint {
        CGPoint(x: Swift.max(x, value.x), y: Swift.max(y, value.y))
    }

    @inlinable
    nonisolated func distance(_ other: CGPoint) -> CGFloat {
        sqrt(pow(x - other.x, 2) + pow(y - other.y, 2))
    }

    nonisolated func applyingInverse(_ transform: CGAffineTransform) -> CGPoint {
        applying(transform.inverted())
    }

    nonisolated func offsetBy(dx: CGFloat = 0, dy: CGFloat = 0) -> CGPoint {
        CGPoint(x: x + dx, y: y + dy)
    }

    var length: CGFloat {
        sqrt(x * x + y * y)
    }

    nonisolated static let unitMidpoint: CGPoint = CGPoint(x: 0.5, y: 0.5)

    nonisolated static func +(left: CGPoint, right: CGPoint) -> CGPoint { left.plus(right) }
    nonisolated static func +=(left: inout CGPoint, right: CGPoint) { left.x += right.x; left.y += right.y }
    nonisolated static func -(left: CGPoint, right: CGPoint) -> CGPoint { CGPoint(x: left.x - right.x, y: left.y - right.y) }
    nonisolated static func *(left: CGPoint, right: CGFloat) -> CGPoint { CGPoint(x: left.x * right, y: left.y * right) }
}

extension CGSize {
    nonisolated var aspectRatio: CGFloat {
        guard height > 0 else { return 0 }
        return width / height
    }

    nonisolated var asPoint: CGPoint {
        CGPoint(x: width, y: height)
    }

    nonisolated var ceil: CGSize {
        CGSize(width: Foundation.ceil(width), height: Foundation.ceil(height))
    }

    nonisolated var isNonEmpty: Bool { width > 0 && height > 0 }

    nonisolated init(square: CGFloat) {
        self.init(width: square, height: square)
    }

    nonisolated static func square(_ size: CGFloat) -> CGSize {
        CGSize(width: size, height: size)
    }
}

extension CGAffineTransform {
    nonisolated static func scale(_ value: CGFloat) -> CGAffineTransform {
        CGAffineTransform(scaleX: value, y: value)
    }

    nonisolated func translate(_ point: CGPoint) -> CGAffineTransform {
        translatedBy(x: point.x, y: point.y)
    }
}

extension CGSize {
    nonisolated func plus(_ value: CGSize) -> CGSize {
        CGSize(width: width + value.width, height: height + value.height)
    }
}

extension CGFloat {
    nonisolated static var epsilon: CGFloat { .ulpOfOne }
}

extension CGFloat {
    nonisolated var square: CGFloat { secondCameraEditor_square }

    nonisolated func squareRoot() -> CGFloat {
        sqrt(self)
    }

    nonisolated static var hairlineWidth: CGFloat { 1 / UIScreen.main.scale }

    nonisolated static func hairlineWidthFraction(_ fraction: CGFloat) -> CGFloat {
        fraction * hairlineWidth
    }
}

// MARK: - NSAttributedString concatenation

nonisolated func + (lhs: NSAttributedString, rhs: NSAttributedString) -> NSAttributedString {
    let result = NSMutableAttributedString(attributedString: lhs)
    result.append(rhs)
    return result
}
