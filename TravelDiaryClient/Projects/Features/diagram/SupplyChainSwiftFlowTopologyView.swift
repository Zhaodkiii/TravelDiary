import SwiftUI

/// An interactive topology backed by the local SwiftFlowNew implementation.
///
/// The view deliberately keeps the graph data local for now. Replacing the
/// sample arrays with the supply-chain repository response does not require a
/// change to the canvas or node UI.
struct SupplyChainSwiftFlowTopologyView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var nodes = SupplyChainFlowNodeData.sampleNodes
    @State private var edges = SupplyChainFlowNodeData.sampleEdges
    @State private var selectedNode: SupplyChainFlowNodeData?

    private let theme = SwiftFlowTheme(
        edgeColor: Color.white.opacity(0.24),
        edgeSelectedColor: SupplyChainFlowColors.cyan,
        edgeWidth: 1.5,
        edgeSelectedWidth: 3,
        nodeBackgroundColor: SupplyChainFlowColors.card,
        nodeSelectedBorderColor: SupplyChainFlowColors.cyan,
        nodeSelectedBorderWidth: 2,
        handleColor: SupplyChainFlowColors.cyan,
        handleBorderColor: SupplyChainFlowColors.background,
        canvasBackgroundColor: SupplyChainFlowColors.background,
        gridColor: Color.white.opacity(0.035),
        gridSpacing: 24,
        edgeLabelColor: .white,
        edgeLabelBackgroundColor: SupplyChainFlowColors.panel
    )

    var body: some View {
        ZStack {
            SupplyChainFlowColors.background.ignoresSafeArea()
            VStack(spacing: 0) {
                navigationBar
                contextBar
                graphCanvas
            }
        }
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $selectedNode) { node in
            SupplyChainFlowSupplierSheet(node: node)
        }
    }

    private var navigationBar: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.title3.weight(.semibold))
                    .frame(width: 40, height: 40)
            }
            .accessibilityLabel("返回")

            VStack(alignment: .leading, spacing: 2) {
                Text("SwiftFlow 供应链图谱")
                    .font(.headline.weight(.bold))
                Text("图片节点 · 可缩放 · 点击查看供应商")
                    .font(.caption)
                    .foregroundStyle(SupplyChainFlowColors.secondaryText)
            }
            Spacer()
            Button { } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.body.weight(.semibold))
                    .frame(width: 40, height: 40)
            }
            .accessibilityLabel("导出图谱")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }

    private var contextBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "car.side.fill")
                .foregroundStyle(SupplyChainFlowColors.cyan)
            Text("小米 SU7")
                .font(.subheadline.weight(.semibold))
            Text("· 从整车到原料")
                .font(.subheadline)
                .foregroundStyle(SupplyChainFlowColors.secondaryText)
            Spacer()
            Text("4 层级")
                .font(.caption.weight(.medium))
                .foregroundStyle(SupplyChainFlowColors.secondaryText)
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(SupplyChainFlowColors.panel, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(SupplyChainFlowColors.border, lineWidth: 1)
        }
        .padding(.horizontal, 14)
        .padding(.top, 4)
    }

    private var graphCanvas: some View {
        SwiftFlow(
            nodes: nodes,
            edges: edges,
            nodesDraggable: false,
            nodesConnectable: false,
            elementsSelectable: true,
            panOnDrag: true,
            zoomOnPinch: true,
            zoomOnDoubleClick: true,
            backgroundVariant: .dots,
            theme: theme,
            colorMode: .dark,
            fitView: true,
            fitViewOptions: FitViewOptions(padding: 0.18, minZoom: 0.55, maxZoom: 1.25),
            onSelectionChange: { selected, _ in
                if let node = selected.first {
                    selectedNode = node.data
                }
            },
            onNodeClick: { node in
                selectedNode = node.data
            }
        ) { node in
            SupplyChainFlowNodeCard(node: node)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 8)
    }
}

private struct SupplyChainFlowNodeCard: View {
    let node: Node<SupplyChainFlowNodeData>

    var body: some View {
        HStack(spacing: 10) {
            Handle(nodeId: node.id, id: "target", type: .target, position: .left, color: node.data.tint)
            Image(systemName: node.data.symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(node.data.tint)
                .frame(width: 42, height: 42)
                .background(node.data.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(node.data.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(node.data.subtitle)
                    .font(.caption2)
                    .foregroundStyle(SupplyChainFlowColors.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if node.data.evidence != nil {
                Text(node.data.evidence!)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(node.data.tint)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(node.data.tint.opacity(0.14), in: Capsule())
            }
            Handle(nodeId: node.id, id: "source", type: .source, position: .right, color: node.data.tint)
        }
        .padding(.horizontal, 12)
        .frame(width: node.data.width, height: 76)
        .background(SupplyChainFlowColors.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(node.selected ? node.data.tint : node.data.tint.opacity(0.46), lineWidth: node.selected ? 2 : 1)
        }
        .shadow(color: node.data.tint.opacity(node.selected ? 0.45 : 0.12), radius: node.selected ? 14 : 7)
    }
}

private struct SupplyChainFlowLegend: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("证据等级")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
            legendRow("A", "确证", SupplyChainFlowColors.orange)
            legendRow("B", "强佐证", SupplyChainFlowColors.cyan)
            legendRow("C", "待核验", SupplyChainFlowColors.blue)
        }
        .padding(12)
        .background(SupplyChainFlowColors.panel.opacity(0.94), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(SupplyChainFlowColors.border, lineWidth: 1)
        }
    }

    private func legendRow(_ key: String, _ title: String, _ color: Color) -> some View {
        HStack(spacing: 7) {
            Text(key)
                .font(.caption2.weight(.bold))
                .frame(width: 20, height: 20)
                .background(color, in: Circle())
            Text(title)
                .font(.caption2)
                .foregroundStyle(SupplyChainFlowColors.secondaryText)
        }
    }
}

private struct SupplyChainFlowSupplierSheet: View {
    let node: SupplyChainFlowNodeData
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(node.title).font(.title3.weight(.bold))
                            Text(node.subtitle).font(.subheadline).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: node.symbol)
                            .foregroundStyle(node.tint)
                    }
                }
                Section("关联供应商") {
                    ForEach(node.suppliers, id: \.self) { supplier in
                        HStack {
                            Text(supplier).fontWeight(.medium)
                            Spacer()
                            Text(node.evidence ?? "待核验")
                                .font(.caption)
                                .foregroundStyle(node.tint)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .navigationTitle("供应商路径")
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

private struct SupplyChainFlowNodeData: Equatable, @unchecked Sendable, Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
    let position: SwiftFlowXYPosition
    let width: CGFloat
    let evidence: String?
    let suppliers: [String]

    nonisolated static func == (lhs: SupplyChainFlowNodeData, rhs: SupplyChainFlowNodeData) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title && lhs.subtitle == rhs.subtitle && lhs.symbol == rhs.symbol && lhs.position == rhs.position && lhs.width == rhs.width && lhs.evidence == rhs.evidence && lhs.suppliers == rhs.suppliers
    }

    static let sampleNodes: [Node<SupplyChainFlowNodeData>] = [
        node("vehicle", "小米 SU7", "整车 · 2024款", "car.side.fill", SupplyChainFlowColors.cyan, 140, 270, 200, "A", ["小米汽车"]),
        node("battery", "动力电池", "电芯 · 电池包 · BMS", "battery.100percent", SupplyChainFlowColors.green, 460, 100, 240, "A", ["宁德时代", "弗迪电池", "中创新航"]),
        node("drive", "电驱系统", "电机 · 电控 · 减速器", "gearshape.2.fill", SupplyChainFlowColors.cyan, 460, 250, 240, "B", ["汇川技术", "联合汽车电子"]),
        node("adas", "智能驾驶", "芯片 · 传感器 · 算法", "sensor.tag.radiowaves.forward.fill", SupplyChainFlowColors.purple, 460, 400, 240, "B", ["地平线", "速腾聚创", "禾赛科技"]),
        node("cell", "动力电芯", "三元 / 磷酸铁锂", "rectangle.3.group.fill", SupplyChainFlowColors.orange, 820, 100, 220, "A", ["宁德时代", "亿纬锂能"]),
        node("pack", "电池包 / CTB", "结构集成 · 热管理", "shippingbox.fill", SupplyChainFlowColors.green, 820, 250, 220, "B", ["宁德时代", "弗迪电池"]),
        node("sic", "功率半导体", "IGBT · SiC", "cpu.fill", SupplyChainFlowColors.blue, 820, 400, 220, "C", ["斯达半导", "时代电气"]),
        node("graphite", "负极材料", "人造石墨", "circle.hexagongrid.fill", SupplyChainFlowColors.orange, 1160, 100, 220, "A", ["尚太科技", "贝特瑞", "杉杉股份"]),
        node("electrolyte", "电解液", "电池关键原料", "drop.fill", SupplyChainFlowColors.muted, 1160, 250, 220, "C", ["天赐材料", "新宙邦"]),
        node("magnet", "高性能磁钢", "电驱关键材料", "cube.fill", SupplyChainFlowColors.muted, 1160, 400, 220, "B", ["金力永磁", "中科三环"])
    ]

    static let sampleEdges: [SwiftFlowEdge<SupplyChainFlowEmptyEdgeData>] = [
        edge("vehicle-battery", "vehicle", "battery", true), edge("vehicle-drive", "vehicle", "drive", false), edge("vehicle-adas", "vehicle", "adas", false),
        edge("battery-cell", "battery", "cell", true), edge("battery-pack", "battery", "pack", false), edge("drive-sic", "drive", "sic", false),
        edge("cell-graphite", "cell", "graphite", true), edge("pack-electrolyte", "pack", "electrolyte", false), edge("sic-magnet", "sic", "magnet", false)
    ]

    private static func node(_ id: String, _ title: String, _ subtitle: String, _ symbol: String, _ tint: Color, _ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ evidence: String?, _ suppliers: [String]) -> Node<SupplyChainFlowNodeData> {
        let data = SupplyChainFlowNodeData(id: id, title: title, subtitle: subtitle, symbol: symbol, tint: tint, position: SwiftFlowXYPosition(x: x, y: y), width: width, evidence: evidence, suppliers: suppliers)
        return Node(id: id, position: data.position, data: data, draggable: false, connectable: false, sourcePosition: .right, targetPosition: .left)
    }

    private static func edge(_ id: String, _ source: String, _ target: String, _ highlighted: Bool) -> SwiftFlowEdge<SupplyChainFlowEmptyEdgeData> {
        SwiftFlowEdge(id: id, source: source, target: target, type: .smoothstep, selected: highlighted, markerEnd: .arrowClosed, style: EdgeStyle(strokeColor: highlighted ? SupplyChainFlowColors.cyan : Color.white.opacity(0.24), strokeWidth: highlighted ? 3 : 1.5, opacity: highlighted ? 1 : 0.7))
    }
}


private enum SupplyChainFlowColors {
    static let background = Color(red: 0.015, green: 0.06, blue: 0.13)
    static let panel = Color(red: 0.035, green: 0.12, blue: 0.23)
    static let card = Color(red: 0.025, green: 0.10, blue: 0.19)
    static let border = Color.white.opacity(0.14)
    static let secondaryText = Color.white.opacity(0.58)
    static let cyan = Color(red: 0.25, green: 0.73, blue: 1.0)
    static let blue = Color(red: 0.20, green: 0.42, blue: 1.0)
    static let purple = Color(red: 0.77, green: 0.28, blue: 1.0)
    static let green = Color(red: 0.25, green: 0.94, blue: 0.48)
    static let orange = Color(red: 1.0, green: 0.64, blue: 0.18)
    static let muted = Color(red: 0.46, green: 0.54, blue: 0.68)
}

#Preview {
    SupplyChainSwiftFlowTopologyView()
}
