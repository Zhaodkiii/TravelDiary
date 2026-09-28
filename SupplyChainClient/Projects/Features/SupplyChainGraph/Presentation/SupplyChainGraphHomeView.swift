import SwiftUI

/// A read-only, touch-friendly supply-chain explorer. SwiftDagre owns the node
/// coordinates; SwiftUI owns the cards, selection state, and supplier detail.
struct SupplyChainGraphHomeView: View {
    @State private var selectedNodeID = "battery-cell"
    @State private var showsSupplierSheet = false

    private let layout = SupplyChainGraphLayout.make()

    private var selectedNode: SupplyChainGraphNode {
        layout.nodes.first(where: { $0.id == selectedNodeID }) ?? layout.nodes[0]
    }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 18) {
                header
                graphCanvas
                legend
            }
            .padding(20)
        }
        .background(Color(red: 0.96, green: 0.98, blue: 1.0))
        .sheet(isPresented: $showsSupplierSheet) {
            SupplierListView(category: selectedNode)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("新能源汽车供应链", systemImage: "point.3.connected.trianglepath.dotted")
                .font(.headline.weight(.semibold))
                .foregroundStyle(Color(red: 0.04, green: 0.14, blue: 0.32))
            Text("从整车到原料 · 点击分类查看关联供应商")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var graphCanvas: some View {
        ZStack(alignment: .topLeading) {
            SupplyChainEdgeCanvas(
                edges: layout.edges,
                selectedNodeID: selectedNodeID,
                selectedPath: layout.selectedPath(to: selectedNodeID),
                canvasSize: layout.canvasSize
            )

            ForEach(layout.nodes) { node in
                SupplyChainNodeCard(
                    node: node,
                    isSelected: node.id == selectedNodeID,
                    isOnSelectedPath: layout.selectedPath(to: selectedNodeID).contains(node.id)
                ) {
                    selectedNodeID = node.id
                    showsSupplierSheet = true
                }
                .frame(width: node.size.width, height: node.size.height)
                .position(node.position)
            }
        }
        .frame(width: layout.canvasSize.width, height: layout.canvasSize.height)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.white)
                .overlay {
                    DotGrid()
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
                .shadow(color: .blue.opacity(0.08), radius: 16, y: 8)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("新能源汽车供应链分类图")
    }

    private var legend: some View {
        HStack(spacing: 16) {
            Label("分类节点", systemImage: "square.fill")
            Label("当前路径", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
            Label("点击查看供应商", systemImage: "hand.tap")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

private struct SupplyChainNodeCard: View {
    let node: SupplyChainGraphNode
    let isSelected: Bool
    let isOnSelectedPath: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(node.tint.opacity(0.13))
                    Image(systemName: node.symbol)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(node.tint)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 4) {
                    Text(node.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(red: 0.04, green: 0.14, blue: 0.32))
                        .lineLimit(1)
                    Text(node.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                } else if isOnSelectedPath {
                    Circle()
                        .fill(.blue)
                        .frame(width: 7, height: 7)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? Color.blue : (isOnSelectedPath ? Color.blue.opacity(0.5) : Color(red: 0.84, green: 0.89, blue: 0.96)), lineWidth: isSelected ? 2 : 1)
            }
            .shadow(color: isSelected ? .blue.opacity(0.18) : .black.opacity(0.04), radius: isSelected ? 10 : 4, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityHint("查看\(node.title)的关联供应商")
    }
}

private struct SupplyChainEdgeCanvas: View {
    let edges: [SupplyChainGraphEdge]
    let selectedNodeID: String
    let selectedPath: Set<String>
    let canvasSize: CGSize

    var body: some View {
        Canvas { context, _ in
            for edge in edges {
                guard edge.points.count > 1 else { continue }
                let isActive = selectedPath.contains(edge.sourceID) && selectedPath.contains(edge.targetID)
                var path = Path()
                path.move(to: edge.points[0])
                for point in edge.points.dropFirst() {
                    path.addLine(to: point)
                }
                context.stroke(
                    path,
                    with: .color(isActive ? .blue : Color(red: 0.74, green: 0.80, blue: 0.89)),
                    style: StrokeStyle(lineWidth: isActive ? 2.5 : 1.25, lineCap: .round, lineJoin: .round)
                )
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .allowsHitTesting(false)
    }
}

private struct DotGrid: View {
    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 18
            for x in stride(from: 0, through: size.width, by: step) {
                for y in stride(from: 0, through: size.height, by: step) {
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1, height: 1)), with: .color(Color.blue.opacity(0.08)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct SupplierListView: View {
    let category: SupplyChainGraphNode
    @Environment(\.dismiss) private var dismiss

    private var suppliers: [String] {
        switch category.id {
        case "battery-cell": ["宁德时代", "中创新航", "亿纬锂能", "国轩高科", "欣旺达"]
        case "anode": ["尚太科技", "贝特瑞", "杉杉股份", "翔丰华"]
        case "battery": ["宁德时代", "弗迪电池", "中创新航", "蜂巢能源"]
        case "motor": ["汇川技术", "联合汽车电子", "方正电机", "精进电动"]
        case "lidar": ["禾赛科技", "速腾聚创", "图达通"]
        default: ["宁德时代", "博世", "德赛西威", "拓普集团"]
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: category.symbol)
                            .font(.title2)
                            .foregroundStyle(category.tint)
                            .frame(width: 46, height: 46)
                            .background(category.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(category.title).font(.title3.weight(.bold))
                            Text(category.subtitle).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }

                Section("关联供应商 · \(suppliers.count) 家") {
                    ForEach(suppliers, id: \.self) { supplier in
                        HStack {
                            Text(supplier).fontWeight(.medium)
                            Spacer()
                            Text(category.title).font(.caption).foregroundStyle(.secondary)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .navigationTitle("供应商")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct SupplyChainGraphNode: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
    let position: CGPoint
    let size: CGSize
}

private struct SupplyChainGraphEdge {
    let sourceID: String
    let targetID: String
    let points: [CGPoint]
}

private struct SupplyChainGraphLayout {
    let nodes: [SupplyChainGraphNode]
    let edges: [SupplyChainGraphEdge]
    let canvasSize: CGSize
    private let parents: [String: String]

    func selectedPath(to nodeID: String) -> Set<String> {
        var path: Set<String> = [nodeID]
        var current = nodeID
        while let parent = parents[current] {
            path.insert(parent)
            current = parent
        }
        return path
    }

    static func make() -> SupplyChainGraphLayout {
        let specs: [GraphNodeSpec] = [
            .init(id: "su7", title: "小米 SU7", subtitle: "当前车型 · 纯电轿车", symbol: "car.side.fill", tint: .orange, parentID: nil, size: .init(width: 210, height: 94)),
            .init(id: "battery", title: "动力电池", subtitle: "电芯 · 电池包 · BMS", symbol: "battery.100percent", tint: .blue, parentID: "su7"),
            .init(id: "drive", title: "电驱系统", subtitle: "电机 · 电控 · 减速器", symbol: "engine.combustion", tint: .indigo, parentID: "su7"),
            .init(id: "smart", title: "智能驾驶", subtitle: "感知 · 决策 · 控制", symbol: "sensor.tag.radiowaves.forward", tint: .purple, parentID: "su7"),
            .init(id: "cockpit", title: "电子座舱", subtitle: "显示 · 交互 · 音响", symbol: "rectangle.on.rectangle", tint: .teal, parentID: "su7"),
            .init(id: "chassis", title: "底盘系统", subtitle: "制动 · 转向 · 悬架", symbol: "car.rear.and.tire.marks", tint: .cyan, parentID: "su7"),
            .init(id: "battery-cell", title: "电芯", subtitle: "动力电池核心单元", symbol: "battery.75percent", tint: .blue, parentID: "battery", size: .init(width: 210, height: 88)),
            .init(id: "battery-pack", title: "电池包 / CTB", subtitle: "系统集成", symbol: "shippingbox.fill", tint: .blue, parentID: "battery"),
            .init(id: "bms", title: "BMS", subtitle: "电池管理系统", symbol: "cpu", tint: .blue, parentID: "battery"),
            .init(id: "motor", title: "驱动电机", subtitle: "高效能量转换", symbol: "gearshape.2", tint: .indigo, parentID: "drive"),
            .init(id: "lidar", title: "激光雷达", subtitle: "环境感知", symbol: "sensor", tint: .purple, parentID: "smart"),
            .init(id: "anode", title: "负极材料", subtitle: "人造石墨", symbol: "circle.hexagongrid.fill", tint: .blue, parentID: "battery-cell", size: .init(width: 200, height: 88)),
            .init(id: "cathode", title: "正极材料", subtitle: "磷酸铁锂", symbol: "circle.grid.cross.fill", tint: .orange, parentID: "battery-cell"),
            .init(id: "electrolyte", title: "隔膜 / 电解液", subtitle: "安全与循环性能", symbol: "drop.fill", tint: .cyan, parentID: "battery-cell")
        ]

        let graph = DagreGraph(options: .init(directed: true, multigraph: false, compound: false))
        let options = LayoutOptions()
        options.rankdir = .leftRight
        options.ranksep = 84
        options.nodesep = 30
        options.marginx = 30
        options.marginy = 36
        graph.setGraph(options)

        for spec in specs {
            graph.setNode(spec.id, label: DagreNodeLabel(size: spec.size))
        }
        for spec in specs {
            if let parentID = spec.parentID {
                try? graph.setEdge(parentID, spec.id, label: DagreEdgeLabel(minlen: 1, weight: 2))
            }
        }
        try? SwiftDagreLayout.layout(graph)

        let nodes = specs.compactMap { spec -> SupplyChainGraphNode? in
            guard let label = graph.node(spec.id) else { return nil }
            return SupplyChainGraphNode(
                id: spec.id,
                title: spec.title,
                subtitle: spec.subtitle,
                symbol: spec.symbol,
                tint: spec.tint,
                position: CGPoint(x: label.x, y: label.y),
                size: spec.size
            )
        }
        let edges = graph.edges().compactMap { edge -> SupplyChainGraphEdge? in
            guard let label = graph.edge(edge.id), label.points.count > 1 else { return nil }
            return SupplyChainGraphEdge(sourceID: edge.v, targetID: edge.w, points: label.points.map(\.cgPoint))
        }
        let parents = Dictionary(uniqueKeysWithValues: specs.compactMap { spec in
            spec.parentID.map { (spec.id, $0) }
        })
        return SupplyChainGraphLayout(
            nodes: nodes,
            edges: edges,
            canvasSize: CGSize(width: max(options.width + 60, 1_220), height: max(options.height + 72, 760)),
            parents: parents
        )
    }
}

private struct GraphNodeSpec {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
    let parentID: String?
    var size: CGSize = .init(width: 190, height: 78)
}

#Preview {
    NavigationStack {
        SupplyChainGraphHomeView()
    }
}
