import Foundation

struct ModelCapabilityProbeSummary: Sendable {
    var supportsText: Bool
    var supportsMultimodal: Bool
    var supportsReasoning: Bool
    var reasoningControllable: Bool
    var supportsToolUse: Bool
    var supportsImageGen: Bool
}

enum ModelCapabilityProbeStep: String, CaseIterable, Sendable {
    case connectivity
    case text
    case multimodal
    case reasoning
    case toolUse
    case imageGen

    var titleKey: String {
        switch self {
        case .connectivity: return "ai_settings.models.online.probe.step.connectivity"
        case .text: return "ai_settings.models.online.probe.step.text"
        case .multimodal: return "ai_settings.models.online.probe.step.multimodal"
        case .reasoning: return "ai_settings.models.online.probe.step.reasoning"
        case .toolUse: return "ai_settings.models.online.probe.step.tool_use"
        case .imageGen: return "ai_settings.models.online.probe.step.image_gen"
        }
    }
}

enum ModelCapabilityProbeStatus: Sendable {
    case pending
    case running
    case success
    case failed
    case skipped
}

struct ModelCapabilityProbeProgressItem: Identifiable, Sendable {
    let id = UUID()
    let step: ModelCapabilityProbeStep
    var status: ModelCapabilityProbeStatus
    var message: String?
}

struct ClientModelCapabilityProbeService: Sendable {
    private let logger: Logger

    init(logger: Logger = ConsoleLogger()) {
        self.logger = logger
    }

    func testConnection(modelName: String, provider: APIKeys) async throws {
        let endpoint = provider.requestURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey = provider.key.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard endpoint.isEmpty == false, apiKey.isEmpty == false, model.isEmpty == false else {
            throw ProbeError.invalidInput
        }

        _ = try await requestChatCompletion(
            endpoint: endpoint,
            apiKey: apiKey,
            body: [
                "model": model,
                "messages": [["role": "user", "content": "Reply only 'pong'."]],
                "max_tokens": 16,
            ]
        )
    }

    func probe(
        modelName: String,
        provider: APIKeys,
        onUpdate: @Sendable (ModelCapabilityProbeStep, ModelCapabilityProbeStatus, String?) async -> Void
    ) async throws -> ModelCapabilityProbeSummary {
        let endpoint = provider.requestURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey = provider.key.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard endpoint.isEmpty == false, apiKey.isEmpty == false, model.isEmpty == false else {
            throw ProbeError.invalidInput
        }

        logger.info("能力探测开始 company=\(provider.company) model=\(model)", module: .aiConfig)

        let textOK = try await runStep(.connectivity, onUpdate: onUpdate) {
            try await requestChatCompletion(
                endpoint: endpoint,
                apiKey: apiKey,
                body: [
                    "model": model,
                    "messages": [["role": "user", "content": "Reply only 'pong'."]],
                    "max_tokens": 16,
                ]
            )
        }

        let supportsText: Bool
        if textOK {
            supportsText = try await runStep(.text, onUpdate: onUpdate) {
                _ = try await requestChatCompletion(
                    endpoint: endpoint,
                    apiKey: apiKey,
                    body: [
                        "model": model,
                        "messages": [["role": "user", "content": "Write one short sentence about health."]],
                        "max_tokens": 32,
                    ]
                )
            }
        } else {
            supportsText = false
        }

        let supportsMultimodal: Bool
        if supportsText {
            supportsMultimodal = try await runStep(.multimodal, onUpdate: onUpdate) {
                _ = try await requestChatCompletion(
                    endpoint: endpoint,
                    apiKey: apiKey,
                    body: [
                        "model": model,
                        "messages": [[
                            "role": "user",
                            "content": [
                                ["type": "text", "text": "Describe this image in one sentence."],
                                [
                                    "type": "image_url",
                                    "image_url": ["url": "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR4nGNgYAAAAAMAASsJTYQAAAAASUVORK5CYII="],
                                ],
                            ],
                        ]],
                        "max_tokens": 48,
                    ]
                )
            }
        } else {
            supportsMultimodal = false
        }

        let supportsReasoning: Bool
        if supportsText {
            supportsReasoning = try await runStep(.reasoning, onUpdate: onUpdate) {
                _ = try await requestChatCompletion(
                    endpoint: endpoint,
                    apiKey: apiKey,
                    body: [
                        "model": model,
                        "messages": [["role": "user", "content": "What is 122 + 57? Return only the number."]],
                        "temperature": 0,
                        "max_tokens": 16,
                    ]
                )
            }
        } else {
            supportsReasoning = false
        }

        let reasoningControllable = supportsReasoning

        let supportsToolUse: Bool
        if supportsText {
            supportsToolUse = try await runStep(.toolUse, onUpdate: onUpdate) {
                let payload = try await requestChatCompletion(
                    endpoint: endpoint,
                    apiKey: apiKey,
                    body: [
                        "model": model,
                        "messages": [["role": "user", "content": "Please call tool get_time and use timezone Asia/Shanghai."]],
                        "tools": [[
                            "type": "function",
                            "function": [
                                "name": "get_time",
                                "description": "Return current time",
                                "parameters": [
                                    "type": "object",
                                    "properties": [
                                        "timezone": [
                                            "type": "string",
                                            "description": "IANA timezone",
                                        ],
                                    ],
                                    "required": ["timezone"],
                                ],
                            ],
                        ]],
                        "tool_choice": "auto",
                        "max_tokens": 48,
                    ]
                )
                guard hasToolCalls(payload) else {
                    throw ProbeError.noToolCalls
                }
            }
        } else {
            supportsToolUse = false
        }

        let supportsImageGen = try await runStep(.imageGen, onUpdate: onUpdate) {
            guard endpoint.hasSuffix("/chat/completions") else {
                throw ProbeError.unsupportedImageProbe
            }
            let imageEndpoint = endpoint.replacingOccurrences(of: "/chat/completions", with: "/images/generations")
            _ = try await requestJSON(
                endpoint: imageEndpoint,
                apiKey: apiKey,
                body: [
                    "model": model,
                    "prompt": "A minimal logo with blue spark.",
                    "size": "512x512",
                ]
            )
        }

        logger.info(
            "能力探测完成 company=\(provider.company) model=\(model) text=\(supportsText) multimodal=\(supportsMultimodal) reasoning=\(supportsReasoning) tools=\(supportsToolUse) image=\(supportsImageGen)",
            module: .aiConfig
        )

        return ModelCapabilityProbeSummary(
            supportsText: supportsText,
            supportsMultimodal: supportsMultimodal,
            supportsReasoning: supportsReasoning,
            reasoningControllable: reasoningControllable,
            supportsToolUse: supportsToolUse,
            supportsImageGen: supportsImageGen
        )
    }

    private func runStep(
        _ step: ModelCapabilityProbeStep,
        onUpdate: @Sendable (ModelCapabilityProbeStep, ModelCapabilityProbeStatus, String?) async -> Void,
        action: () async throws -> Void
    ) async throws -> Bool {
        await onUpdate(step, .running, nil)
        do {
            try await action()
            await onUpdate(step, .success, nil)
            return true
        } catch {
            await onUpdate(step, .failed, error.localizedDescription)
            logger.warning("能力探测 step=\(step.rawValue) 失败：\(error.localizedDescription)", module: .aiConfig)
            return false
        }
    }

    private func requestChatCompletion(
        endpoint: String,
        apiKey: String,
        body: [String: Any]
    ) async throws -> [String: Any] {
        try await requestJSON(endpoint: endpoint, apiKey: apiKey, body: body)
    }

    private func requestJSON(
        endpoint: String,
        apiKey: String,
        body: [String: Any]
    ) async throws -> [String: Any] {
        guard let url = URL(string: endpoint) else {
            throw ProbeError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProbeError.invalidResponse
        }
        guard 200..<300 ~= http.statusCode else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw ProbeError.httpFailed(code: http.statusCode, message: text)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProbeError.invalidPayload
        }
        return json
    }

    private func hasToolCalls(_ payload: [String: Any]) -> Bool {
        guard
            let choices = payload["choices"] as? [[String: Any]],
            let first = choices.first,
            let message = first["message"] as? [String: Any]
        else { return false }
        let toolCalls = message["tool_calls"] as? [[String: Any]]
        return (toolCalls?.isEmpty == false)
    }
}

enum ProbeError: LocalizedError {
    case invalidInput
    case invalidURL
    case invalidResponse
    case invalidPayload
    case noToolCalls
    case unsupportedImageProbe
    case httpFailed(code: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidInput:
            return L10n.text("ai_settings.models.online.probe.err.invalid_input")
        case .invalidURL:
            return L10n.text("ai_settings.models.online.probe.err.invalid_url")
        case .invalidResponse:
            return L10n.text("ai_settings.models.online.probe.err.invalid_response")
        case .invalidPayload:
            return L10n.text("ai_settings.models.online.probe.err.invalid_payload")
        case .noToolCalls:
            return L10n.text("ai_settings.models.online.probe.err.no_tool_calls")
        case .unsupportedImageProbe:
            return L10n.text("ai_settings.models.online.probe.err.unsupported_image_probe")
        case .httpFailed(let code, let message):
            if message.isEmpty {
                return L10n.format("ai_settings.models.online.probe.err.http_failed", code)
            }
            return L10n.format("ai_settings.models.online.probe.err.http_failed_detail", code, message)
        }
    }
}
