import SwiftUI

/// Single entry point for the supply-chain visualizations.
/// The heavy topology canvases are intentionally presented on demand so the
/// tab itself stays lightweight and the user chooses the reading mode first.
struct SupplyChainDiagramHomeView: View {
    @State private var presentedRoute: SupplyChainTopologyRoute?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                overview

                VStack(alignment: .leading, spacing: 12) {
                    Text("选择拓扑视图")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Color(red: 0.04, green: 0.12, blue: 0.27))

                    ForEach(SupplyChainTopologyRoute.allCases) { route in
                        topologyCard(route)
                    }
                }
            }
            .padding(20)
        }
        .background(Color(red: 0.96, green: 0.98, blue: 1.0).ignoresSafeArea())
        .fullScreenCover(item: $presentedRoute) { route in
            ZStack(alignment: .topTrailing) {
                // Each topology keeps its own original layout and navigation
                // treatment. The container only provides dismissal for the
                // full-screen presentation and does not impose a shared chrome.
                topologyView(for: route)

                Button {
                    presentedRoute = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.bold))
                        .foregroundStyle(.primary)
                        .frame(width: 36, height: 36)
                        .background(.thinMaterial, in: Circle())
                        .overlay {
                            Circle().stroke(Color.primary.opacity(0.10), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .padding(.top, 12)
                .padding(.trailing, 16)
                .accessibilityLabel("关闭拓扑页面")
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("汽车工业供应链", systemImage: "point.3.connected.trianglepath.dotted")
                .font(.title2.weight(.bold))
                .foregroundStyle(Color(red: 0.04, green: 0.12, blue: 0.27))
            Text("从整车、核心系统到部件与原料，按需打开对应链路")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var overview: some View {
        HStack(spacing: 0) {
            overviewMetric("1", "车型")
            Divider().frame(height: 34)
            overviewMetric("6", "核心系统")
            Divider().frame(height: 34)
            overviewMetric("4", "链路层级")
        }
        .padding(.vertical, 14)
        .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.blue.opacity(0.08), lineWidth: 1)
        }
    }

    private func overviewMetric(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(.blue)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func topologyCard(_ route: SupplyChainTopologyRoute) -> some View {
        Button {
            presentedRoute = route
        } label: {
            HStack(spacing: 14) {
                Image(systemName: route.symbol)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(route.tint)
                    .frame(width: 52, height: 52)
                    .background(route.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 15, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(route.title)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(Color(red: 0.04, green: 0.12, blue: 0.27))
                    Text(route.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 8)
                Image(systemName: "arrow.up.forward.app")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.blue)
            }
            .padding(16)
            .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.blue.opacity(0.10), lineWidth: 1)
            }
            .shadow(color: .blue.opacity(0.06), radius: 12, y: 5)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func topologyView(for route: SupplyChainTopologyRoute) -> some View {
        switch route {
        case .dagre:
            SupplyChainGraphHomeView()
        case .folded:
            SupplyChainBracketHomeView()
        case .industry:
            TournamentSupplyChainTabView()
        case .topology:
            SupplyChainUnifiedGraphView()
        case .swiftFlow:
            SupplyChainSwiftFlowTopologyView()
        }
    }
}

private enum SupplyChainTopologyRoute: String, CaseIterable, Identifiable {
    case dagre
    case folded
    case industry
    case topology
    case swiftFlow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dagre: return "供应链图谱"
        case .folded: return "折叠式链路"
        case .industry: return "产业链拓扑"
        case .topology: return "深色拓扑图"
        case .swiftFlow: return "SwiftFlow 互动图"
        }
    }

    var subtitle: String {
        switch self {
        case .dagre: return "查看整车、系统、部件与原料的完整关系"
        case .folded: return "初始闭合，点击分类逐层展开供应关系"
        case .industry: return "按车型与核心系统浏览产业链节点"
        case .topology: return "图片节点、证据等级与供应商路径"
        case .swiftFlow: return "可缩放拖拽的图片节点与供应商链路"
        }
    }

    var symbol: String {
        switch self {
        case .dagre: return "circle.grid.3x3.fill"
        case .folded: return "rectangle.3.group"
        case .industry: return "car.side.and.arrow.right"
        case .topology: return "circle.grid.3x3.connected.to.line.below"
        case .swiftFlow: return "arrow.triangle.branch"
        }
    }

    var tint: Color {
        switch self {
        case .dagre: return .blue
        case .folded: return .indigo
        case .industry: return .orange
        case .topology: return .indigo
        case .swiftFlow: return .cyan
        }
    }
}
