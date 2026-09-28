import Foundation

nonisolated enum SearchProviderID: String, Codable, Sendable, CaseIterable {
    case none = "NONE"
    case spark = "SPARK"
    case tavily = "TAVILY"
    case serpAPI = "SERPAPI"
    case zhipu = "ZHIPUAI"
    case bocha = "BOCHAAI"
    case exa = "EXA"
    case brave = "BRAVE"
    case langSearch = "LANGSEARCH"
    case perplexity = "PERPLEXITY"
    case jina = "JINA"
    case searxng = "SEARXNG"
    case duckduckgo = "DUCKDUCKGO"
    case serper = "SERPER"

    init(company: String) {
        let normalized = company.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        switch normalized {
        case "SERPAPI", "SERP_API":
            self = .serpAPI
        case "LANGSEARCH", "LANG_SEARCH":
            self = .langSearch
        case "ZHIPU", "ZHIPUAI":
            self = .zhipu
        case "BOCHA", "BOCHAAI":
            self = .bocha
        case "DDG":
            self = .duckduckgo
        default:
            self = SearchProviderID(rawValue: normalized) ?? .spark
        }
    }
}

nonisolated struct SearchRuntimeConfig: Equatable, Sendable {
    var provider: SearchProviderID
    var displayName: String
    var apiKey: String
    var requestURL: URL
    var searchCount: Int
    var bilingualSearch: Bool
    var revision: SearchRuntimeConfigRevision
    var rawKeyID: UUID
}

nonisolated struct WebSearchRequest: Sendable {
    var query: String
    var config: SearchRuntimeConfig
}

nonisolated struct WebSearchResultItem: Codable, Equatable, Sendable {
    var title: String
    var url: String
    var snippet: String
    var sourceName: String?
    var iconURL: String?
    var publishedAt: Date?
}

nonisolated struct WebSearchResponse: Codable, Equatable, Sendable {
    var providerName: String
    var query: String
    var items: [WebSearchResultItem]
    var totalEstimatedMatches: Int?
    var revision: SearchRuntimeConfigRevision

    var markdown: String {
        guard items.isEmpty == false else {
            return "联网搜索没有返回可用结果。"
        }
        var lines: [String] = [
            "联网搜索结果（\(providerName)，配置版本 \(revision.localRevision)）",
            "查询：\(query)"
        ]
        for (index, item) in items.enumerated() {
            let title = item.title.isEmpty ? item.url : item.title
            lines.append("")
            lines.append("[\(index + 1)] \(title)")
            if item.url.isEmpty == false {
                lines.append("URL: \(item.url)")
            }
            if let source = item.sourceName, source.isEmpty == false {
                lines.append("来源: \(source)")
            }
            let snippet = item.snippet.trimmingCharacters(in: .whitespacesAndNewlines)
            if snippet.isEmpty == false {
                lines.append(snippet)
            }
        }
        return lines.joined(separator: "\n")
    }
}

nonisolated enum SearchRuntimeError: LocalizedError {
    case disabled
    case missingActiveProvider
    case missingAPIKey(String)
    case invalidEndpoint(String)
    case unsupportedProvider(String)
    case emptyQuery
    case badHTTPStatus(Int, String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .disabled:
            return "联网搜索未启用。"
        case .missingActiveProvider:
            return "尚未配置可用的联网搜索引擎，请在设置中的联网搜索里启用一个搜索服务。"
        case .missingAPIKey(let provider):
            return "\(provider) 尚未填写 API Key，请先在设置中的联网搜索里补充密钥。"
        case .invalidEndpoint(let endpoint):
            return "联网搜索 endpoint 无效：\(endpoint)"
        case .unsupportedProvider(let provider):
            return "当前搜索引擎 \(provider) 还没有本地适配器。"
        case .emptyQuery:
            return "搜索关键词不能为空。"
        case .badHTTPStatus(let status, let body):
            return "搜索服务返回异常状态码 \(status)：\(body)"
        case .invalidResponse(let provider):
            return "\(provider) 返回的数据格式无法解析。"
        }
    }
}
