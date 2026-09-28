import Foundation

/// 后端统一包裹结构的解码帮助器。
/// 让 Domain API 只关心业务数据，统一在这里处理 `code/msg/data` 语义。
enum SupportAPIResponseDecoder {
    static func decodeWrappedData<T: Decodable>(
        _ type: T.Type,
        from response: SupportNetworkResponse,
        decoder: JSONDecoder = JSONDecoder.default
    ) throws -> T {
        let logger = ConsoleLogger()
        let wrapped: BackendWrappedResponse<T>
        do {
            wrapped = try decoder.decode(BackendWrappedResponse<T>.self, from: response.data)
            logger.debug(
                "响应解码成功 type=\(String(describing: T.self)) keys=\(jsonKeySummary(response.data))",
                module: .network
            )
        } catch {
            logger.error(
                "响应解码失败 type=\(String(describing: T.self)) error=\(CodableDiagnostics.describe(error)) keys=\(jsonKeySummary(response.data))",
                module: .network
            )
            throw error
        }

        guard wrapped.code == 0 else {
            let backendData: JSONValue? = (try? decoder.decode(BackendWrappedResponse<JSONValue>.self, from: response.data))?.data
            SupportAuthSessionInvalidation.postIfNeeded(
                statusCode: response.httpResponse.statusCode,
                backendCode: wrapped.code,
                message: wrapped.msg,
                source: "SupportAPIResponseDecoder.decodeWrappedData"
            )
            throw SupportNetworkError.http(
                statusCode: response.httpResponse.statusCode,
                backend: BackendError(code: wrapped.code, msg: wrapped.msg, data: backendData),
                data: response.data
            )
        }

        return wrapped.data
    }

    /// 与 `decodeWrappedData` 相同，但若根 JSON **没有** `code` 键（例如 Django REST 直接返回业务对象），则把整段 body 按 `T` 解码。
    /// 用于同时兼容 Spark 统一包裹与裸 JSON 响应。
    static func decodeWrappedDataOrDirect<T: Decodable>(
        _ type: T.Type,
        from response: SupportNetworkResponse,
        decoder: JSONDecoder = JSONDecoder.default
    ) throws -> T {
        let root = try JSONSerialization.jsonObject(with: response.data, options: [.fragmentsAllowed])
        if let dict = root as? [String: Any], dict["code"] != nil {
            return try decodeWrappedData(type, from: response, decoder: decoder)
        }
        return try decoder.decode(T.self, from: response.data)
    }

    private static func jsonKeySummary(_ data: Data) -> String {
        guard
            let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
            let root = object as? [String: Any]
        else {
            return "<non-object>"
        }

        let rootKeys = root.keys.sorted().joined(separator: ",")
        if let payload = root["data"] as? [String: Any] {
            let dataKeys = payload.keys.sorted().joined(separator: ",")
            return "root=[\(rootKeys)] data=[\(dataKeys)]"
        }
        return "root=[\(rootKeys)]"
    }

}
