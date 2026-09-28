import Foundation

/// A 2D coordinate representing a position on the canvas.
nonisolated public struct SwiftFlowXYPosition: Equatable, Sendable, Codable, Hashable {
  public var x: CGFloat
  public var y: CGFloat

  public init(x: CGFloat, y: CGFloat) {
    self.x = x
    self.y = y
  }

  public static let zero = SwiftFlowXYPosition(x: 0, y: 0)
}

extension SwiftFlowXYPosition {
  public static func + (lhs: SwiftFlowXYPosition, rhs: SwiftFlowXYPosition) -> SwiftFlowXYPosition {
    SwiftFlowXYPosition(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
  }

  public static func - (lhs: SwiftFlowXYPosition, rhs: SwiftFlowXYPosition) -> SwiftFlowXYPosition {
    SwiftFlowXYPosition(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
  }

  /// Returns a new position snapped to the given grid.
  public func snapped(to grid: (x: CGFloat, y: CGFloat)) -> SwiftFlowXYPosition {
    SwiftFlowXYPosition(
      x: (x / grid.x).rounded() * grid.x,
      y: (y / grid.y).rounded() * grid.y
    )
  }
}
