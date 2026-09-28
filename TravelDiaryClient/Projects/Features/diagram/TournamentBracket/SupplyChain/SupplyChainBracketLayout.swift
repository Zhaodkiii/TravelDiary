import CoreGraphics
import Foundation

struct SupplyChainBracketLayoutConfiguration: Hashable {
    var nodeSize = CGSize(width: 196, height: 82)
    var vehicleNodeSize = CGSize(width: 220, height: 126)
    var columnSpacing: CGFloat = 92
    var rowSpacing: CGFloat = 18
    var contentInsets = CGSize(width: 24, height: 66)
}

struct SupplyChainEdgeRoute: Hashable {
    let edge: SupplyChainEdge
    let points: [CGPoint]
}

struct SupplyChainBracketLayoutResult {
    let nodeFrames: [String: CGRect]
    let edgeRoutes: [SupplyChainEdgeRoute]
    let canvasSize: CGSize
    let columns: [[String]]
}

struct SupplyChainBracketLayoutEngine {
    let configuration: SupplyChainBracketLayoutConfiguration

    init(configuration: SupplyChainBracketLayoutConfiguration = .init()) {
        self.configuration = configuration
    }

    func layout(_ graph: SupplyChainGraph) -> SupplyChainBracketLayoutResult {
        let columns = makeColumns(graph)
        let maximumColumnHeight = columns.map { columnHeight($0, graph: graph) }.max() ?? 0
        var frames: [String: CGRect] = [:]
        var x = configuration.contentInsets.width

        for column in columns {
            let height = columnHeight(column, graph: graph)
            var y = configuration.contentInsets.height + (maximumColumnHeight - height) / 2
            let width = column.map { nodeSize(graph.node(id: $0)).width }.max() ?? configuration.nodeSize.width

            for nodeID in column {
                let size = nodeSize(graph.node(id: nodeID))
                frames[nodeID] = CGRect(x: x + (width - size.width) / 2, y: y, width: size.width, height: size.height)
                y += size.height + configuration.rowSpacing
            }
            x += width + configuration.columnSpacing
        }

        let routes = graph.edges.compactMap { edge -> SupplyChainEdgeRoute? in
            guard let source = frames[edge.sourceID], let target = frames[edge.targetID] else { return nil }
            let start = CGPoint(x: source.maxX, y: source.midY)
            let end = CGPoint(x: target.minX, y: target.midY)
            let middleX = start.x + (end.x - start.x) / 2
            return SupplyChainEdgeRoute(
                edge: edge,
                points: [start, CGPoint(x: middleX, y: start.y), CGPoint(x: middleX, y: end.y), end]
            )
        }

        let canvasWidth = max(x - configuration.columnSpacing + configuration.contentInsets.width, 0)
        let canvasHeight = maximumColumnHeight + configuration.contentInsets.height * 2
        return SupplyChainBracketLayoutResult(
            nodeFrames: frames,
            edgeRoutes: routes,
            canvasSize: CGSize(width: canvasWidth, height: canvasHeight),
            columns: columns
        )
    }

    private func makeColumns(_ graph: SupplyChainGraph) -> [[String]] {
        let incomingCounts = Dictionary(grouping: graph.edges, by: \.targetID).mapValues(\.count)
        var depths = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, 0) })
        var queue = graph.nodes.filter { incomingCounts[$0.id, default: 0] == 0 }.map(\.id)
        var index = 0

        while index < queue.count {
            let sourceID = queue[index]
            index += 1
            for edge in graph.edges where edge.sourceID == sourceID {
                let candidate = depths[sourceID, default: 0] + 1
                if candidate > depths[edge.targetID, default: 0] {
                    depths[edge.targetID] = candidate
                }
                if !queue.contains(edge.targetID) { queue.append(edge.targetID) }
            }
        }

        let maxDepth = depths.values.max() ?? 0
        return (0...maxDepth).map { depth in
            graph.nodes.filter { depths[$0.id] == depth }.map(\.id)
        }.filter { !$0.isEmpty }
    }

    private func nodeSize(_ node: SupplyChainNode?) -> CGSize {
        node?.kind == .vehicle ? configuration.vehicleNodeSize : configuration.nodeSize
    }

    private func columnHeight(_ nodeIDs: [String], graph: SupplyChainGraph) -> CGFloat {
        guard !nodeIDs.isEmpty else { return 0 }
        return nodeIDs.reduce(CGFloat.zero) { $0 + nodeSize(graph.node(id: $1)).height }
            + CGFloat(nodeIDs.count - 1) * configuration.rowSpacing
    }
}
