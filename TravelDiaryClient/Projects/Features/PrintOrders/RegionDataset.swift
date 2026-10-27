import Foundation

nonisolated struct RegionNode: Codable, Sendable, Equatable, Identifiable {
    var id: String { code }
    let code: String
    let name: String
    let level: String
    let parent_code: String?
    let selectable_leaf: Bool
    let sort_order: Int
}

nonisolated struct RegionDataset: Codable, Sendable {
    let schema_version: Int
    let dataset_version: String
    let regions: [RegionNode]

    func validated() throws -> RegionDataset {
        guard schema_version == 1, !dataset_version.isEmpty, regions.count <= 10_000 else { throw PrintFailure("地区数据格式不受支持") }
        var index: [String: RegionNode] = [:]
        let levels = ["province": 0, "city": 1, "district": 2]
        for node in regions {
            guard node.code.count == 6, node.code.allSatisfy(\.isNumber), !node.name.isEmpty,
                  levels[node.level] != nil, index[node.code] == nil else { throw PrintFailure("地区数据不完整") }
            index[node.code] = node
        }
        let parents = Set(regions.compactMap(\.parent_code))
        for node in regions {
            if node.level == "province" {
                guard node.parent_code == nil, !node.selectable_leaf else { throw PrintFailure("省份数据不完整") }
            } else {
                guard let parent = node.parent_code.flatMap({ index[$0] }), levels[parent.level]! < levels[node.level]! else { throw PrintFailure("地区归属不正确") }
            }
            guard node.selectable_leaf == !parents.contains(node.code) else { throw PrintFailure("地区层级不完整") }
            if node.level == "city" && node.selectable_leaf {
                guard ["441900", "442000", "460400", "620200"].contains(node.code) else { throw PrintFailure("地区缺少区县数据") }
            }
        }
        let provinces = Set([11,12,13,14,15,21,22,23,31,32,33,34,35,36,37,41,42,43,44,45,46,50,51,52,53,54,61,62,63,64,65].map { "\($0)0000" })
        guard Set(regions.filter { $0.level == "province" }.map(\.code)) == provinces,
              regions.filter({ $0.level == "district" }).count >= 2500 else { throw PrintFailure("地区数据覆盖不完整") }
        return self
    }
}

nonisolated struct RegionSelection: Codable, Equatable, Sendable {
    let version: String
    let province: RegionNode
    let city: RegionNode?
    let district: RegionNode?
    var displayName: String { [province.name, city?.name, district?.name].compactMap { $0 }.joined(separator: " ") }
    var leaf: RegionNode { district ?? city ?? province }
}

/// UI groups are separate from real administrative nodes and never serialized as codes.
nonisolated struct RegionPickerOption: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let code: String?
}

nonisolated struct RegionPickerModel: Sendable {
    let dataset: RegionDataset
    private let index: [String: RegionNode]
    private let children: [String: [RegionNode]]
    var provinceID: String
    var cityID: String
    var districtID: String
    var provinces: [RegionPickerOption] { options(children[""] ?? []) }
    var cities: [RegionPickerOption] {
        let nodes = children[provinceID] ?? []
        var result = options(nodes.filter { $0.level == "city" })
        if nodes.contains(where: { $0.level == "district" }) {
            result.append(.init(id: "group:"+provinceID, title: ["110000","120000","310000","500000"].contains(provinceID) ? (index[provinceID]?.name ?? "直辖市") : "省直辖行政单位", code: nil))
        }
        return result
    }
    var districts: [RegionPickerOption] {
        if cityID.hasPrefix("group:") { return options((children[provinceID] ?? []).filter { $0.level == "district" }) }
        let nodes = children[cityID] ?? []
        if nodes.isEmpty, index[cityID]?.selectable_leaf == true { return [.init(id:"leaf:"+cityID,title:"无区县",code:nil)] }
        return options(nodes)
    }
    init(dataset: RegionDataset, province: String? = nil, city: String? = nil, district: String? = nil) {
        self.dataset = dataset
        index = Dictionary(uniqueKeysWithValues: dataset.regions.map { ($0.code, $0) })
        children = Dictionary(grouping: dataset.regions, by: { $0.parent_code ?? "" }).mapValues { $0.sorted { $0.sort_order < $1.sort_order } }
        provinceID = province ?? ""; cityID = city ?? ""; districtID = district ?? ""
        if !provinces.contains(where: { $0.id == provinceID }) { provinceID = provinces.first?.id ?? "" }
        if city == nil, let district, index[district]?.parent_code == provinceID { cityID = "group:"+provinceID }
        repair()
    }
    private func options(_ nodes: [RegionNode]) -> [RegionPickerOption] { nodes.map { .init(id:$0.code,title:$0.name,code:$0.code) } }
    mutating func select(_ id: String, component: Int) {
        switch component { case 0: provinceID=id; case 1: cityID=id; default: districtID=id }
        repair()
    }
    private mutating func repair() {
        if !cities.contains(where: { $0.id == cityID }) { cityID=cities.first?.id ?? "" }
        if !districts.contains(where: { $0.id == districtID }) { districtID=districts.first?.id ?? "" }
    }
    var selection: RegionSelection? {
        guard let province=index[provinceID] else { return nil }
        let city=index[cityID], district=index[districtID]
        guard (district ?? city)?.selectable_leaf == true else { return nil }
        return .init(version:dataset.dataset_version,province:province,city:city,district:district)
    }
}
