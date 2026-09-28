import Foundation

enum SupplyChainNodeKind: String, CaseIterable, Hashable {
    case vehicle
    case system
    case company
    case component
    case material

    var title: String {
        switch self {
        case .vehicle: return "整车"
        case .system: return "核心系统"
        case .company: return "供应企业"
        case .component: return "关键部件"
        case .material: return "上游材料"
        }
    }
}

enum SupplyChainAccent: Hashable {
    case blue
    case orange
    case green
    case purple
    case graphite
}

struct SupplyChainCompany: Identifiable, Hashable {
    let id: String
    let name: String
    let englishName: String?
    let location: String
    let suppliedProduct: String
    let relationship: String
    let evidence: String
    let isCoreSupplier: Bool
}

struct SupplyChainNode: Identifiable, Hashable {
    let id: String
    let kind: SupplyChainNodeKind
    let title: String
    let subtitle: String
    let symbol: String
    let accent: SupplyChainAccent
    let companies: [SupplyChainCompany]
}

struct SupplyChainEdge: Identifiable, Hashable {
    let sourceID: String
    let targetID: String

    var id: String { "\(sourceID)->\(targetID)" }
}

struct SupplyChainGraph: Hashable {
    let nodes: [SupplyChainNode]
    let edges: [SupplyChainEdge]

    var nodeByID: [String: SupplyChainNode] {
        Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
    }

    func node(id: String) -> SupplyChainNode? {
        nodeByID[id]
    }

    func ancestorIDs(of nodeID: String) -> Set<String> {
        var visited: Set<String> = [nodeID]
        var pending = [nodeID]
        let incoming = Dictionary(grouping: edges, by: \.targetID)

        while let current = pending.popLast() {
            for edge in incoming[current, default: []] where visited.insert(edge.sourceID).inserted {
                pending.append(edge.sourceID)
            }
        }
        return visited
    }
}

enum XiaomiSU7SupplyChain {
    static let graph = SupplyChainGraph(
        nodes: [
            node("xiaomi-su7", .vehicle, "小米 SU7", "纯电轿车 · 2024款", "car.side.fill", .orange, []),

            node("battery", .system, "动力电池", "储能与高压安全", "battery.100percent", .blue, [
                company("catl", "宁德时代", "CATL", "福建宁德", "动力电池 / 电芯", "核心供应商", "A级 · 公开披露", true),
                company("fudi", "弗迪电池", nil, "广东深圳", "动力电池", "主要供应商", "B级 · 行业资料", true)
            ]),
            node("drive", .system, "电驱系统", "动力转换与输出", "gearshape.2.fill", .purple, [
                company("inovance", "汇川技术", "INOVANCE", "广东深圳", "电驱控制器", "主要供应商", "B级 · 行业资料", true)
            ]),
            node("adas", .system, "智能驾驶", "感知 · 决策 · 执行", "sensor.tag.radiowaves.forward.fill", .blue, [
                company("nvidia", "英伟达", "NVIDIA", "美国加州", "智驾计算平台", "技术供应商", "A级 · 官方资料", true)
            ]),
            node("body", .system, "车身系统", "安全与轻量化", "car.rear.road.lane", .graphite, [
                company("baosteel", "宝钢股份", nil, "上海", "汽车板材", "材料供应商", "B级 · 行业资料", false)
            ]),
            node("cockpit", .system, "电子座舱", "交互与车载计算", "display.2", .purple, [
                company("qualcomm", "高通", "QUALCOMM", "美国加州", "座舱芯片", "技术供应商", "A级 · 官方资料", true)
            ]),
            node("chassis", .system, "底盘系统", "悬架 · 转向 · 制动", "steeringwheel", .green, [
                company("bosch", "博世", "BOSCH", "德国斯图加特", "制动与底盘控制", "系统供应商", "B级 · 行业资料", true)
            ]),

            node("cell", .component, "电芯", "能量存储核心单元", "rectangle.stack.fill", .blue, [
                company("catl-cell", "宁德时代", "CATL", "福建宁德", "三元锂电芯", "核心供应商", "A级 · 公开披露", true),
                company("eve", "亿纬锂能", "EVE", "广东惠州", "圆柱电芯", "候选供应商", "C级 · 待核验", false)
            ]),
            node("pack", .component, "电池包 / CTB", "结构集成与热管理", "shippingbox.fill", .blue, []),
            node("bms", .component, "BMS", "电池管理与安全", "cpu.fill", .blue, []),
            node("motor", .component, "驱动电机", "高效电能转换", "gearshape.fill", .purple, []),
            node("domain", .component, "智驾域控制器", "融合感知与决策", "memorychip.fill", .blue, []),
            node("body-structure", .component, "一体化车身", "强度与轻量化", "car.side.fill", .graphite, []),
            node("cockpit-chip", .component, "座舱计算平台", "屏幕与交互中枢", "rectangle.connected.to.line.below", .purple, []),
            node("suspension", .component, "悬架与制动", "操控与行驶稳定", "circle.hexagongrid.fill", .green, []),

            node("cathode", .material, "正极材料", "决定能量密度", "mountain.2.fill", .orange, []),
            node("anode", .material, "负极材料 · 人造石墨", "提升充放电性能", "triangle.fill", .graphite, [
                company("shangtai", "石家庄尚太科技", "SHANGTAI TECH", "河北石家庄", "负极材料（人造石墨）", "核心供应商", "A级 · 年报/公告", true),
                company("btr", "贝特瑞新材料", "BTR", "广东深圳", "人造石墨负极", "主要供应商", "B级 · 行业资料", true),
                company("shanshan", "杉杉股份", nil, "浙江宁波", "负极材料", "主要供应商", "B级 · 行业资料", false),
                company("xfh", "翔丰华", nil, "广东深圳", "石墨负极材料", "候选供应商", "C级 · 待核验", false)
            ]),
            node("separator", .material, "隔膜 / 电解液", "离子传导与安全", "drop.triangle.fill", .green, []),
            node("magnet", .material, "稀土永磁材料", "电机磁性核心", "circle.grid.cross.fill", .purple, [])
        ],
        edges: [
            edge("xiaomi-su7", "battery"), edge("xiaomi-su7", "drive"),
            edge("xiaomi-su7", "adas"), edge("xiaomi-su7", "body"),
            edge("xiaomi-su7", "cockpit"), edge("xiaomi-su7", "chassis"),
            edge("battery", "cell"), edge("battery", "pack"), edge("battery", "bms"),
            edge("drive", "motor"), edge("adas", "domain"),
            edge("body", "body-structure"), edge("cockpit", "cockpit-chip"), edge("chassis", "suspension"),
            edge("cell", "cathode"), edge("cell", "anode"), edge("cell", "separator"),
            edge("motor", "magnet")
        ]
    )

    private static func node(
        _ id: String,
        _ kind: SupplyChainNodeKind,
        _ title: String,
        _ subtitle: String,
        _ symbol: String,
        _ accent: SupplyChainAccent,
        _ companies: [SupplyChainCompany]
    ) -> SupplyChainNode {
        SupplyChainNode(id: id, kind: kind, title: title, subtitle: subtitle, symbol: symbol, accent: accent, companies: companies)
    }

    private static func edge(_ source: String, _ target: String) -> SupplyChainEdge {
        SupplyChainEdge(sourceID: source, targetID: target)
    }

    private static func company(
        _ id: String,
        _ name: String,
        _ englishName: String?,
        _ location: String,
        _ product: String,
        _ relationship: String,
        _ evidence: String,
        _ core: Bool
    ) -> SupplyChainCompany {
        SupplyChainCompany(
            id: id,
            name: name,
            englishName: englishName,
            location: location,
            suppliedProduct: product,
            relationship: relationship,
            evidence: evidence,
            isCoreSupplier: core
        )
    }
}
