import Foundation

/// Fixed direct-connect configuration for the current test integration.
enum DiaryAITestConfig {
    static let endpoint = URL(string: "https://ark.cn-beijing.volces.com/api/v3/responses")!
    static let model = "glm-5-3-flash-260828"
    static let apiKey = ProcessInfo.processInfo.environment["DIARY_AI_API_KEY"] ?? ""
    static func validatedKey(_ value: String) throws -> String {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw DiaryAIServiceError.missingCredential }
        guard !key.contains(where: { $0.isWhitespace || $0.isNewline }), !key.lowercased().hasPrefix("bearer") else {
            throw DiaryAIError.invalid("请输入完整 API Key，不要包含 Bearer 前缀、空格或换行。")
        }
        return key
    }
    static func requireAPIKey() throws -> String { try validatedKey(apiKey) }

}

nonisolated enum DiaryAIServiceError: LocalizedError, Sendable {
    case missingCredential
    case authentication
    case rejected(Int)
    var errorDescription: String? {
        switch self {
        case .missingCredential: "项目中的 AI 服务密钥为空，请检查 DiaryAITestConfig。尚未发送请求。"
        case .authentication: "AI 服务认证失败，请检查项目中的固定密钥和模型访问权限。当前排版进度已保留。"
        case .rejected(let status): "AI 服务未接受请求（HTTP \(status)），具体原因已记录到制作日志。当前排版进度已保留。"
        }
    }
    static func response(status: Int, code: String?, body: Data) -> DiaryAIServiceError {
        let object = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        let error = object?["error"] as? [String: Any]
        let message = error?["message"] as? String ?? ""
        if status == 401 || status == 403 || code?.hasPrefix("AuthN_") == true || message.contains("AuthHeader") {
            return .authentication
        }
        return .rejected(status)
    }
}
