import Foundation
import Combine
import CryptoKit
import UIKit

nonisolated struct CustomRequestRow: Codable, Identifiable, Sendable {
    let id: String; let title: String; let status: String; let revision: Int; let unread: Bool
}
nonisolated struct CustomRequestPage: Decodable, Sendable { let results: [CustomRequestRow]; let next_page: Int? }
nonisolated struct CustomAsset: Codable, Identifiable, Sendable {
    let id: String; let client_id: String; let position: Int; let note: String; let must_use: Bool
    let crop_allowed: Bool; let cover_preferred: Bool; let status: String; let thumbnail_url: String?
    let url: String?; let job_id: String; let error: String
}
nonisolated struct CustomEvent: Codable, Identifiable, Sendable {
    let id: String; let sequence: Int; let action: String; let message: String; let created_at: String
}
nonisolated struct CustomDelivery: Codable, Identifiable, Sendable {
    struct Page: Codable, Identifiable, Sendable { let id: String; let title: String; let preview_url: String? }
    let id: String; let number: Int; let status: String; let note: String; let template_id: String; let version: Int
    let title: String; let page_count: Int; let cover_url: String?; let photo_slots: Int; let text_slots: Int; let pages: [Page]
    func book(owner: String) -> RemotePresetBook {
        var result = RemotePresetBook(id: template_id, title: title, series: "private-custom", version: version, page_count: page_count, cover_url: cover_url ?? "")
        result.privateOwner = owner; return result
    }
}
nonisolated struct CustomSubmission: Codable, Identifiable, Sendable {
    struct Snapshot: Codable, Sendable {
        struct Photo: Codable, Identifiable, Sendable { let id: String; let note: String; let must_use: Bool; let crop_allowed: Bool }
        let title: String; let brief: [String: String]; let assets: [Photo]
    }
    let id: Int; let number: Int; let snapshot: Snapshot
}
nonisolated struct CustomRequest: Codable, Identifiable, Sendable {
    let id: String; let number: String; let title: String; let brief: [String: String]; let status: String; let revision: Int
    let due_at: String?; let event_sequence: Int; let last_read_sequence: Int; let revision_round: Int
    let current_delivery_id: String?; let assets: [CustomAsset]; let submissions: [CustomSubmission]; let events: [CustomEvent]; let deliveries: [CustomDelivery]
    let accepted_submission_id: Int?
    let latest_submission_id: Int?
    let pending_submission: Bool?
    let allowed_actions: [String]?
    let cancellation_requested: Bool?
    let next_step: String?
    var editable: Bool { ["draft", "needs_info"].contains(status) }
    func permits(_ action: String, fallback: Bool = true) -> Bool { allowed_actions?.contains(action) ?? fallback }
}
nonisolated struct CustomUploadJob: Codable, Identifiable, Sendable {
    let id: UUID; let owner: String; let requestID: String; let file: URL; let size: Int; let sha256: String
    var mime: String?; var width: Int?; var height: Int?; var progress: Double?
    var uploadedToOSS: Bool?
    var uploadID: String?; var state = "等待上传"; var error: String?
}
nonisolated struct CustomFailure: LocalizedError { let message: String; init(_ message: String) { self.message = message }; var errorDescription: String? { message } }

nonisolated enum CustomPhotoUploadResponse {
    static func accepted(status: Int, body: Data) -> Bool {
        // An acknowledgement may be lost after OSS stores a unique session key.
        // A retry must keep that existing object instead of overwriting it.
        (200..<300).contains(status) || (status == 409 && String(data: body, encoding: .utf8)?.contains("<Code>FileAlreadyExists</Code>") == true)
    }
}

@MainActor
final class CustomizationService: ObservableObject {
    static let shared = CustomizationService()
    @Published private(set) var jobs: [CustomUploadJob] = []
    @Published private(set) var unread = 0
    @Published var routeError: String?
    @Published var refreshSequence = 0
    var visibleRequestID: String?
    @Published var routeID: String?
    private(set) var owner: String?
    private var boundAccount = false
    private var engine: SupportNetworkEngine?
    private var subscription: AnyCancellable?
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Customizations", isDirectory: true)
    private var generation = UUID()
    private var lastProgress: [UUID: Date] = [:]
    func configure(engine: SupportNetworkEngine, sessions: AppSessionStore) {
        self.engine = engine
        subscription = sessions.$state.sink { [weak self] state in
            guard let self else { return }
            let id: String?
            if case let .signedIn(s) = state { id = String(s.accountID); boundAccount = !s.isDeviceAccount }
            else { id = nil; boundAccount = false }
            guard owner != id else { return }
            let wasSignedIn = owner != nil
            generation = UUID(); tasks.values.forEach { $0.cancel() }; tasks = [:]; jobs = []; unread = 0
            if wasSignedIn { routeID = nil; PushAdapter.shared.clearPrivateState() }
            owner = id
            PresetDownloadManager.shared.deactivate()
            if let id {
                PresetDownloadManager.shared.activate(owner: id)
                if let bytes = try? Data(contentsOf: directory(id).appendingPathComponent("jobs.json")), let restored = try? JSONDecoder().decode([CustomUploadJob].self, from: bytes) {
                    jobs = restored.filter { $0.owner == id }
                    for i in jobs.indices where ["正在上传","正在登记","正在校验","排队中","等待上传"].contains(jobs[i].state) { jobs[i].state = "已暂停" }
                }
            }
        }
    }
    func require(_ expected: String, bound: Bool = false) throws {
        guard owner == expected else { throw CustomFailure("账号已变化，请重新打开定制") }
        if bound && !boundAccount { throw CustomFailure("请先在设置中绑定正式账号，以便换机后领取定制成品") }
    }
    func request<T: Decodable>(_ path: String, owner: String, method: SupportHTTPMethod = .get, body: [String: Any]? = nil, key: String? = nil) async throws -> T {
        try require(owner); let stamp = generation
        guard let engine else { throw CustomFailure("服务尚未初始化") }
        let c = URLComponents(string: path)
        let data = try body.map { try JSONSerialization.data(withJSONObject: $0, options: .sortedKeys) }
        let r = try await engine.sendRaw(SupportNetworkRequest(method: method, path: "/api/v1/diary-customizations/" + (c?.path ?? path), queryItems: c?.queryItems,
            headers: key.map { ["Idempotency-Key": $0] } ?? [:], body: data.map { .raw($0, contentType: "application/json") } ?? .none,
            strategy: NetworkStrategy(requiresAuth: true, allowETag: false)))
        try Task.checkCancellation(); try require(owner); guard stamp == generation else { throw CancellationError() }
        return try JSONDecoder().decode(T.self, from: r.data)
    }
    func list(owner: String, page: Int = 1) async throws -> CustomRequestPage { try await request("requests/?page=\(page)", owner: owner) }
    func detail(_ id: String, owner: String) async throws -> CustomRequest {
        let value: CustomRequest = try await request("requests/\(id)/", owner: owner)
        let ready = Set(value.assets.filter { $0.status == "ready" }.compactMap { UUID(uuidString: $0.client_id) })
        var changed = false
        for i in jobs.indices where jobs[i].owner == owner && jobs[i].requestID == id && jobs[i].state != "已完成" && tasks[jobs[i].id] == nil && ready.contains(jobs[i].id) {
            jobs[i].state = "已完成"; jobs[i].uploadedToOSS = true; jobs[i].progress = 1; jobs[i].error = nil
            try? FileManager.default.removeItem(at: jobs[i].file)
            changed = true
        }
        if changed { try? saveJobs(owner) }
        return value
    }
    func create(owner: String) async throws -> CustomRequest {
        try require(owner)
        let url = directory(owner).appendingPathComponent("creation-key")
        let key = (try? String(contentsOf: url, encoding: .utf8)) ?? UUID().uuidString
        try persist(Data(key.utf8), to: url)
        let value: CustomRequest = try await request("requests/", owner: owner, method: .post, body: ["creation_key": key])
        try? FileManager.default.removeItem(at: url); return value
    }
    func action(_ name: String, value: CustomRequest, owner: String, body: [String: Any] = [:]) async throws -> CustomRequest {
        try require(owner, bound: name == "submit")
        let payload = body.merging(["expected_revision": value.revision]) { _, new in new }
        let encoded = try JSONSerialization.data(withJSONObject: payload, options: .sortedKeys)
        let hash = SHA256.hash(data: encoded).map { String(format: "%02x", $0) }.joined()
        // Stable over response loss and process restart; changed content/revision has a distinct key.
        let key = "\(name)-\(hash)"
        return try await request("requests/\(value.id)/\(name == "edit" ? "" : name + "/")", owner: owner, method: name == "edit" ? .patch : .post, body: payload, key: key)
    }
    func read(_ value: CustomRequest, owner: String) async {
        guard value.event_sequence > value.last_read_sequence else { return }
        struct Ack: Decodable { let last_read_sequence: Int }
        let _: Ack? = try? await request("requests/\(value.id)/read/", owner: owner, method: .post, body: ["sequence": value.event_sequence])
        await refreshUnread(owner: owner)
    }
    func refreshUnread(owner: String) async {
        struct Summary: Decodable { let unread_request_count: Int }
        if let r: Summary = try? await request("notification-summary/", owner: owner) { unread = r.unread_request_count }
    }
    func asset(_ asset: CustomAsset, request id: String, owner: String, body: [String: Any]? = nil, delete: Bool = false) async throws -> CustomRequest {
        try await request("requests/\(id)/assets/\(asset.id)/", owner: owner, method: delete ? .delete : .patch, body: body)
    }
    func saveForm(_ fields: [String: String], id: String, owner: String) { try? persist(JSONEncoder().encode(fields), to: directory(owner).appendingPathComponent(id+"-form.json")) }
    func loadForm(id: String, owner: String) -> [String: String]? {
        guard let data = try? Data(contentsOf: directory(owner).appendingPathComponent(id+"-form.json")) else { return nil }
        return try? JSONDecoder().decode([String: String].self, from: data)
    }
    func enqueuePhoto(_ bytes: Data, request id: String, owner: String) async throws {
        try require(owner, bound: true)
        let normalized: (Data, String, Int, Int) = try await Task.detached(priority: .utility) {
            guard let image = UIImage(data: bytes), image.size.width > 0, image.size.height > 0,
                  image.size.width * image.size.height * image.scale * image.scale <= 80_000_000 else { throw CustomFailure("照片太大或无法读取") }
            let scale = min(1,4096/max(image.size.width,image.size.height))
            let size = CGSize(width: image.size.width*scale, height: image.size.height*scale)
            let alpha = image.cgImage.map { [.first,.last,.premultipliedFirst,.premultipliedLast,.alphaOnly].contains($0.alphaInfo) } ?? false
            let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = !alpha
            let renderer = UIGraphicsImageRenderer(size: size, format: format)
            let rendered = renderer.image { c in
                if !alpha { UIColor.white.setFill(); c.fill(CGRect(origin: .zero,size: size)) }
                image.draw(in: CGRect(origin: .zero,size: size))
            }
            guard let result = alpha ? rendered.pngData() : rendered.jpegData(compressionQuality: 0.92), result.count <= 20*1024*1024 else { throw CustomFailure("照片超过 20 MiB，请缩小后重试") }
            return (result, alpha ? "image/png" : "image/jpeg", rendered.cgImage?.width ?? Int(size.width), rendered.cgImage?.height ?? Int(size.height))
        }.value
        try require(owner); let jid = UUID(); let file = directory(owner).appendingPathComponent(jid.uuidString+(normalized.1 == "image/png" ? ".png" : ".jpg"))
        try persist(normalized.0, to: file)
        jobs.append(CustomUploadJob(id: jid, owner: owner, requestID: id, file: file, size: normalized.0.count,
            sha256: SHA256.hash(data: normalized.0).map { String(format: "%02x", $0) }.joined(), mime: normalized.1, width: normalized.2, height: normalized.3))
        try saveJobs(owner); resume(jid)
    }
    func resume(_ id: UUID) {
        guard tasks[id] == nil, let job = jobs.first(where: { $0.id == id }), job.owner == owner else { return }
        guard tasks.count < 3 else { update(id) { $0.state = "等待上传" }; return }
        let stamp = generation
        tasks[id] = Task { [weak self] in
            guard let self else { return }; await upload(job)
            guard generation == stamp else { return }
            tasks[id] = nil
            if let next = jobs.first(where: { $0.owner == owner && $0.state == "等待上传" && tasks[$0.id] == nil }) { resume(next.id) }
        }
    }
    func pause(_ id: UUID) { tasks[id]?.cancel(); update(id) { $0.state = "已暂停" } }
    func discard(_ id: UUID) async throws {
        guard let job = jobs.first(where: { $0.id == id }), job.owner == owner else { throw CancellationError() }
        tasks[id]?.cancel()
        let value = try await detail(job.requestID, owner: job.owner)
        if value.editable, let asset = value.assets.first(where: { UUID(uuidString: $0.client_id) == id }) {
            let _: CustomRequest = try await self.asset(asset,request: job.requestID,owner: job.owner,delete: true)
        }
        try require(job.owner)
        jobs.removeAll { $0.id == id }; try saveJobs(job.owner)
        try? FileManager.default.removeItem(at: job.file); refreshSequence += 1
    }
    func purgeLocalRequest(_ id: String, owner: String, templateIDs: Set<String>) async {
        guard self.owner == owner else { return }
        let removed = jobs.filter { $0.requestID == id && $0.owner == owner }
        for job in removed { tasks[job.id]?.cancel(); try? FileManager.default.removeItem(at: job.file) }
        jobs.removeAll { $0.requestID == id && $0.owner == owner }; try? saveJobs(owner)
        try? FileManager.default.removeItem(at: directory(owner).appendingPathComponent(id+"-form.json"))
        let manager = PresetDownloadManager.shared
        let ids = Set(manager.jobs.filter { job in
            guard job.privateOwner == owner else { return false }
            if job.customizationID == id { return true }
            return (try? JSONDecoder().decode(PresetManifest.self,from: job.manifestData)).map { templateIDs.contains($0.templateBookID) } ?? false
        }.map(\.id))
        for id in ids { manager.pause(id) }
        for _ in 0..<20 {
            if !ids.contains(where: { manager.isRunning($0) }) { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        let safe = ids.filter { !manager.isRunning($0) }
        try? manager.removeDownloads(Set(safe),ownerID: owner)
    }
    private func update(_ id: UUID, _ body: (inout CustomUploadJob) -> Void) {
        guard let i = jobs.firstIndex(where: { $0.id == id && $0.owner == owner }) else { return }; body(&jobs[i]); try? saveJobs(jobs[i].owner)
    }
    private func upload(_ source: CustomUploadJob) async {
        struct Session: Decodable { let id: String; let status: String; let put_url: String?; let put_headers: [String: String]? }
        struct State: Decodable { let id: String; let status: String; let error: String? }
        do {
            try require(source.owner, bound: true); update(source.id) { $0.state = "正在上传"; $0.error = nil }
            let session: Session
            if let uploadID = source.uploadID {
                let state: State = try await request("uploads/\(uploadID)/", owner: source.owner)
                if state.status != "uploading" || source.uploadedToOSS == true {
                    guard ["uploading","ready","queued","processing","failed"].contains(state.status) else { throw CustomFailure("上传会话已结束，请重新添加照片") }
                    session = Session(id: uploadID, status: state.status, put_url: nil, put_headers: nil)
                } else { session = try await request("uploads/\(uploadID)/refresh/", owner: source.owner, method: .post, body: [:]) }
            } else {
                session = try await request("requests/\(source.requestID)/uploads/", owner: source.owner, method: .post,
                    body: ["client_id": source.id.uuidString, "size": source.size, "sha256": source.sha256, "mime": source.mime ?? "image/jpeg", "width":source.width ?? 0,"height":source.height ?? 0])
                update(source.id) { $0.uploadID = session.id }
            }
            if session.status == "uploading" && source.uploadedToOSS != true {
                guard let raw = session.put_url, let url = URL(string: raw), url.scheme == "https", url.host?.hasSuffix(".aliyuncs.com") == true else { throw CustomFailure("无法获取照片上传地址，请重试") }
                try require(source.owner); var r = URLRequest(url: url); r.httpMethod = "PUT"; r.timeoutInterval = 180; r.setValue(source.mime ?? "image/jpeg", forHTTPHeaderField: "Content-Type")
                for (key, value) in session.put_headers ?? [:] { r.setValue(value, forHTTPHeaderField: key) }
                let delegate = CustomPhotoUploadProgress { progress in
                    Task { @MainActor in
                        guard Date().timeIntervalSince(self.lastProgress[source.id] ?? .distantPast) > 0.25 else { return }
                        self.lastProgress[source.id] = Date(); self.update(source.id) { $0.progress = progress }
                    }
                }
                let (body, response) = try await URLSession.shared.upload(for: r, fromFile: source.file, delegate: delegate)
                guard let h = response as? HTTPURLResponse, CustomPhotoUploadResponse.accepted(status: h.statusCode, body: body) else { throw CustomFailure("照片上传失败，请重试") }
                update(source.id) { $0.uploadedToOSS = true; $0.progress = 1 }
            }
            if session.status != "ready" {
                update(source.id) { $0.state = "正在登记" }
                let state: State = try await request("uploads/\(session.id)/complete/", owner: source.owner, method: .post, body: [:])
                guard state.status == "ready" else { throw CustomFailure("照片上传已完成，但服务器尚未完成登记，请更新服务端后重试") }
            }
            update(source.id) { $0.state = "已完成" }; refreshSequence += 1; try? FileManager.default.removeItem(at: source.file)
        } catch { if Task.isCancelled { return }; update(source.id) { $0.state = "失败"; $0.error = error.localizedDescription } }
    }
    private func directory(_ owner: String) -> URL {
        root.appendingPathComponent(SHA256.hash(data: Data(owner.utf8)).map { String(format: "%02x", $0) }.joined(), isDirectory: true)
    }
    private func persist(_ bytes: Data, to url: URL) throws {
        let parent = url.deletingLastPathComponent(); try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        var values = URLResourceValues(); values.isExcludedFromBackup = true; var dir = parent; try dir.setResourceValues(values)
        try bytes.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
    }
    private func saveJobs(_ owner: String) throws { try persist(JSONEncoder().encode(jobs.filter { $0.owner == owner }), to: directory(owner).appendingPathComponent("jobs.json")) }
}

nonisolated func customizationStatus(_ status: String) -> String {
    ["draft":"草稿", "submitted":"已提交，待受理", "needs_info":"待补充资料", "in_production":"制作中", "delivered":"已交付，待确认", "revision_requested":"已提出修改", "completed":"已完成", "cancelled":"已取消", "rejected":"暂无法制作"][status] ?? status
}

private final class CustomPhotoUploadProgress: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let progress: @Sendable (Double) -> Void
    init(_ progress: @escaping @Sendable (Double) -> Void) { self.progress = progress }
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        progress(totalBytesExpectedToSend > 0 ? Double(totalBytesSent)/Double(totalBytesExpectedToSend) : 0)
    }
}
