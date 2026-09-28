import Foundation

struct TavilySearchProvider: WebSearchProvider {
    let provider: SearchProviderID = .tavily
    let session: URLSession

    func search(_ request: WebSearchRequest) async throws -> WebSearchResponse {
        let body: [String: Any] = [
            "api_key": request.config.apiKey,
            "query": request.query,
            "search_depth": "advanced",
            "include_answer": false,
            "include_raw_content": false,
            "max_results": request.config.searchCount
        ]
        var urlRequest = try WebSearchGateway.jsonRequest(url: request.config.requestURL, apiKey: "", body: body, authorization: nil)
        urlRequest.setValue(nil, forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: urlRequest)
        try WebSearchGateway.validate(response: response, data: data)
        let decoded = try JSONDecoder.default.decode(TavilyResponse.self, from: data)
        return WebSearchResponse(
            providerName: request.config.displayName,
            query: request.query,
            items: decoded.results.prefix(request.config.searchCount).map {
                WebSearchResultItem(title: $0.title ?? "", url: $0.url ?? "", snippet: $0.content ?? "", sourceName: nil, iconURL: nil, publishedAt: nil)
            },
            totalEstimatedMatches: nil,
            revision: request.config.revision
        )
    }

    private struct TavilyResponse: Decodable {
        let results: [Item]
        struct Item: Decodable {
            let title: String?
            let url: String?
            let content: String?
        }
    }
}

struct SerpAPISearchProvider: WebSearchProvider {
    let provider: SearchProviderID = .serpAPI
    let session: URLSession

    func search(_ request: WebSearchRequest) async throws -> WebSearchResponse {
        var components = URLComponents(url: request.config.requestURL, resolvingAgainstBaseURL: false)
        var queryItems = components?.queryItems ?? []
        queryItems.append(URLQueryItem(name: "q", value: request.query))
        queryItems.append(URLQueryItem(name: "api_key", value: request.config.apiKey))
        queryItems.append(URLQueryItem(name: "num", value: "\(request.config.searchCount)"))
        components?.queryItems = queryItems
        guard let url = components?.url else {
            throw SearchRuntimeError.invalidEndpoint(request.config.requestURL.absoluteString)
        }
        let (data, response) = try await session.data(from: url)
        try WebSearchGateway.validate(response: response, data: data)
        let decoded = try JSONDecoder.default.decode(SerpAPIResponse.self, from: data)
        let items = (decoded.organicResults ?? []).prefix(request.config.searchCount).map {
            WebSearchResultItem(title: $0.title ?? "", url: $0.link ?? "", snippet: $0.snippet ?? "", sourceName: $0.source, iconURL: nil, publishedAt: nil)
        }
        return WebSearchResponse(providerName: request.config.displayName, query: request.query, items: items, totalEstimatedMatches: nil, revision: request.config.revision)
    }

    private struct SerpAPIResponse: Decodable {
        let organicResults: [Item]?
        struct Item: Decodable {
            let title: String?
            let link: String?
            let snippet: String?
            let source: String?
        }
    }
}

struct ZhipuSearchProvider: WebSearchProvider {
    let provider: SearchProviderID = .zhipu
    let session: URLSession

    func search(_ request: WebSearchRequest) async throws -> WebSearchResponse {
        let body: [String: Any] = [
            "search_engine": "search-std",
            "search_query": request.query
        ]
        let urlRequest = try WebSearchGateway.jsonRequest(url: request.config.requestURL, apiKey: request.config.apiKey, body: body)
        let (data, response) = try await session.data(for: urlRequest)
        try WebSearchGateway.validate(response: response, data: data)
        let decoded = try JSONDecoder.default.decode(ZhipuResponse.self, from: data)
        let items = (decoded.searchResult ?? []).prefix(request.config.searchCount).map {
            WebSearchResultItem(title: $0.title ?? "", url: $0.link ?? "", snippet: $0.content ?? "", sourceName: nil, iconURL: $0.icon, publishedAt: nil)
        }
        return WebSearchResponse(providerName: request.config.displayName, query: request.query, items: items, totalEstimatedMatches: nil, revision: request.config.revision)
    }

    private struct ZhipuResponse: Decodable {
        let searchResult: [Item]?
        struct Item: Decodable {
            let title: String?
            let link: String?
            let content: String?
            let icon: String?
        }
    }
}

struct BraveSearchProvider: WebSearchProvider {
    let provider: SearchProviderID = .brave
    let session: URLSession

    func search(_ request: WebSearchRequest) async throws -> WebSearchResponse {
        var components = URLComponents(url: request.config.requestURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "q", value: request.query),
            URLQueryItem(name: "count", value: "\(request.config.searchCount)")
        ]
        guard let url = components?.url else {
            throw SearchRuntimeError.invalidEndpoint(request.config.requestURL.absoluteString)
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.setValue(request.config.apiKey, forHTTPHeaderField: "X-Subscription-Token")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: urlRequest)
        try WebSearchGateway.validate(response: response, data: data)
        let decoded = try JSONDecoder.default.decode(BraveResponse.self, from: data)
        let items = (decoded.web?.results ?? []).prefix(request.config.searchCount).map {
            WebSearchResultItem(title: $0.title ?? "", url: $0.url ?? "", snippet: $0.description ?? "", sourceName: nil, iconURL: nil, publishedAt: nil)
        }
        return WebSearchResponse(providerName: request.config.displayName, query: request.query, items: items, totalEstimatedMatches: nil, revision: request.config.revision)
    }

    private struct BraveResponse: Decodable {
        let web: Web?
        struct Web: Decodable { let results: [Item]? }
        struct Item: Decodable {
            let title: String?
            let url: String?
            let description: String?
        }
    }
}

struct ExaSearchProvider: WebSearchProvider {
    let provider: SearchProviderID = .exa
    let session: URLSession

    func search(_ request: WebSearchRequest) async throws -> WebSearchResponse {
        let body: [String: Any] = [
            "query": request.query,
            "numResults": request.config.searchCount,
            "contents": ["text": ["maxCharacters": 1200]]
        ]
        var urlRequest = try WebSearchGateway.jsonRequest(url: request.config.requestURL, apiKey: "", body: body, authorization: nil)
        urlRequest.setValue("Bearer \(request.config.apiKey)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: urlRequest)
        try WebSearchGateway.validate(response: response, data: data)
        let decoded = try JSONDecoder.default.decode(ExaResponse.self, from: data)
        let items = decoded.results.prefix(request.config.searchCount).map {
            WebSearchResultItem(title: $0.title ?? "", url: $0.url ?? "", snippet: $0.text ?? "", sourceName: nil, iconURL: nil, publishedAt: nil)
        }
        return WebSearchResponse(providerName: request.config.displayName, query: request.query, items: items, totalEstimatedMatches: nil, revision: request.config.revision)
    }

    private struct ExaResponse: Decodable {
        let results: [Item]
        struct Item: Decodable {
            let title: String?
            let url: String?
            let text: String?
        }
    }
}

struct BochaSearchProvider: WebSearchProvider {
    let provider: SearchProviderID = .bocha
    let session: URLSession

    func search(_ request: WebSearchRequest) async throws -> WebSearchResponse {
        let body: [String: Any] = [
            "query": request.query,
            "freshness": "noLimit",
            "summary": true,
            "count": request.config.searchCount
        ]
        let urlRequest = try WebSearchGateway.jsonRequest(url: request.config.requestURL, apiKey: "", body: body, authorization: request.config.apiKey)
        let (data, response) = try await session.data(for: urlRequest)
        try WebSearchGateway.validate(response: response, data: data)
        let decoded = try JSONDecoder.default.decode(BochaResponse.self, from: data)
        let items = decoded.data.webPages.value.prefix(request.config.searchCount).map {
            WebSearchResultItem(title: $0.name ?? "", url: $0.url ?? "", snippet: $0.summary ?? $0.snippet ?? "", sourceName: $0.siteName, iconURL: $0.siteIcon, publishedAt: nil)
        }
        return WebSearchResponse(providerName: request.config.displayName, query: request.query, items: items, totalEstimatedMatches: decoded.data.webPages.totalEstimatedMatches, revision: request.config.revision)
    }

    private struct BochaResponse: Decodable {
        let data: DataClass
        struct DataClass: Decodable { let webPages: WebPages }
        struct WebPages: Decodable {
            let totalEstimatedMatches: Int?
            let value: [Item]
        }
        struct Item: Decodable {
            let name: String?
            let url: String?
            let snippet: String?
            let summary: String?
            let siteName: String?
            let siteIcon: String?
        }
    }
}

struct LangSearchProvider: WebSearchProvider {
    let provider: SearchProviderID = .langSearch
    let session: URLSession

    func search(_ request: WebSearchRequest) async throws -> WebSearchResponse {
        let body: [String: Any] = [
            "query": request.query,
            "freshness": "noLimit",
            "summary": true,
            "count": request.config.searchCount
        ]
        let urlRequest = try WebSearchGateway.jsonRequest(url: request.config.requestURL, apiKey: request.config.apiKey, body: body)
        let (data, response) = try await session.data(for: urlRequest)
        try WebSearchGateway.validate(response: response, data: data)
        let decoded = try JSONDecoder.default.decode(LangSearchResponse.self, from: data)
        let items = (decoded.data?.webPages?.value ?? decoded.results ?? []).prefix(request.config.searchCount).map {
            WebSearchResultItem(title: $0.name ?? $0.title ?? "", url: $0.url ?? $0.link ?? "", snippet: $0.summary ?? $0.snippet ?? $0.content ?? "", sourceName: $0.siteName, iconURL: $0.siteIcon, publishedAt: nil)
        }
        return WebSearchResponse(providerName: request.config.displayName, query: request.query, items: items, totalEstimatedMatches: nil, revision: request.config.revision)
    }

    private struct LangSearchResponse: Decodable {
        let data: DataClass?
        let results: [Item]?
        struct DataClass: Decodable { let webPages: WebPages? }
        struct WebPages: Decodable { let value: [Item]? }
        struct Item: Decodable {
            let name: String?
            let title: String?
            let url: String?
            let link: String?
            let snippet: String?
            let summary: String?
            let content: String?
            let siteName: String?
            let siteIcon: String?
        }
    }
}

struct PerplexitySearchProvider: WebSearchProvider {
    let provider: SearchProviderID = .perplexity
    let session: URLSession

    func search(_ request: WebSearchRequest) async throws -> WebSearchResponse {
        let body: [String: Any] = [
            "model": "sonar-pro",
            "messages": [
                [
                    "role": "system",
                    "content": "Return concise web search findings with reliable source links."
                ],
                [
                    "role": "user",
                    "content": request.query
                ]
            ],
            "max_tokens": 800
        ]
        let urlRequest = try WebSearchGateway.jsonRequest(
            url: request.config.requestURL,
            apiKey: request.config.apiKey,
            body: body
        )
        let (data, response) = try await session.data(for: urlRequest)
        try WebSearchGateway.validate(response: response, data: data)
        let decoded = try JSONDecoder.default.decode(PerplexityResponse.self, from: data)
        let answer = decoded.choices.first?.message.content ?? ""
        let sourceItems = (decoded.searchResults ?? []).map {
            WebSearchResultItem(
                title: $0.title ?? $0.url ?? "Perplexity source",
                url: $0.url ?? "",
                snippet: $0.snippet ?? answer,
                sourceName: "Perplexity",
                iconURL: nil,
                publishedAt: nil
            )
        }
        let citationItems = decoded.citations.map {
            WebSearchResultItem(
                title: $0,
                url: $0,
                snippet: answer,
                sourceName: "Perplexity",
                iconURL: nil,
                publishedAt: nil
            )
        }
        let items = (sourceItems.isEmpty ? citationItems : sourceItems)
            .filter { $0.url.isEmpty == false }
            .prefix(request.config.searchCount)
        let collectedItems = Array(items)
        let fallback = [
            WebSearchResultItem(
                title: "Perplexity answer",
                url: request.config.requestURL.absoluteString,
                snippet: answer,
                sourceName: "Perplexity",
                iconURL: nil,
                publishedAt: nil
            )
        ]
        return WebSearchResponse(
            providerName: request.config.displayName,
            query: request.query,
            items: collectedItems.isEmpty && answer.isEmpty == false ? fallback : collectedItems,
            totalEstimatedMatches: nil,
            revision: request.config.revision
        )
    }

    private struct PerplexityResponse: Decodable {
        let choices: [Choice]
        let citations: [String]
        let searchResults: [SearchResult]?


        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodableKey.self)
            choices = try container.decodeIfPresent([Choice].self, forKey: .key("choices")) ?? []
            citations = try container.decodeIfPresent([String].self, forKey: .key("citations")) ?? []
            searchResults = try container.decodeIfPresent([SearchResult].self, forKey: .key("searchResults"))
        }

        struct Choice: Decodable {
            let message: Message
        }

        struct Message: Decodable {
            let content: String?
        }

        struct SearchResult: Decodable {
            let title: String?
            let url: String?
            let snippet: String?
        }
    }
}

struct JinaSearchProvider: WebSearchProvider {
    let provider: SearchProviderID = .jina
    let session: URLSession

    func search(_ request: WebSearchRequest) async throws -> WebSearchResponse {
        let encodedQuery = request.query.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? request.query
        let base = request.config.requestURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let urlString = "\(base)/\(encodedQuery)"
        guard let url = URL(string: urlString) else {
            throw SearchRuntimeError.invalidEndpoint(urlString)
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "GET"
        urlRequest.timeoutInterval = 60
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        if request.config.apiKey.isEmpty == false {
            urlRequest.setValue("Bearer \(request.config.apiKey)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await session.data(for: urlRequest)
        try WebSearchGateway.validate(response: response, data: data)
        let decoded = try JSONDecoder.default.decode(JinaResponse.self, from: data)
        let items = decoded.data.prefix(request.config.searchCount).map {
            WebSearchResultItem(
                title: $0.title ?? "",
                url: $0.url ?? "",
                snippet: $0.content ?? $0.description ?? "",
                sourceName: "Jina",
                iconURL: nil,
                publishedAt: nil
            )
        }
        return WebSearchResponse(
            providerName: request.config.displayName,
            query: request.query,
            items: Array(items),
            totalEstimatedMatches: nil,
            revision: request.config.revision
        )
    }

    private struct JinaResponse: Decodable {
        let data: [Item]
        struct Item: Decodable {
            let title: String?
            let url: String?
            let description: String?
            let content: String?
        }
    }
}

struct SearXNGSearchProvider: WebSearchProvider {
    let provider: SearchProviderID = .searxng
    let session: URLSession

    func search(_ request: WebSearchRequest) async throws -> WebSearchResponse {
        let base = request.config.requestURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let endpoint = URL(string: "\(base)/search") else {
            throw SearchRuntimeError.invalidEndpoint(request.config.requestURL.absoluteString)
        }
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "q", value: request.query),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let url = components?.url else {
            throw SearchRuntimeError.invalidEndpoint(endpoint.absoluteString)
        }
        let (data, response) = try await session.data(from: url)
        try WebSearchGateway.validate(response: response, data: data)
        let decoded = try JSONDecoder.default.decode(SearXNGResponse.self, from: data)
        let items = decoded.results.prefix(request.config.searchCount).map {
            WebSearchResultItem(
                title: $0.title ?? "",
                url: $0.url ?? "",
                snippet: $0.content ?? "",
                sourceName: $0.engine ?? "SearXNG",
                iconURL: nil,
                publishedAt: nil
            )
        }
        return WebSearchResponse(
            providerName: request.config.displayName,
            query: request.query,
            items: Array(items),
            totalEstimatedMatches: nil,
            revision: request.config.revision
        )
    }

    private struct SearXNGResponse: Decodable {
        let results: [Item]
        struct Item: Decodable {
            let title: String?
            let url: String?
            let content: String?
            let engine: String?
        }
    }
}

struct SerperSearchProvider: WebSearchProvider {
    let provider: SearchProviderID = .serper
    let session: URLSession

    func search(_ request: WebSearchRequest) async throws -> WebSearchResponse {
        let body: [String: Any] = [
            "q": request.query,
            "num": request.config.searchCount
        ]
        var urlRequest = try WebSearchGateway.jsonRequest(
            url: request.config.requestURL,
            apiKey: "",
            body: body,
            authorization: nil
        )
        urlRequest.setValue(request.config.apiKey, forHTTPHeaderField: "X-API-KEY")
        let (data, response) = try await session.data(for: urlRequest)
        try WebSearchGateway.validate(response: response, data: data)
        let decoded = try JSONDecoder.default.decode(SerperResponse.self, from: data)
        let items = (decoded.organic ?? []).prefix(request.config.searchCount).map {
            WebSearchResultItem(
                title: $0.title ?? "",
                url: $0.link ?? "",
                snippet: $0.snippet ?? "",
                sourceName: $0.source,
                iconURL: nil,
                publishedAt: nil
            )
        }
        return WebSearchResponse(
            providerName: request.config.displayName,
            query: request.query,
            items: Array(items),
            totalEstimatedMatches: nil,
            revision: request.config.revision
        )
    }

    private struct SerperResponse: Decodable {
        let organic: [Item]?
        struct Item: Decodable {
            let title: String?
            let link: String?
            let snippet: String?
            let source: String?
        }
    }
}

struct DuckDuckGoSearchProvider: WebSearchProvider {
    let provider: SearchProviderID = .duckduckgo
    let session: URLSession

    func search(_ request: WebSearchRequest) async throws -> WebSearchResponse {
        let endpoint = DuckDuckGoHTMLParser.searchEndpoint(from: request.config.requestURL)
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 30
        urlRequest.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        let encodedQuery = request.query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? request.query
        urlRequest.httpBody = "q=\(encodedQuery)".data(using: .utf8)

        let (data, response) = try await session.data(for: urlRequest)
        try WebSearchGateway.validate(response: response, data: data)
        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw SearchRuntimeError.invalidResponse("DuckDuckGo")
        }

        let items = DuckDuckGoHTMLParser.parse(html: html, limit: request.config.searchCount)
        return WebSearchResponse(
            providerName: request.config.displayName,
            query: request.query,
            items: items,
            totalEstimatedMatches: items.isEmpty ? 0 : items.count,
            revision: request.config.revision
        )
    }
}

nonisolated enum DuckDuckGoHTMLParser {
    static func searchEndpoint(from requestURL: URL) -> URL {
        let normalized = requestURL.absoluteString.lowercased()
        if normalized.contains("html.duckduckgo.com") {
            return requestURL
        }
        return URL(string: SearchProviderCatalog.defaultRequestURL(for: .duckduckgo))!
    }

    static func parse(html: String, limit: Int) -> [WebSearchResultItem] {
        let capped = max(1, min(limit, 20))
        var items: [WebSearchResultItem] = []
        let linkPattern = #"<a[^>]*class="[^"]*result__a[^"]*"[^>]*href="([^"]+)"[^>]*>(.*?)</a>"#
        let snippetPattern = #"<a[^>]*class="[^"]*result__snippet[^"]*"[^>]*>(.*?)</a>"#

        guard let linkRegex = try? NSRegularExpression(pattern: linkPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let snippetRegex = try? NSRegularExpression(pattern: snippetPattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
        else {
            return []
        }

        let nsHTML = html as NSString
        let linkMatches = linkRegex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))
        let snippetMatches = snippetRegex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))

        for (index, match) in linkMatches.enumerated() {
            guard items.count < capped else { break }
            guard match.numberOfRanges >= 3 else { continue }
            let rawURL = nsHTML.substring(with: match.range(at: 1))
            let rawTitle = stripHTML(nsHTML.substring(with: match.range(at: 2)))
            let url = normalizeURL(rawURL)
            guard url.isEmpty == false else { continue }

            let snippet: String
            if index < snippetMatches.count, snippetMatches[index].numberOfRanges >= 2 {
                snippet = stripHTML(nsHTML.substring(with: snippetMatches[index].range(at: 1)))
            } else {
                snippet = ""
            }

            items.append(
                WebSearchResultItem(
                    title: decodeHTMLEntities(rawTitle),
                    url: url,
                    snippet: decodeHTMLEntities(snippet),
                    sourceName: "DuckDuckGo",
                    iconURL: nil,
                    publishedAt: nil
                )
            )
        }
        return items
    }

    private static func stripHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizeURL(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("//") {
            return "https:\(trimmed)"
        }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return trimmed
        }
        return trimmed
    }

    private static func decodeHTMLEntities(_ text: String) -> String {
        var value = text
        let entities = [
            "&nbsp;": " ",
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&#39;": "'",
            "&apos;": "'"
        ]
        for (entity, replacement) in entities {
            value = value.replacingOccurrences(of: entity, with: replacement)
        }
        return value
    }
}

struct NoneSearchProvider: WebSearchProvider {
    let provider: SearchProviderID = .none
    let session: URLSession

    func search(_ request: WebSearchRequest) async throws -> WebSearchResponse {
        _ = session
        return WebSearchResponse(
            providerName: request.config.displayName,
            query: request.query,
            items: [],
            totalEstimatedMatches: 0,
            revision: request.config.revision
        )
    }
}
