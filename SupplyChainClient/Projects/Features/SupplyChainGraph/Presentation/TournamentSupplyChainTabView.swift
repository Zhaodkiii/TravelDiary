import SwiftUI

/// Mobile supply-chain explorer built on the generic left-to-right bracket engine.
/// The graph contains classifications only; company details are presented separately.
struct TournamentSupplyChainTabView: View {
    private let graph = XiaomiSU7SupplyChain.graph

    @State private var selectedNodeID = "anode"
    @State private var presentedNode: SupplyChainNode?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            systemShortcuts

            SupplyChainBracketGraphView(
                graph: graph,
                selectedNodeID: $selectedNodeID,
                onNodeTap: handleNodeTap
            )
            .frame(maxHeight: .infinity)
            .padding(.horizontal, 12)

            footerHint
        }
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(Color(red: 0.985, green: 0.99, blue: 1).ignoresSafeArea())
        .sheet(item: $presentedNode) { node in
            SupplyChainCompanySheet(node: node)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("小米 SU7 完整供应链")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color(red: 0.04, green: 0.12, blue: 0.27))
                Text("从整车到系统、部件与上游材料")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("从左向右")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.blue)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.09), in: Capsule())
        }
        .padding(.horizontal, 18)
    }

    private var systemShortcuts: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(graph.nodes.filter { $0.kind == .system }) { node in
                    Button {
                        selectedNodeID = node.id
                        presentedNode = node
                    } label: {
                        Label(node.title, systemImage: node.symbol)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(selectedNodeID == node.id ? .white : Color(red: 0.08, green: 0.18, blue: 0.34))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 8)
                            .background(selectedNodeID == node.id ? Color.blue : Color.white, in: Capsule())
                            .overlay {
                                if selectedNodeID != node.id {
                                    Capsule().stroke(Color.black.opacity(0.08), lineWidth: 1)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 2)
        }
    }

    private var footerHint: some View {
        HStack(spacing: 7) {
            Image(systemName: "hand.draw.fill")
                .foregroundStyle(Color.blue)
            Text("横向拖动查看完整链路 · 点击分类查看相关企业")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 18)
    }

    private func handleNodeTap(_ node: SupplyChainNode) {
        presentedNode = node
    }
}

private struct SupplyChainCompanySheet: View {
    let node: SupplyChainNode

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    nodeSummary
                    metrics
                    supplierSection
                    evidenceNotice
                }
                .padding(18)
            }
            .background(Color(red: 0.97, green: 0.98, blue: 0.995))
            .navigationTitle("相关企业")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private var nodeSummary: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.blue.opacity(0.10))
                Image(systemName: node.symbol)
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(Color.blue)
                    .symbolRenderingMode(.hierarchical)
            }
            .frame(width: 76, height: 76)

            VStack(alignment: .leading, spacing: 5) {
                Text(node.kind.title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.blue)
                Text(node.title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Color(red: 0.04, green: 0.12, blue: 0.27))
                Text(node.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var metrics: some View {
        HStack(spacing: 0) {
            metric("\(node.companies.count)", "已收录企业")
            Divider().frame(height: 34)
            metric("\(node.companies.filter(\.isCoreSupplier).count)", "核心供应商")
            Divider().frame(height: 34)
            metric(verifiedCount, "高可信证据")
        }
        .padding(.vertical, 14)
        .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var supplierSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("供应企业")
                    .font(.headline.weight(.bold))
                Spacer()
                Text("按关联可信度排序")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if node.companies.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "building.2.crop.circle")
                        .font(.system(size: 34))
                        .foregroundStyle(Color.secondary)
                    Text("企业信息待补充")
                        .font(.headline)
                    Text("当前仅建立了分类链路，后续可由 Excel 或数据库补充供应关系。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .padding(.horizontal, 20)
                .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                ForEach(node.companies) { company in
                    SupplyChainCompanyRow(company: company)
                }
            }
        }
    }

    private var evidenceNotice: some View {
        Label("企业仅在详情层展示，链路图保持为分类视图；证据等级用于区分公开披露与待核验数据。", systemImage: "checkmark.shield.fill")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(14)
            .background(Color.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var verifiedCount: String {
        "\(node.companies.filter { $0.evidence.hasPrefix("A") }.count)"
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(Color(red: 0.04, green: 0.12, blue: 0.27))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct SupplyChainCompanyRow: View {
    let company: SupplyChainCompany

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top, spacing: 12) {
                Text(String(company.name.prefix(1)))
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(company.isCoreSupplier ? Color.blue : Color(red: 0.38, green: 0.47, blue: 0.60), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(company.name)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(Color(red: 0.05, green: 0.12, blue: 0.24))
                    if let englishName = company.englishName {
                        Text(englishName)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(company.relationship)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(company.isCoreSupplier ? Color.blue : Color.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background((company.isCoreSupplier ? Color.blue : Color.gray).opacity(0.09), in: Capsule())
            }

            Divider()

            Label(company.suppliedProduct, systemImage: "shippingbox.fill")
                .font(.subheadline.weight(.medium))
            HStack {
                Label(company.location, systemImage: "mappin.and.ellipse")
                Spacer()
                Label(company.evidence, systemImage: "doc.text.magnifyingglass")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(15)
        .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.055), lineWidth: 1)
        }
    }
}

#Preview {
    TournamentSupplyChainTabView()
}
