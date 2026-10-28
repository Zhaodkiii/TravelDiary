import Foundation

/// 成功响应体的 JSON 解码方式。
enum SupportResponseDecodingMode: Sendable {
    /// 后端统一包裹：`{ "code": Int, "msg": String, "data": T }`，`code == 0` 取 `data`。
    case backendWrapped
    /// 根对象即目标类型，例如 token 刷新 `{ "access": "...", "refresh": "..." }`。
    case direct
}

/// 与 `.backendWrapped` 模式对应的外层结构。
struct BackendWrappedResponse<T: Decodable>: Decodable {
    let code: Int
    let msg: String
    let data: T
}

/// 网络编排入口：串行门控 → 鉴权 → ETag →（外层）重试 → 传输 → 解码/错误映射。
final class SupportNetworkEngine {
    private let baseURL: URL
    private let transport: SupportNetworkTransport
    private let gate: SerialRequestGate
    private let etagInterceptor: ETagHTTPInterceptor
    private let retryPolicy: RetryPolicy
    private let authProvider: AuthTokenProvider
    private let deviceCache: DeviceCache
    private let logger: Logger

    /// 供上层挂接同一套日志实现。
    var networkLogger: Logger { logger }
    var serviceBaseURL: URL { baseURL }

    init(
        baseURL: URL,
        transport: SupportNetworkTransport = URLSessionNetworkTransport(),
        gate: SerialRequestGate = SerialRequestGate(),
        etagInterceptor: ETagHTTPInterceptor = ETagHTTPInterceptor(store: DeviceCache()),
        retryPolicy: RetryPolicy = RetryPolicy(),
        authProvider: AuthTokenProvider? = nil,
        deviceCache: DeviceCache = DeviceCache(),
        logger: Logger = ConsoleLogger()
    ) {
        self.baseURL = baseURL
        self.transport = transport
        self.gate = gate
        self.etagInterceptor = etagInterceptor
        self.retryPolicy = retryPolicy
        self.deviceCache = deviceCache
        self.logger = logger
        if let authProvider {
            self.authProvider = authProvider
        } else {
            self.authProvider = AuthTokenProvider(transport: transport, baseURL: baseURL, logger: logger)
        }
    }

    // MARK: - 公开 API

    /// 发送请求并按 `decodingMode` 解码为 `T`（内部先 `sendRaw`）。
    func send<T: Decodable>(
        _ request: SupportNetworkRequest,
        decodingMode: SupportResponseDecodingMode = .backendWrapped,
        decoder: JSONDecoder = JSONDecoder.default
    ) async throws -> T {
        let response = try await sendRaw(request)
        return try decodeSuccess(response: response, type: T.self, mode: decodingMode, decoder: decoder)
    }

    /// 原始发送接口，供 Operation 层复用。
    /// 负责完整的串行调度、重试、鉴权和 ETag 合并，但不负责 JSON 解码。
    func sendRaw(_ request: SupportNetworkRequest) async throws -> SupportNetworkResponse {
        let serialKey = request.strategy.serialKey ?? request.path

        var retryCount = 0
        while true {
            // 首次请求用业务优先级，重试走统一 `.retry`，避免饿死其它请求。
            let priority: SerialRequestGate.Priority = retryCount == 0
            ? request.strategy.queuePriority.gatePriority
            : .retry
            let policy = RetryPolicy(config: request.strategy.retryConfig, scheduler: retryPolicy.scheduler)

            do {
                let response = try await gate.enqueue(serialKey: serialKey, priority: priority) {
                    try await self.performAttempt(request)
                }

                // 401：强制刷新 token 后重试；`AuthTokenProvider` 内会去重并发刷新。
                if request.strategy.requiresAuth,
                   request.strategy.allowsAuthRefreshOn401,
                   response.httpResponse.statusCode == 401,
                   retryCount < request.strategy.retryConfig.maxRetryCount + 1 {
                    logger.info(SupportNetworkingStrings.HTTPClient.authRefreshTriggered(path: request.path), module: .network)
                    do {
                        _ = try await authProvider.forceRefreshTokens()
                    } catch {
                        let backendError = try? decodeBackendError(from: response.data)
                        postAuthInvalidationIfNeeded(
                            statusCode: response.httpResponse.statusCode,
                            backendCode: backendError?.code,
                            message: backendError?.msg ?? "",
                            source: "SupportNetworkEngine.sendRaw.refreshFailed",
                            refreshError: error
                        )
                        throw SupportNetworkError.refreshFailed(backendError, error)
                    }
                    retryCount += 1
                    continue
                }

                // 成功：2xx，或 304 且已合并本地 body（`didMerge304`）。
                if isSuccess(response: response) {
                    return response
                }

                // 尝试解析标准业务错误体，供 `httpError` 携带。
                let backendError = try? decodeBackendError(from: response.data)

                // 按 HTTP 状态码决定是否退避后重试。
                if shouldRetry(request: request, retryCount: retryCount, statusCode: response.httpResponse.statusCode, error: nil) {
                    retryCount += 1
                    try await policy.sleepIfNeeded(
                        retryCount: retryCount - 1,
                        retryAfterHeader: response.httpResponse.value(forHTTPHeaderField: "Retry-After"),
                        responseStatusCode: response.httpResponse.statusCode
                    )
                    continue
                }

                SupportAuthSessionInvalidation.postIfNeeded(
                    statusCode: response.httpResponse.statusCode,
                    backendCode: backendError?.code,
                    message: backendError?.msg ?? "",
                    source: "SupportNetworkEngine.sendRaw"
                )
                throw SupportNetworkError.http(
                    statusCode: response.httpResponse.statusCode,
                    backend: backendError,
                    data: response.data
                )
            } catch let error as SupportNetworkError {
                // 传输层失败：仅对可重试的 URLError 退避重试。
                if case .transport(let urlError) = error {
                    if shouldRetry(request: request, retryCount: retryCount, statusCode: nil, error: urlError) {
                        retryCount += 1
                        try await policy.sleepIfNeeded(
                            retryCount: retryCount - 1,
                            retryAfterHeader: nil,
                            responseStatusCode: nil
                        )
                        continue
                    }
                    throw error
                }
                throw error
            } catch is CancellationError {
                throw SupportNetworkError.cancelled
            } catch {
                // 其它异常：若策略允许则退避重试，否则原样抛出。
                if shouldRetry(request: request, retryCount: retryCount, statusCode: nil, error: nil) {
                    retryCount += 1
                    try await policy.sleepIfNeeded(retryCount: retryCount - 1, retryAfterHeader: nil, responseStatusCode: nil)
                    continue
                }
                throw error
            }
        }
    }

    /// 登录后写入 token 等场景暴露同一 `AuthTokenProvider`。
    func tokenProvider() -> AuthTokenProvider { authProvider }

    /// 兼容既有 Support API 命名。
    func tokenStore() -> AuthTokenProvider { authProvider }
    /// 与引擎关联的设备/ETag 等缓存句柄。
    func cache() -> DeviceCache { deviceCache }

    private func postAuthInvalidationIfNeeded(
        statusCode: Int,
        backendCode: Int?,
        message: String,
        source: String,
        refreshError: Error
    ) {
        let shouldInvalidateForRefreshError: Bool
        if let providerError = refreshError as? AuthTokenProviderError {
            switch providerError {
            case .missingTokens, .refreshFailed:
                shouldInvalidateForRefreshError = true
            case .refreshTemporarilyUnavailable, .invalidRefreshResponse:
                shouldInvalidateForRefreshError = false
            }
        } else {
            shouldInvalidateForRefreshError = false
        }

        guard shouldInvalidateForRefreshError else { return }
        SupportAuthSessionInvalidation.postIfNeeded(
            statusCode: statusCode,
            backendCode: backendCode,
            message: message,
            source: source
        )
    }

    // MARK: - 单次请求：组装与发送

    /// 构建 `URLRequest`，注入鉴权与 ETag，经 transport 发送并做 304 合并（若启用）。
    private func performAttempt(_ request: SupportNetworkRequest) async throws -> SupportNetworkResponse {
        var urlComponents = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        // 手动拼接 path，避免 `URLComponents` 与 base 斜杠重复或缺失。
        let basePath = urlComponents?.path ?? ""
        let requestPath = request.path.hasPrefix("/") ? String(request.path.dropFirst()) : request.path
        urlComponents?.path = basePath + "/" + requestPath

        if let queryItems = request.queryItems, !queryItems.isEmpty {
            urlComponents?.queryItems = queryItems
        }
        guard let url = urlComponents?.url else { throw SupportNetworkError.invalidResponse }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method.rawValue

        // 启用 ETag 时禁用「本地 HTTP 缓存」对 304 的透明合并：`URLSession` 默认会用 `URLCache` 在收到 304 后
        // 直接回填缓存里的 200 响应体，上层看到的常是 `statusCode == 200`，`intercept` 的 304 分支永远不会执行。
        // 自定义磁盘 ETag 需在真实 304 + 空 body 时合并，故对此类请求强制走网络校验。
        if request.strategy.allowETag {
            urlRequest.cachePolicy = .reloadIgnoringLocalCacheData
        }

        // 单请求超时覆盖 URLSession 默认值。
        if let timeoutInterval = request.timeoutInterval {
            urlRequest.timeoutInterval = timeoutInterval
        }

        // 链路追踪：每个出站请求带独立 ID。
        let requestId = RequestIdGenerator.make()
        urlRequest.setValue(requestId, forHTTPHeaderField: "X-Request-ID")

        if request.path.hasPrefix("/api/v1/materials/") || request.path.hasPrefix("/api/v1/diary-presets/") {
            let billingSession = await MainActor.run { BillingStore.shared.bootstrapInfo?.session_id }
            if let billingSession { urlRequest.setValue(billingSession, forHTTPHeaderField: "X-Billing-Session") }
        }
        // 调用方自定义头（可补充 `.raw` 的 Content-Type 等）。
        for (k, v) in request.headers {
            urlRequest.setValue(v, forHTTPHeaderField: k)
        }

        switch request.body {
        case .none:
            break
        case .json(let anyEncodable):
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.httpBody = try JSONEncoder.default.encode(anyEncodable)
        case .raw(let data, let contentType):
            // raw body 也必须显式声明 Content-Type，否则后端可能按 form 解析导致字段缺失。
            if urlRequest.value(forHTTPHeaderField: "Content-Type") == nil {
                urlRequest.setValue(contentType, forHTTPHeaderField: "Content-Type")
            }
            urlRequest.httpBody = data
        }

        // 鉴权头（异步取最新 access token）。
        if request.strategy.requiresAuth {
            let header = try await authProvider.authorizationHeaderValue()
            urlRequest.setValue(header, forHTTPHeaderField: "Authorization")
        }

        // 条件请求：在 transport 前附加 If-None-Match。
        let cacheKey: String? = request.strategy.allowETag ? etagInterceptor.cacheKey(for: urlRequest) : nil
        var conditionalBody: Data?
        if let cacheKey, request.strategy.allowETag {
            // Keep the matching body alive for this request even if the global LRU evicts it.
            conditionalBody = etagInterceptor.store.cachedBody(forKey: cacheKey)
            if conditionalBody != nil {
                urlRequest = etagInterceptor.applyIfNoneMatch(to: urlRequest, cacheKey: cacheKey, request: request)
            } else { urlRequest.setValue(nil, forHTTPHeaderField: "If-None-Match") }
        }

        let transportResponse = try await transport.send(urlRequest)
        if let cacheKey, request.strategy.allowETag {
            // 更新本地 ETag/304 合并 body。
            return etagInterceptor.intercept(
                transportResponse: transportResponse,
                cacheKey: cacheKey,
                request: request,
                conditionalBody: conditionalBody
            )
        }

        // 未启用 ETag：直通包装为 SupportNetworkResponse。
        return SupportNetworkResponse(data: transportResponse.data, httpResponse: transportResponse.httpResponse, didMerge304: false)
    }

    // MARK: - 解码与错误映射

    /// 业务上视为成功：2xx，或 304 且已合并缓存体。
    private func isSuccess(response: SupportNetworkResponse) -> Bool {
        if response.httpResponse.statusCode >= 200 && response.httpResponse.statusCode < 300 {
            return true
        }
        if response.httpResponse.statusCode == 304 && response.didMerge304 {
            return true
        }
        return false
    }

    /// 按模式解码成功载荷；`backendWrapped` 下 `code != 0` 转为 `httpError`。
    private func decodeSuccess<T: Decodable>(
        response: SupportNetworkResponse,
        type: T.Type,
        mode: SupportResponseDecodingMode,
        decoder: JSONDecoder
    ) throws -> T {
        switch mode {
        case .direct:
            return try decoder.decode(T.self, from: response.data)

        case .backendWrapped:
            let wrapped = try decoder.decode(BackendWrappedResponse<T>.self, from: response.data)
            if wrapped.code != 0 {
                // 业务失败：用包裹层 code/msg 构造 BackendError。
                let backend = BackendError(code: wrapped.code, msg: wrapped.msg, data: nil)
                throw SupportNetworkError.http(
                    statusCode: response.httpResponse.statusCode,
                    backend: backend,
                    data: response.data
                )
            }
            return wrapped.data
        }
    }

    /// 从错误响应 body 解析 `{ code, msg, data? }`（与成功体形态一致时常用）。
    private func decodeBackendError(from data: Data) throws -> BackendError {
        try JSONDecoder.default.decode(BackendError.self, from: data)
    }

    // MARK: - 是否重试

    /// 结合开关、幂等性、次数上限与 `RetryPolicy` 规则判定。
    private func shouldRetry(
        request: SupportNetworkRequest,
        retryCount: Int,
        statusCode: Int?,
        error: URLError?
    ) -> Bool {
        guard request.strategy.retryConfig.isEnabled else { return false }

        // 非幂等请求默认不重试；显式 `isIdempotent` 或 GET 除外。
        let shouldAllow = request.strategy.isIdempotent || request.method == .get
        guard shouldAllow else { return false }

        let maxRetry = request.strategy.retryConfig.maxRetryCount
        guard retryCount < maxRetry else { return false }

        let policy = RetryPolicy(config: request.strategy.retryConfig, scheduler: retryPolicy.scheduler)
        return policy.shouldRetry(statusCode: statusCode, error: error)
    }
}
