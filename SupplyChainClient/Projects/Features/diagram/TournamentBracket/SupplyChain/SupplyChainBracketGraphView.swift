import SwiftUI

struct SupplyChainBracketGraphView: View {
    let graph: SupplyChainGraph
    @Binding var selectedNodeID: String
    let onNodeTap: (SupplyChainNode) -> Void

    private let layout: SupplyChainBracketLayoutResult

    init(
        graph: SupplyChainGraph,
        selectedNodeID: Binding<String>,
        onNodeTap: @escaping (SupplyChainNode) -> Void
    ) {
        self.graph = graph
        _selectedNodeID = selectedNodeID
        self.onNodeTap = onNodeTap
        layout = SupplyChainBracketLayoutEngine().layout(graph)
    }

    var body: some View {
        ScrollView([.horizontal, .vertical], showsIndicators: false) {
            ZStack(alignment: .topLeading) {
                graphBackground
                edgeCanvas
                columnHeaders

                ForEach(graph.nodes) { node in
                    if let frame = layout.nodeFrames[node.id] {
                        SupplyChainGraphNodeCard(
                            node: node,
                            isSelected: node.id == selectedNodeID,
                            isOnSelectedPath: selectedPath.contains(node.id)
                        )
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                        .onTapGesture {
                            selectedNodeID = node.id
                            onNodeTap(node)
                        }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHint(node.companies.isEmpty ? "查看该分类" : "查看相关供应商")
                    }
                }
            }
            .frame(width: layout.canvasSize.width, height: layout.canvasSize.height)
        }
        .background(Color(red: 0.965, green: 0.978, blue: 0.995))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.blue.opacity(0.10), lineWidth: 1)
        }
    }

    private var selectedPath: Set<String> {
        graph.ancestorIDs(of: selectedNodeID)
    }

    private var graphBackground: some View {
        Canvas { context, size in
            var path = Path()
            let spacing: CGFloat = 24
            stride(from: CGFloat.zero, through: size.width, by: spacing).forEach { x in
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
            stride(from: CGFloat.zero, through: size.height, by: spacing).forEach { y in
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(path, with: .color(Color.blue.opacity(0.035)), lineWidth: 0.7)
        }
    }

    private var edgeCanvas: some View {
        Canvas { context, _ in
            for route in layout.edgeRoutes {
                let active = selectedPath.contains(route.edge.sourceID) && selectedPath.contains(route.edge.targetID)
                var path = Path()
                guard let first = route.points.first else { continue }
                path.move(to: first)
                for index in 1..<route.points.count {
                    let point = route.points[index]
                    if index < route.points.count - 1 {
                        let previous = route.points[index - 1]
                        let next = route.points[index + 1]
                        path.addLine(to: roundedCornerEntry(previous: previous, corner: point, next: next))
                        path.addQuadCurve(to: roundedCornerExit(previous: previous, corner: point, next: next), control: point)
                    } else {
                        path.addLine(to: point)
                    }
                }
                context.stroke(
                    path,
                    with: .color(active ? Color.blue : Color(red: 0.70, green: 0.77, blue: 0.86)),
                    style: StrokeStyle(lineWidth: active ? 3 : 1.5, lineCap: .round, lineJoin: .round)
                )
                if active, let end = route.points.last {
                    context.fill(Path(ellipseIn: CGRect(x: end.x - 4, y: end.y - 4, width: 8, height: 8)), with: .color(.blue))
                }
            }
        }
    }

    private var columnHeaders: some View {
        ForEach(Array(layout.columns.enumerated()), id: \.offset) { _, nodeIDs in
            if let nodeID = nodeIDs.first,
               let node = graph.node(id: nodeID),
               let frame = layout.nodeFrames[nodeID] {
                VStack(alignment: .leading, spacing: 3) {
                    Text(node.kind.title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color(red: 0.08, green: 0.17, blue: 0.33))
                    Capsule()
                        .fill(Color.blue.opacity(0.65))
                        .frame(width: 26, height: 3)
                }
                .position(x: frame.minX + 36, y: 29)
            }
        }
    }

    private func roundedCornerEntry(previous: CGPoint, corner: CGPoint, next: CGPoint) -> CGPoint {
        let radius: CGFloat = 10
        return CGPoint(
            x: corner.x + (previous.x == corner.x ? 0 : (previous.x < corner.x ? -radius : radius)),
            y: corner.y + (previous.y == corner.y ? 0 : (previous.y < corner.y ? -radius : radius))
        )
    }

    private func roundedCornerExit(previous: CGPoint, corner: CGPoint, next: CGPoint) -> CGPoint {
        let radius: CGFloat = 10
        return CGPoint(
            x: corner.x + (next.x == corner.x ? 0 : (next.x < corner.x ? -radius : radius)),
            y: corner.y + (next.y == corner.y ? 0 : (next.y < corner.y ? -radius : radius))
        )
    }
}

private struct SupplyChainGraphNodeCard: View {
    let node: SupplyChainNode
    let isSelected: Bool
    let isOnSelectedPath: Bool

    var body: some View {
        HStack(spacing: 12) {
            artwork
            VStack(alignment: .leading, spacing: 5) {
                if node.kind == .vehicle {
                    Text("当前车型")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange, in: Capsule())
                }
                Text(node.title)
                    .font(node.kind == .vehicle ? .title3.weight(.bold) : .subheadline.weight(.bold))
                    .foregroundStyle(isSelected ? Color.blue : Color(red: 0.05, green: 0.12, blue: 0.25))
                    .lineLimit(2)
                Text(node.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if !node.companies.isEmpty {
                    Label("\(node.companies.count) 家企业", systemImage: "building.2")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.blue)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(isSelected ? Color.blue : Color.secondary.opacity(0.5))
        }
        .padding(10)
        .background(.white.opacity(0.97), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(isSelected ? Color.blue : (isOnSelectedPath ? Color.blue.opacity(0.35) : Color.black.opacity(0.07)), lineWidth: isSelected ? 2 : 1)
        }
        .shadow(color: Color(red: 0.08, green: 0.20, blue: 0.38).opacity(isSelected ? 0.16 : 0.07), radius: isSelected ? 10 : 5, y: 3)
        .animation(.easeOut(duration: 0.2), value: isSelected)
    }

    private var artwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(accentColor.opacity(0.11))
            Image(systemName: node.symbol)
                .font(.system(size: node.kind == .vehicle ? 34 : 25, weight: .medium))
                .foregroundStyle(accentColor)
                .symbolRenderingMode(.hierarchical)
        }
        .frame(width: node.kind == .vehicle ? 74 : 56, height: node.kind == .vehicle ? 88 : 60)
    }

    private var accentColor: Color {
        switch node.accent {
        case .blue: return .blue
        case .orange: return .orange
        case .green: return .green
        case .purple: return .purple
        case .graphite: return Color(red: 0.24, green: 0.29, blue: 0.36)
        }
    }
}
