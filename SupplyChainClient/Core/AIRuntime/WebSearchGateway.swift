import Foundation

nonisolated enum WebFetchError: LocalizedError {
    case unsupportedScheme(String)
    case missingHost
    case disallowedHost(String)
    case redirectBlocked(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedScheme(let scheme):
            return "Unsupported URL scheme: \(scheme). Use http:// or https://."
        case .missingHost:
            return "URL is missing a host."
        case .disallowedHost(let host):
            return "Refusing to fetch private/loopback host: \(host)."
        case .redirectBlocked(let host):
            return "Redirect to private/loopback host blocked: \(host)."
        }
    }
}

private final class WebFetchRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        if let host = request.url?.host, PrivateHostGuard.isDisallowedHost(host) {
            completionHandler(nil)
        } else {
            completionHandler(request)
        }
    }
}

protocol WebSearchProvider: Sendable {
    var provider: SearchProviderID { get }
    func search(_ request: WebSearchRequest) async throws -> WebSearchResponse
}

final class WebSearchGateway: @unchecked Sendable {
    static let defaultMaxChars = 50_000
    static let maxResponseBytes = 4 * 1024 * 1024

    private let providers: [SearchProviderID: any WebSearchProvider]
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
        let list: [any WebSearchProvider] = [
            NoneSearchProvider(session: session),
            TavilySearchProvider(session: session),
            SerpAPISearchProvider(session: session),
            ZhipuSearchProvider(session: session),
            BraveSearchProvider(session: session),
            ExaSearchProvider(session: session),
            BochaSearchProvider(session: session),
            LangSearchProvider(session: session),
            PerplexitySearchProvider(session: session),
            JinaSearchProvider(session: session),
            SearXNGSearchProvider(session: session),
            SerperSearchProvider(session: session),
            DuckDuckGoSearchProvider(session: session)
        ]
        providers = Dictionary(uniqueKeysWithValues: list.map { ($0.provider, $0) })
    }

    func search(query: String, config: SearchRuntimeConfig) async throws -> WebSearchResponse {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { throw SearchRuntimeError.emptyQuery }
        guard let provider = providers[config.provider] else {
            throw SearchRuntimeError.unsupportedProvider(config.displayName)
        }
        return try await provider.search(WebSearchRequest(query: trimmed, config: config))
    }

    func readWebPage(
        urlString: String,
        maxChars: Int = WebSearchGateway.defaultMaxChars,
        hostValidator: @escaping @Sendable (String) -> Bool = PrivateHostGuard.isDisallowedHost
    ) async throws -> String {
        let trimmed = Self.cleanURLString(urlString)
        guard let url = URL(string: trimmed) else {
            throw WebFetchError.unsupportedScheme("(empty)")
        }

        let scheme = (url.scheme ?? "").lowercased()
        guard scheme == "http" || scheme == "https" else {
            throw WebFetchError.unsupportedScheme(url.scheme ?? "(empty)")
        }

        guard let host = url.host?.trimmingCharacters(in: .whitespacesAndNewlines), host.isEmpty == false else {
            throw WebFetchError.missingHost
        }
        if hostValidator(host) {
            throw WebFetchError.disallowedHost(host)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,*/*;q=0.5", forHTTPHeaderField: "Accept")

        let redirectGuard = WebFetchRedirectGuard()
        let fetchSession = URLSession(configuration: .ephemeral, delegate: redirectGuard, delegateQueue: nil)
        let (asyncBytes, response) = try await fetchSession.bytes(for: request)

        if let http = response as? HTTPURLResponse {
            if (300...399).contains(http.statusCode),
               let location = http.value(forHTTPHeaderField: "Location"),
               let redirectURL = URL(string: location, relativeTo: http.url),
               let redirectHost = redirectURL.host,
               hostValidator(redirectHost) {
                throw WebFetchError.redirectBlocked(redirectHost)
            }
            if let finalHost = http.url?.host, hostValidator(finalHost) {
                throw WebFetchError.redirectBlocked(finalHost)
            }
        }

        var data = Data()
        data.reserveCapacity(min(Self.maxResponseBytes, 4096))
        for try await byte in asyncBytes {
            data.append(byte)
            if data.count >= Self.maxResponseBytes {
                break
            }
        }

        try Self.validate(response: response, data: data)

        let html = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
        let text = Self.extractReadableText(from: html)
        let clipped = Self.clipText(text, maxChars: max(1, maxChars))
        return clipped.isEmpty ? "网页读取完成，但未提取到可读正文。" : clipped
    }

    static func cleanURLString(_ urlString: String) -> String {
        var trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        trimmed = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "`\"'"))
        return trimmed
    }

    static func clipText(_ text: String, maxChars: Int) -> String {
        guard text.count > maxChars else { return text }
        let endIndex = text.index(text.startIndex, offsetBy: maxChars)
        return String(text[..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines) + "\n…[truncated]"
    }

    static func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data.prefix(500), encoding: .utf8) ?? ""
            throw SearchRuntimeError.badHTTPStatus(http.statusCode, body)
        }
    }

    static func jsonRequest(url: URL, apiKey: String, body: [String: Any], authorization: String? = nil) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let authorization {
            request.setValue(authorization, forHTTPHeaderField: "Authorization")
        } else if apiKey.isEmpty == false {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    static func extractReadableText(from html: String) -> String {
        var text = html
        let patterns = [
            "(?is)<script[^>]*>.*?</script>",
            "(?is)<style[^>]*>.*?</style>",
            "(?is)<[^>]+>"
        ]
        for pattern in patterns {
            text = text.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        let entities = [
            "&nbsp;": " ",
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&#39;": "'"
        ]
        for (entity, value) in entities {
            text = text.replacingOccurrences(of: entity, with: value)
        }
        return text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { $0.isEmpty == false }
            .joined(separator: " ")
    }
}
