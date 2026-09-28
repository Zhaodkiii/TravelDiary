import Foundation

/// Versioned offline contract produced from the integration workbook.
/// The UI intentionally depends on this shape rather than on XLSX parsing.
struct SupplyChainGraphDocument: Codable {
    let schemaVersion: String
    let generatedAt: String
    let sourceWorkbook: String
    let rootProductID: String
    let nodes: [SupplyChainGraphDocumentNode]
    let edges: [SupplyChainGraphDocumentEdge]
}

struct SupplyChainGraphDocumentNode: Codable, Identifiable {
    let id: String
    let parentID: String?
    let kind: String
    let title: String
    let subtitle: String?
    let imageAssetName: String?
    let evidence: String?
    let metadata: [String: String]
}

struct SupplyChainGraphDocumentEdge: Codable, Identifiable {
    let id: String
    let sourceID: String
    let targetID: String
    let relationKind: String
    let evidence: String
    let vehicleScope: [String]
    let sharedRelation: Bool
    let sourceIDs: [String]
}

enum SupplyChainGraphDocumentError: LocalizedError {
    case missingResource
    case unsupportedVersion(String)
    case duplicateID(String)
    case orphanEdge(String)

    var errorDescription: String? {
        switch self {
        case .missingResource: return "供应链数据文件不存在"
        case .unsupportedVersion(let version): return "不支持的供应链数据版本：\(version)"
        case .duplicateID(let id): return "供应链节点 ID 重复：\(id)"
        case .orphanEdge(let id): return "供应链关系引用不存在的节点：\(id)"
        }
    }
}

/// Bundle-first loader. A generated `supply-chain-graph.json` can be dropped
/// into the app resources without changing the view layer. During migration,
/// the existing static graph remains a deterministic offline fallback.
enum SupplyChainGraphDocumentLoader {
    static func load(from bundle: Bundle = .main) throws -> SupplyChainGraphDocument {
        guard let url = bundle.url(forResource: "supply-chain-graph", withExtension: "json") else {
            throw SupplyChainGraphDocumentError.missingResource
        }
        let document = try JSONDecoder().decode(SupplyChainGraphDocument.self, from: Data(contentsOf: url))
        try validate(document)
        return document
    }

    static func validate(_ document: SupplyChainGraphDocument) throws {
        guard document.schemaVersion.hasPrefix("1.") else {
            throw SupplyChainGraphDocumentError.unsupportedVersion(document.schemaVersion)
        }
        var ids = Set<String>()
        for node in document.nodes where !ids.insert(node.id).inserted {
            throw SupplyChainGraphDocumentError.duplicateID(node.id)
        }
        for edge in document.edges where !ids.contains(edge.sourceID) || !ids.contains(edge.targetID) {
            throw SupplyChainGraphDocumentError.orphanEdge(edge.id)
        }
    }
}
