import Foundation
import CryptoKit

/// 本地 ETag 元数据与响应体的持久化抽象（内存或磁盘实现均可）。
protocol ETagStore: Sendable {
    /// 读取缓存元数据（ETag、过期时间等）。
    func record(forKey key: String) -> ETagCacheRecord?
    /// 读取与键关联的完整响应体（供 304 合并）。
    func cachedBody(forKey key: String) -> Data?
    /// 原子写入元数据与 body。
    func store(record: ETagCacheRecord, body: Data, forKey key: String) throws
    /// 删除该键对应的元数据与 body 文件。
    func removeCache(forKey key: String)
}

extension ETagStore {
    /// 仅读取已缓存的 ETag 字符串。
    func etag(forKey key: String) -> String? {
        record(forKey: key)?.etag
    }

    /// 便捷写入：自动填充 `lastUpdated`，可选过期时间。
    func store(etag: String, body: Data, forKey key: String, expirationDate: Date? = nil) throws {
        try store(
            record: ETagCacheRecord(
                etag: etag,
                lastUpdated: Date(),
                expirationDate: expirationDate
            ),
            body: body,
            forKey: key
        )
    }
}

/// 将 ETag 元数据（`.meta.json`）与响应体（`.body`）写入 Caches 目录下的子文件夹。
struct FileETagStore: ETagStore {
    /// 所有缓存文件的前缀目录。
    let baseDirectory: URL
    let fileManager: FileManager

    /// - Parameter baseDirectory: 为 `nil` 时使用 `Caches/TravelDiary.ETagCache`。
    init(
        baseDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        if let baseDirectory {
            self.baseDirectory = baseDirectory
        } else {
            // 系统缓存目录，随设备清理策略可被清空。
            self.baseDirectory = StoragePaths.system.cache("ETagResponses")
        }
    }

    func record(forKey key: String) -> ETagCacheRecord? {
        let url = baseDirectory.appendingPathComponent("\(key).meta.json", isDirectory: false)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder.default.decode(ETagCacheRecord.self, from: data)
    }

    func cachedBody(forKey key: String) -> Data? {
        let url = baseDirectory.appendingPathComponent("\(key).body", isDirectory: false)
        return try? Data(contentsOf: url)
    }

    func store(record: ETagCacheRecord, body: Data, forKey key: String) throws {
        if !fileManager.fileExists(atPath: baseDirectory.path) {
            try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        }

        // 元数据与 body 分文件，便于单独读取 ETag 或合并 304。
        let metadataURL = baseDirectory.appendingPathComponent("\(key).meta.json", isDirectory: false)
        try AtomicFileWriter.write(try JSONEncoder.default.encode(record), to: metadataURL)

        let bodyURL = baseDirectory.appendingPathComponent("\(key).body", isDirectory: false)
        try AtomicFileWriter.write(body, to: bodyURL)
    }

    func removeCache(forKey key: String) {
        try? fileManager.removeItem(at: baseDirectory.appendingPathComponent("\(key).meta.json", isDirectory: false))
        try? fileManager.removeItem(at: baseDirectory.appendingPathComponent("\(key).body", isDirectory: false))
    }
}

/// 在出站请求上附加 `If-None-Match`，并将 `304` 与本地缓存体合并为完整响应。
struct ETagHTTPInterceptor: Sendable {
    /// 当响应未带可用缓存头时，用于推算本地条目过期的默认 TTL（秒）。
    struct CachePolicy: Sendable {
        let defaultTTL: TimeInterval

        /// 默认 300 秒。
        static let `default` = CachePolicy(defaultTTL: 300)
    }

    let store: ETagStore
    let logger: Logger
    let cachePolicy: CachePolicy

    init(
        store: ETagStore,
        logger: Logger = ConsoleLogger(),
        cachePolicy: CachePolicy = .default
    ) {
        self.store = store
        self.logger = logger
        self.cachePolicy = cachePolicy
    }

    /// 由 URL（含 query）与 `Authorization` 指纹生成稳定键，再 SHA256 十六进制，避免键过长。
    func cacheKey(for request: URLRequest) -> String {
        // 若需按更多请求头区分缓存，可在此扩展 fingerprint。
        let urlString = request.url?.absoluteString ?? "missing_url"
        let auth = request.value(forHTTPHeaderField: "Authorization") ?? ""
        let fingerprint = "\(urlString)|Authorization:\(auth)"
        let digest = SHA256.hash(data: fingerprint.data(using: .utf8) ?? Data())
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// 未过期则设置 `If-None-Match`；已过期则删除本地条目，避免错误复用。
    /// 同时把客户端期望的 ETag 缓存秒数上送给服务端，用于服务端返回匹配的 `Cache-Control`。
    func applyIfNoneMatch(to urlRequest: URLRequest, cacheKey: String, request: SupportNetworkRequest) -> URLRequest {
        var req = urlRequest
        if req.value(forHTTPHeaderField: "X-Cache-Max-Age") == nil,
           let ttl = request.strategy.etagTTL,
           ttl > 0 {
            req.setValue(String(Int(ttl)), forHTTPHeaderField: "X-Cache-Max-Age")
        }
        if let record = store.record(forKey: cacheKey) {
            if record.isExpired() {
                store.removeCache(forKey: cacheKey)
                logger.debug(SupportNetworkingStrings.ETag.skipStaleCache(key: cacheKey), module: .cache)
            } else {
                req.setValue(record.etag, forHTTPHeaderField: "If-None-Match")
                logger.debug(SupportNetworkingStrings.ETag.apply(tag: record.etag, key: cacheKey), module: .cache)
            }
        }
        return req
    }

    /// 处理传输层结果：`304` 合并本地 body；`2xx` 且带 ETag 则更新缓存。
    /// - Returns: 合并后的响应；仅当用本地 body 填满 `data` 时 `didMerge304 == true`。
    func intercept(
        transportResponse: SupportTransportResponse,
        cacheKey: String,
        request: SupportNetworkRequest
    ) -> SupportNetworkResponse {
        let httpResponse = transportResponse.httpResponse

        if httpResponse.statusCode == 304 {
            if let cached = store.cachedBody(forKey: cacheKey) {
                let presentation = JSONPayloadFormatting.prettyUTF8StringForLog(from: cached)
                logger.verbose(
                    SupportNetworkingStrings.ETag.merged304FullPayload(
                        path: request.path,
                        cacheKey: cacheKey,
                        byteCount: cached.count,
                        presentationBody: presentation
                    ),
                    module: .cache
                )
                return SupportNetworkResponse(
                    data: cached,
                    httpResponse: httpResponse,
                    didMerge304: true
                )
            } else {
                // 无本地 body 可合并，交由上层按 HTTP 错误处理。
                return SupportNetworkResponse(
                    data: transportResponse.data,
                    httpResponse: httpResponse,
                    didMerge304: false
                )
            }
        }

        // 成功响应：持久化新 ETag 与 body，供下次条件请求与 304 合并。
        if (200...299).contains(httpResponse.statusCode) {
            let maybeETag = httpResponse.value(forHTTPHeaderField: "ETag")
            if let etag = maybeETag, !etag.isEmpty {
                let expirationDate = self.computeExpirationDate(
                    from: httpResponse,
                    request: request
                )
                _ = try? store.store(
                    record: ETagCacheRecord(
                        etag: etag,
                        lastUpdated: Date(),
                        expirationDate: expirationDate
                    ),
                    body: transportResponse.data,
                    forKey: cacheKey
                )
                logger.debug(SupportNetworkingStrings.ETag.store(tag: etag, key: cacheKey), module: .cache)
            }
        }

        // 非 304 或未写入缓存的其它路径：原样返回。
        return SupportNetworkResponse(
            data: transportResponse.data,
            httpResponse: httpResponse,
            didMerge304: false
        )
    }

    /// 判定本地 ETag 缓存何时过期。优先级：`Cache-Control` → `Expires` → 请求/策略的 TTL。
    private func computeExpirationDate(
        from response: HTTPURLResponse,
        request: SupportNetworkRequest
    ) -> Date? {
        // 若存在 Cache-Control，按其语义处理（RFC 7234 的简化实现）。
        if let cacheControl = response.value(forHTTPHeaderField: "Cache-Control")?.lowercased() {
            // no-store：立即过期，避免后续请求继续带 If-None-Match。
            if cacheControl.contains("no-store") {
                return Date()
            }

            let directives = cacheControl.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            // max-age：从当前时刻起可缓存的秒数。
            if let directive = directives.first(where: { $0.hasPrefix("max-age=") }),
               let seconds = TimeInterval(directive.replacingOccurrences(of: "max-age=", with: "")) {
                return Date().addingTimeInterval(seconds)
            }
        }

        // Expires：HTTP 日期头，使用固定 locale 与 GMT 解析。
        if let expires = response.value(forHTTPHeaderField: "Expires") {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            if let date = formatter.date(from: expires) {
                return date
            }
        }

        // 无上述缓存头：用请求的 etagTTL 或策略默认 TTL；nil 表示不设过期（见 ETagCacheRecord.isExpired）。
        let ttl = request.strategy.etagTTL ?? cachePolicy.defaultTTL
        return ttl > 0 ? Date().addingTimeInterval(ttl) : nil
    }
}
