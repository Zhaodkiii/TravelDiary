import Foundation

/// 同类请求回调合并缓存。
/// 当多个调用方并发请求相同资源时，只执行一次真实网络请求，
/// 其余调用方直接等待同一个 `Task` 结果。
actor SupportCallbackCache {
    private var inFlight: [String: Task<SupportNetworkResponse, Error>] = [:]

    func execute(
        key: String,
        operationName: String,
        businessPurpose: String,
        logger: Logger,
        taskFactory: @escaping @Sendable () async throws -> SupportNetworkResponse
    ) async throws -> SupportNetworkResponse {
        if let existing = inFlight[key] {
            logger.debug(
                SupportNetworkingStrings.Backend.callbackCacheHit(
                    key: key,
                    operation: operationName,
                    business: businessPurpose
                ),
                module: .network
            )
            return try await existing.value
        }

        logger.debug(
            SupportNetworkingStrings.Backend.callbackCacheMiss(
                key: key,
                operation: operationName,
                business: businessPurpose
            ),
            module: .network
        )

        let task = Task<SupportNetworkResponse, Error> {
            try await taskFactory()
        }
        inFlight[key] = task

        defer {
            inFlight[key] = nil
        }

        return try await task.value
    }
}
