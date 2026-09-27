import Foundation

/// Backend 的基础装配容器。
/// 职责类似 purchases-ios 的 `BackendConfiguration`：
/// 统一持有网络引擎、回调合并缓存和日志器，并负责执行 Operation。
final class SupportBackendConfiguration: @unchecked Sendable {
    let engine: SupportNetworkEngine
    let callbackCache: SupportCallbackCache
    let deviceCache: DeviceCache
    let logger: Logger

    init(
        engine: SupportNetworkEngine,
        deviceCache: DeviceCache = DeviceCache(),
        callbackCache: SupportCallbackCache = SupportCallbackCache(),
        logger: Logger? = nil
    ) {
        self.engine = engine
        self.deviceCache = deviceCache
        self.callbackCache = callbackCache
        self.logger = logger ?? engine.networkLogger
    }

    func execute(_ operation: some SupportNetworkOperation) async throws -> SupportNetworkResponse {
        let business = SupportNetworkOperationBusinessPurpose.describe(operation)
        logger.debug(
            SupportNetworkingStrings.Backend.executing(
                api: operation.apiName,
                operation: operation.name,
                business: business
            ),
            module: .network
        )
        let query = operation.request.queryItems?
            .map { "\($0.name)=\($0.value ?? "")" }
            .joined(separator: "&") ?? ""
        logger.debug(
            "业务=\(business) Operation 请求详情 method=\(operation.request.method.rawValue) path=\(operation.request.path) query=\(query) requiresAuth=\(operation.request.strategy.requiresAuth) allowETag=\(operation.request.strategy.allowETag) retryEnabled=\(operation.request.strategy.retryConfig.isEnabled) maxRetry=\(operation.request.strategy.retryConfig.maxRetryCount) serialKey=\(operation.request.strategy.serialKey ?? "-") queuePriority=\(operation.request.strategy.queuePriority)",
            module: .network
        )

        if let key = operation.callbackCacheKey {
            return try await callbackCache.execute(
                key: key,
                operationName: operation.name,
                businessPurpose: business,
                logger: logger
            ) {
                try await operation.execute(with: self.engine)
            }
        }

        return try await operation.execute(with: engine)
    }

    func executeDecoded<T: Decodable>(
        _ type: T.Type,
        operation: some SupportNetworkOperation,
        wrapped: Bool = true,
        decoder: JSONDecoder = .default
    ) async throws -> T {
        let response = try await execute(operation)
        if wrapped {
            return try SupportAPIResponseDecoder.decodeWrappedData(type, from: response, decoder: decoder)
        }
        return try decoder.decode(T.self, from: response.data)
    }
}
