import Foundation

/// 传输层原始结果：响应体字节与 `HTTPURLResponse`（不做 JSON 解码）。
struct SupportTransportResponse: Sendable {
    let data: Data
    let httpResponse: HTTPURLResponse
}

/// 最底层 HTTP 发送抽象，便于单测注入 mock。
protocol SupportNetworkTransport: Sendable {
    func send(_ urlRequest: URLRequest) async throws -> SupportTransportResponse
}

/// 基于 `URLSession` 的默认实现：只返回字节与状态码，不解析业务 JSON。
struct URLSessionNetworkTransport: SupportNetworkTransport {
    let session: URLSession
    let logger: Logger

    /// 默认使用 `URLSession.shared` 与控制台日志。
    init(session: URLSession = .shared, logger: Logger = ConsoleLogger()) {
        self.session = session
        self.logger = logger
    }

    func send(_ urlRequest: URLRequest) async throws -> SupportTransportResponse {
        let request = urlRequest
        let method = request.httpMethod ?? "GET"
        let urlForLog = NetworkLogSanitizer.loggableURL(request.url)
        let requestId = request.value(forHTTPHeaderField: "X-Request-ID") ?? "-"

        let requestHeaders = NetworkLogSanitizer.headersPreview(request.allHTTPHeaderFields)
        let requestBody = NetworkLogSanitizer.bodyFullUTF8(data: request.httpBody, contentType: request.value(forHTTPHeaderField: "Content-Type"))

        logger.info(
            SupportNetworkingStrings.HTTPClient.outbound(
                method: method,
                url: urlForLog,
                requestId: requestId
            ),
            module: .network
        )
        logger.info(
            SupportNetworkingStrings.HTTPClient.outboundRaw(headers: requestHeaders, body: requestBody),
            module: .network
        )

        let roundTripStart = Date()
        do {
            let (data, response) = try await session.data(for: request, delegate: nil)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw SupportNetworkError.invalidResponse
            }
            let cost = Date().timeIntervalSince(roundTripStart)
            let responseByteCount = data.count
            let responseHeaders = NetworkLogSanitizer.headersPreview(httpResponse.allHeaderFields)
            let responseBody = NetworkLogSanitizer.bodyFullUTF8(
                data: data,
                contentType: httpResponse.value(forHTTPHeaderField: "Content-Type")
            )

            logger.info(
                SupportNetworkingStrings.HTTPClient.inbound(
                    method: method,
                    url: urlForLog,
                    requestId: requestId,
                    statusCode: httpResponse.statusCode,
                    cost: cost,
                    responseByteCount: responseByteCount
                ),
                module: .network
            )
            logger.verbose(
                SupportNetworkingStrings.HTTPClient.inboundRaw(
                    method: method,
                    url: urlForLog,
                    requestId: requestId,
                    statusCode: httpResponse.statusCode,
                    cost: cost,
                    headers: responseHeaders,
                    body: responseBody
                ),
                module: .network
            )
            return SupportTransportResponse(data: data, httpResponse: httpResponse)
        } catch let urlError as URLError {
            logger.warning(
                SupportNetworkingStrings.HTTPClient.failedRequest(
                    method: method,
                    url: urlForLog,
                    reason: "URLError(\(urlError.code.rawValue))"
                ),
                module: .network
            )
            throw SupportNetworkError.transport(urlError)
        } catch {
            logger.error(
                SupportNetworkingStrings.HTTPClient.failedRequest(
                    method: method,
                    url: urlForLog,
                    reason: error.localizedDescription
                ),
                module: .network
            )
            throw error
        }
    }
}

// MARK: - 日志用 URL / 头 / 体

private enum NetworkLogSanitizer {
    static func loggableURL(_ url: URL?) -> String {
        guard let url else { return "-" }
        var path = url.path
        if let query = url.query, query.isEmpty == false {
            path += "?\(query)"
        }
        if path.isEmpty == false, path != "/" {
            return path.hasPrefix("/") ? path : "/\(path)"
        }
        return url.absoluteString
    }

    static func headersPreview(_ headers: [String: String]?) -> String {
        guard let headers, headers.isEmpty == false else { return "{}" }
        return serializeDictionary(headers)
    }

    static func headersPreview(_ headers: [AnyHashable: Any]?) -> String {
        guard let headers, headers.isEmpty == false else { return "{}" }
        let normalized = Dictionary(uniqueKeysWithValues: headers.map { (String(describing: $0.key), String(describing: $0.value)) })
        return serializeDictionary(normalized)
    }

    /// 完整 UTF-8 正文；非 UTF-8 时返回占位，不截断。
    static func bodyFullUTF8(data: Data?, contentType: String?) -> String {
        guard let data, data.isEmpty == false else { return "" }
        _ = contentType
        guard let text = String(data: data, encoding: .utf8) else {
            return "<二进制：\(data.count) 字节>"
        }
        return text
    }

    private static func serializeDictionary(_ source: [String: String]) -> String {
        var sanitized: [String: String] = [:]
        sanitized.reserveCapacity(source.count)

        for (key, value) in source {
            let lower = key.lowercased()
            if lower == "authorization" {
                sanitized[key] = redactAuthorization(value)
            } else if lower.contains("token") || lower == "x-api-key" || lower == "api-key" {
                sanitized[key] = "***"
            } else {
                sanitized[key] = value
            }
        }

        let ordered = sanitized.keys.sorted().map { key in
            "\"\(key)\":\"\(escape(sanitized[key] ?? ""))\""
        }
        return "{\(ordered.joined(separator: ","))}"
    }

    private static func redactAuthorization(_ value: String) -> String {
        guard value.isEmpty == false else { return value }
        let comps = value.split(separator: " ", maxSplits: 1).map(String.init)
        guard comps.count == 2 else { return "***" }
        return "\(comps[0]) ***"
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}
