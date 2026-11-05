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
            if case let .signedIn(session) = state, !session.isDeviceAccount {
                account = String(session.accountID)
            } else {
                account = nil
            }
            guard account != owner else { return }
            owner = account
            generation = UUID()
            quota = nil
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
            error = nil
        } catch {
            guard stamp == generation else { return }
            self.error = error.localizedDescription
        }
    }

    func complete(task: DiaryProductionTask, digest: String) async throws -> DiaryProductionTask {
        try await request("tasks/\(task.id.uuidString.lowercased())/complete/",
                          body: ["digest": digest])
    }

    func start(key: UUID, digest: String) async throws -> DiaryProductionTask {
        try await request("tasks/", body: ["attempt_key": key.uuidString, "input_digest": digest])
    }

    func task(_ id: UUID) async throws -> DiaryProductionTask {
        try await request("tasks/\(id.uuidString.lowercased())/")
    }

    func action(_ action: String, task: DiaryProductionTask) async throws -> DiaryProductionTask {
        try await request("tasks/\(task.id.uuidString.lowercased())/\(action)/", body: ["version": task.version])
    }

    private func request<T: Decodable>(_ path: String, body: [String: Any]? = nil) async throws -> T {
        guard owner != nil else { throw DiaryAIError.invalid("登录后可查看制作额度") }
        guard let engine else { throw DiaryAIError.invalid("制作服务尚未初始化") }
        let stamp = generation
        let data = try body.map { try JSONSerialization.data(withJSONObject: $0) }
        let operation = CacheableSupportNetworkOperation(
            name: "AIProduction", apiName: "AIProductionAPI",
            request: .init(
                method: body == nil ? .get : .post,
                path: "/api/v1/ai-production/" + path,
                body: data.map { .raw($0, contentType: "application/json") } ?? .none,
                timeoutInterval: 240,
                strategy: .init(requiresAuth: true, allowETag: false)
            )
        )
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let value = try await SupportBackendConfiguration(engine: engine)
            .executeDecoded(T.self, operation: operation, decoder: decoder)
        guard stamp == generation else { throw CancellationError() }
        return value
    }
}
