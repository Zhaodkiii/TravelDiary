import Foundation
import Combine
import UIKit
import CryptoKit

@MainActor
final class HelpFeedbackService: ObservableObject {
    static let shared = HelpFeedbackService()
    @Published private(set) var unread = 0
    @Published var guestDraft: FeedbackDraft?
    @Published var routeID: String?
    @Published var routeError: String?
    private var engine: SupportNetworkEngine?
    private(set) var owner: String?
    private var bound = false
    private var generation = UUID()
    private var subscription: AnyCancellable?
    func configure(engine: SupportNetworkEngine, sessions: AppSessionStore) {
        self.engine = engine
        subscription = sessions.$state.sink { [weak self] state in
            guard let self else { return }
            let previousBound = bound
            let previousOwner = owner
            let id: String?
            if case let .signedIn(session) = state { id = String(session.accountID); bound = !session.isDeviceAccount }
            else { id = nil; bound = false }
            if !previousBound && bound, let previousOwner, let data = try? Data(contentsOf: directory(previousOwner).appendingPathComponent("draft.json")), let draft = try? JSONDecoder().decode(FeedbackDraft.self,from:data), !draft.isEmpty { guestDraft = draft }
            else if previousBound && id != owner { guestDraft = nil }
            guard id != owner else { return }
            let hadOwner = owner != nil
            generation = UUID(); unread = 0; owner = id
            if hadOwner { routeID = nil; routeError = nil; UserDefaults.standard.removeObject(forKey: "support-push-pending-v1") }
        }
    }
    func require(_ owner: String, formal: Bool = false) throws {
        guard self.owner == owner else { throw HelpFailure("账号已变化，请重新打开帮助与反馈") }
        if formal && !bound { throw HelpFailure("请先登录或绑定正式账号，以便换设备查看回复") }
    }
    func request<T: Decodable>(_ path: String, owner: String? = nil, method: SupportHTTPMethod = .get, body: [String: Any]? = nil) async throws -> T {
        if let owner { try require(owner) }
        let stamp = generation
        guard let engine else { throw HelpFailure("服务尚未初始化") }
        let c = URLComponents(string: path)
        let data = try body.map { try JSONSerialization.data(withJSONObject: $0, options: .sortedKeys) }
        // Public help content only. Tickets, messages, unread counts and upload URLs stay live.
        let cacheable = method == .get && (path == "config/" || path.hasPrefix("help/categories/") || path.hasPrefix("help/articles/"))
        let request = SupportNetworkRequest(method: method, path: "/api/v1/support/" + (c?.path ?? path), queryItems: c?.queryItems,
            body: data.map { .raw($0, contentType: "application/json") } ?? .none,
            strategy: NetworkStrategy(requiresAuth: owner != nil, allowETag: cacheable))
        let fetch: @MainActor () async throws -> Data = {
            let response = try await engine.sendRaw(request)
            _ = try JSONDecoder().decode(T.self, from: response.data)
            return response.data
        }
        let bytes: Data
        if cacheable {
            bytes = try await CatalogResponseCache.shared.load(owner: owner ?? "public-help", domain: "help",
                path: engine.serviceBaseURL.absoluteString + "/support/" + path, fetch: fetch)
        } else { bytes = try await fetch() }
        try Task.checkCancellation()
        if let owner { try require(owner); guard stamp == generation else { throw CancellationError() } }
        return try JSONDecoder().decode(T.self, from: bytes)
    }

    func config() async throws -> HelpServiceConfig { try await request("config/") }
    func categories() async throws -> [HelpCategory] { try await request("help/categories/") }
    func articles(query: String, category: String, cursor: String? = nil) async throws -> SupportPage<HelpArticle> {
        var c = URLComponents(); c.path = "help/articles/"; c.queryItems = [URLQueryItem(name:"q",value:query),URLQueryItem(name:"category",value:category),URLQueryItem(name:"version",value:AppVersionInformation.version),URLQueryItem(name:"limit",value:"20"),URLQueryItem(name:"cursor",value:cursor)]
        return try await request(c.string ?? "help/articles/")
    }
    func article(_ id: String) async throws -> HelpArticle { try await request("help/articles/\(id)/?version=\(AppVersionInformation.version)") }
    func ticket(_ id: String, owner: String) async throws -> FeedbackTicket { try await request("tickets/\(id)/", owner: owner) }
    func tickets(owner: String, status: String = "", cursor: String? = nil) async throws -> SupportPage<FeedbackTicket> {
        try await request("tickets/?status=\(status)&cursor=\(cursor ?? "")", owner: owner)
    }
    func messages(_ id: String, owner: String, afterSequence: Int? = nil) async throws -> SupportPage<FeedbackMessage> { try await request("tickets/\(id)/messages/?limit=50&after_sequence=\(afterSequence.map(String.init) ?? "")", owner: owner) }
    func refreshUnread(owner: String) async {
        struct Summary: Decodable { let unread_ticket_count: Int }
        if let r: Summary = try? await request("summary/", owner: owner) { unread = r.unread_ticket_count }
    }
    func read(_ id: String, sequence: Int, owner: String) async {
        struct Ack: Decodable { let through_sequence: Int }
        let _: Ack? = try? await request("tickets/\(id)/read/", owner: owner, method: .post, body: ["through_sequence":sequence])
        await refreshUnread(owner: owner)
    }
    func submitted(_ key: String, owner: String) async throws -> FeedbackTicket? {
        struct Result: Decodable { let ticket: FeedbackTicket? }
        let r: Result = try await request("submission/?client_request_id=\(key)",owner:owner)
        return r.ticket
    }
    func create(_ draft: FeedbackDraft, owner: String) async throws -> FeedbackTicket {
        try require(owner, formal: true)
        var body: [String: Any] = ["title":draft.title.trimmingCharacters(in:.whitespacesAndNewlines),"description":draft.description.trimmingCharacters(in:.whitespacesAndNewlines),"kind":draft.kind,"contact":draft.contact.trimmingCharacters(in:.whitespacesAndNewlines),"source":draft.articleID == nil ? "settings" : "help", "attachments":draft.photos.compactMap(\.attachmentID),"environment":AppVersionInformation.environment,"client_request_id":draft.requestID]
        if let id = draft.articleID { body["article_id"] = id }
        if let id = draft.previousID { body["previous_ticket_id"] = id }
        if !draft.relatedID.isEmpty { body["related_type"] = draft.relatedType; body["related_id"] = draft.relatedID }
        guard draft.photos.allSatisfy({ $0.attachmentID != nil }) else { throw HelpFailure("请等待截图全部上传完成") }
        return try await request("tickets/", owner: owner, method: .post, body: body)
    }
    func reply(_ ticket: FeedbackTicket, text: String, photos: [FeedbackPhoto], owner: String, action: String? = nil) async throws -> FeedbackTicket {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard photos.allSatisfy({ $0.attachmentID != nil }) else { throw HelpFailure("请等待截图全部上传完成") }
        var body: [String: Any] = ["body":text,"revision":ticket.revision,"attachments":photos.compactMap(\.attachmentID)]
        if let action { body["action"] = action }
        let signatureBody: [String:Any] = ["body":text,"attachments":photos.map { $0.id.uuidString },"action":action ?? "reply"]
        let signatureBytes = try JSONSerialization.data(withJSONObject:signatureBody,options:.sortedKeys)
        let signature = SHA256.hash(data:signatureBytes).map { String(format:"%02x",$0) }.joined()
        let pending = directory(owner).appendingPathComponent("pending-"+ticket.id+"-"+signature+".json")
        if let data = try? Data(contentsOf:pending), let saved = try? JSONSerialization.jsonObject(with:data) as? [String:Any] { body = saved }
        else {
            body["client_request_id"] = UUID().uuidString
            try FileManager.default.createDirectory(at:directory(owner),withIntermediateDirectories:true)
            try JSONSerialization.data(withJSONObject:body,options:.sortedKeys).write(to:pending,options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
        }
        do {
            let value: FeedbackTicket = try await request("tickets/\(ticket.id)/\(action == nil ? "messages" : "actions")/",owner:owner,method:.post,body:body)
            try? FileManager.default.removeItem(at:pending);return value
        } catch {
            // A definitive conflict/rejection did not commit this operation. A timeout keeps the exact payload.
            if case SupportNetworkError.http(let status,_,_) = error, [400,403,404,409].contains(status) { try? FileManager.default.removeItem(at:pending) }
            throw error
        }
    }

    func attachment(_ id: String, owner: String) async throws -> URL {
        struct Link: Decodable { let url: String }
        let link: Link = try await request("attachments/\(id)/url/", owner: owner)
        guard let url = URL(string:link.url), url.scheme == "https", url.host?.hasSuffix(".aliyuncs.com") == true else { throw HelpFailure("截图地址不可用") }
        return url
    }
    func upload(_ photo: FeedbackPhoto, owner: String) async throws -> FeedbackPhoto {
        try require(owner, formal: true); let stamp = generation
        if photo.attachmentID != nil, let date = photo.uploadedAt, Date().timeIntervalSince(date) < 1200 { return photo }
        struct Upload: Decodable { let id: String; let put_url: String; let put_headers: [String:String] }
        let upload: Upload = try await request("uploads/", owner: owner, method: .post, body:["mime":"image/jpeg","size":photo.bytes.count])
        guard let url = URL(string:upload.put_url), url.scheme == "https", url.host?.hasSuffix(".aliyuncs.com") == true else { throw HelpFailure("无法获取截图上传地址") }
        var r = URLRequest(url:url); r.httpMethod = "PUT"; r.timeoutInterval = 120
        for (k,v) in upload.put_headers { r.setValue(v,forHTTPHeaderField:k) }
        let (_,response) = try await URLSession.shared.upload(for:r,from:photo.bytes)
        try require(owner); guard stamp == generation else { throw CancellationError() }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw HelpFailure("截图上传失败，请重试或移除截图") }
        struct Ack: Decodable { let id: String; let status: String }
        let _: Ack = try await request("uploads/\(upload.id)/complete/", owner: owner, method: .post, body:[:])
        var result = photo; result.attachmentID = upload.id; result.uploadedAt = Date(); return result
    }
    func normalizePhoto(_ data: Data) throws -> FeedbackPhoto {
        guard let image = UIImage(data:data), image.size.width > 0, image.size.height > 0,
              image.size.width * image.size.height * image.scale * image.scale <= 80_000_000 else { throw HelpFailure("截图无法读取或像素过大") }
        let scale = min(1,2400/max(image.size.width,image.size.height)); let size = CGSize(width:image.size.width*scale,height:image.size.height*scale)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let flattened = UIGraphicsImageRenderer(size:size,format:format).image { ctx in UIColor.white.setFill();ctx.fill(CGRect(origin:.zero,size:size));image.draw(in:CGRect(origin:.zero,size:size)) }
        guard let bytes = flattened.jpegData(compressionQuality:0.88), bytes.count <= 10_000_000 else { throw HelpFailure("截图超过 10 MB，请缩小后重试") }
        return FeedbackPhoto(bytes:bytes)
    }
    private func directory(_ owner: String) -> URL { StoragePaths.system.accounts.appendingPathComponent(StoragePaths.scopeKey(owner)).appendingPathComponent("support",isDirectory:true) }
    func save(_ draft: FeedbackDraft, owner: String, name: String = "draft") throws {
        try require(owner); let dir = directory(owner); try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        let data = try JSONEncoder().encode(draft)
        try data.write(to:dir.appendingPathComponent(name+".json"),options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
    }
    func load(owner: String, name: String = "draft") -> FeedbackDraft? { guard self.owner == owner, let data = try? Data(contentsOf:directory(owner).appendingPathComponent(name+".json")) else { return nil };return try? JSONDecoder().decode(FeedbackDraft.self,from:data) }
    func removeDraft(owner: String, name: String = "draft") { guard self.owner == owner else { return };try? FileManager.default.removeItem(at:directory(owner).appendingPathComponent(name+".json")) }
    func cache<T: Encodable>(_ value: T, name: String) { guard let data = try? JSONEncoder().encode(value) else { return }; UserDefaults.standard.set(data,forKey:"help-public-"+name) }
    func cached<T: Decodable>(_ type: T.Type, name: String) -> T? { guard let data = UserDefaults.standard.data(forKey:"help-public-"+name) else { return nil };return try? JSONDecoder().decode(type,from:data) }
    func removeCachedArticle(_ id: String) {
        UserDefaults.standard.removeObject(forKey:"help-public-article-"+id)
        if let articles = cached([HelpArticle].self,name:"articles") { cache(articles.filter { $0.id != id },name:"articles") }
    }
}
