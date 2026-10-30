import Foundation
import Combine
import CryptoKit
import UIKit

nonisolated struct CloudFont: Codable, Identifiable, Sendable {
    struct Face: Codable, Identifiable, Sendable { let id: String; let asset_id: String; let postscript_name: String; let label: String }
    struct Content: Codable, Sendable {
        let title: String; let author: String; let description: String
        let styles: [String]; let languages: [String]; let faces: [Face]
        let default_face: String; let cover: String?; let previews: [String]
    }
    let id: String; let title: String; let version: Int; let active: Bool
    let content: Content; let images: [String: String]
    let commerce: ContentCommerce?; let access: ContentAccess.Access
    var favorite: Bool?; var acquired: Bool?
    var priceLabel: String {
        if access.permanently_owned { return "已获取" }
        switch commerce?.access_mode {
        case "free": return "免费"
        case "pro_only": return "Pro 专属"
        case "pro_or_diamond": return "Pro 免费 · \(commerce?.diamond_price ?? 0) 钻"
        case "diamond_only": return "\(commerce?.diamond_price ?? 0) 钻"
        default: return "暂不可获取"
        }
    }
}
nonisolated struct FontPage: Codable, Sendable { let items: [CloudFont]; let count: Int? }
nonisolated struct FontDownloadPlan: Codable, Sendable {
    let font_id: String; let version: String; let face_id: String; let postscript_name: String
    let display_name: String; let url: String; let sha256: String; let byte_size: Int; let mime: String
    let usage_grant: String?
    var reference: DiaryFontReference { DiaryFontReference(id: font_id, version: version, faceID: face_id) }
}
nonisolated struct FontLocalRecord: Codable, Sendable, Identifiable {
    let entry: DiaryFontEntry; let byteSize: Int; let downloadedAt: Date
    var lastUsed: Date; var retained: Bool
    var id: String { entry.cacheIdentity }
}

nonisolated enum FontDisk {
    static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("FontLibrary", isDirectory: true)
    }
    static var index: URL { root.appendingPathComponent("index.json") }
    static func records() -> [FontLocalRecord] {
        guard let data = try? Data(contentsOf: index) else { return [] }
        return (try? JSONDecoder().decode([FontLocalRecord].self, from: data)) ?? []
    }
    static func file(_ entry: DiaryFontEntry) -> URL? {
        guard let hash = entry.sha256, hash.count == 64, hash.allSatisfy(\.isHexDigit) else { return nil }
        return root.appendingPathComponent("blobs/\(hash)/font")
    }
    static func save(_ records: [FontLocalRecord]) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var directory = root; var values = URLResourceValues(); values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        try JSONEncoder().encode(records).write(to: index, options: .atomic)
    }
    static func hash(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        var digest = SHA256()
        while let bytes = try handle.read(upToCount: 1024 * 1024), !bytes.isEmpty { digest.update(data: bytes) }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

actor FontDownloadManager {
    static let shared = FontDownloadManager()
    private var pending: [String: Task<URL, Error>] = [:]
    func download(_ plan: FontDownloadPlan) async throws -> DiaryFontEntry {
        guard plan.sha256.count == 64, plan.sha256.allSatisfy(\.isHexDigit), plan.byte_size > 0, plan.byte_size <= 100 * 1024 * 1024 else { throw BillingFailure("字体资源描述无效") }
        let entry = DiaryFontEntry(id: plan.font_id, version: plan.version, displayName: plan.display_name,
                                  category: "cloud", postScriptName: plan.postscript_name, relativePath: nil, sha256: plan.sha256, faceID: plan.face_id)
        guard let destination = FontDisk.file(entry) else { throw URLError(.badURL) }
        if FileManager.default.fileExists(atPath: destination.path), try FontDisk.hash(destination) == plan.sha256 {
            try remember(entry, size: plan.byte_size); return entry
        }
        let task: Task<URL, Error>
        if let existing = pending[plan.sha256] { task = existing }
        else {
            task = Task.detached(priority: .userInitiated) {
                guard let url = URL(string: plan.url), url.scheme == "https", url.host?.hasSuffix(".aliyuncs.com") == true else { throw URLError(.badURL) }
                let (temporary, response) = try await URLSession.shared.download(from: url)
                defer { try? FileManager.default.removeItem(at: temporary) }
                guard (response as? HTTPURLResponse)?.statusCode == 200,
                      (try temporary.resourceValues(forKeys: [.fileSizeKey])).fileSize == plan.byte_size,
                      try FontDisk.hash(temporary) == plan.sha256 else { throw BillingFailure("字体文件校验失败，请重试") }
                try Task.checkCancellation()
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
                try FileManager.default.moveItem(at: temporary, to: destination)
                return destination
            }
            pending[plan.sha256] = task
        }
        defer { pending[plan.sha256] = nil }
        _ = try await task.value
        try remember(entry, size: plan.byte_size)
        return entry
    }
    private func remember(_ entry: DiaryFontEntry, size: Int) throws {
        var records = FontDisk.records().filter { $0.id != entry.cacheIdentity }
        records.append(FontLocalRecord(entry: entry, byteSize: size, downloadedAt: Date(), lastUsed: Date(), retained: true))
        try FontDisk.save(records)
    }
    func remove(_ record: FontLocalRecord) throws {
        guard pending[record.entry.sha256 ?? ""] == nil else { throw BillingFailure("字体正在下载，请稍后清理") }
        // Explicit removal only: automatic eviction must not guess document references.
        let records = FontDisk.records().filter { $0.id != record.id }
        try FontDisk.save(records)
        if !records.contains(where: { $0.entry.sha256 == record.entry.sha256 }), let file = FontDisk.file(record.entry), FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.removeItem(at: file)
        }
    }
}

@MainActor final class CloudFontRepository: ObservableObject {
    static let shared = CloudFontRepository()
    @Published private(set) var owner = ""
    @Published private(set) var generation = UUID()
    @Published private(set) var catalogRevision = UUID()
    private var engine: SupportNetworkEngine?
    private var subscription: AnyCancellable?
    func configure(engine: SupportNetworkEngine, sessions: AppSessionStore) {
        self.engine = engine
        subscription = sessions.$state.sink { [weak self] state in
            let next: String
            if case let .signedIn(session) = state { next = String(session.accountID) } else { next = "" }
            guard let self, owner != next else { return }
            owner = next; generation = UUID()
        }
    }
    func request<T: Decodable>(_ path: String, method: SupportHTTPMethod = .get, body: [String: Any]? = nil, forceRefresh: Bool = false, onCached: ((T) -> Void)? = nil) async throws -> T {
        guard let engine, !owner.isEmpty else { throw BillingFailure("请先登录账户") }
        let stamp = generation
        var headers: [String: String] = [:]
        if let session = BillingStore.shared.bootstrapInfo?.session_id { headers["X-Billing-Session"] = session }
        let parts = URLComponents(string: path)
        let data = try body.map { try JSONSerialization.data(withJSONObject: $0, options: .sortedKeys) }
        let cacheable = method == .get && (path.hasPrefix("families/") || path == "mine/")
        let request = SupportNetworkRequest(method: method, path: "/api/v1/fonts/" + (parts?.path ?? path), queryItems: parts?.queryItems, headers: headers,
            body: data.map { .raw($0, contentType: "application/json") } ?? .none, strategy: NetworkStrategy(requiresAuth: true, allowETag: cacheable))
        let fetch: @MainActor () async throws -> Data = { [self] in
            guard stamp == generation else { throw CancellationError() }
            let response = try await engine.sendRaw(request)
            guard stamp == generation else { throw CancellationError() }
            _ = try JSONDecoder().decode(T.self, from: response.data)
            return response.data
        }
        let bytes: Data
        if cacheable {
            bytes = try await CatalogResponseCache.shared.load(owner: owner, domain: "fonts",
                path: engine.serviceBaseURL.absoluteString + "/fonts/" + path + "|billing=" + (headers["X-Billing-Session"] ?? ""), forceRefresh: forceRefresh,
                onCached: { data in if let value = try? JSONDecoder().decode(T.self, from: data) { onCached?(value) } }, fetch: fetch)
        } else {
            bytes = try await fetch()
            if path.hasSuffix("/favorite/") || path.hasSuffix("/claim/") {
                CatalogResponseCache.shared.invalidate(owner: owner, domain: "fonts")
                catalogRevision = UUID()
            }
        }
        guard stamp == generation else { throw CancellationError() }
        return try JSONDecoder().decode(T.self, from: bytes)
    }
    func list(mine: Bool, query: String = "", sort: String = "popular", page: Int = 1,
              forceRefresh: Bool = false, onCached: ((FontPage) -> Void)? = nil) async throws -> FontPage {
        let path = mine ? "mine/" : MaterialRoutes.path("families/", ["q": query,"sort":sort,"page":String(page)])
        return try await request(path, forceRefresh: forceRefresh, onCached: onCached)
    }
    func favorite(_ font: CloudFont, value: Bool) async throws {
        let _: [String: Bool] = try await request("families/\(font.id)/favorite/",method:.post,body:["favorite":value])
    }
    func use(_ font: CloudFont, face: String, documentID: UUID?) async throws -> DiaryFontReference {
        let stamp = generation
        let _: [String: Bool] = try await request("families/\(font.id)/claim/",method:.post,body:[:])
        var body: [String: Any] = ["font_id":font.id,"version":font.version,"face_id":face,"purpose":"use"]
        if let documentID { body["document_id"] = documentID.uuidString }
        let plan: FontDownloadPlan = try await request("download-plans/",method:.post,body:body)
        let entry = try await FontDownloadManager.shared.download(plan)
        guard stamp == generation else { throw CancellationError() }
        DiaryFontCatalog.shared.addDownloaded(entry)
        await DiaryFontCatalog.shared.prewarm([entry.reference])
        guard DiaryFontCatalog.shared.available(entry.reference) else { throw BillingFailure("字体注册失败，原字体未修改") }
        return entry.reference
    }
    func restore(_ reference: DiaryFontReference, documentID: UUID) async throws {
        guard let face = reference.faceID, let version = Int(reference.version) else { return }
        let stamp = generation
        let plan: FontDownloadPlan = try await request("download-plans/", method: .post, body: [
            "font_id": reference.id, "version": version, "face_id": face,
            "purpose": "restore", "document_id": documentID.uuidString])
        let entry = try await FontDownloadManager.shared.download(plan)
        guard generation == stamp else { throw CancellationError() }
        DiaryFontCatalog.shared.addDownloaded(entry)
    }
    func recordUse(_ reference: DiaryFontReference) {
        var items = recent().filter { $0 != reference }; items.insert(reference,at:0)
        UserDefaults.standard.set(try? JSONEncoder().encode(Array(items.prefix(30))),forKey:"font.recent.\(owner)")
    }
    func recent() -> [DiaryFontReference] {
        guard let data = UserDefaults.standard.data(forKey:"font.recent.\(owner)") else { return [] }
        return (try? JSONDecoder().decode([DiaryFontReference].self,from:data)) ?? []
    }
}
