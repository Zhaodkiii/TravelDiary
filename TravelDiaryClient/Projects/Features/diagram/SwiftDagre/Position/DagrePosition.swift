// SPDX-License-Identifier: MIT
// SwiftDagre - A Swift port of @dagrejs/dagre

/// Position assignment for nodes in a layered graph.
/// The Dagre prefix keeps this source compatible with the bundled SwiftFlow
/// component, which also exposes a type named `Position`.
public enum DagrePosition {

    /// Assigns x and y coordinates to all nodes
    /// - Throws: `GraphError` if graph operations fail
    public static func run(_ g: DagreGraph, nodesep: Double, edgesep: Double, ranksep: Double, align: LayoutOptions.Alignment? = nil) throws {
        let nonCompound = try GraphUtil.asNonCompoundGraph(g)
        PositionY.run(nonCompound, ranksep: ranksep)
        let xs = try BrandesKopf.positionX(nonCompound, nodesep: nodesep, edgesep: edgesep, align: align)

        for (v, x) in xs {
            if let label = g.node(v) {
                label.x = x
            }
        }

        for v in nonCompound.nodes() {
            if let ncLabel = nonCompound.node(v), let label = g.node(v) {
                label.y = ncLabel.y
            }
        }
    }
}
