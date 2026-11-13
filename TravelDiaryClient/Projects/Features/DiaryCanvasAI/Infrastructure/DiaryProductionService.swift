import Foundation
import Combine

struct DiaryProductionQuota: Decodable {
    struct Window: Decodable, Identifiable {
        let kind: String
        let limit: Int
        let used: Int
        let reserved: Int
        let available: Int
        let resetAt: String?
        let startsAt: String?
        let status: String?
        let policyVersion: Int?
        var id: String { kind }
    }
    let serverTime: String
    let policyVersion: Int
    let canStart: Bool
    let serviceStatus: String?
    let nextEligibleAt: String?
    let blockedReasons: [String]?
    let entitled: Bool
    let windows: [Window]
}

struct DiaryProductionTask: Codable {
    let id: UUID
    let state: String
    let version: Int
    let attemptKey: UUID
    let expiresAt: String
}

@MainActor
final class DiaryProductionService: ObservableObject {
    static let shared = DiaryProductionService()
    @Published private(set) var runtimeManifestValue: DiaryAITaskRuntime.Manifest?
    @Published private(set) var quota: DiaryProductionQuota?
    @Published private(set) var error: String?
    @Published private(set) var loading = false
    @Published private(set) var owner: String?
    private var engine: SupportNetworkEngine?
    private var subscription: AnyCancellable?
    private var generation = UUID()

    func configure(engine: SupportNetworkEngine, sessions: AppSessionStore) {
        self.engine = engine
        subscription = sessions.$state.sink { [weak self] state in
            guard let self else { return }
            let account: String?
            // Device and registered accounts share production ownership and quota.
            if case let .signedIn(session) = state {
                account = String(session.accountID)
            } else {
                account = nil
            }
            guard account != owner else { return }
            owner = account
            generation = UUID()
            quota = nil
            runtimeManifestValue = nil
            error = nil
            loading = false
        }
    }

    func refresh() async {
        guard !loading else { return }
        let stamp = generation
        loading = true
        defer { if stamp == generation { loading = false } }
        do {
            let result: DiaryProductionQuota = try await request("quota/")
            guard stamp == generation else { return }
            quota = result
            let manifest = try await runtimeManifest()
            guard stamp == generation else { return }
            runtimeManifestValue = manifest
            error = manifest.availableScenes.contains("diary.layout") ? nil : "AI 服务暂不可用，已有进度会保留。"
        } catch {
            guard stamp == generation else { return }
            self.error = error.localizedDescription
        }
    }

    func complete(task: DiaryProductionTask, digest: String, page: UUID? = nil, faces: [String] = []) async throws -> DiaryProductionTask {
        var body: [String: Any] = ["digest": digest]
        if let page { body["page_id"] = page.uuidString; body["faces"] = faces }
        return try await request("tasks/\(task.id.uuidString.lowercased())/complete/",
                          body: body)
    }

    func start(key: UUID, digest: String, scenes: [String] = ["diary.layout"]) async throws -> DiaryProductionTask {
        try await request("tasks/", body: ["attempt_key": key.uuidString, "input_digest": digest, "client_capabilities": DiaryAITaskRuntime.capabilities, "required_scenes": scenes])
    }

    func task(_ id: UUID) async throws -> DiaryProductionTask {
        try await request("tasks/\(id.uuidString.lowercased())/")
    }

    func action(_ action: String, task: DiaryProductionTask) async throws -> DiaryProductionTask {
        try await request("tasks/\(task.id.uuidString.lowercased())/\(action)/", body: ["version": task.version])
    }

    func runtimeConfiguration(_ taskID: UUID) async throws -> DiaryAITaskRuntime.Configuration {
        try await request("tasks/\(taskID.uuidString.lowercased())/configuration/", body: ["request_id": UUID().uuidString, "client_capabilities": DiaryAITaskRuntime.capabilities], runtime: true)
    }
    func runtimeManifest() async throws -> DiaryAITaskRuntime.Manifest {
        try await request("manifest/", runtime: true)
    }

    private func request<T: Decodable>(_ path: String, body: [String: Any]? = nil, runtime: Bool = false) async throws -> T {
        guard owner != nil else { throw DiaryAIError.invalid("登录后可查看制作额度") }
        guard let engine else { throw DiaryAIError.invalid("制作服务尚未初始化") }
        let stamp = generation
        let data = try body.map { try JSONSerialization.data(withJSONObject: $0) }
        let operation = CacheableSupportNetworkOperation(
            name: "AIProduction", apiName: "AIProductionAPI",
            request: .init(
                method: body == nil ? .get : .post,
                path: (runtime ? "/api/v1/ai-runtime/" : "/api/v1/ai-production/") + path,
                body: data.map { .raw($0, contentType: "application/json") } ?? .none,
                timeoutInterval: 240,
                strategy: .init(requiresAuth: true, allowETag: false)
            )
        )
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: text) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: text) else { throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid date")) }
            return date
        }
        let value = try await SupportBackendConfiguration(engine: engine)
            .executeDecoded(T.self, operation: operation, decoder: decoder)
        guard stamp == generation else { throw CancellationError() }
        return value
    }
}
