import SwiftUI
import Combine

nonisolated struct DiaryAIWorkspaceEvent: Codable, Identifiable, Sendable {
    var id = UUID()
    var date = Date()
    var kind: String
    var title: String
    var detail: String
    var images: [Data] = []
}
nonisolated struct DiaryAIWorkspaceCheckpoint: Codable, Sendable {
    var document: DiaryDocument
    var drawings: [UUID: Data]
    var pending: [UUID]
    init(_ document: DiaryDocument, pending: [UUID]) {
        self.document = document; self.pending = pending; drawings = document.objects.mapValues(\.drawing)
    }
    var restoredDocument: DiaryDocument {
        var result = document
        for (id, bytes) in drawings { result.objects[id]?.drawing = bytes }
        return result
    }
}
nonisolated struct DiaryAIWorkspaceArchive: Codable, Sendable {
    var awaitingConfirmation: Bool? = nil
    var logSession: String? = nil
    var schema = 1
    var baseline: DiaryAIWorkspaceCheckpoint
    var checkpoints: [DiaryAIWorkspaceCheckpoint]
    var request: DiaryAIRequest
    var events: [DiaryAIWorkspaceEvent]
    var composition: String
    var version: Int
    var textDone: Bool? = nil
    var background: DiaryAIBackgroundRecord? = nil
}

/// One writer, explicit two-object batches, durable checkpoints before UI publication.
@MainActor final class DiaryAIWorkspace: ObservableObject {
    static let maximumBatchLayers = 5
    @Published private(set) var active = false
    @Published private(set) var running = false
    @Published private(set) var pending: [UUID] = []
    @Published private(set) var processing: [UUID] = []
    @Published private(set) var events: [DiaryAIWorkspaceEvent] = []
    @Published private(set) var preview: UIImage?
    @Published private(set) var original: UIImage?
    @Published private(set) var thumbnails: [UUID: UIImage] = [:]
    @Published private(set) var objects: [DiaryAIObject] = []
    @Published private(set) var version = 0
    @Published private(set) var stage = "准备排版"
    @Published var error: String?
    @Published var panelVisible = true
    @Published private(set) var selected: Set<UUID> = []
    private weak var source: DiaryEditorSession?
    private var working: DiaryEditorSession?
    private var bridge: DiaryEditorAIBridge?
    private var baseline: DiaryAIWorkspaceCheckpoint?
    private var checkpoints: [DiaryAIWorkspaceCheckpoint] = []
    private var request = DiaryAIRequest.defaults(.relayout)
    private var composition = ""
    private var task: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?
    private var generation = UUID()
    private var queue: [UUID] = []
    private var batchExpires: Date?
    private var autoAll = false
    private var textDone = false
    private var awaitingConfirmation = false
    @Published private(set) var backgroundRecord: DiaryAIBackgroundRecord?
    @Published private(set) var backgroundPreview: UIImage?
    private let backgroundProvider: any DiaryAIBackgroundProvider
    private let albumSaver: any DiaryAIBackgroundAlbumSaving
    var hasBackgroundRequest: Bool { request.background != nil }
    var isBackgroundOnly: Bool { request.background?.backgroundOnly == true }
    var needsTextCompletion: Bool { request.action == .relayout && request.canCreateText && !textDone && !isBackgroundOnly }
    var canGenerateBackground: Bool { active && !running && pending.isEmpty && hasBackgroundRequest && !needsTextCompletion }
    var canRetryAlbum: Bool { !running && backgroundRecord?.layerID != nil && backgroundRecord?.albumState != "saved" }
    private let model: any DiaryAIModelClient
    private let productionLog: DiaryAIProductionLog
    private let archiveURL: URL
    private let storage: DiaryAIWorkspaceStore
    private var storageSequence = 0
    var canRollback: Bool { checkpoints.count > 1 && !running }
    init(session: DiaryEditorSession, model: (any DiaryAIModelClient)? = nil, root: URL? = nil, backgroundProvider: (any DiaryAIBackgroundProvider)? = nil, albumSaver: (any DiaryAIBackgroundAlbumSaving)? = nil) {
        self.backgroundProvider = backgroundProvider ?? DiarySeedreamBackgroundProvider()
        self.albumSaver = albumSaver ?? DiaryAIBackgroundAlbum()
        productionLog = DiaryAIProductionLog(owner: session.store.ownerID, page: session.document.id, root: root ?? StoragePaths.system.support)
        source = session
        let client = DiaryArkResponsesClient(); client.workspaceMode = true
        self.model = model ?? client
        archiveURL = (root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0])
            .appendingPathComponent("DiaryCanvasAI/Workspaces/\(DiaryEditorAIBridge(session).storageKey).json")
        storage = DiaryAIWorkspaceStore(url: archiveURL)
    }
    private func log(_ kind: String, _ title: String, _ detail: String = "", images: [DiaryAIImage] = []) {
        let descriptions = images.map { "\($0.id) · \($0.caption) · \($0.data.count / 1024) KB" }.joined(separator: "\n")
        let smallImages = images.compactMap { item -> Data? in
            guard let image = UIImage(data: item.data) else { return nil }
            let ratio = min(1, 480 / max(image.size.width, image.size.height))
            let size = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            return UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }.jpegData(compressionQuality: 0.65)
        }
        productionLog.record("event", ["kind": kind, "title": title, "detail": detail, "images": images.map { ["id": $0.id, "caption": $0.caption, "file": productionLog.attachment($0.data, ext: "jpg")] }])
        events.append(.init(kind: kind, title: title, detail: detail + (descriptions.isEmpty ? "" : "\n" + descriptions), images: smallImages))
    }
    func exportProductionLog() async throws -> URL {
        productionLog.record("export", ["eventCount": events.count, "version": version, "pending": pending.map(\.uuidString)])
        return try await productionLog.export()
    }
    func enter(_ request: DiaryAIRequest) async {
        guard !active, let source else { return }
        (model as? DiaryArkResponsesClient)?.productionLog = productionLog
        (backgroundProvider as? DiarySeedreamBackgroundProvider)?.productionLog = productionLog
        if let bytes = try? JSONEncoder().encode(request) { productionLog.data("settings", bytes) }
        source.finishInteraction(); self.request = request; error = nil
        do {
            let saved = try await storage.load()
            if let saved, saved.schema == 1, let last = saved.checkpoints.last,
               try DiaryEditorAIBridge.digest(saved.baseline.restoredDocument) == DiaryEditorAIBridge.digest(source.document) {
                awaitingConfirmation = saved.awaitingConfirmation ?? false
                if let name = saved.logSession { productionLog.resume(name) }
                backgroundRecord = saved.background
                baseline = saved.baseline; checkpoints = saved.checkpoints; pending = last.pending
                self.request = saved.request; events = saved.events; composition = saved.composition; version = saved.version; textDone = saved.textDone ?? false
                if request.action == saved.request.action && request.selectedOnly == saved.request.selectedOnly {
                    self.request = request
                    if request.canCreateText && !saved.request.canCreateText { textDone = false }
                    if request.background != saved.request.background && backgroundRecord?.layerID == nil { backgroundRecord = nil }
                    if request != saved.request { log("settings", "已将新设置应用到恢复任务", "保留已提交布局和批次进度；后续操作使用本次面板设置。") }
                } else {
                    log("settings", "继续原任务的操作范围", "入口或选择范围不同，恢复任务保留原范围；请保存或放弃原任务后创建新任务。")
                }
                try await setup(last.restoredDocument)
                log("restore", "已恢复上次工作版本", "没有自动发起模型请求。")
            } else {
                backgroundRecord = nil; backgroundPreview = nil
                baseline = .init(source.document, pending: [])
                try await setup(source.document)
                pending = request.action == .relayout && request.background?.backgroundOnly != true ? objects.filter { $0.editable && $0.role != "background" && (!request.selectedOnly || $0.id == source.selectedID) }.map(\.id) : []
                checkpoints = [.init(source.document, pending: pending)]; version = 0; composition = ""; events = []; textDone = false; queue = []; selected = []
                log("checkpoint", "已创建排版前恢复点", "照片与相框绑定保留；待排区不改变源图层坐标。")
            }
            if let bytes = try? JSONEncoder().encode(self.request) { productionLog.data("effective-settings", bytes) }
            let originalBridge = DiaryEditorAIBridge(source); _ = try await originalBridge.capture(self.request)
            original = UIImage(data: try await originalBridge.originalPreview())
            try await persist(); active = true; panelVisible = true
            try await refresh()
            if let file = backgroundRecord?.filename { backgroundPreview = UIImage(contentsOfFile: backgroundFile(file).path) }
            source.aiWorkspacePresented = true
            if hasBackgroundRequest {
                log("preflight", "背景生成范围", objects.contains { $0.role == "background" && $0.locked } ? "背景已锁定，开始前需解除锁定或关闭生成背景。" : "排版阶段保留现有背景；新背景生成并通过检查后替换工作版本中的旧背景，原始恢复点保留。")
            }
        } catch { active = false; self.error = error.localizedDescription; source.errorMessage = error.localizedDescription }
    }
    private func setup(_ document: DiaryDocument) async throws {
        guard let source else { throw DiaryAIError.invalid("编辑器已关闭") }
        var images = source.images
        for (id, asset) in document.assets where images[id] == nil { images[id] = try await source.store.loadOriginalImage(asset, documentID: document.id) }
        let session = DiaryEditorSession(document: document, images: images, store: source.store, contentID: source.contentID)
        session.aiTransientSession = true; session.selectedID = source.selectedID
        working = session; let adapter = DiaryEditorAIBridge(session); bridge = adapter
        objects = adapter.objectChoices
        for object in objects where thumbnails[object.id] == nil {
            if let outer = document.layer(object.id) {
                func leafAsset(_ layer: DiaryLayer, visited: Set<UUID>) -> UUID? {
                    if layer.isPhotoFrame { return nil }
                    if let asset = layer.assetID { return asset }
                    guard let child = layer.contentID, !visited.contains(child), let content = document.objects[child] else { return nil }
                    return content.layers.compactMap { leafAsset($0, visited: visited.union([child])) }.first
                }
                if let asset = leafAsset(outer, visited: []), let image = images[asset] {
                    let ratio = min(1, 240 / max(image.size.width, image.size.height))
                    let size = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
                    let format = UIGraphicsImageRendererFormat(); format.scale = 1
                    thumbnails[object.id] = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
                }
            }
        }
    }
    private func refresh() async throws {
        guard let bridge else { return }
        bridge.allowedBatchIDs = nil; bridge.excludedRenderIDs = Set(pending)
        var contextRequest = request; contextRequest.selectedOnly = false
        _ = try await bridge.capture(contextRequest)
        preview = UIImage(data: try await bridge.originalPreview()); objects = bridge.objectChoices
    }
    func toggle(_ id: UUID) { if selected.contains(id) { selected.remove(id) } else if pending.contains(id) { selected.insert(id) } }
    func enqueue(_ ids: [UUID], hint: CGPoint? = nil) {
        let added = ids.filter { pending.contains($0) && !queue.contains($0) && !processing.contains($0) }
        queue += added; selected.subtract(added)
        if let hint { log("queue", "素材已加入下一批", "期望位置：页面横向 \(Int(hint.x * 100))%、纵向 \(Int(hint.y * 100))%；作为软约束。")
            composition += "\n用户希望 \(added.map(\.uuidString).joined(separator: ",")) 靠近页面归一化位置 \(hint)（需乘以画布宽高转换到设计单位），不越界、不遮挡。"
        }
        if !running { run(all: false) }
    }
    func processAll() { run(all: true) }
    func processSelected() { enqueue(Array(selected)) }
    func pause() {
        generation = UUID(); task?.cancel(); watchdog?.cancel(); task = nil; watchdog = nil; running = false; processing = []
        stage = "已暂停"; log("pause", "已暂停", "已提交批次保留，未提交操作丢弃。")
        Task { do { try await persist() } catch { self.error = error.localizedDescription } }
    }
    func rollback() async {
        guard canRollback, checkpoints.count > 1 else { return }
        do {
            let old = checkpoints.removeLast()
            guard let previous = checkpoints.last else { checkpoints.append(old); return }
            let previousIDs = Set(previous.restoredDocument.objects.values.flatMap(\.layers).map(\.id))
            if old.restoredDocument.objects.values.flatMap(\.layers).contains(where: { $0.kind == .text && !previousIDs.contains($0.id) }) { textDone = false }
            awaitingConfirmation = false
            pending = previous.pending; version += 1
            try await setup(previous.restoredDocument)
            if let id = backgroundRecord?.layerID, previous.restoredDocument.layer(id) == nil { backgroundRecord = nil; backgroundPreview = nil }
            try await persist(); try await refresh()
            log("rollback", "已回退上一批")
        } catch { self.error = error.localizedDescription }
    }
    func exitRestoringOriginal() async {
        pause()
        do { try await removeArchive(); active = false; source?.aiWorkspacePresented = false; working = nil; bridge = nil }
        catch { self.error = error.localizedDescription }
    }
    func save() async -> Bool {
        guard !running, let source, let baseline, let working else { return false }
        do {
            guard source.document == baseline.restoredDocument else { throw DiaryAIError.invalid("原作品已变化，不能覆盖。请退出后重新进入。") }
            var published = working.document
            // Pending objects remain fully editable assets in the document, hidden from the exported page.
            for id in pending { published.update(id) { $0.visible = false } }
            _ = try DiaryDocumentStore.validate(published)
            guard source.applyAIDraft(published, expected: baseline.restoredDocument, additionalImages: working.images) else { throw DiaryAIError.invalid("无法发布当前工作版本") }
            self.baseline = .init(source.document, pending: pending)
            try await persist()
            try await source.save()
            let needsBackgroundRecovery = request.background != nil && (backgroundRecord?.layerID == nil || (request.background?.saveToAlbum == true && backgroundRecord?.albumState != "saved"))
            if pending.isEmpty && !needsTextCompletion && !needsBackgroundRecovery { try await removeArchive() }
            active = false; source.aiWorkspacePresented = false; return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func keepForLater() async {
        pause()
        do { try await persist(); active = false; source?.aiWorkspacePresented = false }
        catch { self.error = error.localizedDescription }
    }
    private func persist() async throws {
        try await productionLog.flush()
        guard let baseline else { return }
        storageSequence += 1
        let value = DiaryAIWorkspaceArchive(awaitingConfirmation: awaitingConfirmation, logSession: productionLog.directory.lastPathComponent, baseline: baseline, checkpoints: checkpoints, request: request, events: events, composition: composition, version: version, textDone: textDone, background: backgroundRecord)
        try await storage.save(value, sequence: storageSequence)
    }
    private func removeArchive() async throws {
        storageSequence += 1
        try await storage.remove(sequence: storageSequence)
    }
    private func run(all: Bool) {
        guard active, !running else { return }
        if isBackgroundOnly || (hasBackgroundRequest && pending.isEmpty && !composition.isEmpty && !needsTextCompletion) { generateBackground(); return }
        if hasBackgroundRequest && objects.contains(where: { $0.role == "background" && $0.locked }) {
            error = "背景已锁定：请退出后解除背景锁定，或关闭生成背景再开始。尚未发起模型请求。"
            log("error", "开始前检查未通过", error!); return
        }
        autoAll = all; running = true; error = nil
        if request.action != .relayout && queue.isEmpty {
            queue = objects.filter { $0.editable && $0.role != "background" && (!request.selectedOnly || $0.id == source?.selectedID) && (request.action != .writing || $0.role == "text") }.map(\.id)
        }
        let token = UUID(); generation = token
        task = Task {
            defer { if generation == token { running = false; processing = []; watchdog?.cancel() } }
            do {
                if awaitingConfirmation {
                    (model as? DiaryArkResponsesClient)?.allowedWorkspaceTools = ["finish_batch"]
                    (model as? DiaryArkResponsesClient)?.planning = false
                    let reply = try await timedRequest(prompt: "上一批已提交，当前版本\(version)。只调用finish_batch，expectedVersion必须为整数\(version)。禁止重新修改图层。", images: preview.flatMap { $0.jpegData(compressionQuality: 0.8) }.map { [.init(id: "confirmed-canvas", caption: "已提交结果", data: $0)] } ?? [], continuation: nil, results: [], token: token)
                    guard reply.calls.count == 1, reply.calls.first?.name == "finish_batch" else { throw DiaryAIError.invalid("结果已保存，确认未完成；重试仅确认，不重新排版。") }
                    let args = try JSONSerialization.jsonObject(with: Data(reply.calls[0].arguments.utf8)) as? [String: Any]
                    guard args?["expectedVersion"] as? Int == version else { throw DiaryAIError.invalid("确认版本参数必须为整数\(version)") }
                    awaitingConfirmation = false; try await persist()
                }
                if composition.isEmpty {
                    if request.action == .writing {
                        composition = "仅处理文字，按用户指定的文字形式、字体、颜色和位置执行；保留所有照片、贴纸和背景。优先空白区域，不做整页重排。"
                        log("plan", "进入文字处理", "跳过整页构图规划，直接创建或修改可编辑文字。")
                    } else { try await plan(token: token) }
                }
                var batches = 0
                while generation == token && batches < 60 {
                    try Task.checkCancellation()
                    var ids = Array(queue.filter { request.action != .relayout || pending.contains($0) }.prefix(Self.maximumBatchLayers))
                    if ids.isEmpty && autoAll {
                        let order = ["photo", "group", "text", "textImage", "decoration", "frame"]
                        let remaining = pending.compactMap { id in objects.first { $0.id == id } }
                        if let role = order.first(where: { r in remaining.contains { $0.role == r } }) { ids = Array(remaining.filter { $0.role == role }.prefix(Self.maximumBatchLayers).map(\.id)) }
                    }
                    if autoAll && request.action == .relayout && request.canCreateText && !textDone && !pending.contains(where: { id in objects.first { $0.id == id }?.role == "photo" }) {
                        ids = []
                    }
                    if ids.isEmpty {
                        if request.action != .relayout && batches == 0 && !request.canCreateText {
                            ids = Array(objects.filter { $0.editable && $0.role != "background" && (!request.selectedOnly || $0.id == source?.selectedID) && (request.action != .writing || $0.role == "text") }.prefix(Self.maximumBatchLayers).map(\.id))
                        } else if !(request.canCreateText && !textDone && pending.allSatisfy { id in objects.first { $0.id == id }?.role != "photo" }) { break }
                    }
                    processing = ids; stage = ids.isEmpty ? "正在添加文字" : "正在处理 \(ids.compactMap { id in objects.first { $0.id == id }?.shortID }.joined(separator: "、"))"
                    try await batch(ids: ids, token: token)
                    queue.removeAll { ids.contains($0) }; batches += 1
                    if ids.isEmpty || request.action == .writing { textDone = true }
                    if !autoAll && queue.isEmpty { break }
                }
                if generation == token && pending.isEmpty && !needsTextCompletion && request.background != nil { try await createBackground(token: token) }
                if generation == token { stage = needsTextCompletion ? "照片排版已保留，待补充文字" : pending.isEmpty ? "本轮处理完成，可以保存" : "等待选择下一批素材"; log("complete", stage); try await persist() }
            } catch is CancellationError {} catch {
                if generation == token { let message = (error as? URLError)?.code == .timedOut ? "模型连接等待超时，已提交批次保留。手动重试会发起新请求，可能再次计费。" : error.localizedDescription; self.error = message; log("error", needsTextCompletion && pending.isEmpty ? "文字阶段未完成，已有排版保留" : pending.isEmpty && hasBackgroundRequest ? "背景阶段未完成，已有排版保留" : "当前批次未完成，已提交批次保留", message); try? await persist() }
            }
        }
    }
    private var hasRetainedVisualContent: Bool {
        guard let working else { return true }
        let retained = working.scopeLayers.filter { $0.visible && !pending.contains($0.id) && !($0.frameTargetID.map(pending.contains) ?? false) }
        return !retained.isEmpty || !working.content.drawing.isEmpty || working.content.background != nil
    }
    private func backgroundFile(_ filename: String) -> URL {
        archiveURL.deletingPathExtension().appendingPathComponent(URL(fileURLWithPath: filename).lastPathComponent)
    }
    func skipPendingText() async {
        guard active, !running, needsTextCompletion else { return }
        textDone = true
        log("skip", "用户已跳过新增文字", "保留已完成排版，可继续处理素材或生成背景。")
        do { try await persist() } catch { self.error = error.localizedDescription }
    }
    func generateBackground(regenerate: Bool = false) {
        guard canGenerateBackground else { return }
        if regenerate { backgroundRecord = nil; backgroundPreview = nil }
        running = true; error = nil
        let token = UUID(); generation = token
        task = Task {
            defer { if generation == token { running = false; watchdog?.cancel() } }
            do { try await createBackground(token: token); stage = "背景已完成，可以保存" }
            catch is CancellationError {} catch {
                if generation == token { self.error = error.localizedDescription; log("error", "背景尚未完成，排版已保留", error.localizedDescription); try? await persist() }
            }
        }
    }
    private func createBackground(token: UUID) async throws {
        guard let options = request.background, let working, let bridge, pending.isEmpty else { return }
        guard !needsTextCompletion else { throw DiaryAIError.invalid("新增文字尚未完成，请重试文字或明确跳过后再生成背景。") }
        if let id = backgroundRecord?.layerID, working.document.layer(id) != nil { return }
        guard !objects.contains(where: { $0.role == "background" && $0.locked }) else { throw DiaryAIError.invalid("当前背景已锁定，请先解除锁定后再生成。") }
        let started = Date(), expected = working.document
        let digest = try DiaryEditorAIBridge.digest(expected)
        if backgroundRecord?.inputDigest != digest { backgroundRecord = .init(inputDigest: digest) }
        guard let recordID = backgroundRecord?.id else { return }
        watchdog?.cancel()
        watchdog = Task { do { try await Task.sleep(for: .seconds(600)); if generation == token { pause(); error = "背景任务达到总时限，已保留排版与已下载图片。手动重试可能再次计费。" } } catch {} }
        defer { if generation == token { watchdog?.cancel() } }
        func check() throws { try Task.checkCancellation(); guard generation == token, self.working?.document == expected else { throw CancellationError() } }
        log("phase", "生成主题背景")
        stage = "准备背景参考图"
        bridge.excludedRenderIDs = Set(objects.filter { $0.role == "background" }.map(\.id))
        _ = try await bridge.capture(request)
        let reference = try DiaryAIBackgroundImaging.jpeg(try await bridge.originalPreview())
        try check()
        let size = working.content.referenceSize
        _ = try DiaryAIBackgroundImaging.exactSize(size)
        let style = DiaryAIBackgroundStyle.resolve(options.style)
        let occupied = objects.filter { $0.role != "background" && $0.visible }.map { "\($0.shortID) · \($0.role) · \($0.name) · 边界\($0.bounds) · 旋转\($0.angle)度 · \(request.heroID == $0.id ? "用户指定主照片" : "")" }.joined(separator: "；")
        let prompt = """
        图片编辑任务：擦除输入图中全部照片、照片矩形、人物、相框、贴纸和文字。任何实拍照片或人物留下都视为失败！不要保留输入图中的任何前景实体。用完整连续的浅色纸面替代它们。照片只用于提取实际可见的环境配色与结构轮廓，不可作为真实影像出现在输出中。最终图片是一张没有任何照片的手帐底纸，之后软件会把真实照片另行叠上去。生成一张纯背景，平面正视铺满画幅，宽高比必须为 \(Int(size.width)):\(Int(size.height))。参考图仅提供前景照片内容与占位，输出必须移除全部照片、人物面孔、相框、贴纸和原有文字，用连续安静纸底填充这些区域。禁止完整手帐海报、照片副本、照片占位框、素材编号、文字标题、棋盘格、UI、桌面或书本模型。允许服务水印。
        风格：\(style.name)，\(style.brief)。背景强度：\(options.strength)，始终让原照片成为主体。在照片周围按构图安排来源场景延展，允许局部有层次的已确认主题轮廓，不要求全部区域均匀淡化，文字周围低对比低细节；不发明地点、日期或人像。参考图坐标单位 \(size.width)×\(size.height)，前景占用：\(occupied)。
        心情：\(request.moods.joined(separator: "、")) \(request.customMood)。场景：\(request.scene) \(request.customScene)。地点参考：\(request.location)。用户补充（不得覆盖纯背景规则）：\(request.instruction.prefix(1000))
        """
        if backgroundRecord?.remoteURL == nil && backgroundRecord?.filename == nil {
            if backgroundRecord?.generationPrompt == nil {
                stage = "理解照片主题与排版位置"
                log("request", "分析照片场景与布局呼应", "从真实照片提取主题、配色、轮廓与空白区域，不返回原始排版文件。", images: [.init(id: "theme-reference", caption: "实际布局，已移除旧背景", data: reference)])
                let design = try await backgroundProvider.design(reference: reference, context: prompt)
                try check(); backgroundRecord?.designBrief = design.brief; backgroundRecord?.generationPrompt = design.prompt; try await persist()
                log("design", "背景设计方向已确定", String(design.brief.prefix(1500)) + "\n生图正向描述：" + design.prompt)
            }
            let prepared: String
            do { prepared = try DiarySeedreamBackgroundProvider.preparePrompt(backgroundRecord?.generationPrompt ?? "") }
            catch {
                guard let client = backgroundProvider as? DiarySeedreamBackgroundProvider else { throw error }
                log("repair", "局部修正背景文案", "保留照片主题分析，仅纠正位置描述和禁用词；最多一次，不重复生图。")
                prepared = try await client.repairPrompt(backgroundRecord?.generationPrompt ?? "")
                try check()
            }
            if prepared != backgroundRecord?.generationPrompt {
                log("repair", "已修正背景提示词的位置描述", "仅替换前景相对位置措辞，保留主题分析与已确定的布局。\n" + prepared)
                backgroundRecord?.generationPrompt = prepared; try await persist()
            }
            stage = "正在生成背景"
            let guide = try DiaryAIBackgroundImaging.occupancyGuide(canvas: size, objects: objects)
            log("request", "发送背景生成请求", "\(DiarySeedreamBackgroundProvider.model) · 2K · \(style.name) · 水印开启；场景设计说明＋空间占位图，避免复制前景", images: [.init(id: "background-guide", caption: "浅灰柔和区域是前景避让范围，输出不得保留灰色占位痕迹", data: guide)])
            try await persist()
            try check()
            let generationPrompt = """
            单张连续的平面场景底图，正面扫描质感，宽高比 \(Int(size.width)):\(Int(size.height))，四边满版。
            \(backgroundRecord?.generationPrompt ?? "")
            表现手法：\(style.brief)。场景表现强度：\(options.strength)。\(DiaryAIBackgroundStyle.sceneDirection(options.strength))
            主题实体严格限定于上面的正向场景描述，不添加新的环境类型或通用旅行图标。强度只影响覆盖面积、笔触密度和对比，不改变主题。
            输入的浅灰柔和分布表示前景密度，密集区域退让、空隙区域可延展景物，不画灰块、不把每处前景边界机械挖空。以纸墨消融、景物疏密和色彩过渡连接区域。输出场景背景：无摄影画面、人像、文字、装饰贴片、边框、折痕和中线，无立体展示物。
            """
            let url = try await backgroundProvider.generate(reference: guide, prompt: generationPrompt)
            try check(); backgroundRecord?.remoteURL = url; try await persist()
            log("response", "背景服务已返回图片地址", "开始下载；不会把临时地址作为作品资源。")
        }
        var bytes: Data
        if let filename = backgroundRecord?.filename { bytes = try Data(contentsOf: backgroundFile(filename)) }
        else {
            guard let url = backgroundRecord?.remoteURL else { throw DiaryAIError.invalid("背景下载地址缺失") }
            stage = "正在下载并匹配画布比例"
            try check()
            let downloaded = try await backgroundProvider.download(url); try check()
            // Keep the original download so a proportion/quality failure does not pay for a second generation.
            let rawName = "\(recordID).original"
            try FileManager.default.createDirectory(at: backgroundFile(rawName).deletingLastPathComponent(), withIntermediateDirectories: true)
            try downloaded.write(to: backgroundFile(rawName), options: .atomic)
            backgroundRecord?.filename = rawName; try await persist(); bytes = downloaded
        }
        bytes = try DiaryAIBackgroundImaging.prepare(bytes, canvas: size)
        let filename = "\(recordID).png"
        try bytes.write(to: backgroundFile(filename), options: .atomic)
        backgroundRecord?.filename = filename
        backgroundPreview = UIImage(data: bytes); try await persist()
        if backgroundRecord?.verified != true {
            stage = "检查纯背景与前景残留"
            log("inspect", "检查生成的纯背景", "对照参考图检查重复照片、文字与占位框。", images: [.init(id: "background", caption: "生成背景", data: bytes)])
            try check()
            try await backgroundProvider.validate(reference: reference, background: bytes); try check()
            backgroundRecord?.verified = true; try await persist()
        }
        stage = "正在加入画布"
        let candidate = DiaryEditorSession(document: expected, images: working.images, store: working.store, contentID: working.contentID)
        candidate.aiTransientSession = true
        guard await candidate.importMaterialBackground(bytes, name: "AI背景 · \(style.name)") else { throw DiaryAIError.invalid(candidate.errorMessage ?? "背景资源导入失败") }
        try check()
        guard let layerID = candidate.selectedID else { throw DiaryAIError.invalid("背景图层未创建") }
        self.working = candidate; self.bridge = DiaryEditorAIBridge(candidate)
        objects = self.bridge?.objectChoices ?? []
        backgroundRecord?.layerID = layerID
        checkpoints.append(.init(candidate.document, pending: pending)); version += 1
        try await persist(); try await refresh()
        log("commit", "背景已加入工作画布", "\(Int(size.width)):\(Int(size.height)) · 等比适配 · 用时 \(Int(Date().timeIntervalSince(started))) 秒；保存后发布到作品。")
        if options.saveToAlbum { await writeBackgroundAlbum(token: token) }
    }
    func retryBackgroundAlbum() {
        guard canRetryAlbum else { return }
        running = true; error = nil; let token = UUID(); generation = token
        task = Task { await writeBackgroundAlbum(token: token); if generation == token { running = false } }
    }
    private func writeBackgroundAlbum(token: UUID) async {
        guard generation == token, let recordID = backgroundRecord?.id, backgroundRecord?.albumState != "saved", let filename = backgroundRecord?.filename else { return }
        do {
            stage = "正在保存到相册"
            let bytes = try Data(contentsOf: backgroundFile(filename))
            backgroundRecord?.albumState = "saving"; try await persist()
            try Task.checkCancellation()
            try await albumSaver.save(bytes)
            guard backgroundRecord?.id == recordID, generation == token else { return }
            backgroundRecord?.albumState = "saved"; try await persist()
            log("album", "背景已保存到相册", "放弃本轮或撤销不会删除相册中的图片。")
        } catch {
            guard backgroundRecord?.id == recordID, generation == token else { return }
            backgroundRecord?.albumState = "failed"; try? await persist()
            if generation == token { self.error = error.localizedDescription; log("error", "背景已加入，相册保存未完成", error.localizedDescription) }
        }
    }
    private func timedRequest(prompt: String?, images: [DiaryAIImage], continuation: Data?, results: [DiaryAIToolResult], token: UUID) async throws -> DiaryAIModelReply {
        watchdog?.cancel()
        let remaining = min(DiaryAIRequestLimits.requestDeadline, batchExpires?.timeIntervalSinceNow ?? DiaryAIRequestLimits.requestDeadline)
        guard remaining > 0 else { throw DiaryAIError.invalid("本批达到总时限，已提交批次保留。") }
        watchdog = Task { do { try await Task.sleep(for: .seconds(remaining)); if generation == token { pause(); error = "本次请求达到总时限，已提交批次保留。手动重试会发起新请求，可能再次计费。" } } catch {} }
        if let client = model as? DiaryArkResponsesClient {
            client.expectedWorkspaceVersion = version
            client.onTransportEvent = { [weak self] title, detail in
                guard let self, self.generation == token else { return }
                self.log("transport", title, detail)
            }
        }
        let effectivePrompt = (model is DiaryArkResponsesClient) ? prompt.map { $0 + "\n当前工具schema不要求expectedVersion，由客户端绑定当前请求版本；不要输出expectedVersion。" } : prompt
        log("request", "正在发送本轮输入", "\(images.count + results.flatMap(\.images).count) 张图片；等待模型响应", images: images + results.flatMap(\.images))
        let result = try await model.respond(prompt: effectivePrompt, images: images, continuation: continuation, results: results)
        try Task.checkCancellation(); guard generation == token else { throw CancellationError() }
        watchdog?.cancel()
        log("response", "模型已响应", "\(result.calls.count) 个工具调用 · 输入 \(result.inputTokens.map(String.init) ?? "未知") tokens · 输出 \(result.outputTokens.map(String.init) ?? "未知") tokens")
        return result
    }
    private func plan(token: UUID) async throws {
        log("phase", "整体构图规划")
        guard let bridge else { return }
        bridge.allowedBatchIDs = nil; bridge.excludedRenderIDs = Set(pending)
        (model as? DiaryArkResponsesClient)?.planning = true
        var req = request; req.selectedOnly = false
        let context = try await bridge.capture(req)
        var images = try await bridge.initialImages(req)
        if !images.isEmpty { images[0].id = "layout-base"; images[0].caption = "排版基础画布：待排照片、贴纸及绑定相框全部移出；只显示背景和不参与本轮的固定内容。不是原版布局图。素材板与画布分开提供。" }
        if !hasRetainedVisualContent { images.removeAll { $0.id == "layout-base" } }
        let prompt = "若没有 layout-base，则画布为空白；按尺寸和素材规划。若有，第一张 layout-base 是清理待排素材后的排版基础，不是原来的布局。素材板只用于识别素材，不代表素材已放在页面上。先看清背景的图案、主体和留白，再规划构图。先规划整体构图，不执行图层修改。只调用 plan_composition，expectedVersion=\(version)，summary 用80～160字说明左右页分区、主照片、照片大小比例、文字预留区和贴纸依附关系；只调用此工具一次，禁止输出JSON排版文件、操作数组和长篇正文。避免所有对象缩小聚在中央。背景不可遮挡的主体也需预留。全部图层：\(try DiaryAIDraftController.json(context))。用户要求：\(try DiaryAIDraftController.json(request))。风格：\(DiaryAIStyleLibrary.brief(request.style))。后续每批最多5个图层，同类素材优先一起处理。"
        let response = try await timedRequest(prompt: prompt, images: images, continuation: nil, results: [], token: token)
        guard let call = response.calls.first(where: { $0.name == "plan_composition" }), let raw = try JSONSerialization.jsonObject(with: Data(call.arguments.utf8)) as? [String: Any], raw["expectedVersion"] as? Int == version,
              let summary = raw["summary"] as? String, !summary.isEmpty else { throw DiaryAIError.invalid("模型未给出整体构图，请重试") }
        composition = summary; log("plan", "整体构图已确定", summary); try await persist()
    }
    static func toolsForBatchStage(base: Set<String>, hasOperations: Bool, committed: Bool) -> Set<String> {
        if committed { return ["finish_batch"] }
        var tools = base
        tools.remove("finish_batch")
        if !hasOperations { tools.remove("commit_batch"); tools.remove("rollback_batch"); tools.remove("validate_layout") }
        else { tools.subtract(["get_workspace", "get_canvas_image", "list_fonts", "list_frame_styles", "inspect_layers", "validate_layout"]) }
        return tools
    }
    private func batch(ids: [UUID], token: UUID) async throws {
        let names = ids.compactMap { id in objects.first { $0.id == id }?.shortID }.joined(separator: "、")
        let count = events.filter { $0.kind == "phase" && $0.title.hasPrefix("第 ") }.count + 1
        log("phase", "第 \(count) 批 · \(ids.isEmpty ? "新增文字" : names)", "本批\(ids.count)个已有图层；逐项操作、统一提交后确认。")
        guard let bridge, let working else { return }
        (model as? DiaryArkResponsesClient)?.planning = false
        let batchStarted = Date()
        batchExpires = batchStarted.addingTimeInterval(DiaryAIRequestLimits.batchDeadline)
        defer { batchExpires = nil }
        bridge.allowedBatchIDs = Set(ids); bridge.excludedRenderIDs = Set(pending)
        var req = request; req.selectedOnly = false
        if !ids.isEmpty && request.action == .relayout { req.allowsText = false }
        var context = try await bridge.capture(req)
        context.objects = context.objects.filter { ids.contains($0.id) || (!pending.contains($0.id) && $0.visible) }
        var images = [DiaryAIImage(id: "current-canvas", caption: "最新排版画布：背景＋已完成摆放的对象；未完成照片、贴纸、相框不在画布中。本批素材单独附图。", data: try await bridge.originalPreview())]
        if !hasRetainedVisualContent { images = [] }
        if !ids.isEmpty { images += try await bridge.inspect(.init(contextID: context.id, objectIDs: ids, view: "fullAsset")) }
        if let client = model as? DiaryArkResponsesClient {
            var tools: Set<String> = ["get_workspace", "get_canvas_image", "list_fonts", "list_frame_styles", "inspect_layers", "rollback_batch", "commit_batch", "validate_layout", "finish_batch"]
            if req.canMove || ids.contains(where: { id in context.objects.first { $0.id == id }?.role == "text" }) { tools.insert("place_layer") }
            if ids.contains(where: { id in context.objects.first { $0.id == id }?.role == "text" }) { tools.insert("update_text") }
            if req.canCreateText { tools.insert("create_text") }
            if req.allowsCrop { tools.insert("set_photo_crop") }
            if req.allowsFrames { tools.insert("set_photo_frame") }
            if req.allowsDecorations { tools.insert("set_decoration_visibility") }
            client.allowedWorkspaceTools = tools
            client.allowedLayerReferences = context.objects.filter { ids.contains($0.id) }.flatMap { [$0.shortID, $0.id.uuidString] }
        }
        var operations: [DiaryAIOperation] = [], continuation: Data?, results: [DiaryAIToolResult] = []
        var committed = false, committedRound: Int?, seen: [String: String] = [:]
        let batchVersion = version
        var commitFailed = false
        var inspections = 0
        var missingCallRetries = 0
        var repeatedErrors = 0
        var recoveryPrompt: String?
        let batchTools = (model as? DiaryArkResponsesClient)?.allowedWorkspaceTools ?? []
        for round in 0..<8 {
            guard Date().timeIntervalSince(batchStarted) < DiaryAIRequestLimits.batchDeadline else { throw DiaryAIError.invalid("本批达到总时限，已提交操作保留。手动重试可能产生新请求和费用。") }
            if let client = model as? DiaryArkResponsesClient {
                client.allowedWorkspaceTools = Self.toolsForBatchStage(base: batchTools, hasOperations: !operations.isEmpty, committed: committed)
                if !committed && ids.isEmpty && !operations.isEmpty { client.allowedWorkspaceTools = commitFailed ? ["rollback_batch", "create_text"] : ["commit_batch"] }
            }
            let prompt = round == 0 ? """
            输出约定：只通过工具调用完成操作，不输出正文说明、Markdown、完整排版JSON、operations数组或任何文件。只传工具必填参数和确实要改的字段。客户端负责UUID解析、坐标换算、字体测量、资源和保存，你不需要生成这些数据。图层objectID优先使用本批L编号，版本号从工具返回读取。
            最短流程：新增文字批次先create_text；已有图层批次先place_layer或update_text。然后commit_batch；下一轮查看提交返回图片后finish_batch。必要时先裁剪或调整相框。已有图片、字体和版本足够时不要重复查询；不要输出长篇设计说明。commit_batch失败保留已暂存操作，按错误修订对应图层后再次提交。只有需要清空整批重做才用rollback_batch，清空后必须补齐全部对象。
            你在图层工作台中逐步设计手帐。仅使用工具处理本批对象，不返回完整文件或全页计划。先调用单项图层工具，修改暂存；commit_batch 原子执行并显示画布，返回图片用于确认已执行结果，提交后只调用finish_batch，不再调用修改工具；需要进一步调整留给下一批。每个工具必须带 expectedVersion，当前版本 \(batchVersion)。提交后版本加1。
            操作权限：\(try DiaryAIDraftController.json(request))。照片默认等比缩放；width 表示当前旋转可见边界的目标宽度，center={x,y} 是设计单位的视觉中心。set_photo_crop 只在授权时使用。create_text 必须有稳定 clientObjectKey；同key再次create_text表示修订暂存文字，可调整位置和文本框，不要用update_text修改尚未提交的新文字。文字不能放在spineX中央，左右各留24设计单位；使用左右页空白区。create_text必须使用目录中的fontID；用户指定字体与纸卡时遵从指定，否则按标题、旁注角色选择目录内字体和承托。主标题用短句与语义换行，正文/旁注与标题形成字号层级；完整词语不能被拆到两行。可用paper选择文字承托，标题优先titleParchment，短注可用warmHeart、blueTape、kraftStrip，心愿可用pinkWish，植物场景botanicalLine；不为所有文字都加纸卡，避免装饰堆积。禁止虚构事实。不要移动本批之外的对象。不删除、解锁，不修改背景。单项工具参数未知时调用查询。
            本批ID：\(ids.map(\.uuidString))。待排ID：\(pending.map(\.uuidString))。
            全局构图：\(composition)。本批定位不能把所有照片缩小到页面中心，要形成主次、留白和阅读顺序。
            place_layer 的 width 是换框、旋转后的最终可见包围盒宽度，center 是最终可见中心；客户端先完成裁剪与相框再统一定位，无需重复补偿相框尺寸。
            贴纸应贴近有语义关联的照片边缘或文字，避开人脸、建筑主体、文字和重要物体；不把相机、邮票等排成孤立的素材清单。优先装饰照片外缘空白，不以覆盖主体来填空。左右页须有连贯的阅读路径；底部大块留白要对应预留标题、旁注或明确的呼吸区，不把全部元素挤到上半页。
            已授权新增文字时，本批照片保持文字预留区；文字阶段必须实际创建可编辑文字，不能仅在说明中声称完成。
            页面及每个图层详细数据（只读输入，绝不复述或原样输出）：\(try DiaryAIDraftController.json(context))
            不能把素材编号、透明底板写入作品。先提交本批后再看最新整页图。需要新增文字且本批为空时只创建文字。已有文字按权限保留正文。
            """ : recoveryPrompt
            recoveryPrompt = nil
            let reply = try await timedRequest(prompt: prompt, images: round == 0 ? images : [], continuation: continuation, results: results, token: token)
            continuation = reply.continuation; results = []
            if reply.calls.isEmpty {
                guard missingCallRetries < 2 else { throw DiaryAIError.invalid(committed ? "本批已保存，模型未完成结果确认；请检查画布后继续。" : "模型未完成必要操作，当前批次未提交，已完成批次保留。") }
                missingCallRetries += 1
                let next = committed ? "已提交并附上最新画布，当前版本\(version)，请仅调用finish_batch。" : operations.isEmpty ? "尚未暂存操作；新增文字请先create_text，已有图层请先place_layer/update_text。禁止finish_batch。" : "已有\(operations.count)项暂存操作，请调用commit_batch。禁止finish_batch。"
                recoveryPrompt = "请继续完成本批，必须调用当前允许的工具，不要回复说明文字。" + next
                log("recovery", "正在纠正模型调用顺序", next)
                continue
            }
            for call in reply.calls {
                if let previous = seen[call.id] {
                    guard previous == call.arguments else { throw DiaryAIError.invalid("重复工具调用内容冲突") }
                    results.append(.init(callID: call.id, text: "此前调用已执行；不要重复提交。")); continue
                }
                seen[call.id] = call.arguments
                log("tool", "调用 \(call.name)", call.arguments)
                do {
                    let allowed = Self.toolsForBatchStage(base: batchTools, hasOperations: !operations.isEmpty, committed: committed)
                    guard allowed.contains(call.name) || !(model is DiaryArkResponsesClient) else { throw DiaryAIError.invalid("工具不属于当前阶段；允许：\(allowed.sorted().joined(separator: ","))") }
                    if committed && call.name != "finish_batch" { throw DiaryAIError.invalid("本批已提交，当前版本\(version)；下一轮只调用finish_batch，不要再移动或回滚图层。") }
                    guard let raw = try JSONSerialization.jsonObject(with: Data(call.arguments.utf8)) as? [String: Any] else { throw DiaryAIError.invalid("参数必须为JSON对象") }
                    guard raw["expectedVersion"] != nil else { throw DiaryAIError.invalid("缺少expectedVersion字段") }
                    guard raw["expectedVersion"] is NSNumber, !(raw["expectedVersion"] is String) else { throw DiaryAIError.invalid("expectedVersion类型错误：必须是整数\(version)，不能是字符串") }
                    guard raw["expectedVersion"] as? Int == version else { throw DiaryAIError.invalid("版本不匹配，当前版本 \(version)") }
                    for key in ["width", "angle", "fontSize"] where raw[key] != nil { guard raw[key] is NSNumber else { throw DiaryAIError.invalid("\(key)必须是数字，不能是字符串") } }
                    if let center = raw["center"] { guard let point = center as? [String: Any], point["x"] is NSNumber, point["y"] is NSNumber else { throw DiaryAIError.invalid("center必须是包含数字x、y的对象，不能是JSON字符串") } }
                    var text = "", feedback: [DiaryAIImage] = []
                    if let operation = try DiaryAIWorkspaceTools.parse(call, version: version, context: context) {
                        guard !committed, operations.count < 30 else { throw DiaryAIError.invalid("本批已提交或操作数过多") }
                        if operation.type != "createText" { guard let id = operation.objectID, ids.contains(id) else { throw DiaryAIError.invalid("只能处理本批对象") } }
                        if let index = operations.firstIndex(where: { $0.type == operation.type && (($0.objectID != nil && $0.objectID == operation.objectID) || ($0.clientObjectKey != nil && $0.clientObjectKey == operation.clientObjectKey)) }) {
                            let old = operations[index]
                            if operation.type == "setPlacement", let previous = old.scale, let next = operation.scale, next < previous * 0.5 {
                                throw DiaryAIError.invalid("同一图层已暂存摆放，本次缩小超过一半，可能混淆图层。请核对编号；确需重设时rollback_batch后明确重新排版本批。")
                            }
                            operations[index] = operation
                            log("revision", "修订已暂存图层", "同一图层的同类操作已替换，不重复执行。")
                        } else { operations.append(operation) }
                        commitFailed = false
                        text = "操作已暂存（\(operations.count)项），当前版本\(version)。下一步：完成本批必要操作后立即commit_batch；不要get_workspace、validate_layout或重复创建相同文字。"
                    } else {
                        switch call.name {
                        case "get_workspace": text = "当前版本 \(version)；已暂存\(operations.count)项；已提交=\(committed)。\(operations.isEmpty ? "请先创建或调整本批对象" : "请立即commit_batch")。\(try DiaryAIDraftController.json(context))"
                        case "list_fonts": text = try DiaryAIDraftController.json(context.fonts)
                        case "list_frame_styles": text = context.frameStyles.joined(separator: "、")
                        case "inspect_layers":
                            guard inspections < 2 else { throw DiaryAIError.invalid("本批补图次数已用完") }; inspections += 1
                            guard let values = raw["objectIDs"] as? [String] else { throw DiaryAIError.invalid("缺少对象ID") }
                            let wanted = values.compactMap { reference in context.objects.first { $0.shortID == reference || $0.id.uuidString.caseInsensitiveCompare(reference) == .orderedSame }?.id }; guard wanted.count <= Self.maximumBatchLayers && wanted.allSatisfy(ids.contains) else { throw DiaryAIError.invalid("补图超出本批范围") }
                            feedback = try await bridge.inspect(.init(contextID: context.id, objectIDs: wanted, view: "fullAsset")); text = "素材图片已附"
                        case "get_canvas_image":
                            let bytes = committed ? (preview?.jpegData(compressionQuality: 0.82) ?? Data()) : try await bridge.originalPreview()
                            feedback = [.init(id: "canvas-v\(version)", caption: "当前已提交画布", data: bytes)]; text = "当前画布"
                        case "rollback_batch": guard !committed else { throw DiaryAIError.invalid("已提交批次需用户回退") }; operations = []; commitFailed = false; text = "已清空本批全部未提交操作（不只失败的一项）。必须重新摆放全部对象：\(ids.compactMap { id in context.objects.first { $0.id == id }?.shortID }.joined(separator: "、"))，全部暂存后才能commit_batch。"
                        case "commit_batch":
                            guard !committed, !operations.isEmpty else { throw DiaryAIError.invalid("没有待提交操作或已经提交") }
                            if request.action == .relayout {
                                guard Set(ids).isSubset(of: Set(operations.filter { $0.type == "setPlacement" || ($0.type == "updateText" && $0.center != nil) }.compactMap(\.objectID))) else { throw DiaryAIError.invalid("本批尚未摆放：\(ids.filter { id in !operations.contains { $0.objectID == id && ($0.type == "setPlacement" || ($0.type == "updateText" && $0.center != nil)) } }.compactMap { id in context.objects.first { $0.id == id }?.shortID }.joined(separator: "、"))。保留已有暂存操作，补齐这些对象后再提交。") }
                            }
                            bridge.excludedRenderIDs = Set(pending).subtracting(ids)
                            let draft = try await bridge.propose(.init(schemaVersion: 1, contextID: context.id, baseDigest: context.digest, summary: raw["summary"] as? String ?? "完成本批", operations: operations))
                            try Task.checkCancellation(); guard generation == token else { throw CancellationError() }
                            try bridge.apply()
                            let previous = pending; pending.removeAll { ids.contains($0) }
                            let previousTextDone = textDone
                            if operations.contains(where: { $0.type == "createText" }) { textDone = true }
                            checkpoints.append(.init(working.document, pending: pending)); version += 1; awaitingConfirmation = true
                            do { try await persist() } catch {
                                checkpoints.removeLast(); pending = previous; textDone = previousTextDone; version -= 1
                                if let last = checkpoints.last { try await setup(last.restoredDocument) }
                                throw error
                            }
                            committed = true; committedRound = round; preview = UIImage(data: draft.preview); objects = bridge.objectChoices
                            feedback = [.init(id: "canvas-v\(version)", caption: "本批已提交，请检查效果后 finish_batch", data: draft.preview)]
                            text = "提交成功，版本 \(version)。\(draft.summary)；\(draft.warnings.joined(separator: "；"))。实际位置：\(objects.filter { ids.contains($0.id) }.map { "\($0.shortID)中心\($0.center)" }.joined(separator: "；"))。对照规划检查贴纸是否依附对应照片，禁止把贴纸排成左上素材清单；检查文字换行与下方留白用途。"
                        case "validate_layout": text = committed ? "本批已通过原生文档和几何校验，请结合图片检查效果。" : "请先 commit_batch，失败会返回具体校验错误。"
                        case "finish_batch":
                            guard committed, let committedRound, round > committedRound else { throw DiaryAIError.invalid(committed ? "本批已提交；下一轮查看返回图片后仅调用finish_batch，版本\(version)" : operations.isEmpty ? "尚未创建或修改图层；请先create_text或place_layer，再commit_batch" : "已有暂存操作，请先commit_batch；下一轮看图后再finish_batch") }
                            awaitingConfirmation = false; try await persist()
                            log("batch", "本批完成", "版本 \(version) 已保存；剩余 \(pending.count) 项")
                            return
                        default: throw DiaryAIError.invalid("本工作台不支持该工具")
                        }
                    }
                    let labels = ["place_layer": "摆放图层", "create_text": "新增文字", "update_text": "修改文字", "set_photo_crop": "调整照片取景", "set_photo_frame": "调整相框", "attach_decoration": "放置贴纸", "commit_batch": "本批已提交到画布"]
                    let target = (raw["objectID"] as? String).flatMap { reference in context.objects.first { $0.shortID == reference || $0.id.uuidString.caseInsensitiveCompare(reference) == .orderedSame }?.shortID }
                    log("result", (target.map { $0 + " · " } ?? "") + (labels[call.name] ?? call.name) + (operations.isEmpty || committed ? "" : " · 已暂存"), text, images: feedback)
                    results.append(.init(callID: call.id, text: text, images: feedback))
                } catch is CancellationError { throw CancellationError() }
                catch {
                    repeatedErrors += 1
                    if repeatedErrors >= 2 {
                        continuation = nil
                        recoveryPrompt = "当前版本\(version)，已提交=\(committed)。只处理本批ID：\(ids)。\(committed ? "只调用finish_batch。" : "参数用原生数字与对象，仅提交本批必要操作。") 最近错误：\(error.localizedDescription)"
                        repeatedErrors = 0
                    }
                    if call.name == "commit_batch" { commitFailed = true }; log("error", "\(call.name) 未执行", error.localizedDescription); results.append(.init(callID: call.id, text: "ERROR: \(error.localizedDescription)。请修复参数。")) }
            }
        }
        throw DiaryAIError.invalid(committed ? "本批已保存，但视觉确认未完成；请检查画布后继续。" : "本批达到调用上限，请调整要求后重试。")
    }
}
