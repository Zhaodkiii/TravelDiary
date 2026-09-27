import Foundation

struct ProviderRemoteModel: Identifiable, Equatable, Sendable {
    var id: String { name }
    let name: String
    let displayName: String
    let ownedBy: String
    let supportsText: Bool
    let supportsMultimodal: Bool
    let supportsReasoning: Bool
    let supportsToolUse: Bool
    let supportsImageGen: Bool
}

struct ProviderModelCatalogService: Sendable {
    private let session: URLSession
    private let logger: Logger

    nonisolated init(session: URLSession = .shared, logger: Logger = ConsoleLogger()) {
        self.session = session
        self.logger = logger
    }

    func fetchModels(for provider: APIKeys) async throws -> [ProviderRemoteModel] {
        let endpoint = provider.requestURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey = provider.key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard endpoint.isEmpty == false, apiKey.isEmpty == false else {
            throw ProviderModelCatalogError.invalidProvider
        }

        let kind = endpointKind(for: endpoint)
        logger.info("开始刷新厂商模型列表 company=\(provider.company) kind=\(kind.rawValue)", module: .aiConfig)

        let models: [ProviderRemoteModel]
        switch kind {
        case .openAICompatible:
            models = try await fetchOpenAICompatibleModels(endpoint: endpoint, apiKey: apiKey)
        case .anthropic:
            models = try await fetchAnthropicModels(apiKey: apiKey)
        case .gemini:
            models = try await fetchGeminiModels(endpoint: endpoint, apiKey: apiKey)
        }

        let filtered = models
            .filter { $0.supportsText || $0.supportsImageGen }
            .uniqued(by: \.name)
            .sorted {
                $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
            }

        logger.info("厂商模型列表刷新完成 company=\(provider.company) count=\(filtered.count)", module: .aiConfig)
        return filtered
    }

    private func fetchOpenAICompatibleModels(endpoint: String, apiKey: String) async throws -> [ProviderRemoteModel] {
        let url = try listURLForOpenAICompatibleEndpoint(endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let payload = try await requestJSON(request)

        guard let data = payload["data"] as? [[String: Any]] else {
            throw ProviderModelCatalogError.invalidResponse
        }

        return data.compactMap { item in
            guard let rawName = item["id"] as? String else { return nil }
            return modelFromName(
                rawName,
                displayName: rawName,
                ownedBy: item["owned_by"] as? String ?? ""
            )
        }
    }

    private func fetchAnthropicModels(apiKey: String) async throws -> [ProviderRemoteModel] {
        guard let url = URL(string: "https://api.anthropic.com/v1/models") else {
            throw ProviderModelCatalogError.invalidProvider
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let payload = try await requestJSON(request)

        guard let data = payload["data"] as? [[String: Any]] else {
            throw ProviderModelCatalogError.invalidResponse
        }

        return data.compactMap { item in
            guard let rawName = item["id"] as? String else { return nil }
            let displayName = item["display_name"] as? String ?? rawName
            return modelFromName(rawName, displayName: displayName, ownedBy: "Anthropic")
        }
    }

    private func fetchGeminiModels(endpoint: String, apiKey: String) async throws -> [ProviderRemoteModel] {
        guard var components = URLComponents(string: endpoint) else {
            throw ProviderModelCatalogError.invalidProvider
        }
        components.queryItems = (components.queryItems ?? []) + [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "pageSize", value: "1000"),
        ]
        guard let url = components.url else {
            throw ProviderModelCatalogError.invalidProvider
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let payload = try await requestJSON(request)

        guard let models = payload["models"] as? [[String: Any]] else {
            throw ProviderModelCatalogError.invalidResponse
        }

        return models.compactMap { item -> ProviderRemoteModel? in
            guard let rawName = item["name"] as? String else { return nil }
            let generationMethods = item["supportedGenerationMethods"] as? [String] ?? []
            let supportsImageGen = generationMethods.contains("generateImages")
            let supportsText = generationMethods.contains("generateContent") || generationMethods.contains("streamGenerateContent")
            guard supportsText || supportsImageGen else { return nil }

            let rawDisplayName = item["displayName"] as? String
            let displayName: String
            if let rawDisplayName, rawDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                displayName = rawDisplayName
            } else {
                displayName = rawName.replacingOccurrences(of: "models/", with: "")
            }

            guard let model = modelFromName(
                rawName.replacingOccurrences(of: "models/", with: ""),
                displayName: displayName,
                ownedBy: "Google"
            ) else {
                return nil
            }

            return ProviderRemoteModel(
                name: model.name,
                displayName: model.displayName,
                ownedBy: model.ownedBy,
                supportsText: supportsText,
                supportsMultimodal: true,
                supportsReasoning: model.supportsReasoning,
                supportsToolUse: generationMethods.contains("generateContent"),
                supportsImageGen: supportsImageGen
            )
        }
    }

    private func requestJSON(_ request: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderModelCatalogError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ProviderModelCatalogError.requestFailed(statusCode: http.statusCode, body: body)
        }
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw ProviderModelCatalogError.invalidResponse
        }
        return json
    }

    private func listURLForOpenAICompatibleEndpoint(_ endpoint: String) throws -> URL {
        guard var components = URLComponents(string: endpoint) else {
            throw ProviderModelCatalogError.invalidProvider
        }
        let path = components.path
        if path.hasSuffix("/models") == false {
            let replacements = [
                "/chat/completions",
                "/responses",
                "/completions",
                "/messages",
            ]
            if let matched = replacements.first(where: { path.hasSuffix($0) }) {
                components.path = String(path.dropLast(matched.count)) + "/models"
            } else {
                let normalizedPath = path.hasSuffix("/") ? String(path.dropLast()) : path
                components.path = normalizedPath + "/models"
            }
        }
        components.query = nil
        guard let url = components.url else {
            throw ProviderModelCatalogError.invalidProvider
        }
        return url
    }

    private func endpointKind(for endpoint: String) -> ProviderEndpointKind {
        let normalized = endpoint.lowercased()
        if normalized.contains("generativelanguage.googleapis.com") {
            return .gemini
        }
        if normalized.contains("api.anthropic.com") || normalized.hasSuffix("/v1/messages") {
            return .anthropic
        }
        return .openAICompatible
    }

    private func modelFromName(_ rawName: String, displayName: String, ownedBy: String) -> ProviderRemoteModel? {
        let normalizedName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedName.isEmpty == false else { return nil }

        let lowercased = normalizedName.lowercased()
        if lowercased.contains("embedding") || lowercased.contains("moderation") {
            return nil
        }

        let supportsImageGen = lowercased.contains("image") || lowercased.contains("dall-e")
        let isAudioOnly = lowercased.contains("whisper")
            || lowercased.contains("tts")
            || lowercased.contains("transcribe")
            || lowercased.contains("realtime")
            || lowercased.contains("audio")
        let supportsText = supportsImageGen == false && isAudioOnly == false
        let supportsMultimodal = supportsText && (
            lowercased.contains("gpt-4o")
            || lowercased.contains("gpt-4.1")
            || lowercased.contains("gpt-5")
            || lowercased.contains("gemini")
            || lowercased.contains("claude")
            || lowercased.contains("vision")
            || lowercased.contains("vl")
            || lowercased.contains("omni")
        )
        let supportsReasoning = supportsText && (
            lowercased.contains("reason")
            || lowercased.contains("thinking")
            || lowercased.contains("o1")
            || lowercased.contains("o3")
            || lowercased.contains("o4")
            || lowercased.contains("gpt-5")
            || lowercased.contains("sonnet")
            || lowercased.contains("opus")
            || lowercased.contains("pro")
        )

        return ProviderRemoteModel(
            name: normalizedName,
            displayName: displayName,
            ownedBy: ownedBy,
            supportsText: supportsText,
            supportsMultimodal: supportsMultimodal,
            supportsReasoning: supportsReasoning,
            supportsToolUse: supportsText,
            supportsImageGen: supportsImageGen
        )
    }
}

private enum ProviderEndpointKind: String {
    case openAICompatible
    case anthropic
    case gemini
}

enum ProviderModelCatalogError: LocalizedError {
    case invalidProvider
    case invalidResponse
    case requestFailed(statusCode: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .invalidProvider:
            return "请先填写有效的请求地址和 API Key"
        case .invalidResponse:
            return "模型列表返回格式无法识别"
        case .requestFailed(let statusCode, let body):
            let message = body.trimmingCharacters(in: .whitespacesAndNewlines)
            if message.isEmpty {
                return "刷新模型列表失败（HTTP \(statusCode)）"
            }
            return "刷新模型列表失败（HTTP \(statusCode)）：\(message)"
        }
    }
}

private extension Array {
    func uniqued<T: Hashable>(by keyPath: KeyPath<Element, T>) -> [Element] {
        var seen: Set<T> = []
        return filter { seen.insert($0[keyPath: keyPath]).inserted }
    }
}
