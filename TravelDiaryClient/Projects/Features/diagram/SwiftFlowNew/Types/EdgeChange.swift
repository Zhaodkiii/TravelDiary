import Foundation

/// Describes a mutation to an edge in the graph.
///
/// Apply changes via `applyEdgeChanges(_:edges:)`.
public enum EdgeChange<EdgeData: Equatable & Sendable & Hashable>: Sendable {
  case selection(id: String, selected: Bool)
  case remove(id: String)
  case add(item: SwiftFlowEdge<EdgeData>)
  case replace(id: String, item: SwiftFlowEdge<EdgeData>)
}
