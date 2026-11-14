import Foundation
import CryptoKit
import Combine

/// Credentials only live in memory. Restart/resume always authenticates and obtains a new lease.
@MainActor final class DiaryAITaskRuntime {
    struct Manifest: Decodable {
        let availableScenes: [String]
        let minimumBuild: Int
    }
    struct Credential: Decodable {
        let version: Int
        let authScheme: String
        let secret: String
    }
    struct Scene: Decodable {
        struct Limits: Decodable { let requestTimeoutSeconds: Int }
        let adapterId: String
        let providerId: String
        let endpoint: URL
        let modelId: String
        let credentialSlotId: String
        let parameters: [String: DiaryAIRuntimeJSON]
        let limits: Limits
    }
    struct Configuration: Decodable {
        let schemaVersion: Int
        let taskId: UUID
        let releaseId: UUID
        let configHash: String
        let controlVersion: Int
        let serverTime: Date
        let leaseExpiresAt: Date
        let scenes: [String: Scene]
        let credentials: [String: Credential]
    }
    #if DEBUG
    private static var testConfiguration: Configuration?
    static func installTestConfiguration(_ data: Data) throws {
        guard NSClassFromString("XCTestCase") != nil else {
            throw DiaryAIError.invalid("此配置仅支持 XCTest 运行")
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        let value = try decoder.decode(Configuration.self, from: data)
        try validate(value, task: value.taskId)
        testConfiguration = value
    }
    static func clearTestConfiguration() { testConfiguration = nil }
    #endif
    struct Access {
        let scene: Scene
        let credential: Credential
    }
    private var taskID: UUID?
    private var owner: String?
    private var configuration: Configuration?
    private var pinnedRelease: UUID?
    private var pinnedHash: String?
    private var deadline: TimeInterval = 0
    private var refresh: Task<Configuration, Error>?
    private var subscription: AnyCancellable?
    private var sessions: [URLSession] = []
    private var generation = UUID()
    private var foregroundSubscription: AnyCancellable?
    private var needsRefresh = true
    var releaseID: UUID? { configuration?.releaseId }

    init() {
        subscription = DiaryProductionService.shared.$owner.sink { [weak self] account in
            guard let self, let owner = self.owner, owner != account else { return }
            self.clear()
            self.sessions.forEach { session in session.getAllTasks { $0.forEach { $0.cancel() } } }
        }
        foregroundSubscription = NotificationCenter.default.publisher(for: NSNotification.Name("UIApplicationWillEnterForegroundNotification"))
            .sink { [weak self] _ in self?.needsRefresh = true }
    }
    func register(_ session: URLSession) { sessions.append(session) }
    func clear() {
        generation = UUID(); refresh?.cancel(); refresh = nil
        configuration = nil; pinnedRelease = nil; pinnedHash = nil; deadline = 0; taskID = nil; owner = nil; needsRefresh = true
    }
    func bind(_ task: DiaryProductionTask) async throws {
        if taskID != task.id { clear() }
        taskID = task.id; owner = DiaryProductionService.shared.owner
        _ = try await obtain(force: true)
    }
    static var capabilities: [String: Any] {
        ["platform": "ios", "app_build": Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1") ?? 1,
         "contract_version": 1, "schema_versions": [1], "adapter_ids": ["ark_responses_v1", "ark_images_v1"]]
    }
    func access(_ name: String, force: Bool = false) async throws -> Access {
        let config = try await obtain(force: force)
        guard let scene = config.scenes[name], let credential = config.credentials[scene.credentialSlotId] else {
            throw DiaryAIError.invalid("本次任务未配置所需 AI 场景，请结束本次任务后重新制作。")
        }
        return Access(scene: scene, credential: credential)
    }
    private var callRunning = false
    private var waitingCalls: [CheckedContinuation<Void, Never>] = []

    private func enterCallQueue() async {
        if callRunning {
            await withCheckedContinuation { waitingCalls.append($0) }
        } else {
            callRunning = true
        }
    }

    private func leaveCallQueue() {
        if waitingCalls.isEmpty { callRunning = false }
        else { waitingCalls.removeFirst().resume() }
    }

    func meteredResponse(scene: String, request: URLRequest, operation: () async throws -> Data) async throws -> Data {
        #if DEBUG
        if Self.testConfiguration != nil { return try await operation() }
        #endif
        let stamp = generation
        await enterCallQueue()
        defer { leaveCallQueue() }
        try Task.checkCancellation()
        guard stamp == generation else { throw CancellationError() }
        try assertOwner()
        guard let taskID, let owner, let body = request.httpBody,
              let payload = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            throw DiaryAIError.invalid("AI 调用缺少制作上下文。")
        }
        let call = UUID()
        var parameters: [String: Any] = [:]
        for key in ["size", "max_output_tokens"] { parameters[key] = payload[key] }
        let digest = SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined()
        let service = DiaryProductionService.shared
        try await service.authorizeCall(taskID: taskID, callID: call, scene: scene, digest: digest, parameters: parameters)

        let result: Result<Data, Error>
        do {
            try assertOwner()
            try Task.checkCancellation()
            result = .success(try await operation())
        }
        catch { result = .failure(error) }
        let response = (try? result.get()).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let reported = response?["usage"] as? [String: Any] ?? [:]
        var usage: [String: Int] = [:]
        for key in ["input_tokens", "output_tokens", "generated_images", "cached_input_tokens"] {
            usage[key] = reported[key] as? Int
        }
        if usage["cached_input_tokens"] == nil {
            usage["cached_input_tokens"] = (reported["input_tokens_details"] as? [String: Any])?["cached_tokens"] as? Int
        }
        let state: String
        switch result {
        case .failure(let error): state = error is CancellationError ? "cancelled" : "failed"
        case .success:
            state = response?["error"] != nil || ["failed", "incomplete"].contains(response?["status"] as? String ?? "") ? "failed" : "completed"
        }
        let report = DiaryProductionService.UsageReport(owner: owner, task: taskID, call: call, event: UUID(),
            state: state, usage: usage, providerRequestID: response?["id"] as? String ?? "")
        await Task { await service.recordUsage(report) }.value
        return try result.get()
    }

    func assertOwner() throws {
        #if DEBUG
        if Self.testConfiguration != nil { return }
        #endif
        guard owner != nil, owner == DiaryProductionService.shared.owner else { throw CancellationError() }
    }
    private func obtain(force: Bool) async throws -> Configuration {
        #if DEBUG
        if let value = Self.testConfiguration { return value }
        #endif
        try assertOwner()
        if !force, !needsRefresh, let configuration, ProcessInfo.processInfo.systemUptime < deadline - 60 { return configuration }
        guard let taskID else { throw DiaryAIError.invalid("请先创建制作任务，再获取 AI 服务配置。") }
        let stamp = generation
        if refresh == nil {
            refresh = Task { try await DiaryProductionService.shared.runtimeConfiguration(taskID) }
        }
        defer { if generation == stamp { refresh = nil } }
        do {
            let value = try await refresh!.value
            try assertOwner()
            guard generation == stamp else { throw CancellationError() }
            try Self.validate(value, task: taskID)
            if let pinnedRelease, pinnedRelease != value.releaseId || pinnedHash != value.configHash {
                throw DiaryAIError.invalid("任务配置版本发生变化，已暂停以保留进度。")
            }
            let duration = value.leaseExpiresAt.timeIntervalSince(value.serverTime)
            guard duration > 0, duration <= 901 else { throw DiaryAIError.invalid("AI 服务配置已过期，请重试。") }
            configuration = value
            pinnedRelease = value.releaseId; pinnedHash = value.configHash
            deadline = ProcessInfo.processInfo.systemUptime + duration
            needsRefresh = false
            return value
        } catch {
            // Fail closed: explicit revocation and transport failures never silently reuse credentials.
            if generation == stamp { configuration = nil; deadline = 0 }
            throw error
        }
    }
    static func validate(_ value: Configuration, task: UUID) throws {
        guard value.schemaVersion == 1, value.taskId == task, !value.scenes.isEmpty else {
            throw DiaryAIError.invalid("AI 服务配置不兼容，请更新客户端。")
        }
        for (name, scene) in value.scenes {
            guard ["diary.layout", "diary.background.design", "diary.background.generate", "diary.background.review"].contains(name),
                  scene.adapterId == (name == "diary.background.generate" ? "ark_images_v1" : "ark_responses_v1"),
                  scene.endpoint.scheme == "https", let host = scene.endpoint.host, !host.isEmpty,
                  scene.endpoint.user == nil, scene.endpoint.password == nil,
                  scene.endpoint.query == nil, scene.endpoint.fragment == nil,
                  scene.endpoint.port == nil || scene.endpoint.port == 443,
                  (10...360).contains(scene.limits.requestTimeoutSeconds), !scene.modelId.isEmpty,
                  let key = value.credentials[scene.credentialSlotId], key.authScheme == "bearer" else {
                throw DiaryAIError.invalid("AI 配置包含不支持的协议、端点或凭证。")
            }
            _ = try DiaryAITestConfig.validatedKey(key.secret)
            let allowed = scene.adapterId == "ark_images_v1" ? Set(["size", "watermark", "response_format"]) : Set(["max_output_tokens", "thinking", "reasoning"])
            guard Set(scene.parameters.keys).isSubset(of: allowed) else { throw DiaryAIError.invalid("AI 配置含不支持的参数。") }
            for (name, value) in scene.parameters {
                let valid: Bool
                switch (name, value) {
                case ("max_output_tokens", .number(let n)): valid = n.rounded() == n && (256...32768).contains(n)
                case ("size", .string(let v)): valid = ["1K", "2K", "4K"].contains(v)
                case ("watermark", .bool): valid = true
                case ("response_format", .string(let v)): valid = v == "url"
                case ("thinking", .object(let v)):
                    if case .string(let type) = v["type"], v.count == 1 { valid = ["enabled", "disabled"].contains(type) } else { valid = false }
                case ("reasoning", .object(let v)):
                    if case .string(let effort) = v["effort"], v.count == 1 { valid = ["low", "medium", "high"].contains(effort) } else { valid = false }
                default: valid = false
                }
                guard valid else { throw DiaryAIError.invalid("AI 服务配置参数无效。") }
            }
        }
    }
}

/// Small typed JSON representation; never persists the credential envelope.
nonisolated enum DiaryAIRuntimeJSON: Decodable, Sendable {
    case string(String), number(Double), bool(Bool), object([String: DiaryAIRuntimeJSON]), array([DiaryAIRuntimeJSON]), null
    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let v = try? value.decode(Bool.self) { self = .bool(v) }
        else if let v = try? value.decode(String.self) { self = .string(v) }
        else if let v = try? value.decode(Double.self) { self = .number(v) }
        else if let v = try? value.decode([String: Self].self) { self = .object(v) }
        else { self = .array(try value.decode([Self].self)) }
    }
    var foundation: Any {
        switch self {
        case .string(let v): v
        case .number(let v): NSNumber(value: v)
        case .bool(let v): v
        case .object(let v): v.mapValues(\.foundation)
        case .array(let v): v.map(\.foundation)
        case .null: NSNull()
        }
    }
}

nonisolated final class DiaryAIRejectRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static let shared = DiaryAIRejectRedirects()
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
