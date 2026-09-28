import Foundation

nonisolated enum BackendErrorLocalizer {
    static func message(for backend: BackendError?, statusCode: Int? = nil) -> String {
        if let backend {
            if let embedded = embeddedUserMessage(from: backend.data), embedded.isEmpty == false {
                return embedded
            }

            let codeKey = "api_error.code.\(backend.code)"
            let codeText = L10n.text(codeKey, fallback: codeKey)
            if codeText != codeKey {
                return codeText
            }

            let msgKey = messageKey(for: backend.msg)
            let msgText = L10n.text(msgKey, fallback: msgKey)
            if msgText != msgKey {
                return msgText
            }

            let cleanMessage = backend.msg.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleanMessage.isEmpty == false {
                return cleanMessage
            }
        }

        if let statusCode {
            let statusKey = "api_error.http.\(statusCode)"
            let statusText = L10n.text(statusKey, fallback: statusKey)
            if statusText != statusKey {
                return statusText
            }
            return String(
                format: L10n.text("api_error.http.generic", fallback: "请求失败（HTTP %@），请稍后重试。"),
                "\(statusCode)"
            )
        }

        return L10n.text("api_error.unknown", fallback: "操作失败，请稍后重试。")
    }

    private static func embeddedUserMessage(from data: JSONValue?) -> String? {
        guard case .object(let obj) = data else { return nil }
        if case .string(let message) = obj["message"] {
            return message.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if case .string(let msg) = obj["msg"] {
            return msg.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private static func messageKey(for message: String) -> String {
        let normalized = message
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .map { character -> Character in
                if character.isLetter || character.isNumber {
                    return character
                }
                return "_"
            }
        let collapsed = String(normalized)
            .split(separator: "_")
            .joined(separator: "_")
        return "api_error.msg.\(collapsed.isEmpty ? "unknown" : collapsed)"
    }
}

