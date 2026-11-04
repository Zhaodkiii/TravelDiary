import Foundation

/// SSE frames are assembled before decoding; no partial tool arguments leave the adapter.
nonisolated struct DiaryAIStreamDecoder {
    private var dataLines: [String] = []
    private var bufferedBytes = 0
    private(set) var completed: Data?
    mutating func acceptNetworkLine(_ line: String) throws -> Bool {
        var completeEvent = try accept(line)
        // Foundation's lines sequence may omit blank separators; Ark uses complete JSON data lines.
        if line.hasPrefix("data:") {
            let payload = Data(line.dropFirst(5).trimmingCharacters(in: .whitespaces).utf8)
            if (try? JSONSerialization.jsonObject(with: payload)) != nil || String(decoding: payload, as: UTF8.self) == "[DONE]" {
                completeEvent = try accept("") || completeEvent
            }
        }
        return completeEvent
    }
    mutating func accept(_ line: String) throws -> Bool {
        if line.isEmpty {
            guard !dataLines.isEmpty else { return false }
            let data = Data(dataLines.joined(separator: "\n").utf8)
            dataLines.removeAll(keepingCapacity: true); bufferedBytes = 0
            if String(decoding: data, as: UTF8.self) == "[DONE]" { return true }
            guard let event = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw DiaryAIError.invalid("流式事件格式无效") }
            switch event["type"] as? String {
            case "response.completed":
                guard let response = event["response"] as? [String: Any] else { throw DiaryAIError.invalid("流式响应缺少完成结果") }
                completed = try JSONSerialization.data(withJSONObject: response)
            case "response.failed", "response.incomplete", "error": throw DiaryAIError.invalid("模型响应失败或不完整；未提交的工具不会执行，请重试当前批次。")
            default: break
            }
            return true
        }
        if line.hasPrefix("data:") {
            let value = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            bufferedBytes += value.utf8.count
            guard bufferedBytes <= 8_000_000 else { throw DiaryAIError.invalid("流式事件超过大小限制") }
            dataLines.append(value)
        }
        return false
    }
}

enum DiaryAIRequestLimits {
    static let idleTimeout: TimeInterval = 120
    static let requestDeadline: TimeInterval = 240
    static let batchDeadline: TimeInterval = 600
}

/// JSON parsing of stream frames never executes on the UI actor.
actor DiaryAIStreamParser {
    private var decoder = DiaryAIStreamDecoder()
    func accept(_ line: String) throws -> (event: Bool, completed: Data?) {
        let event = try decoder.acceptNetworkLine(line)
        return (event, decoder.completed)
    }
}
