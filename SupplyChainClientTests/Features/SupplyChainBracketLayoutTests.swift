import XCTest
@testable import SupplyChainClient

final class SupplyChainBracketLayoutTests: XCTestCase {
    func testEveryEdgeFlowsFromLeftToRight() {
        let graph = XiaomiSU7SupplyChain.graph
        let result = SupplyChainBracketLayoutEngine().layout(graph)

        for edge in graph.edges {
            let source = try XCTUnwrap(result.nodeFrames[edge.sourceID])
            let target = try XCTUnwrap(result.nodeFrames[edge.targetID])
            XCTAssertLessThan(source.maxX, target.minX, edge.id)
        }
    }

    func testNodesWithinEachColumnDoNotOverlap() throws {
        let graph = XiaomiSU7SupplyChain.graph
        let result = SupplyChainBracketLayoutEngine().layout(graph)

        for column in result.columns {
            let frames = try column.map { try XCTUnwrap(result.nodeFrames[$0]) }
            for leftIndex in frames.indices {
                for rightIndex in frames.indices where rightIndex > leftIndex {
                    XCTAssertFalse(frames[leftIndex].intersects(frames[rightIndex]))
                }
            }
        }
    }

    func testSelectedMaterialReturnsCompleteAncestorPath() {
        let path = XiaomiSU7SupplyChain.graph.ancestorIDs(of: "anode")

        XCTAssertEqual(path, ["xiaomi-su7", "battery", "cell", "anode"])
    }
}
