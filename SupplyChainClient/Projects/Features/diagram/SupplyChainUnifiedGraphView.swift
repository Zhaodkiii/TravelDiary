import SwiftUI
import UIKit

/// The production graph surface: one continuous, image-first canvas that can
/// be panned in both directions and expanded one active branch at a time.
struct SupplyChainUnifiedGraphView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var increaseContrast = UIAccessibility.isDarkerSystemColorsEnabled

    @State private var activeSystemID: String?
    @State private var activeCompanyID: String?
    @State private var expandedIDs: Set<String> = []
    @State private var selectedNode: SupplyChainNode?
    @State private var zoom: CGFloat = 1
    @State private var committedZoom: CGFloat = 1
    @State private var loadState: UnifiedGraphLoadState = .loaded

    private let graph = XiaomiSU7SupplyChain.graph

    var body: some View {
        ZStack {
            UnifiedGraphTheme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                graphContent
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(nil)
        .sheet(item: $selectedNode) { node in
            UnifiedGraphDetailSheet(node: node, graph: graph)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .onAppear {
            resetTransientState()
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3.weight(.semibold))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("返回")

                VStack(spacing: 2) {
                    Text("供应链图谱")
                        .font(.headline.weight(.bold))
                    Text("小米 SU7 · 从整车到原料")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                Button { } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.title3.weight(.semibold))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("导出图谱")
            }
            .foregroundStyle(UnifiedGraphTheme.primaryText)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                Text("小米 SU7 · 从整车到原料")
                    .font(.subheadline)
                Spacer()
                Text("A/B/C/D")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .frame(height: 46)
            .background(UnifiedGraphTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(UnifiedGraphTheme.border(for: increaseContrast), lineWidth: increaseContrast ? 1.5 : 1)
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 6)
        .padding(.bottom, 8)
        .background(UnifiedGraphTheme.background.opacity(0.96))
    }

    @ViewBuilder
    private var graphContent: some View {
        switch loadState {
        case .loading:
            UnifiedGraphSkeletonView()
        case .empty:
            UnifiedGraphStateView(symbol: "car.2", title: "暂无可达供应链", message: "当前车型没有可展示的关系", actionTitle: "返回车型") { dismiss() }
        case .error(let message):
            UnifiedGraphStateView(symbol: "exclamationmark.triangle", title: "图谱加载失败", message: message, actionTitle: "重试") { loadState = .loaded }
        case .loaded:
            canvas
        }
    }

    private var canvas: some View {
        GeometryReader { proxy in
            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                graphCanvas
                    .scaleEffect(zoom, anchor: .top)
                    .frame(width: max(proxy.size.width, graphCanvasWidth), alignment: .topLeading)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 18)
            }
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { value in zoom = min(max(committedZoom * value, 0.65), 2.4) }
                    .onEnded { _ in committedZoom = zoom }
            )
            .overlay(alignment: .bottom) { canvasLegend }
        }
    }

    private var graphCanvasWidth: CGFloat {
        let count = max(3, visibleSystemNodes.count)
        return CGFloat(count) * 184 + 32
    }

    private var graphCanvas: some View {
        VStack(spacing: 0) {
            UnifiedGraphRootNode(node: graph.node(id: "xiaomi-su7")!, onInfo: { selectedNode = graph.node(id: "xiaomi-su7") })
            UnifiedGraphBranchConnector(color: .cyan)
            horizontalNodeRail(visibleSystemNodes, minHeight: 176)

            if let systemID = activeSystemID, let system = graph.node(id: systemID) {
                UnifiedGraphBranchConnector(color: color(for: system))
                sectionTitle("\(system.title) · 相关企业", subtitle: "点击企业展开内部产品链路")
                horizontalNodeRail(companies(for: system), minHeight: 166)

                if let companyID = activeCompanyID, let company = company(for: companyID, in: system) {
                    UnifiedGraphBranchConnector(color: color(for: system))
                    sectionTitle("\(company.title) · 企业产品链路", subtitle: "从产品继续向下查看部件与原料")
                    horizontalNodeRail(products(for: system), minHeight: 150)
                    horizontalNodeRail(materials(for: system), minHeight: 150)
                }
            }
            Spacer(minLength: 160)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func horizontalNodeRail(_ nodes: [SupplyChainNode], minHeight: CGFloat) -> some View {
        LazyHStack(alignment: .top, spacing: 14) {
            ForEach(nodes) { node in
                UnifiedGraphNodeCard(
                    node: node,
                    isActive: expandedIDs.contains(node.id),
                    isDimmed: isDimmed(node),
                    contrast: increaseContrast,
                    onTap: { handleTap(node) },
                    onInfo: { selectedNode = node }
                )
                .frame(width: 166, height: minHeight)
            }
        }
        .frame(minWidth: max(graphCanvasWidth - 36, CGFloat(nodes.count) * 180), alignment: .leading)
        .padding(.horizontal, 2)
    }

    private var visibleSystemNodes: [SupplyChainNode] {
        graph.nodes.filter { $0.kind == .system }
    }

    private func companies(for system: SupplyChainNode) -> [SupplyChainNode] {
        let ids = system.companies.map(\.id)
        return ids.enumerated().map { index, id in
            SupplyChainNode(id: id, kind: .company, title: system.companies[index].name,
                            subtitle: system.companies[index].suppliedProduct,
                            symbol: "building.2.fill", accent: system.accent,
                            companies: [])
        }
    }

    private func company(for id: String, in system: SupplyChainNode) -> SupplyChainNode? {
        companies(for: system).first(where: { $0.id == id })
    }

    private func products(for system: SupplyChainNode) -> [SupplyChainNode] {
        let children = graph.edges.filter { $0.sourceID == system.id }.compactMap { graph.node(id: $0.targetID) }
        return children.filter { $0.kind == .component }
    }

    private func materials(for system: SupplyChainNode) -> [SupplyChainNode] {
        let components = products(for: system).map(\.id)
        return graph.edges.filter { components.contains($0.sourceID) }.compactMap { graph.node(id: $0.targetID) }.filter { $0.kind == .material }
    }

    private func handleTap(_ node: SupplyChainNode) {
        let animation: Animation? = reduceMotion ? nil : .snappy(duration: 0.28)
        withAnimation(animation) {
            switch node.kind {
            case .system:
                activeSystemID = activeSystemID == node.id ? nil : node.id
                activeCompanyID = nil
                expandedIDs = activeSystemID.map { [$0] } ?? []
            case .company:
                activeCompanyID = activeCompanyID == node.id ? nil : node.id
                expandedIDs = Set([activeSystemID, activeCompanyID].compactMap { $0 })
            default:
                if expandedIDs.contains(node.id) { expandedIDs.remove(node.id) } else { expandedIDs.insert(node.id) }
            }
        }
    }

    private func isDimmed(_ node: SupplyChainNode) -> Bool {
        if node.kind == .system { return activeSystemID != nil && activeSystemID != node.id }
        if node.kind == .company { return activeCompanyID != nil && activeCompanyID != node.id }
        return false
    }

    private func color(for node: SupplyChainNode) -> Color {
        switch node.accent {
        case .blue: return .blue
        case .orange: return .orange
        case .green: return .green
        case .purple: return .purple
        case .graphite: return .indigo
        }
    }

    private func sectionTitle(_ title: String, subtitle: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title3.weight(.bold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("左右滑动").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        }
        .foregroundStyle(UnifiedGraphTheme.primaryText)
        .padding(.top, 22)
        .padding(.bottom, 10)
    }

    private var canvasLegend: some View {
        HStack(spacing: 12) {
            legend("A", "确证", .orange)
            legend("B", "强佐证", .blue)
            legend("C", "待核验", .indigo)
            legend("D", "推断", .green)
        }
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay { Capsule().stroke(UnifiedGraphTheme.border(for: increaseContrast), lineWidth: 1) }
        .padding(.bottom, 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("证据图例：A 确证，B 强佐证，C 待核验，D 推断")
    }

    private func legend(_ level: String, _ title: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Text(level).foregroundStyle(color)
            Text(title).foregroundStyle(.secondary)
        }
    }

    private func resetTransientState() {
        activeSystemID = nil
        activeCompanyID = nil
        expandedIDs = []
        zoom = 1
        committedZoom = 1
    }
}

private enum UnifiedGraphLoadState: Equatable {
    case loading
    case loaded
    case empty
    case error(String)
}

private enum UnifiedGraphTheme {
    static var background: Color { Color(uiColor: .systemBackground) }
    static var surface: Color { Color(uiColor: .secondarySystemBackground) }
    static var primaryText: Color { Color(uiColor: .label) }
    static func border(for highContrast: Bool) -> Color { Color(uiColor: .separator).opacity(highContrast ? 0.95 : 0.55) }
}

private struct UnifiedGraphRootNode: View {
    let node: SupplyChainNode
    let onInfo: () -> Void
    var body: some View {
        HStack(spacing: 16) {
            UnifiedGraphImage(symbol: node.symbol, tint: .cyan, size: 84)
            VStack(alignment: .leading, spacing: 5) {
                Text("当前车型").font(.caption.weight(.bold)).foregroundStyle(.orange)
                Text(node.title).font(.title2.weight(.bold))
                Text(node.subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onInfo) { Image(systemName: "info.circle") }
                .buttonStyle(.plain)
                .font(.title3)
                .accessibilityLabel("查看\(node.title)详情")
        }
        .foregroundStyle(UnifiedGraphTheme.primaryText)
        .padding(18)
        .background(UnifiedGraphTheme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.cyan.opacity(0.7), lineWidth: 1.5) }
    }
}

private struct UnifiedGraphNodeCard: View {
    let node: SupplyChainNode
    let isActive: Bool
    let isDimmed: Bool
    let contrast: Bool
    let onTap: () -> Void
    let onInfo: () -> Void

    private var tint: Color {
        switch node.accent {
        case .blue: return .blue
        case .orange: return .orange
        case .green: return .green
        case .purple: return .purple
        case .graphite: return .indigo
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                UnifiedGraphImage(symbol: node.symbol, tint: tint, size: 58)
                Spacer()
                Button(action: onInfo) {
                    Image(systemName: "info.circle")
                        .font(.body.weight(.semibold))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("查看\(node.title)详情")
            }
            Spacer(minLength: 2)
            Text(node.title).font(.headline.weight(.bold)).lineLimit(2)
            Text(node.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            HStack(spacing: 6) {
                Text(node.kind.title).font(.caption2.weight(.semibold))
                Spacer()
                Image(systemName: isActive ? "chevron.up" : "chevron.down").font(.caption.weight(.bold))
            }
            .foregroundStyle(tint)
        }
        .padding(13)
        .foregroundStyle(UnifiedGraphTheme.primaryText)
        .background(UnifiedGraphTheme.surface.opacity(isDimmed ? 0.42 : 1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(tint.opacity(isDimmed ? 0.25 : (contrast ? 0.95 : 0.7)), lineWidth: isActive || contrast ? 2 : 1)
        }
        .opacity(isDimmed ? 0.48 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(node.title)，\(node.kind.title)")
        .accessibilityHint(isActive ? "已展开，双击收起" : "双击展开链路")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

private struct UnifiedGraphImage: View {
    let symbol: String
    let tint: Color
    let size: CGFloat
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 15, style: .continuous).fill(tint.opacity(0.12))
            Image(systemName: symbol).font(.system(size: size * 0.42, weight: .medium)).foregroundStyle(tint)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct UnifiedGraphBranchConnector: View {
    let color: Color
    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(color.opacity(0.75)).frame(width: 2, height: 22)
            Circle().fill(color).frame(width: 8, height: 8).shadow(color: color, radius: 5)
            Rectangle().fill(color.opacity(0.75)).frame(width: 2, height: 16)
        }
        .frame(height: 46)
        .accessibilityHidden(true)
    }
}

private struct UnifiedGraphDetailSheet: View {
    let node: SupplyChainNode
    let graph: SupplyChainGraph
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("节点") {
                    LabeledContent("名称", value: node.title)
                    LabeledContent("类型", value: node.kind.title)
                    LabeledContent("说明", value: node.subtitle)
                }
                if !node.companies.isEmpty {
                    Section("相关供应商") {
                        ForEach(node.companies) { company in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(company.name).font(.headline)
                                Text("\(company.suppliedProduct) · \(company.relationship)")
                                    .font(.subheadline).foregroundStyle(.secondary)
                                Text("证据：\(company.evidence)").font(.caption).foregroundStyle(.orange)
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }
                Section("关系说明") {
                    Text("该节点属于小米 SU7 可达供应链。关系来源和车型范围将在 JSON 数据接入后显示。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("节点详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

private struct UnifiedGraphSkeletonView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                ForEach(0..<7, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 18).fill(.secondary.opacity(0.12)).frame(height: 110)
                }
            }
            .padding(20)
            .redacted(reason: .placeholder)
        }
        .accessibilityLabel("正在加载供应链图谱")
    }
}

private struct UnifiedGraphStateView: View {
    let symbol: String
    let title: String
    let message: String
    let actionTitle: String
    let action: () -> Void
    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(message)
        } actions: {
            Button(actionTitle, action: action)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    SupplyChainUnifiedGraphView()
}
