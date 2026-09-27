//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension CGFloat {
    @inlinable
    nonisolated public static func secondCameraEditor_clamp(_ value: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        Swift.max(min, Swift.min(max, value))
    }

    @inlinable
    nonisolated public static func secondCameraEditor_clamp01(_ value: CGFloat) -> CGFloat {
        secondCameraEditor_clamp(value, min: 0, max: 1)
    }

    @inlinable
    nonisolated public static func secondCameraEditor_lerp(left: CGFloat, right: CGFloat, alpha: CGFloat) -> CGFloat {
        (left * (1.0 - alpha)) + (right * alpha)
    }

    @inlinable
    nonisolated public static func secondCameraEditor_inverseLerp(_ value: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        (value - min) / (max - min)
    }

    /// Ceil to an even number
    @inlinable
    nonisolated public static func secondCameraEditor_ceilEven(_ value: CGFloat) -> CGFloat {
        2.0 * Darwin.ceil(value * 0.5)
    }
}

extension CGSize {
    @inlinable
    nonisolated public static func secondCameraEditor_ceil(_ size: CGSize) -> CGSize {
        CGSize(width: Darwin.ceil(size.width), height: Darwin.ceil(size.height))
    }

    @inlinable
    nonisolated public static func secondCameraEditor_floor(_ size: CGSize) -> CGSize {
        CGSize(width: Darwin.floor(size.width), height: Darwin.floor(size.height))
    }

    @inlinable
    nonisolated public static func secondCameraEditor_round(_ size: CGSize) -> CGSize {
        CGSize(width: Darwin.round(size.width), height: Darwin.round(size.height))
    }

    @inlinable
    nonisolated public static func secondCameraEditor_max(_ a: CGSize, _ b: CGSize) -> CGSize {
        CGSize(width: Swift.max(a.width, b.width), height: Swift.max(a.height, b.height))
    }

    @inlinable
    nonisolated public static func secondCameraEditor_scale(_ size: CGSize, factor: CGFloat) -> CGSize {
        CGSize(width: size.width * factor, height: size.height * factor)
    }

    @inlinable
    nonisolated public static func secondCameraEditor_add(_ lhs: CGSize, _ rhs: CGSize) -> CGSize {
        CGSize(width: lhs.width + rhs.width, height: lhs.height + rhs.height)
    }
}

extension CGPoint {
    @inlinable
    nonisolated public static func secondCameraEditor_add(_ lhs: CGPoint, _ rhs: CGPoint) -> CGPoint {
        CGPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }

    @inlinable
    nonisolated public static func secondCameraEditor_subtract(_ lhs: CGPoint, _ rhs: CGPoint) -> CGPoint {
        CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }

    @inlinable
    nonisolated public static func secondCameraEditor_scale(_ point: CGPoint, factor: CGFloat) -> CGPoint {
        CGPoint(x: point.x * factor, y: point.y * factor)
    }

    @inlinable
    nonisolated public static func secondCameraEditor_min(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: Swift.min(a.x, b.x), y: Swift.min(a.y, b.y))
    }

    @inlinable
    nonisolated public static func secondCameraEditor_max(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: Swift.max(a.x, b.x), y: Swift.max(a.y, b.y))
    }

    @inlinable
    nonisolated public static func secondCameraEditor_clamp01(_ point: CGPoint) -> CGPoint {
        CGPoint(x: CGFloat.secondCameraEditor_clamp01(point.x), y: CGFloat.secondCameraEditor_clamp01(point.y))
    }

    @inlinable
    nonisolated public static func secondCameraEditor_invert(_ point: CGPoint) -> CGPoint {
        CGPoint(x: -point.x, y: -point.y)
    }
}

extension CGRect {
    @inlinable
    nonisolated public static func secondCameraEditor_scale(_ rect: CGRect, factor: CGFloat) -> CGRect {
        CGRect(
            origin: CGPoint.secondCameraEditor_scale(rect.origin, factor: factor),
            size: CGSize.secondCameraEditor_scale(rect.size, factor: factor)
        )
    }
}
