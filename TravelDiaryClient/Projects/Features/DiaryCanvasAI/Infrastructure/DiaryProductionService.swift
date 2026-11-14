import Foundation
import Combine

struct DiaryProductionQuota: Decodable {
    struct Window: Decodable, Identifiable {
        let kind: String
        let remainingRatio: Double
        let resetAt: String?
        let startsAt: String?
        let status: String?
        var id: String { kind }
    }
    let serverTime: String
    let policyVersion: Int
    let pendingUsage: Bool
    let serviceStatus: String?
    let entitled: Bool
    let plan: String?
    let entitlementState: String?
    let membershipExpiresAt: String?
    let windows: [Window]
}

struct DiaryProductionTask: Codable {
    let id: UUID
    let state: String
    let version: Int
    let attemptKey: UUID
}

@MainActor
final class DiaryProductionService: ObservableObject {
    static let shared = DiaryProductionService()
    @Published private(set) var runtimeManifestValue: DiaryAITaskRuntime.Manifest?
    @Published private(set) var quota: DiaryProductionQuota?
    @Published private(set) var error: String?
    @Published private(set) var loading = false
    @Published private(set) var owner: String?
    @Published private(set) var canPurchaseMembership = false
    @Published private(set) var upgradeSuggested = false
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
                canPurchaseMembership = !session.isDeviceAccount
            } else {
                account = nil
                canPurchaseMembership = false
            }
            guard account != owner else { return }
            owner = account
            generation = UUID()
            quota = nil
            upgradeSuggested = false
            runtimeManifestValue = nil
            error = nil
            loading = false
        }
    }

    func refreshQuota() async {
        let stamp = generation
        if let snapshot: DiaryProductionQuota = try? await request("quota/"), stamp == generation {
            applyQuota(snapshot)
        }
    }

    private func applyQuota(_ snapshot: DiaryProductionQuota) {
        if let current = quota, current.serverTime > snapshot.serverTime { return }
        quota = snapshot
        if snapshot.plan != "free" { upgradeSuggested = false }
    }

    func refresh() async {
        guard !loading else { return }
        let stamp = generation
        loading = true
        defer { if stamp == generation { loading = false } }
        await flushUsage()
        do {
            let result: DiaryProductionQuota = try await request("quota/")
            guard stamp == generation else { return }
            applyQuota(result)
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
        try await request("tasks/", body: ["usage_metering": true, "attempt_key": key.uuidString, "input_digest": digest, "client_capabilities": DiaryAITaskRuntime.capabilities, "required_scenes": scenes])
    }

    func task(_ id: UUID) async throws -> DiaryProductionTask {
        try await request("tasks/\(id.uuidString.lowercased())/")
    }

    func action(_ action: String, task: DiaryProductionTask) async throws -> DiaryProductionTask {
        try await request("tasks/\(task.id.uuidString.lowercased())/\(action)/", body: ["version": task.version])
    }

    struct Call: Decodable {
        let accountingState: String
        let quota: DiaryProductionQuota?
    }

    func authorizeCall(taskID: UUID, callID: UUID, scene: String, digest: String, parameters: [String: Any]) async throws {
        upgradeSuggested = false
        await flushUsage()
        let call: Call
        do {
            call = try await request("tasks/\(taskID.uuidString)/calls/", body: [
                "call_id": callID.uuidString, "scene": scene, "input_digest": digest, "parameters": parameters
            ])
        } catch let error as SupportNetworkError {
            guard case .http(_, let backend, _) = error, case .object(let details) = backend?.data,
                  details["error_key"] == .string("QUOTA_INSUFFICIENT") else { throw error }
            upgradeSuggested = details["plan"] == .string("free")
            await refreshQuota()
            let windows: [String]
            if case .array(let values) = details["blocked_windows"] {
                windows = values.compactMap {
                    switch $0 {
                    case .string("short"): return "5 小时"
                    case .string("weekly"): return "7 天"
                    default: return nil
                    }
                }
            } else { windows = [] }
            let name = windows.isEmpty ? "制作" : windows.joined(separator: "、")
            let date: Date?
            if case .string(let value) = details["next_eligible_at"] {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                date = formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
            } else { date = nil }
            let recovery = date.map { "，\($0.formatted(date: .abbreviated, time: .shortened)) 恢复" } ?? ""
            throw DiaryAIError.invalid("\(name)额度不足\(recovery)。")
        }
        guard call.accountingState == "pending" else { throw DiaryAIError.invalid("此调用许可已结束，请重新发起制作。") }
    }

    struct UsageReport: Codable {
        let owner: String
        let task: UUID
        let call: UUID
        let event: UUID
        let state: String
        let usage: [String: Int]
        let providerRequestID: String
    }

    private var reporting: Set<UUID> = []

    func recordUsage(_ report: UsageReport) async {
        let key = "diary.ai.usage.\(report.owner).\(report.call.uuidString)"
        if let data = try? JSONEncoder().encode(report) { UserDefaults.standard.set(data, forKey: key) }
        await deliver(report, key: key)
    }

    private func deliver(_ report: UsageReport, key: String) async {
        guard owner == report.owner, reporting.insert(report.call).inserted else { return }
        defer { reporting.remove(report.call) }
        do {
            let result: Call = try await request(
                "tasks/\(report.task.uuidString)/calls/\(report.call.uuidString)/usage/",
                body: ["event_id": report.event.uuidString, "execution_state": report.state,
                       "usage": report.usage, "provider_request_id": report.providerRequestID]
            )
            UserDefaults.standard.removeObject(forKey: key)
            if owner == report.owner, let snapshot = result.quota { applyQuota(snapshot) }
        } catch {
            // Persisted under the original account for retry on refresh.
        }
    }

    private func flushUsage() async {
        guard let owner else { return }
        let prefix = "diary.ai.usage.\(owner)."
        for (key, value) in UserDefaults.standard.dictionaryRepresentation() where key.hasPrefix(prefix) {
            if let data = value as? Data, let report = try? JSONDecoder().decode(UsageReport.self, from: data) {
                await deliver(report, key: key)
            }
        }
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
        var headers: [String: String] = [:]
        let billing = BillingStore.shared
        if !runtime, let account = billing.owner, account == owner, let info = billing.bootstrapInfo {
            // Refresh an existing billing session before using it in the store environment.
            if path == "quota/" || (body != nil && path.hasSuffix("/calls/")) {
                try await billing.ready(owner: account)
                guard stamp == generation else { throw CancellationError() }
                headers["X-Billing-Session"] = billing.bootstrapInfo?.session_id
            } else {
                headers["X-Billing-Session"] = info.session_id
            }
        }
        let data = try body.map { try JSONSerialization.data(withJSONObject: $0) }
        let operation = CacheableSupportNetworkOperation(
            name: "AIProduction", apiName: "AIProductionAPI",
            request: .init(
                method: body == nil ? .get : .post,
                path: (runtime ? "/api/v1/ai-runtime/" : "/api/v1/ai-production/") + path,
                headers: headers,
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
