import Foundation

/// Credential validation shared by the remote configuration adapters.
enum DiaryAITestConfig {
    static func validatedKey(_ value: String) throws -> String {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw DiaryAIServiceError.missingCredential }
        guard !key.contains(where: { $0.isWhitespace || $0.isNewline }), !key.lowercased().hasPrefix("bearer") else {
            throw DiaryAIError.invalid("请输入完整 API Key，不要包含 Bearer 前缀、空格或换行。")
        }
        return key
    }


}

nonisolated enum DiaryAIServiceError: LocalizedError, Sendable {
    case missingCredential
    case authentication
    case rejected(Int)
    var errorDescription: String? {
        switch self {
        case .missingCredential: "AI 服务配置尚未就绪，请稍后重试。尚未发送请求。"
        case .authentication: "AI 服务认证失败，请稍后重试或联系管理员。当前排版进度已保留。"
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
