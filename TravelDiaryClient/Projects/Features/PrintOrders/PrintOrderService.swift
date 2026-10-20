import Foundation
import Combine
import CryptoKit

nonisolated struct PrintLocalJob: Codable, Identifiable, Sendable {
    var id: UUID { submission.key }
    let owner: String
    let directory: URL
    let submission: PrintSubmission
    var orderID: String?
    var uploadIDs: [String:String]?
    var completedRoles: [String]?
    var productionID: String?
    var state = "等待上传"
    var error: String?
}

@MainActor
final class PrintOrderService: ObservableObject {
    static let shared = PrintOrderService()
    @Published private(set) var jobs: [PrintLocalJob] = []
    @Published private(set) var progress: [UUID: Double] = [:]
    private var engine: SupportNetworkEngine?
    private var owner: String?
    private var boundAccount = false
    private var subscription: AnyCancellable?
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private let root = StoragePaths.system.accounts

    func configure(engine: SupportNetworkEngine, sessions: AppSessionStore) {
        self.engine = engine
        subscription = sessions.$state.sink { [weak self] state in
            guard let self else { return }
            let id: String?
            if case let .signedIn(session) = state { id = String(session.accountID); boundAccount = !session.isDeviceAccount }
            else { id = nil; boundAccount = false }
            guard id != owner else { return }
            tasks.values.forEach { $0.cancel() }; tasks.removeAll(); progress = [:]; jobs = []; owner = id
            if let id, let data = try? Data(contentsOf: index(id)), let saved = try? JSONDecoder().decode([PrintLocalJob].self, from: data) {
                jobs = saved.filter { $0.owner == id }
                for i in jobs.indices where jobs[i].state == "正在上传" { jobs[i].state = "上传已暂停" }
            }
        }
    }
    func requireOwner(_ expected: String, bound: Bool = false) throws {
        guard owner == expected else { throw PrintFailure("登录状态已变化，请重新打开订单") }
        if bound && !boundAccount { throw PrintFailure("请先在设置中绑定手机号或邮箱，再提交印制订单") }
    }
    func request<T: Decodable>(_ path: String, owner expected: String, body: Data? = nil) async throws -> T {
        try requireOwner(expected)
        guard let engine else { throw PrintFailure("服务尚未初始化") }
        let components = URLComponents(string: path)
        let response = try await engine.sendRaw(SupportNetworkRequest(method: body == nil ? .get : .post,
            path: "/api/v1/print/" + (components?.path ?? path), queryItems: components?.queryItems, body: body.map { .raw($0, contentType: "application/json") } ?? .none,
            strategy: NetworkStrategy(requiresAuth: true, allowETag: false)))
        try Task.checkCancellation(); try requireOwner(expected)
        return try JSONDecoder().decode(T.self, from: response.data)
    }
    func json(_ value: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) }
    func products(owner: String) async throws -> [PrintProduct] { try await request("products/", owner: owner) }
    func orders(owner: String, offset: Int = 0) async throws -> PrintOrderPage { try await request("orders/?offset=\(offset)", owner: owner) }
    func revisionOrders(bookID: UUID, owner: String) async throws -> [PrintOrder] {
        var result: [PrintOrder] = []; var offset = 0
        repeat {
            let page: PrintOrderPage = try await request("orders/?book_id=\(bookID.uuidString.lowercased())&state=needs_revision&offset=\(offset)", owner: owner)
            result += page.results
            guard let next = page.next_offset else { break }; offset = next
        } while true
        return result
    }
    func order(_ id: String, owner: String) async throws -> PrintOrder { try await request("orders/\(id)/", owner: owner) }
    func quote(product: PrintProduct, pages: Int, quantity: Int, address: PrintAddress, owner: String) async throws -> PrintQuote {
        try await request("quotes/", owner: owner, body: json(["product_id":product.id,"page_count":pages,"quantity":quantity,"region":address.region]))
    }
    func action(_ action: String, order: PrintOrder, owner: String, message: String = "", key: UUID) async throws -> PrintOrder {
        try await request("orders/\(order.id)/actions/", owner: owner,
            body: json(["action":action,"key":key.uuidString,"revision":order.revision,"message":message]))
    }
    func refreshPayment(_ id: String, owner: String) async throws -> PrintOrder {
        try await request("orders/\(id)/refresh-payment/", owner: owner, body: json([:]))
    }
    func pay(_ id: String, owner: String) async throws {
        try WeChatPrintPayment.shared.checkAvailability()
        let params: WeChatPaymentParameters = try await request("orders/\(id)/payments/", owner: owner, body: json([:]))
        try requireOwner(owner)
        try await WeChatPrintPayment.shared.pay(params)
    }
    func enqueue(_ submission: PrintSubmission, directory: URL, owner: String) throws -> UUID {
        try requireOwner(owner, bound: true)
        if let existing = jobs.first(where: { $0.id == submission.key }) { return existing.id }
        let job = PrintLocalJob(owner: owner, directory: directory, submission: submission)
        jobs.append(job)
        do { try persist(owner) } catch { jobs.removeAll { $0.id == job.id }; throw error }
        resume(job.id)
        return job.id
    }
    func resume(_ id: UUID) {
        guard tasks[id] == nil, let job = jobs.first(where: { $0.id == id }), job.owner == owner else { return }
        tasks[id] = Task { [weak self] in
            guard let self else { return }
            await upload(id)
            tasks[id] = nil
        }
    }
    func pause(_ id: UUID) { tasks[id]?.cancel() }
    func isRunning(_ id: UUID) -> Bool { tasks[id] != nil }
    func draftDirectory(owner: String) throws -> URL {
        try requireOwner(owner)
        let dir = StoragePaths.system.printOrders(owner).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: dir.path)
        return dir
    }
    private func index(_ owner: String) -> URL { StoragePaths.system.printOrders(owner).appendingPathComponent("jobs.json") }
    private func persist(_ owner: String) throws {
        let url = index(owner)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(jobs.filter { $0.owner == owner }).write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
    }
    private func mutate(_ id: UUID, _ change: (inout PrintLocalJob) -> Void) throws {
        guard let i = jobs.firstIndex(where: { $0.id == id }), jobs[i].owner == owner else { throw CancellationError() }
        change(&jobs[i]); try persist(jobs[i].owner)
    }
    private func upload(_ id: UUID) async {
        guard let job = jobs.first(where: { $0.id == id }) else { return }
        do {
            try requireOwner(job.owner, bound: true)
            try mutate(id) { $0.state = "正在上传"; $0.error = nil }
            // 恢复时校验文件摘要，绝不使用已修改的作品替换旧稿。
            for file in job.submission.files {
                let url = job.directory.appendingPathComponent(file.role + ".pdf")
                let hash = try await Task.detached { try DiaryBookPrintExporter.hashFile(url) }.value
                guard hash == file.sha256 else { throw PrintFailure("本地生产稿已丢失或变化，请取消订单后重新准备") }
            }
            try Task.checkCancellation()
            let order: PrintOrder
            if let existing = job.orderID { order = try await self.order(existing, owner: job.owner) }
            else {
                order = try await request("orders/", owner: job.owner, body: JSONEncoder().encode(job.submission))
                try mutate(id) { $0.orderID = order.id; $0.productionID = order.production_id }
                if job.submission.revise_order_id != nil {
                    let replaced = jobs.filter { $0.id != id && $0.orderID == order.id && $0.owner == job.owner }
                    for previous in replaced {
                        tasks[previous.id]?.cancel()
                        if previous.directory.standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path + "/") {
                            try? FileManager.default.removeItem(at: previous.directory)
                        }
                    }
                    jobs.removeAll { previous in replaced.contains { $0.id == previous.id } }
                    try persist(job.owner)
                }
            }
            if let expected = job.productionID, expected != order.production_id {
                throw PrintFailure("此上传任务已被新生产稿替换，请返回订单使用最新任务")
            }
            if !order.allowed_actions.contains("upload") && order.file_state != "ready" && order.file_state != "checking" {
                throw PrintFailure("订单已变化，当前不能继续此上传任务")
            }
            if order.file_state == "ready" || order.file_state == "checking" {
                try mutate(id) { $0.state = "已上传" }; return
            }
            var uploads = job.uploadIDs ?? [:]
            var completed = Set(job.completedRoles ?? [])
            func getPlan() async throws -> PrintUploadPlan {
                try await request("orders/\(order.id)/upload/", owner: job.owner,
                    body: json(["production_id": order.production_id ?? "", "uploads": uploads]))
            }
            var plan = try await getPlan()
            let total = job.submission.files.reduce(0) { $0 + $1.size }
            var sent = job.submission.files.filter { completed.contains($0.role) }.reduce(0) { $0 + $1.size }
            progress[id] = Double(sent) / Double(max(total, 1))
            for role in job.submission.files.map(\.role).sorted() {
                if completed.contains(role) { continue }
                guard var file = plan.files.first(where: { $0.role == role }),
                      let expected = job.submission.files.first(where: { $0.role == role }) else { throw PrintFailure("上传计划不完整") }
                var existing: [Int: PrintOSSXML.Part] = [:]
                if let listURL = file.list_url {
                    let (data, response) = try await PrintOSSXML.send(url: listURL, method: "GET")
                    if (response as? HTTPURLResponse)?.statusCode == 200 {
                        existing = try PrintOSSXML.read(data).parts
                    } else {
                        // 合并成功但响应丢失时，在手机直接向 OSS 确认对象；服务器不参与。
                        let (_, head) = try await PrintOSSXML.send(url: file.head_url, method: "HEAD")
                        if let http = head as? HTTPURLResponse, http.statusCode == 200,
                           Int(http.value(forHTTPHeaderField: "Content-Length") ?? "") == expected.size {
                            completed.insert(role); try mutate(id) { $0.completedRoles = Array(completed) }
                            sent += expected.size; progress[id] = Double(sent)/Double(max(total,1)); continue
                        }
                        guard (response as? HTTPURLResponse)?.statusCode == 404 else {
                            try PrintUploadHTTP.validate(response: response, body: data); throw PrintFailure("无法读取上传会话")
                        }
                        uploads.removeValue(forKey: role)
                        file = plan.files.first(where: { $0.role == role })!
                    }
                }
                if file.upload_id == nil || uploads[role] == nil && existing.isEmpty {
                    let (data, response) = try await PrintOSSXML.send(url: file.init_url, method: "POST", headers: file.init_headers)
                    try PrintUploadHTTP.validate(response: response, body: data)
                    guard let uploadID = try PrintOSSXML.read(data).uploadID else { throw PrintFailure("无法建立分片上传会话") }
                    uploads[role] = uploadID
                    try mutate(id) { $0.uploadIDs = uploads }
                    plan = try await getPlan()
                    guard let updated = plan.files.first(where: { $0.role == role }) else { throw PrintFailure("上传计划不完整") }
                    file = updated; existing = [:]
                }
                var etags: [Int:String] = [:]
                let source = job.directory.appendingPathComponent(role + ".pdf")
                for part in file.parts {
                    try Task.checkCancellation(); try requireOwner(job.owner)
                    if let have = existing[part.number], have.size == part.size {
                        etags[part.number] = have.etag; sent += part.size
                        progress[id] = Double(sent)/Double(max(total,1)); continue
                    }
                    guard let url = URL(string: part.url), url.scheme == "https", part.size > 0, part.size <= 5*1024*1024, part.offset >= 0 else { throw PrintFailure("上传地址无效") }
                    let chunk = job.directory.appendingPathComponent("upload-part.tmp")
                    try await Task.detached {
                        let handle = try FileHandle(forReadingFrom: source); defer { try? handle.close() }
                        try handle.seek(toOffset: UInt64(part.offset))
                        guard let data = try handle.read(upToCount: part.size), data.count == part.size else { throw PrintFailure("生产文件不完整") }
                        try data.write(to: chunk, options: [.atomic, .completeFileProtectionUnlessOpen])
                    }.value
                    defer { try? FileManager.default.removeItem(at: chunk) }
                    let req = try PrintUploadHTTP.request(url: url, headers: part.headers)
                    let (body, response) = try await URLSession.shared.upload(for: req, fromFile: chunk)
                    try PrintUploadHTTP.validate(response: response, body: body)
                    guard let etag = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "ETag"), !etag.isEmpty else { throw PrintFailure("上传未返回分片凭据，请重试") }
                    etags[part.number] = etag
                    try requireOwner(job.owner); sent += part.size; progress[id] = Double(sent)/Double(max(total,1))
                }
                guard let completeURL = file.complete_url else { throw PrintFailure("缺少合并上传授权") }
                let xml = PrintOSSXML.completion(etags)
                let (body, response) = try await PrintOSSXML.send(url: completeURL, method: "POST", headers: file.complete_headers, body: Data(xml.utf8))
                try PrintUploadHTTP.validate(response: response, body: body)
                guard try PrintOSSXML.read(body).root == "CompleteMultipartUploadResult" else { throw PrintFailure("文件合并未完成，请重试") }
                completed.insert(role); try mutate(id) { $0.completedRoles = Array(completed) }
            }
            let _: PrintOrder = try await request("orders/\(order.id)/complete-upload/", owner: job.owner,
                body: json(["production_id":plan.production_id,"client_confirmed":true,"completed_roles":completed.sorted()]))
            try mutate(id) { $0.state = "已上传" }; progress[id] = 1
        } catch {
            try? mutate(id) { $0.state = "上传已暂停"; $0.error = error is CancellationError ? nil : error.localizedDescription }
        }
    }
}


/// OSS signs Content-Type: use exactly the header declared in the upload plan.
nonisolated enum PrintUploadHTTP {
    static func request(url: URL, headers: [String: String]?) throws -> URLRequest {
        guard url.scheme == "https" else { throw PrintFailure("上传地址无效") }
        let expected = headers ?? ["Content-Type": "application/octet-stream"]
        guard expected.count == 1, expected["Content-Type"] == "application/octet-stream" else {
            throw PrintFailure("上传请求头不匹配，请刷新上传任务后重试")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"; request.timeoutInterval = 120
        request.setValue(expected["Content-Type"], forHTTPHeaderField: "Content-Type")
        return request
    }

    static func validate(response: URLResponse, body: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw PrintFailure("上传服务响应无效，请重试") }
        guard !(200..<300).contains(http.statusCode) else { return }
        // Error XML can contain signed URLs and signature inputs. Extract only the safe error code.
        let xml = String(decoding: body.prefix(8192), as: UTF8.self)
        let expression = try? NSRegularExpression(pattern: "<Code>([A-Za-z0-9_\\-]{1,80})</Code>")
        let match = expression?.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml))
        let code = match.flatMap { Range($0.range(at: 1), in: xml) }.map { String(xml[$0]) }
        let diagnostic = "HTTP \(http.statusCode)" + (code.map { " / " + $0 } ?? "")
        let hint: String
        switch code {
        case "SignatureDoesNotMatch": hint = "上传授权校验失败，请重新获取上传授权"
        case "AccessDenied", "RequestTimeTooSkewed", "ExpiredToken", "SecurityTokenExpired": hint = "上传授权失效或权限不足，请重试；若持续失败请联系工作人员"
        case "NoSuchUpload": hint = "上传会话已失效，请继续上传以重新建立会话"
        default: hint = "分片上传未完成，请重试"
        }
        throw PrintFailure("\(hint)（\(diagnostic)）；已上传的部分会保留")
    }
}


nonisolated final class PrintOSSXML: NSObject, XMLParserDelegate {
    struct Part { let size: Int; let etag: String }
    var uploadID: String?
    var root = ""
    var parts: [Int:Part] = [:]
    private var text = ""
    private var number = 0
    private var size = 0
    private var etag = ""
    static func read(_ data: Data) throws -> PrintOSSXML {
        guard data.count <= 1024*1024 else { throw PrintFailure("上传服务响应过大") }
        let result = PrintOSSXML(); let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false; parser.delegate = result
        guard parser.parse() else { throw PrintFailure("无法读取上传服务响应") }
        return result
    }
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String:String]) {
        if root.isEmpty { root = name }; text = ""
        if name == "Part" { number = 0; size = 0; etag = "" }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if name == "UploadId" { uploadID = value }
        if name == "PartNumber" { number = Int(value) ?? 0 }
        if name == "Size" { size = Int(value) ?? 0 }
        if name == "ETag" { etag = value }
        if name == "Part", number > 0, !etag.isEmpty { parts[number] = Part(size: size, etag: etag) }
    }
    static func completion(_ etags: [Int:String]) -> String {
        let parts = etags.keys.sorted().map { number in
            let value = etags[number]!.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
            return "<Part><PartNumber>\(number)</PartNumber><ETag>\(value)</ETag></Part>"
        }.joined()
        return "<CompleteMultipartUpload>" + parts + "</CompleteMultipartUpload>"
    }
    static func send(url: String, method: String, headers: [String:String] = [:], body: Data? = nil) async throws -> (Data, URLResponse) {
        guard let url = URL(string: url), url.scheme == "https" else { throw PrintFailure("上传授权地址无效") }
        var request = URLRequest(url: url); request.httpMethod = method; request.timeoutInterval = 120
        for (key,value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        request.httpBody = body
        return try await URLSession.shared.data(for: request)
    }
}
