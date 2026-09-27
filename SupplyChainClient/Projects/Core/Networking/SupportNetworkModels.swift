import Foundation

// MARK: - HTTP 方法

/// 与后端约定的 HTTP 动词。
nonisolated enum SupportHTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

// MARK: - 请求体

/// 将任意 `Encodable` 擦除为统一类型，便于放入 `SupportBody.json`。
nonisolated struct AnyEncodable: Encodable, @unchecked Sendable {
    private let _encode: (Encoder) throws -> Void

    init<E: Encodable>(_ wrapped: E) {
        self._encode = { encoder in
            try wrapped.encode(to: encoder)
        }
    }

    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}

/// 出站请求体：无、`JSON` 编码、或原始字节（自定义 `Content-Type`）。
nonisolated enum SupportBody: Sendable {
    case none
    case json(AnyEncodable)
    case raw(Data, contentType: String)

    /// 写入 `Content-Type` 头时使用；`.none` 为不设置。
    var contentType: String? {
        switch self {
        case .none:
            return nil
        case .json:
            return "application/json"
        case let .raw(_, contentType):
            return contentType
        }
    }
}

// MARK: - 重试

/// 传输层 / HTTP 失败时的自动重试策略。
nonisolated struct RetryConfig: Sendable {
    /// 是否启用自动重试。
    var isEnabled: Bool
    /// 最大重试次数（不含首次请求）。
    var maxRetryCount: Int
    /// 这些 HTTP 状态码会触发重试。
    var retryableStatusCodes: Set<Int>
    /// 这些 `URLError` 会触发重试。
    var retryableURLErrorCodes: Set<URLError.Code>
    /// 是否尊重响应头 `Retry-After`。
    var honorsRetryAfter: Bool
    /// 第 n 次重试前的等待秒数，长度应覆盖 `maxRetryCount` 次重试间隔。
    var backoffIntervals: [TimeInterval]

    /// 默认：429/5xx、常见网络错误、指数式间隔 `[0, 0.75, 3]`。
    static let `default` = RetryConfig(
        isEnabled: true,
        maxRetryCount: 2,
        retryableStatusCodes: [429, 500, 502, 503, 504],
        retryableURLErrorCodes: [
            .timedOut,
            .cannotFindHost,
            .cannotConnectToHost,
            .networkConnectionLost,
            .notConnectedToInternet,
            .dnsLookupFailed
        ],
        honorsRetryAfter: true,
        backoffIntervals: [0, 0.75, 3]
    )

}

// MARK: - 队列优先级

/// 同一串行门（`SerialRequestGate`）内请求的相对优先级，数值越小越优先。
nonisolated enum RequestQueuePriority: Int, Codable, Sendable {
    case veryHigh = 0
    case high = 1
    case normal = 2
    case low = 3

    /// 映射到底层串行门实现使用的优先级。
    var gatePriority: SerialRequestGate.Priority {
        switch self {
        case .veryHigh: return .veryHigh
        case .high: return .high
        case .normal: return .normal
        case .low: return .low
        }
    }
}

extension RequestQueuePriority: CustomStringConvertible {
    var description: String {
        switch self {
        case .veryHigh: return "veryHigh"
        case .high: return "high"
        case .normal: return "normal"
        case .low: return "low"
        }
    }
}


// MARK: - 网络策略

/// 单条请求在鉴权、ETag、串行、重试等行为上的配置。
nonisolated struct NetworkStrategy: Sendable {
    /// 是否附加 `Authorization` 并参与 token 刷新流程。
    var requiresAuth: Bool

    /// 是否启用 ETag / `304` 与本地缓存合并。
    var allowETag: Bool

    /// 串行 FIFO 分组键；为 `nil` 时通常回落为请求 path。
    var serialKey: String?

    /// 重试策略（状态码、`URLError`、`Retry-After` 等）。
    var retryConfig: RetryConfig

    /// 非 GET 请求是否视为幂等，从而允许自动重试。
    var isIdempotent: Bool

    /// 请求在串行队列中的优先级。
    var queuePriority: RequestQueuePriority

    /// 401 时是否触发 token 刷新并重试；Bridge Token 等一次性凭证应设为 `false`。
    var allowsAuthRefreshOn401: Bool

    /// ETag 本地缓存的默认存活时间；服务端 `Cache-Control` / `Expires` 优先。
    var etagTTL: TimeInterval?

    init(
        requiresAuth: Bool = false,
        allowETag: Bool = false,
        serialKey: String? = nil,
        retryConfig: RetryConfig = .default,
        isIdempotent: Bool = false,
        queuePriority: RequestQueuePriority = .normal,
        allowsAuthRefreshOn401: Bool = true,
        etagTTL: TimeInterval? = nil
    ) {
        self.requiresAuth = requiresAuth
        self.allowETag = allowETag
        self.serialKey = serialKey
        self.retryConfig = retryConfig
        self.isIdempotent = isIdempotent
        self.queuePriority = queuePriority
        self.allowsAuthRefreshOn401 = allowsAuthRefreshOn401
        self.etagTTL = etagTTL
    }

    /// 兼容旧 Support 调用：等价于 `retryConfig.isEnabled`。
    var allowRetry: Bool {
        get { retryConfig.isEnabled }
        set { retryConfig.isEnabled = newValue }
    }

}

// MARK: - 请求与响应

/// 描述一次 API 调用：路径、查询串、头、体与策略。
nonisolated struct SupportNetworkRequest: Sendable {
    var method: SupportHTTPMethod
    /// 相对 path（不含 base URL）。
    var path: String
    var queryItems: [URLQueryItem]?
    var headers: [String: String]
    var body: SupportBody
    /// 覆盖默认超时；`nil` 使用客户端全局配置。
    var timeoutInterval: TimeInterval?
    var strategy: NetworkStrategy

    init(
        method: SupportHTTPMethod,
        path: String,
        queryItems: [URLQueryItem]? = nil,
        headers: [String: String] = [:],
        body: SupportBody = .none,
        timeoutInterval: TimeInterval? = nil,
        strategy: NetworkStrategy = NetworkStrategy()
    ) {
        self.method = method
        self.path = path
        self.queryItems = queryItems
        self.headers = headers
        self.body = body
        self.timeoutInterval = timeoutInterval
        self.strategy = strategy
    }
}

/// 传输层返回的原始结果；`304` 时可能已合并本地缓存体以便上层按 200 解码。
nonisolated struct SupportNetworkResponse: Sendable {
    let data: Data
    let httpResponse: HTTPURLResponse
    /// 为 `true` 表示 `304` 已用本地缓存 body 填充 `data`。
    let didMerge304: Bool
}

// MARK: - ETag 缓存元数据

/// 磁盘上 ETag 条目：标签、更新时间、可选过期时刻。
nonisolated struct ETagCacheRecord: Codable, Sendable {
    let etag: String
    let lastUpdated: Date
    /// `nil` 表示不按时间过期，仅依赖服务端 `304`。
    let expirationDate: Date?

    /// `expirationDate` 为 `nil` 时视为未过期。
    func isExpired(referenceDate: Date = Date()) -> Bool {
        guard let expirationDate else { return false }
        return expirationDate <= referenceDate
    }
}

// MARK: - 后端错误与动态 JSON

/// 弱类型 JSON，用于解析结构不固定的 `data` 等字段。
nonisolated enum JSONValue: Decodable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        // 按 JSON 标量常见顺序尝试解码。
        if container.decodeNil() {
            self = .null
            return
        }
        if let b = try? container.decode(Bool.self) {
            self = .bool(b)
            return
        }
        if let s = try? container.decode(String.self) {
            self = .string(s)
            return
        }
        if let n = try? container.decode(Double.self) {
            self = .number(n)
            return
        }
        if let obj = try? container.decode([String: JSONValue].self) {
            self = .object(obj)
            return
        }
        if let arr = try? container.decode([JSONValue].self) {
            self = .array(arr)
            return
        }
        throw DecodingError.typeMismatch(JSONValue.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported JSON value"))
    }
}

/// 医疗接口日期的编解码：ISO8601、`yyyy-MM-dd`、或历史时间戳数字。
nonisolated enum MedicalDateCoding {
    /// 解码：字符串（ISO8601 / 仅日期）或数字（legacy 参考时间戳，含毫秒推断）。
    static func decodeFlexibleDate(from decoder: Decoder) throws -> Date {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            if let date = decodeISO8601(value) {
                return date
            }
            if let date = decodeDateOnly(value) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported date string: \(value)")
        }
        if let value = try? container.decode(Double.self) {
            return decodeLegacyReferenceTimestamp(value)
        }
        if let value = try? container.decode(Int.self) {
            return decodeLegacyReferenceTimestamp(Double(value))
        }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported date value")
    }

    /// 编码为 `yyyy-MM-dd`（当前时区日历日）。
    static func encodeDateOnly(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// 编码为带小数的 ISO8601 字符串。
    static func encodeISO8601(_ date: Date) -> String {
        ISO8601DateFormatter.medicalWithFractionalSeconds.string(from: date)
    }

    /// 将 `yyyy-MM-dd` 字符串解析为 `Date`；传 `nil` 或非法值时返回默认日期（默认当前时间）。
    static func decodeDateOnlyOrDefaultNow(_ value: String?, defaultDate: Date = Date()) -> Date {
        Date.parseOrNow(value, defaultDate: defaultDate)
    }

    private static func decodeDateOnly(_ value: String) -> Date? {
        // 与 encodeDateOnly 对称。
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    private static func decodeISO8601(_ value: String) -> Date? {
        // 先尝试带小数秒，再回落到基础 ISO8601。
        if let date = ISO8601DateFormatter.medicalWithFractionalSeconds.date(from: value) {
            return date
        }
        return ISO8601DateFormatter.medicalBasic.date(from: value)
    }

    /// 兼容历史字段：绝对值极大时视为毫秒，否则为秒；均按 `Date` 参考系解析。
    private static func decodeLegacyReferenceTimestamp(_ value: Double) -> Date {
        let seconds = abs(value) > 100_000_000_000 ? value / 1000 : value
        return Date(timeIntervalSinceReferenceDate: seconds)
    }
}

extension Date {
    /// 将可选字符串自动按多种格式解析为 `Date`；为空或解析失败时返回默认日期（默认当前时间）。
    nonisolated static func parseOrNow(
        _ value: String?,
        defaultDate: Date = Date()
    ) -> Date {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), value.isEmpty == false else {
            return defaultDate
        }

        // 优先尝试 ISO8601（含/不含小数秒）
        if let date = ISO8601DateFormatter.medicalWithFractionalSeconds.date(from: value) {
            return date
        }
        if let date = ISO8601DateFormatter.medicalBasic.date(from: value) {
            return date
        }

        // 再尝试常见日期/时间格式
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current

        let supportedFormats = [
            "yyyy-MM-dd",
            "yyyy/MM/dd",
            "yyyy.MM.dd",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy/MM/dd HH:mm:ss",
            "yyyy.MM.dd HH:mm:ss",
            "yyyy-MM-dd HH:mm",
            "yyyy/MM/dd HH:mm",
            "yyyy.MM.dd HH:mm"
        ]

        for format in supportedFormats {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date
            }
        }

        // 兼容纯数字时间戳（秒/毫秒）
        if let numeric = Double(value) {
            let seconds = abs(numeric) > 100_000_000_000 ? numeric / 1000 : numeric
            return Date(timeIntervalSinceReferenceDate: seconds)
        }

        return defaultDate
    }
}

/// `MedicalDateCoding` 使用的 ISO8601 解析器缓存。
private extension ISO8601DateFormatter {
    /// 带小数秒的互联网日期时间。
    nonisolated static var medicalWithFractionalSeconds: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    /// 无小数秒的基础 ISO8601。
    nonisolated static var medicalBasic: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }
}

/// 后端业务错误载荷（与 HTTP 状态码配合使用）。
nonisolated struct BackendError: Decodable, Sendable {
    let code: Int
    let msg: String
    let msgValue: JSONValue
    let data: JSONValue?


    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodableKey.self)
        code = try container.decode(Int.self, forKey: .key("code"))
        msgValue = (try? container.decode(JSONValue.self, forKey: .key("msg"))) ?? .string("")
        data = try? container.decodeIfPresent(JSONValue.self, forKey: .key("data"))
        msg = Self.stringify(value: msgValue)
    }

    init(code: Int, msg: String, data: JSONValue?) {
        self.code = code
        self.msg = msg
        self.msgValue = .string(msg)
        self.data = data
    }

    private static func stringify(value: JSONValue) -> String {
        switch value {
        case .string(let text):
            return text
        case .number(let number):
            return String(number)
        case .bool(let flag):
            return flag ? "true" : "false"
        case .null:
            return ""
        case .array(let rows):
            return rows.map { stringify(value: $0) }.filter { $0.isEmpty == false }.joined(separator: ", ")
        case .object(let object):
            let pairs = object
                .sorted { $0.key < $1.key }
                .map { key, value in
                    let rendered = stringify(value: value)
                    return rendered.isEmpty ? key : "\(key): \(rendered)"
                }
            return pairs.joined(separator: "; ")
        }
    }
}

/// 网络栈对上层暴露的统一错误。
nonisolated enum SupportNetworkError: Error, Sendable {
    /// 调用方取消或任务被撤销。
    case cancelled
    /// 底层 `URLSession` / 连接类错误。
    case transport(URLError)
    /// 无有效 `HTTPURLResponse` 等异常响应形态。
    case invalidResponse
    /// HTTP 非成功状态；可能附带解析后的 `BackendError` 与原始 body。
    case http(statusCode: Int, backend: BackendError?, data: Data)
    /// 响应体 JSON 解码失败。
    case decoding(Error)
    /// 鉴权刷新失败（业务错误 + 底层错误可选）。
    case refreshFailed(BackendError?, Error?)
    /// 超时。
    case timeout
}

extension SupportNetworkError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "请求已取消。"
        case .transport(let urlError):
            return "网络异常：\(urlError.localizedDescription)"
        case .invalidResponse:
            return L10n.text("api_error.invalid_response", fallback: "服务器响应无效，请稍后重试。")
        case .http(let statusCode, let backend, _):
            return BackendErrorLocalizer.message(for: backend, statusCode: statusCode)
        case .decoding(_):
            return L10n.text("api_error.decoding", fallback: "数据解析失败，请稍后重试。")
        case .refreshFailed(let backend, _):
            return BackendErrorLocalizer.message(for: backend, statusCode: 401)
        case .timeout:
            return L10n.text("api_error.timeout", fallback: "请求超时，请检查网络后重试。")
        }
    }
}

/// 认证失效事件：仅用于“服务端明确判定鉴权失败”后，通知 App 层回到登录页。
nonisolated enum SupportAuthSessionInvalidation {
    static let notificationName = Notification.Name("Support.Auth.SessionInvalidatedByServer")

    static func shouldInvalidate(statusCode: Int, backendCode: Int?, message: String) -> Bool {
        if statusCode == 403 {
            return false
        }
        if statusCode == 401 {
            return true
        }
        if isAuthFailureMessage(message) {
            return true
        }
        guard let backendCode else { return false }
        return (40100...40199).contains(backendCode)
    }

    private static func isAuthFailureMessage(_ message: String) -> Bool {
        let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized.isEmpty == false else { return false }
        let authFailureTokens = [
            "token_not_valid",
            "device_session_revoked",
            "device_session_replaced",
            "device_session_not_found",
            "device_mismatch",
            "authentication_failed",
            "not_authenticated",
            "invalid_token",
            "token_expired",
            "given token not valid",
        ]
        return authFailureTokens.contains { normalized == $0 || normalized.contains($0) }
    }

    static func postIfNeeded(
        statusCode: Int,
        backendCode: Int?,
        message: String,
        source: String
    ) {
        guard shouldInvalidate(statusCode: statusCode, backendCode: backendCode, message: message) else { return }
        let userInfo: [AnyHashable: Any] = [
            "statusCode": statusCode,
            "backendCode": backendCode ?? -1,
            "message": message,
            "source": source
        ]
        NotificationCenter.default.post(
            name: notificationName,
            object: nil,
            userInfo: userInfo
        )
        NotificationCenter.default.post(
            name: Notification.Name("SupportAuthInvalidated"),
            object: nil,
            userInfo: userInfo
        )
    }
}
