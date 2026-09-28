import SwiftUI

/// A tournament-bracket-inspired supply-chain view. Unlike the free-layout
/// graph tab, this page deliberately keeps the relationship reading left → right.
struct SupplyChainBracketHomeView: View {
    @State private var selectedID = "su7"
    @State private var expandedIDs: Set<String> = []
    @State private var showsDetail = false

    private let layout = SupplyChainBracketLayout.sample

    private var selectedNode: SupplyChainBracketNode {
        layout.nodes.first(where: { $0.id == selectedID }) ?? layout.nodes[0]
    }

    private var visibleNodeIDs: Set<String> {
        layout.visibleNodeIDs(expandedIDs: expandedIDs)
    }

    private var visibleNodes: [SupplyChainBracketNode] {
        layout.nodes.filter { visibleNodeIDs.contains($0.id) }
    }

    private var visibleEdges: [SupplyChainBracketEdge] {
        layout.edges.filter { visibleNodeIDs.contains($0.from) && visibleNodeIDs.contains($0.to) }
    }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("供应链括号图")
                        .font(.title3.weight(.bold))
                    Text("整车在左，供应关系逐级向右展开")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                ZStack(alignment: .topLeading) {
                    BracketEdgeCanvas(
                        edges: visibleEdges,
                        activePath: layout.path(to: selectedID),
                        size: layout.size
                    )

                    ForEach(visibleNodes) { node in
                        BracketCategoryCard(
                            node: node,
                            isSelected: node.id == selectedID,
                            isActive: layout.path(to: selectedID).contains(node.id),
                            isExpanded: expandedIDs.contains(node.id),
                            hasChildren: layout.hasChildren(node.id)
                        ) {
                            selectedID = node.id
                            if layout.hasChildren(node.id) {
                                withAnimation(.easeInOut(duration: 0.24)) {
                                    if expandedIDs.contains(node.id) {
                                        expandedIDs.remove(node.id)
                                    } else {
                                        expandedIDs.insert(node.id)
                                    }
                                }
                            } else {
                                showsDetail = true
                            }
                        }
                        .frame(width: node.size.width, height: node.size.height)
                        .position(node.position)
                    }

                    ForEach(layout.columnTitles, id: \.title) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.index)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.blue)
                            Text(item.title)
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(Color(red: 0.04, green: 0.14, blue: 0.32))
                        }
                        .position(x: item.x, y: 38)
                    }
                }
                .frame(width: layout.size.width, height: layout.size.height)
                .background {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(.white)
                        .overlay {
                            BracketGrid()
                                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        }
                        .shadow(color: .blue.opacity(0.08), radius: 16, y: 8)
                }

                Label("点击系统展开拓扑，点击末级节点查看供应商", systemImage: "hand.tap")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .background(Color(red: 0.96, green: 0.98, blue: 1.0))
        .sheet(isPresented: $showsDetail) {
            BracketSupplierSheet(node: selectedNode)
        }
    }
}

private struct BracketCategoryCard: View {
    let node: SupplyChainBracketNode
    let isSelected: Bool
    let isActive: Bool
    let isExpanded: Bool
    let hasChildren: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: node.symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(node.tint)
                    .frame(width: 48, height: 48)
                    .background(node.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(node.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color(red: 0.04, green: 0.14, blue: 0.32))
                        .lineLimit(1)
                    Text(node.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if hasChildren {
                    Image(systemName: isExpanded ? "chevron.down.circle.fill" : "chevron.right.circle")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(isExpanded ? .blue : .secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(isSelected ? Color.blue.opacity(0.06) : .white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? .blue : (isActive ? .blue.opacity(0.45) : Color(red: 0.84, green: 0.89, blue: 0.96)), lineWidth: isSelected ? 2.5 : 1)
            }
            .shadow(color: isSelected ? .blue.opacity(0.16) : .black.opacity(0.04), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
    }
}

private struct BracketEdgeCanvas: View {
    let edges: [SupplyChainBracketEdge]
    let activePath: Set<String>
    let size: CGSize

    var body: some View {
        Canvas { context, _ in
            for edge in edges {
                let active = activePath.contains(edge.from) && activePath.contains(edge.to)
                let color = active ? Color.blue : Color(red: 0.76, green: 0.82, blue: 0.90)
                let width: CGFloat = active ? 3 : 1.5
                let middleX = (edge.start.x + edge.end.x) / 2
                var path = Path()
                path.move(to: edge.start)
                path.addLine(to: CGPoint(x: middleX, y: edge.start.y))
                path.addLine(to: CGPoint(x: middleX, y: edge.end.y))
                path.addLine(to: edge.end)
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
                context.fill(Path(ellipseIn: CGRect(x: edge.end.x - 4, y: edge.end.y - 4, width: 8, height: 8)), with: .color(color))
            }
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
    }
}

private struct BracketGrid: View {
    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 20
            for x in stride(from: 0, through: size.width, by: step) {
                for y in stride(from: 0, through: size.height, by: step) {
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1, height: 1)), with: .color(.blue.opacity(0.07)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct BracketSupplierSheet: View {
    let node: SupplyChainBracketNode
    @Environment(\.dismiss) private var dismiss

    private var suppliers: [String] {
        switch node.id {
        case "battery-cell": ["宁德时代", "中创新航", "亿纬锂能", "国轩高科", "欣旺达"]
        case "anode": ["尚太科技", "贝特瑞", "杉杉股份", "翔丰华"]
        default: ["宁德时代", "博世", "德赛西威", "汇川技术"]
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label(node.title, systemImage: node.symbol)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(node.tint)
                    Text(node.subtitle).foregroundStyle(.secondary)
                }
                Section("关联供应商 · \(suppliers.count) 家") {
                    ForEach(suppliers, id: \.self) { supplier in
                        Label(supplier, systemImage: "building.2")
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

private struct SupplyChainBracketNode: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
    let position: CGPoint
    let size: CGSize
}

private struct SupplyChainBracketEdge {
    let from: String
    let to: String
    let start: CGPoint
    let end: CGPoint
}

private struct SupplyChainBracketLayout {
    struct ColumnTitle {
        let index: String
        let title: String
        let x: CGFloat
    }

    let nodes: [SupplyChainBracketNode]
    let edges: [SupplyChainBracketEdge]
    let size = CGSize(width: 1_380, height: 930)
    let parents: [String: String]
    let columnTitles: [ColumnTitle] = [
        .init(index: "01", title: "整车产品", x: 140),
        .init(index: "02", title: "核心系统", x: 410),
        .init(index: "03", title: "关键部件", x: 725),
        .init(index: "04", title: "上游材料", x: 1_040)
    ]

    func path(to id: String) -> Set<String> {
        var result: Set<String> = [id]
        var current = id
        while let parent = parents[current] {
            result.insert(parent)
            current = parent
        }
        return result
    }

    func hasChildren(_ id: String) -> Bool {
        parents.values.contains(id)
    }

    func visibleNodeIDs(expandedIDs: Set<String>) -> Set<String> {
        var visible: Set<String> = ["su7"]
        var changed = true
        while changed {
            changed = false
            for (child, parent) in parents where visible.contains(parent) && expandedIDs.contains(parent) {
                if visible.insert(child).inserted {
                    changed = true
                }
            }
        }
        return visible
    }

    static let sample: SupplyChainBracketLayout = {
        let card = CGSize(width: 220, height: 84)
        let root = SupplyChainBracketNode(id: "su7", title: "小米 SU7", subtitle: "2024款 · 纯电轿车", symbol: "car.side.fill", tint: .orange, position: .init(x: 145, y: 450), size: .init(width: 230, height: 112))
        let systems = [
            node("battery", "动力电池", "电芯 · 电池包 · BMS", "battery.100percent", .blue, 410, 170, card),
            node("drive", "电驱系统", "电机 · 电控 · 减速器", "engine.combustion", .indigo, 410, 310, card),
            node("smart", "智能驾驶", "感知 · 决策 · 控制", "sensor.tag.radiowaves.forward", .purple, 410, 450, card),
            node("body", "车身系统", "结构 · 内外饰 · 轻量化", "car", .cyan, 410, 590, card),
            node("cockpit", "电子座舱", "显示 · 交互 · 音响", "rectangle.on.rectangle", .teal, 410, 730, card),
            node("chassis", "底盘系统", "制动 · 转向 · 悬架", "car.rear.and.tire.marks", .blue, 410, 850, card)
        ]
        let components = [
            node("battery-cell", "电芯", "电池核心单元", "battery.75percent", .blue, 725, 170, card),
            node("battery-pack", "电池包 / CTB", "系统集成", "shippingbox.fill", .blue, 725, 310, card),
            node("bms", "BMS", "电池管理系统", "cpu", .blue, 725, 450, card),
            node("motor", "驱动电机", "高效能量转换", "gearshape.2", .indigo, 725, 590, card),
            node("lidar", "激光雷达", "环境感知", "sensor", .purple, 725, 730, card)
        ]
        let materials = [
            node("anode", "负极材料", "人造石墨", "circle.hexagongrid.fill", .blue, 1_040, 170, card),
            node("cathode", "正极材料", "磷酸铁锂", "circle.grid.cross.fill", .orange, 1_040, 310, card),
            node("electrolyte", "隔膜 / 电解液", "安全与循环性能", "drop.fill", .cyan, 1_040, 450, card)
        ]
        let all = [root] + systems + components + materials
        let parents = [
            "battery": "su7", "drive": "su7", "smart": "su7", "body": "su7", "cockpit": "su7", "chassis": "su7",
            "battery-cell": "battery", "battery-pack": "battery", "bms": "battery", "motor": "drive", "lidar": "smart",
            "anode": "battery-cell", "cathode": "battery-cell", "electrolyte": "battery-cell"
        ]
        let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        let edges = parents.compactMap { child, parent -> SupplyChainBracketEdge? in
            guard let source = byID[parent], let target = byID[child] else { return nil }
            return .init(
                from: parent,
                to: child,
                start: .init(x: source.position.x + source.size.width / 2, y: source.position.y),
                end: .init(x: target.position.x - target.size.width / 2, y: target.position.y)
            )
        }
        return .init(nodes: all, edges: edges, parents: parents)
    }()

    private static func node(_ id: String, _ title: String, _ subtitle: String, _ symbol: String, _ tint: Color, _ x: CGFloat, _ y: CGFloat, _ size: CGSize) -> SupplyChainBracketNode {
        .init(id: id, title: title, subtitle: subtitle, symbol: symbol, tint: tint, position: .init(x: x, y: y), size: size)
    }
}

#Preview {
    SupplyChainBracketHomeView()
}
