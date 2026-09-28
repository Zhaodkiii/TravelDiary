import SwiftUI

/// Mobile topology explorer with three separated reading levels:
/// product → category systems → suppliers → the selected supplier's products.
struct SupplyChainTopologyMapView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var level: TopologyLevel = .systems
    @State private var selectedSystem = "动力电池"
    @State private var selectedCompany = "宁德时代"
    @State private var zoom: CGFloat = 1

    var body: some View {
        ZStack {
            TopologyColors.background.ignoresSafeArea()
            VStack(spacing: 0) {
                navigationBar
                queryBar
                content
            }
            VStack { Spacer(); bottomControls }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
        }
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var navigationBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.title2.weight(.medium))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("返回")
            Spacer()
            Text("供应链拓扑图").font(.headline.weight(.bold))
            Spacer()
            Button { } label: {
                Label("导出", systemImage: "square.and.arrow.up")
                    .font(.subheadline.weight(.semibold))
            }
            .frame(minWidth: 64, minHeight: 44)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.top, 6)
    }

    private var queryBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(TopologyColors.secondaryText)
            Text("小米 SU7 · 从整车到原料")
                .font(.subheadline)
                .foregroundStyle(TopologyColors.secondaryText)
            Spacer()
            Image(systemName: "chevron.down")
                .font(.caption.weight(.bold))
                .foregroundStyle(TopologyColors.secondaryText)
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(TopologyColors.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(TopologyColors.border, lineWidth: 1) }
        .padding(.horizontal, 20)
        .padding(.top, 6)
    }

    private var content: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                productRoot
                TopologyConnectorLine(color: TopologyColors.cyan)
                switch level {
                case .systems: systemsLevel
                case .companies: companiesLevel
                case .products: productsLevel
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 110)
            .scaleEffect(zoom, anchor: .top)
            .animation(.easeOut(duration: 0.22), value: level)
        }
    }

    private var productRoot: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().fill(TopologyColors.cyan.opacity(0.10))
                Circle().stroke(TopologyColors.cyan, lineWidth: 2)
                    .shadow(color: TopologyColors.cyan.opacity(0.8), radius: 12)
                Image(systemName: "car.side.fill")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(TopologyColors.cyan)
            }
            .frame(width: 104, height: 104)
            Text("小米 SU7").font(.title2.weight(.bold)).foregroundStyle(.white)
            Text("纯电轿车 · 从整车到原料")
                .font(.caption)
                .foregroundStyle(TopologyColors.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }

    private var systemsLevel: some View {
        VStack(alignment: .leading, spacing: 14) {
            levelTitle("核心系统", subtitle: "选择一个系统，查看对应企业链路")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(TopologySystem.all) { system in
                    Button {
                        selectedSystem = system.title
                        level = .companies
                    } label: { TopologySystemCard(system: system) }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var companiesLevel: some View {
        VStack(alignment: .leading, spacing: 14) {
            levelTitle(selectedSystem, subtitle: "相关企业链路 · 点击企业查看内部产品")
            TopologyPathBadge(text: "小米 SU7  →  \(selectedSystem)", tint: TopologyColors.green)
            ForEach(TopologyCompany.forSystem(selectedSystem)) { company in
                Button {
                    selectedCompany = company.title
                    level = .products
                } label: { TopologyCompanyCard(company: company) }
                .buttonStyle(.plain)
            }
        }
    }

    private var productsLevel: some View {
        VStack(alignment: .leading, spacing: 14) {
            levelTitle(selectedCompany, subtitle: "企业内部产品链路")
            Button { level = .companies } label: {
                Label("返回企业链路", systemImage: "chevron.left")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TopologyColors.cyan)
            }
            .buttonStyle(.plain)
            TopologyPathBadge(text: "小米 SU7  →  \(selectedSystem)  →  \(selectedCompany)", tint: TopologyColors.orange)
            ForEach(TopologyProduct.forCompany(selectedCompany)) { product in
                TopologyProductCard(product: product)
            }
        }
    }

    private func levelTitle(_ title: String, subtitle: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            if level != .systems {
                Button {
                    level = level == .products ? .companies : .systems
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(TopologyColors.cyan)
                        .frame(width: 28, height: 28)
                        .background(TopologyColors.cyan.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(level == .products ? "返回企业链路" : "返回核心系统")
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.title3.weight(.bold)).foregroundStyle(.white)
                Text(subtitle).font(.caption).foregroundStyle(TopologyColors.secondaryText)
            }
            Spacer()
            Text(level.label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(TopologyColors.cyan)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(TopologyColors.cyan.opacity(0.12), in: Capsule())
        }
    }

    private var bottomControls: some View {
        HStack(spacing: 10) {
            topologyControl("line.3.horizontal.decrease.circle", "筛选") { }
            topologyControl("arrow.down.right.and.arrow.up.left", "切换层级") { zoom = zoom == 1 ? 0.88 : 1 }
            topologyControl("viewfinder", "全屏") { zoom = 1 }
        }
        .padding(10)
        .background(TopologyColors.panel.opacity(0.96), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(TopologyColors.border, lineWidth: 1) }
    }

    private func topologyControl(_ symbol: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(TopologyColors.control, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct TopologyConnectorLine: View {
    let color: Color
    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(color.opacity(0.78)).frame(width: 2, height: 20)
            Circle().fill(color).frame(width: 7, height: 7).shadow(color: color, radius: 5)
            Rectangle().fill(color.opacity(0.78)).frame(width: 2, height: 14)
        }
        .frame(height: 41)
    }
}

private struct TopologySystemCard: View {
    let system: TopologySystem
    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().fill(system.tint.opacity(0.12))
                Circle().stroke(system.tint, lineWidth: 1.8).shadow(color: system.tint.opacity(0.7), radius: 8)
                Image(systemName: system.symbol).font(.title2.weight(.medium)).foregroundStyle(system.tint)
            }
            .frame(width: 76, height: 76)
            Text(system.title).font(.subheadline.weight(.bold)).foregroundStyle(.white)
            Text(system.subtitle).font(.caption2).foregroundStyle(TopologyColors.secondaryText).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(TopologyColors.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(system.tint.opacity(0.55), lineWidth: 1) }
    }
}

private struct TopologyCompanyCard: View {
    let company: TopologyCompany
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(company.tint.opacity(0.14))
                Image(systemName: "building.2.fill").font(.title2).foregroundStyle(company.tint)
            }
            .frame(width: 54, height: 54)
            VStack(alignment: .leading, spacing: 4) {
                Text(company.title).font(.headline.weight(.bold)).foregroundStyle(.white)
                Text(company.subtitle).font(.caption).foregroundStyle(TopologyColors.secondaryText)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 5) {
                Text(company.evidence).font(.caption.weight(.bold)).foregroundStyle(company.tint)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(company.tint.opacity(0.12), in: Capsule())
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(TopologyColors.secondaryText)
            }
        }
        .padding(14)
        .background(TopologyColors.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(company.tint.opacity(0.55), lineWidth: 1) }
    }
}

private struct TopologyProductCard: View {
    let product: TopologyProduct
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(product.tint.opacity(0.14))
                Image(systemName: product.symbol).font(.title2).foregroundStyle(product.tint)
            }
            .frame(width: 54, height: 54)
            VStack(alignment: .leading, spacing: 4) {
                Text(product.title).font(.headline.weight(.bold)).foregroundStyle(.white)
                Text(product.subtitle).font(.caption).foregroundStyle(TopologyColors.secondaryText)
            }
            Spacer()
            Image(systemName: "arrow.up.right").font(.caption.weight(.bold)).foregroundStyle(product.tint)
        }
        .padding(14)
        .background(TopologyColors.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(product.tint.opacity(0.45), lineWidth: 1) }
    }
}

private struct TopologyPathBadge: View {
    let text: String
    let tint: Color
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(tint).frame(width: 7, height: 7)
            Text(text).font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.82)).lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 12).frame(height: 34)
        .background(tint.opacity(0.10), in: Capsule())
        .overlay { Capsule().stroke(tint.opacity(0.35), lineWidth: 1) }
    }
}

private enum TopologyLevel: Equatable {
    case systems, companies, products
    var label: String {
        switch self { case .systems: "产品"; case .companies: "企业"; case .products: "产品链路" }
    }
}

private struct TopologySystem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color

    static let all: [TopologySystem] = [
        .init(id: "battery", title: "动力电池", subtitle: "电芯 · 电池包 · BMS", symbol: "battery.100percent", tint: TopologyColors.green),
        .init(id: "drive", title: "电驱系统", subtitle: "电机 · 电控 · 减速器", symbol: "gearshape.2.fill", tint: TopologyColors.cyan),
        .init(id: "smart", title: "智能驾驶", subtitle: "感知 · 决策 · 控制", symbol: "sensor.tag.radiowaves.forward.fill", tint: TopologyColors.purple),
        .init(id: "body", title: "车身系统", subtitle: "结构 · 内外饰 · 轻量化", symbol: "car.side.fill", tint: TopologyColors.orange),
        .init(id: "cockpit", title: "电子座舱", subtitle: "显示 · 交互 · 音响", symbol: "rectangle.on.rectangle", tint: .teal),
        .init(id: "chassis", title: "底盘系统", subtitle: "制动 · 转向 · 悬架", symbol: "car.rear.and.tire.marks", tint: TopologyColors.blue)
    ]
}

private struct TopologyCompany: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let evidence: String
    let tint: Color

    static func forSystem(_ system: String) -> [TopologyCompany] {
        switch system {
        case "动力电池": return [
            .init(id: "catl", title: "宁德时代", subtitle: "动力电池 · 电芯与电池包", evidence: "A 确证", tint: TopologyColors.orange),
            .init(id: "fudi", title: "弗迪电池", subtitle: "动力电池 · 电芯与CTP", evidence: "A 确证", tint: TopologyColors.blue),
            .init(id: "calb", title: "中创新航", subtitle: "动力电池 · 电芯与系统", evidence: "B 强佐证", tint: TopologyColors.cyan),
            .init(id: "eve", title: "亿纬锂能", subtitle: "动力电池 · 大圆柱电芯", evidence: "B 强佐证", tint: TopologyColors.green)
        ]
        case "电驱系统": return [
            .init(id: "inovance", title: "汇川技术", subtitle: "驱动电机 · 电控系统", evidence: "A 确证", tint: TopologyColors.cyan),
            .init(id: "uaes", title: "联合汽车电子", subtitle: "电控 · 功率模块", evidence: "B 强佐证", tint: TopologyColors.blue)
        ]
        case "智能驾驶": return [
            .init(id: "hesai", title: "禾赛科技", subtitle: "激光雷达 · 感知系统", evidence: "A 确证", tint: TopologyColors.purple),
            .init(id: "robosense", title: "速腾聚创", subtitle: "激光雷达 · 感知系统", evidence: "B 强佐证", tint: TopologyColors.blue)
        ]
        default: return [
            .init(id: "bosch", title: "博世", subtitle: "制动 · 转向 · 底盘系统", evidence: "B 强佐证", tint: TopologyColors.orange),
            .init(id: "tuopu", title: "拓普集团", subtitle: "轻量化结构 · 底盘部件", evidence: "B 强佐证", tint: TopologyColors.green)
        ]
        }
    }
}

private struct TopologyProduct: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color

    static func forCompany(_ company: String) -> [TopologyProduct] {
        switch company {
        case "宁德时代": return [
            .init(id: "qilin", title: "麒麟电池", subtitle: "第三代CTP · 高能量密度", symbol: "battery.100percent", tint: TopologyColors.orange),
            .init(id: "cell", title: "动力电芯", subtitle: "三元锂电芯 · 磷酸铁锂电芯", symbol: "square.stack.3d.up.fill", tint: TopologyColors.cyan),
            .init(id: "bms", title: "BMS 电池管理系统", subtitle: "热管理 · 安全监控 · SOC估算", symbol: "cpu.fill", tint: TopologyColors.green)
        ]
        case "弗迪电池": return [
            .init(id: "blade", title: "刀片电池", subtitle: "磷酸铁锂 · 高安全性", symbol: "rectangle.stack.fill", tint: TopologyColors.blue),
            .init(id: "ctb", title: "CTB 电池包", subtitle: "电池车身一体化", symbol: "shippingbox.fill", tint: TopologyColors.cyan)
        ]
        case "汇川技术": return [
            .init(id: "motor", title: "永磁同步电机", subtitle: "高效驱动 · 扁线定子", symbol: "gearshape.2.fill", tint: TopologyColors.cyan),
            .init(id: "inverter", title: "电机控制器", subtitle: "功率模块 · 控制算法", symbol: "cpu.fill", tint: TopologyColors.blue),
            .init(id: "reducer", title: "减速器", subtitle: "齿轮传动 · 精密加工", symbol: "circle.hexagongrid.fill", tint: TopologyColors.green)
        ]
        default: return [
            .init(id: "sensor", title: "核心传感器", subtitle: "环境感知与信号采集", symbol: "sensor.tag.radiowaves.forward.fill", tint: TopologyColors.purple),
            .init(id: "controller", title: "域控制器", subtitle: "数据融合 · 决策控制", symbol: "cpu.fill", tint: TopologyColors.blue)
        ]
        }
    }
}

private enum TopologyColors {
    static let background = Color(red: 0.015, green: 0.06, blue: 0.13)
    static let panel = Color(red: 0.035, green: 0.12, blue: 0.23)
    static let card = Color(red: 0.025, green: 0.10, blue: 0.19)
    static let control = Color(red: 0.05, green: 0.16, blue: 0.29)
    static let border = Color.white.opacity(0.14)
    static let secondaryText = Color.white.opacity(0.58)
    static let cyan = Color(red: 0.25, green: 0.73, blue: 1.0)
    static let blue = Color(red: 0.20, green: 0.42, blue: 1.0)
    static let purple = Color(red: 0.77, green: 0.28, blue: 1.0)
    static let green = Color(red: 0.25, green: 0.94, blue: 0.48)
    static let orange = Color(red: 1.0, green: 0.64, blue: 0.18)
}

#Preview { SupplyChainTopologyMapView() }
