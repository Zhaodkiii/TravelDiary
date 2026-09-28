import Foundation

struct ProviderConnectionTestResult: Codable, Sendable {
    let ok: Bool?
    let reachable: Bool?
    let message: String?

    var isReachable: Bool { reachable ?? ok ?? false }

    init(reachable: Bool, message: String?) {
        self.ok = reachable
        self.reachable = reachable
        self.message = message
    }
}

struct SupportAIConfigAPI {
    let configuration: SupportBackendConfiguration

    init(configuration: SupportBackendConfiguration) {
        self.configuration = configuration
    }

    init(engine: SupportNetworkEngine) {
        self.configuration = SupportBackendConfiguration(
            engine: engine,
            deviceCache: engine.cache(),
            logger: engine.networkLogger
        )
    }

    func fetchBootstrapPatch(
        platform: String = "ios",
        clientVersion: String? = nil
    ) async throws -> AIRemoteSettingsPatch {
        var queryItems: [URLQueryItem] = [URLQueryItem(name: "platform", value: platform)]
        if let clientVersion, clientVersion.isEmpty == false {
            queryItems.append(URLQueryItem(name: "client_version", value: clientVersion))
        }

        let operation = CacheableSupportNetworkOperation(
            name: "AIConfig.Bootstrap",
            apiName: "AIConfigAPI",
            request: SupportNetworkRequest(
                method: .get,
                path: "/api/v1/ai/config/bootstrap/",
                queryItems: queryItems,
                strategy: NetworkStrategy(
                    requiresAuth: true,
                    allowETag: true,
                    serialKey: "ai.config.bootstrap",
                    retryConfig: .default,
                    isIdempotent: true,
                    queuePriority: .normal,
                    etagTTL: 60
                )
            )
        )

        let response = try await configuration.execute(operation)
        let payload = try SupportAPIResponseDecoder.decodeWrappedData(RemoteAIBootstrapPayload.self, from: response)
        return payload.toPatch()
    }

    /// 兼容旧调用名。
    func fetchBootstrap() async throws -> AIRemoteSettingsPatch {
        try await fetchBootstrapPatch()
    }

    func fetchTrialStatus() async throws -> AITrialState {
        let operation = CacheableSupportNetworkOperation(
            name: "AIConfig.TrialStatus",
            apiName: "AIConfigAPI",
            request: SupportNetworkRequest(
                method: .get,
                path: "/api/v1/ai/trial/status/",
                strategy: NetworkStrategy(
                    requiresAuth: true,
                    allowETag: false,
                    serialKey: "ai.trial.status",
                    retryConfig: .default,
                    isIdempotent: true,
                    queuePriority: .normal
                )
            )
        )
        let response = try await configuration.execute(operation)
        let payload = try SupportAPIResponseDecoder.decodeWrappedData(RemoteTrialStatusPayload.self, from: response)
        return payload.toModel()
    }

    func applyTrial(note: String = "") async throws -> AITrialApplicationSubmission {
        nonisolated struct ApplyTrialBody: Encodable {
            let note: String
        }
        let operation = CacheableSupportNetworkOperation(
            name: "AIConfig.TrialApply",
            apiName: "AIConfigAPI",
            request: SupportNetworkRequest(
                method: .post,
                path: "/api/v1/ai/trial/apply/",
                body: .json(AnyEncodable(ApplyTrialBody(note: note))),
                strategy: NetworkStrategy(
                    requiresAuth: true,
                    allowETag: false,
                    serialKey: "ai.trial.apply",
                    retryConfig: .default,
                    isIdempotent: false,
                    queuePriority: .high
                )
            )
        )
        let response = try await configuration.execute(operation)
        let payload = try SupportAPIResponseDecoder.decodeWrappedData(RemoteTrialApplySubmissionPayload.self, from: response)
        return payload.toModel()
    }

    func testProviderConnection(requestURL: String, apiKey: String, model: String) async throws -> ProviderConnectionTestResult {
        nonisolated struct TestProviderBody: Encodable {
            let request_url: String
            let api_key: String
            let model: String
        }
        let operation = CacheableSupportNetworkOperation(
            name: "AIConfig.ProviderConnectionTest",
            apiName: "AIConfigAPI",
            request: SupportNetworkRequest(
                method: .post,
                path: "/api/v1/ai/providers/test-connection/",
                body: .json(
                    AnyEncodable(
                        TestProviderBody(
                            request_url: requestURL,
                            api_key: apiKey,
                            model: model
                        )
                    )
                ),
                strategy: NetworkStrategy(
                    requiresAuth: true,
                    allowETag: false,
                    serialKey: "ai.provider.test_connection",
                    retryConfig: .default,
                    isIdempotent: false,
                    queuePriority: .high
                )
            )
        )
        let response = try await configuration.execute(operation)
        return try SupportAPIResponseDecoder.decodeWrappedData(ProviderConnectionTestResult.self, from: response)
    }

    func testProviderConnection(providerID: String, requestURL: String, apiKey: String) async throws -> ProviderConnectionTestResult {
        try await testProviderConnection(requestURL: requestURL, apiKey: apiKey, model: providerID)
    }
}

struct BackendAIRemoteConfigProvider: AIRemoteConfigProvider, @unchecked Sendable {
    private let api: SupportAIConfigAPI
    private let platform: String
    private let clientVersion: String?

    init(
        api: SupportAIConfigAPI,
        platform: String = "ios",
        clientVersion: String? = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    ) {
        self.api = api
        self.platform = platform
        self.clientVersion = clientVersion
    }

    func fetchRemotePatch() async throws -> AIRemoteSettingsPatch {
        try await api.fetchBootstrapPatch(platform: platform, clientVersion: clientVersion)
    }
}

private struct RemoteAIBootstrapPayload: Decodable {
    let revision: String?
    let scenarios: RemoteScenarioCollection?
    let smallTasks: [SmallTask]?

    func toPatch() -> AIRemoteSettingsPatch {
        let smallTasks = smallTasks ?? []
        guard let scenarios else {
            return AIRemoteSettingsPatch(revision: revision, scenarioRemoteBundles: nil, smallTasks: smallTasks)
        }
        return AIRemoteSettingsPatch(
            revision: revision,
            scenarioRemoteBundles: scenarios.asProScenarioCollection(),
            smallTasks: smallTasks
        )
    }
}

private struct RemoteScenarioCollection: Decodable {
    let chat: AIScenarioRemoteBundle?
    let embedding: AIScenarioRemoteBundle?
    let voice: AIScenarioRemoteBundle?
    let supportTicketAnalysis: AIScenarioRemoteBundle?
    let supportReplyDraft: AIScenarioRemoteBundle?
    let supportKnowledgeAnswer: AIScenarioRemoteBundle?
    let optimizationText: AIScenarioRemoteBundle?
    let optimizationVisual: AIScenarioRemoteBundle?
    let contextFolding: AIScenarioRemoteBundle?
    let router: AIScenarioRemoteBundle?
    let modelConfig: AIScenarioRemoteBundle?

    // 兼容后端仍下发医疗场景 key 时映射到 Support 场景
    let medicalStructuredExtraction: AIScenarioRemoteBundle?
    let medicalReportExtraction: AIScenarioRemoteBundle?
    let prescriptionExtraction: AIScenarioRemoteBundle?

    func asProScenarioCollection() -> AIScenarioRemoteBundlesCollection {
        let empty = AIScenarioRemoteBundle(defaultModelName: "", models: [])
        return AIScenarioRemoteBundlesCollection(
            chat: markPro(chat) ?? empty,
            embedding: markPro(embedding) ?? empty,
            voice: markPro(voice) ?? empty,
            supportTicketAnalysis: markPro(supportTicketAnalysis) ?? markPro(medicalStructuredExtraction) ?? empty,
            supportReplyDraft: markPro(supportReplyDraft) ?? markPro(prescriptionExtraction) ?? empty,
            supportKnowledgeAnswer: markPro(supportKnowledgeAnswer) ?? markPro(medicalReportExtraction) ?? empty,
            optimizationText: markPro(optimizationText) ?? empty,
            optimizationVisual: markPro(optimizationVisual) ?? empty,
            contextFolding: markPro(contextFolding) ?? empty,
            router: markPro(router) ?? empty,
            modelConfig: markPro(modelConfig) ?? empty
        )
    }

    private func markPro(_ bundle: AIScenarioRemoteBundle?) -> AIScenarioRemoteBundle? {
        guard let bundle else { return nil }
        let proSource = AIRecordSource.pro.rawValue
        let markedModels = bundle.models.map { row -> AIScenarioRemoteModelRow in
            var m = row
            m.source = proSource
            return m
        }
        return AIScenarioRemoteBundle(defaultModelName: bundle.defaultModelName, models: markedModels)
    }
}

private struct RemoteTrialStatusPayload: Decodable {
    let status: String?
    let isActive: Bool?
    let grantSource: String?
    let startedAt: String?
    let expiresAt: String?
    let remainingSeconds: Int?

    func toModel() -> AITrialState {
        let formatter = ISO8601DateFormatter()
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        func parseDate(_ value: String?) -> Date? {
            guard let value else { return nil }
            return fractionalFormatter.date(from: value) ?? formatter.date(from: value)
        }

        return AITrialState(
            status: status ?? AITrialState.inactive.status,
            isActive: isActive ?? false,
            grantSource: grantSource ?? AITrialState.inactive.grantSource,
            startedAt: parseDate(startedAt),
            expiresAt: parseDate(expiresAt),
            remainingSeconds: remainingSeconds ?? 0
        )
    }
}

private struct RemoteTrialApplySubmissionPayload: Decodable {
    let submitted: Bool?
    let applicationId: Int?
    let sequence: Int?
    let status: String?
    let message: String?

    func toModel() -> AITrialApplicationSubmission {
        AITrialApplicationSubmission(
            submitted: submitted ?? true,
            applicationId: applicationId ?? 0,
            sequence: sequence ?? 0,
            status: status ?? "pending",
            message: message ?? ""
        )
    }
}
