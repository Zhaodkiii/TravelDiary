import Foundation

/// Stateless application protocol; the opaque continuation is exclusively owned by this adapter.
@MainActor final class DiaryArkResponsesClient: DiaryAIModelClient {
    weak var productionLog: DiaryAIProductionLog?
    var expectedWorkspaceVersion: Int?
    var requiresBackgroundDesign = false
    var workspaceMode = false
    var planning = false
    var contentTextCount: ClosedRange<Int>?
    var allowedLayerReferences: [String]?
    var allowedWorkspaceTools: Set<String>?
    var onTransportEvent: ((String, String) -> Void)?
    let runtime: DiaryAITaskRuntime
    private let session: URLSession
    init(session: URLSession? = nil, runtime: DiaryAITaskRuntime = DiaryAITaskRuntime()) {
        self.runtime = runtime
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = DiaryAIRequestLimits.idleTimeout
        configuration.timeoutIntervalForResource = DiaryAIRequestLimits.requestDeadline
        configuration.urlCache = nil
        self.session = session ?? URLSession(configuration: configuration, delegate: DiaryAIRejectRedirects.shared, delegateQueue: nil)
        runtime.register(self.session)
    }

    static func tools() -> [[String: Any]] {
        let names = ["get_canvas_context", "inspect_assets", "list_available_fonts", "get_style_reference", "propose_layout", "render_draft", "validate_draft", "finish_candidate"]
        return names.map { name in
            var properties: [String: Any] = ["contextID": ["type": "string"]]
            var required = ["contextID"]
            if name == "inspect_assets" {
                properties["objectIDs"] = ["type": "array", "items": ["type": "string"], "maxItems": 3]
                properties["view"] = ["type": "string", "enum": ["fullAsset", "currentCrop", "canvasRegion"]]
                required += ["objectIDs", "view"]
            }
            if name == "propose_layout" {
                // Local decoding and operation-specific field/permission validation remain authoritative.
                properties["plan"] = ["type": "object", "properties": [
                    "schemaVersion": ["type": "integer"], "contextID": ["type": "string"],
                    "baseDigest": ["type": "string"], "summary": ["type": "string"],
                    "operations": ["type": "array", "maxItems": 200, "items": ["type": "object"]]
                ], "required": ["schemaVersion", "contextID", "baseDigest", "summary", "operations"]]
                required.append("plan")
            }
            if ["render_draft", "validate_draft", "finish_candidate"].contains(name) {
                properties["draftRevision"] = ["type": "integer"]; required.append("draftRevision")
            }
            return ["type": "function", "name": name, "description": name == "propose_layout" ? "Submit a complete plan from the immutable base. Returns validated draft and preview for visual review." : name,
                    "parameters": ["type": "object", "properties": properties, "required": required, "additionalProperties": false]]
        }
    }

    func respond(prompt: String?, images: [DiaryAIImage], continuation: Data?, results: [DiaryAIToolResult]) async throws -> DiaryAIModelReply {
        var access = try await runtime.access("diary.layout")
        var apiKey = access.credential.secret
        productionLog?.registerSecret(apiKey)
        var history = try continuation.map { try JSONSerialization.jsonObject(with: $0) as? [[String: Any]] ?? [] } ?? []
        func imageParts(_ values: [DiaryAIImage]) -> [[String: Any]] {
            values.flatMap { image in [
                ["type": "input_text", "text": "Image \(image.id): \(image.caption)"],
                ["type": "input_image", "image_url": "data:image/jpeg;base64,\(image.data.base64EncodedString())"]
            ] }
        }
        if let prompt { history.append(["role": "user", "content": [["type": "input_text", "text": prompt]] + imageParts(images)]) }
        for result in results { history.append(["type": "function_call_output", "call_id": result.callID, "output": result.text]) }
        let feedbackImages = results.flatMap(\.images)
        if !feedbackImages.isEmpty { history.append(["role": "user", "content": imageParts(feedbackImages)]) }
        var request = URLRequest(url: access.scene.endpoint)
        request.httpMethod = "POST"; request.timeoutInterval = min(DiaryAIRequestLimits.idleTimeout, Double(access.scene.limits.requestTimeoutSeconds))
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        var selectedTools = workspaceMode ? DiaryAIWorkspaceTools.schemas.filter { tool in
            guard let name = tool["name"] as? String else { return false }
            return planning ? name == "plan_composition" : name != "plan_composition" && (allowedWorkspaceTools?.contains(name) ?? true)
        } : Self.tools()
        if let contentTextCount { selectedTools = [DiaryNativeContent.schema(textCount: contentTextCount)] }
        if workspaceMode, planning, let references = allowedLayerReferences, !references.isEmpty {
            for index in selectedTools.indices {
                guard var parameters = selectedTools[index]["parameters"] as? [String: Any], var properties = parameters["properties"] as? [String: Any], var regions = properties["regions"] as? [String: Any], var items = regions["items"] as? [String: Any], var fields = items["properties"] as? [String: Any] else { continue }
                fields["objectID"] = ["type": "string", "enum": references]
                items["properties"] = fields; regions["items"] = items; properties["regions"] = regions; parameters["properties"] = properties; selectedTools[index]["parameters"] = parameters
            }
        }
        if workspaceMode, !planning, let references = allowedLayerReferences {
            if references.isEmpty {
                selectedTools.removeAll { tool in
                    let parameters = tool["parameters"] as? [String: Any]
                    let properties = parameters?["properties"] as? [String: Any]
                    return properties?["objectID"] != nil || properties?["objectIDs"] != nil
                }
            }
            for index in selectedTools.indices {
                guard var parameters = selectedTools[index]["parameters"] as? [String: Any], var properties = parameters["properties"] as? [String: Any] else { continue }
                if var object = properties["objectID"] as? [String: Any] { object["enum"] = references; properties["objectID"] = object }
                if var objects = properties["objectIDs"] as? [String: Any] { objects["items"] = ["type": "string", "enum": references]; properties["objectIDs"] = objects }
                parameters["properties"] = properties; selectedTools[index]["parameters"] = parameters
            }
        }
        if requiresBackgroundDesign && workspaceMode && !planning {
            for index in selectedTools.indices where selectedTools[index]["name"] as? String == "finish_batch" {
                guard var parameters = selectedTools[index]["parameters"] as? [String: Any] else { continue }
                parameters["required"] = (parameters["required"] as? [String] ?? []) + ["backgroundBrief", "backgroundPrompt"]
                selectedTools[index]["parameters"] = parameters
            }
        }
        if workspaceMode, expectedWorkspaceVersion != nil {
            for index in selectedTools.indices {
                guard var parameters = selectedTools[index]["parameters"] as? [String: Any], var properties = parameters["properties"] as? [String: Any] else { continue }
                properties.removeValue(forKey: "expectedVersion")
                if let required = parameters["required"] as? [String] { parameters["required"] = required.filter { $0 != "expectedVersion" } }
                for key in ["width", "fontSize"] {
                    if var field = properties[key] as? [String: Any] { field["exclusiveMinimum"] = 0; properties[key] = field }
                }
                parameters["properties"] = properties; selectedTools[index]["parameters"] = parameters
            }
        }
        var requestBody: [String: Any] = ["model": access.scene.modelId, "input": history,
            "tools": selectedTools,
            "tool_choice": workspaceMode ? "required" : "auto",
            "thinking": ["type": "enabled"], "reasoning": ["effort": "low"],
            "stream": true, "max_output_tokens": planning ? 4096 : 8192, "store": false]
        requestBody.merge(access.scene.parameters.mapValues(\.foundation)) { _, new in new }
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        var received: Data?
        var refreshedCredential = false
        for attempt in 0..<3 {
            try Task.checkCancellation()
            try runtime.assertOwner()
            let started = Date()
            onTransportEvent?("开始连接模型服务", "规划：\(planning ? "是" : "否") · 思考：\("low")")
            productionLog?.record("request", ["endpoint": request.url!.absoluteString, "attempt": attempt])
            if let body = request.httpBody { productionLog?.data("request-body", body) }
            let (bytes, response) = try await session.bytes(for: request)
            productionLog?.record("response-status", ["status": (response as? HTTPURLResponse)?.statusCode ?? 0, "headers": (response as? HTTPURLResponse)?.allHeaderFields.reduce(into: [String: String]()) { $0[String(describing: $1.key)] = String(describing: $1.value) } ?? [:]])
            onTransportEvent?("已收到响应头", String(format: "连接并收到响应头 %.2f 秒", Date().timeIntervalSince(started)))
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (200..<300).contains(status) {
                guard (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type")?.contains("text/event-stream") == true else {
                    throw DiaryAIError.invalid("接口未返回 SSE 流，未执行任何未提交操作。")
                }
                let parser = DiaryAIStreamParser()
                var firstEvent = false
                for try await line in bytes.lines {
                    try Task.checkCancellation()
                    try runtime.assertOwner()
                    guard Date().timeIntervalSince(started) < DiaryAIRequestLimits.requestDeadline else {
                        throw DiaryAIError.invalid("本次模型请求超过总时限，已提交批次保留。手动重试会发起新请求，可能再次计费。")
                    }
                    if line.hasPrefix("data:"), let payload = line.dropFirst(5).data(using: .utf8) { productionLog?.data("sse", payload) }
                    else if !line.isEmpty && !line.hasPrefix("event:") { productionLog?.record("sse", ["line": line]) }
                    let parsed = try await parser.accept(line)
                    if parsed.event, !firstEvent {
                        firstEvent = true
                        onTransportEvent?("已收到首个流式事件", String(format: "首事件耗时 %.2f 秒", Date().timeIntervalSince(started)))
                    }
                    if let completed = parsed.completed { received = completed; break }
                }
                guard received != nil else { throw DiaryAIError.invalid("流式连接中断，未收到完整结果。已提交批次保留；重试可能产生新请求和费用。") }
                onTransportEvent?("模型输出完整接收", String(format: "本次耗时 %.2f 秒；工具参数现在才进入校验", Date().timeIntervalSince(started)))
                break
            }
            var errorBody = Data()
            for try await byte in bytes {
                errorBody.append(byte)
                if errorBody.count >= 16_384 { break }
            }
            let sanitizedBody = Data(String(decoding: errorBody, as: UTF8.self).replacingOccurrences(of: apiKey, with: "[REDACTED]").utf8)
            productionLog?.data("response-error", sanitizedBody)
            if status == 401, !refreshedCredential, attempt < 2 {
                refreshedCredential = true
                let fresh = try await runtime.access("diary.layout", force: true)
                if fresh.credential.version != access.credential.version {
                    access = fresh; apiKey = fresh.credential.secret
                    productionLog?.registerSecret(apiKey)
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    continue
                }
            }
            if status == 429, attempt < 2 {
                let delay = min(15, max(1, Double((response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Retry-After") ?? "") ?? Double(2 << attempt)))
                try await Task.sleep(for: .seconds(delay)); continue
            }
            let serviceError = DiaryAIServiceError.response(status: status, code: (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "x-error-code"), body: sanitizedBody)
            if case .authentication = serviceError { throw serviceError }
            let message: String
            switch status {
            case 404: message = "当前模型或接口不可用，请确认模型访问权限。"
            case 429: message = "请求过于频繁，请稍后重试。"
            case 400, 422: throw serviceError
            default: message = "模型服务暂不可用（HTTP \(status)），请重试。"
            }
            throw DiaryAIError.invalid(message)
        }
        guard let data = received else { throw DiaryAIError.invalid("模型服务未返回结果") }
        productionLog?.data("response-body", data)
        let reply = try Self.decode(data, maximumCalls: workspaceMode ? 30 : 12)
        let calls = try reply.calls.map { call in
            guard workspaceMode, let version = expectedWorkspaceVersion else { return call }
            // Invalid arguments are reported by the tool runtime per call, so one bad call cannot discard valid siblings.
            return (try? Self.bindVersion(call, version: version)) ?? call
        }
        let body = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        history += body["output"] as? [[String: Any]] ?? []
        return DiaryAIModelReply(calls: calls, text: reply.text, continuation: try JSONSerialization.data(withJSONObject: history), inputTokens: reply.inputTokens, outputTokens: reply.outputTokens)
    }

    static func bindVersion(_ call: DiaryAIToolCall, version: Int) throws -> DiaryAIToolCall {
        guard var raw = try JSONSerialization.jsonObject(with: Data(call.arguments.utf8)) as? [String: Any] else { throw DiaryAIError.invalid("工具参数必须为对象") }
        if let supplied = raw["expectedVersion"] {
            guard !(supplied is String), supplied as? Int == version else { throw DiaryAIError.invalid("模型返回过期或无效版本，未执行操作") }
        }
        raw["expectedVersion"] = version
        return .init(id: call.id, name: call.name, arguments: String(decoding: try JSONSerialization.data(withJSONObject: raw), as: UTF8.self))
    }
    static func decode(_ data: Data, maximumCalls: Int = 12) throws -> DiaryAIModelReply {
        guard let body = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              body["status"] as? String == "completed", let output = body["output"] as? [[String: Any]] else {
            throw DiaryAIError.invalid("模型响应不完整，没有应用任何修改。")
        }
        var calls: [DiaryAIToolCall] = [], text = ""
        for item in output {
            if item["type"] as? String == "function_call" {
                guard let id = item["call_id"] as? String, let name = item["name"] as? String,
                      let arguments = item["arguments"] as? String, arguments.utf8.count <= 256_000 else { throw DiaryAIError.invalid("工具参数无效") }
                calls.append(.init(id: id, name: name, arguments: arguments))
            }
            for part in item["content"] as? [[String: Any]] ?? [] where part["type"] as? String == "output_text" { text += part["text"] as? String ?? "" }
        }
        guard calls.count <= maximumCalls, Set(calls.map(\.id)).count == calls.count else { throw DiaryAIError.invalid("工具调用重复或过多") }
        let usage = body["usage"] as? [String: Any]
        return .init(calls: calls, text: text, continuation: Data(), inputTokens: usage?["input_tokens"] as? Int, outputTokens: usage?["output_tokens"] as? Int)
    }
}
