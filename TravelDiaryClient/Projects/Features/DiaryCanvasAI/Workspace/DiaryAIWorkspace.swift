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
    var parallelExecution: Bool? = nil
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
    var layoutRegions: [DiaryAILayoutRegion]? = nil
    var visualRevision: DiaryAIVisualRevision? = nil
    var confirmationScope: DiaryAIVisualRevision? = nil
}

/// One writer, bounded batches and visual repairs, durable checkpoints before UI publication.
@MainActor final class DiaryAIWorkspace: ObservableObject {
    static let maximumBatchLayers = 8
    static let maximumStickers = 8
    var stickerCount: Int { objects.filter { $0.visible && ["decoration", "group", "textImage"].contains($0.role) }.count }
    var canAddSticker: Bool { stickerCount < Self.maximumStickers && !running && !saving }
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
    @Published private(set) var displaySession: DiaryEditorSession?
    private var working: DiaryEditorSession?
    @Published private(set) var preparingPhotos: [UUID] = []
    func beginPreparingPhotos(_ count: Int) -> [UUID] {
        let ids = (0..<count).map { _ in UUID() }
        preparingPhotos += ids
        return ids
    }
    func finishPreparingPhotos(_ ids: [UUID]) { preparingPhotos.removeAll { ids.contains($0) } }
    @Published private(set) var addingMaterials = false
    func configureAndStart(_ value: DiaryAIRequest) {
        guard active, !running, !addingMaterials, preparingPhotos.isEmpty else { return }
        request = value.coordinated()
        log("settings", "整页制作设置", request.designBrief)
        if value.action != .relayout { pending = [] }
        Task {
            do { try await refresh(); processAll() }
            catch { self.error = error.localizedDescription }
        }
    }
    private var bridge: DiaryEditorAIBridge?
    private var baseline: DiaryAIWorkspaceCheckpoint?
    private var checkpoints: [DiaryAIWorkspaceCheckpoint] = []
    private var request = DiaryAIRequest.defaults(.relayout)
    var currentDesign: DiaryAIDesignSelection? { request.design }
    private var composition = ""
    private var layoutRegions: [DiaryAILayoutRegion] = []
    private var visualRevision: DiaryAIVisualRevision?
    private var confirmationScope: DiaryAIVisualRevision?
    private var task: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?
    private var backgroundTask: Task<Void, Error>?
    private var albumTask: Task<Void, Never>?
    private var parallelExecution: Bool
    private var generation = UUID()
    private var discarded = false
    private var queue: [UUID] = []
    private var batchExpires: Date?
    private var autoAll = false
    private var textDone = false
    private var awaitingConfirmation = false
    @Published private(set) var backgroundRecord: DiaryAIBackgroundRecord?
    @Published private(set) var backgroundPreview: UIImage?
    private let backgroundProvider: any DiaryAIBackgroundProvider
    private let albumSaver: any DiaryAIBackgroundAlbumSaving
    @Published private(set) var saving = false
    var canSaveWork: Bool {
        active && !running && !addingMaterials && preparingPhotos.isEmpty && !saving &&
        objects.contains { $0.visible && !pending.contains($0.id) }
    }
    var hasBackgroundRequest: Bool { request.background != nil }
    var isBackgroundOnly: Bool { request.background?.backgroundOnly == true }
    var needsTextCompletion: Bool { request.action == .relayout && request.canCreateText && !textDone && !isBackgroundOnly }
    var canContinueText: Bool {
        needsTextCompletion && !composition.isEmpty && !pending.contains { id in objects.first { $0.id == id }?.role == "photo" } && !awaitingConfirmation && visualRevision == nil
    }
    var canGenerateBackground: Bool { active && !running && pending.isEmpty && hasBackgroundRequest && !needsTextCompletion && visualRevision == nil && (!awaitingConfirmation || backgroundRecord?.verified == false) }
    var canRetryAlbum: Bool { !running && backgroundRecord?.layerID != nil && backgroundRecord?.albumState != "saved" }
    private var pendingBackgroundDesign: DiaryAIBackgroundDesign?
    private let efficientExecution: Bool
    private let model: any DiaryAIModelClient
    private let productionLog: DiaryAIProductionLog
    private let archiveURL: URL
    private let storage: DiaryAIWorkspaceStore
    private var storageSequence = 0
    var canRollback: Bool { checkpoints.count > 1 && !running && !addingMaterials }
    init(session: DiaryEditorSession, model: (any DiaryAIModelClient)? = nil, root: URL? = nil, backgroundProvider: (any DiaryAIBackgroundProvider)? = nil, albumSaver: (any DiaryAIBackgroundAlbumSaving)? = nil, efficientExecution: Bool? = nil, parallelExecution: Bool? = nil) {
        self.parallelExecution = parallelExecution ?? (UserDefaults.standard.object(forKey: "DiaryCanvasAI.parallelExecution") as? Bool ?? true)
        self.backgroundProvider = backgroundProvider ?? DiarySeedreamBackgroundProvider()
        self.albumSaver = albumSaver ?? DiaryAIBackgroundAlbum()
        productionLog = DiaryAIProductionLog(owner: session.store.ownerID, page: session.document.id, root: root ?? StoragePaths.system.support)
        source = session
        let client = DiaryArkResponsesClient(); client.workspaceMode = true
        self.model = model ?? client
        self.efficientExecution = efficientExecution ?? (model == nil || model is DiaryArkResponsesClient)
        archiveURL = (root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0])
            .appendingPathComponent("DiaryCanvasAI/Workspaces/\(DiaryEditorAIBridge(session).storageKey).json")
        storage = DiaryAIWorkspaceStore(url: archiveURL)
    }
    private var thumbnailTask: Task<Void, Never>?

    private func log(_ kind: String, _ title: String, _ detail: String = "", images: [DiaryAIImage] = []) {
        let descriptions = images.map { "\($0.id) · \($0.caption) · \($0.data.count / 1024) KB" }.joined(separator: "\n")
        productionLog.record("event", ["kind": kind, "title": title, "detail": detail, "images": images.map { ["id": $0.id, "caption": $0.caption, "file": productionLog.attachment($0.data, ext: "jpg")] }])
        events.append(.init(kind: kind, title: title, detail: detail + (descriptions.isEmpty ? "" : "\n" + descriptions), images: []))
        guard !images.isEmpty, let eventID = events.last?.id else { return }
        let previous = thumbnailTask
        thumbnailTask = Task { [weak self] in
            await previous?.value
            let thumbnails = (try? await DiaryAIImageWork.run { images.compactMap { DiaryAIImageWork.thumbnail($0.data) } }) ?? []
            guard let self, let index = self.events.firstIndex(where: { $0.id == eventID }) else { return }
            self.events[index].images = thumbnails
        }
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
        pendingBackgroundDesign = nil
        source.finishInteraction(); self.request = request.coordinated(); error = nil
        do {
            let saved = try await storage.load()
            if let saved, saved.schema == 1, let last = saved.checkpoints.last,
               try DiaryEditorAIBridge.digest(saved.baseline.restoredDocument) == DiaryEditorAIBridge.digest(source.document) {
                parallelExecution = saved.parallelExecution ?? false
                awaitingConfirmation = saved.awaitingConfirmation ?? false
                layoutRegions = saved.layoutRegions ?? []; visualRevision = saved.visualRevision; confirmationScope = saved.confirmationScope
                if let name = saved.logSession { productionLog.resume(name) }
                backgroundRecord = saved.background
                baseline = saved.baseline; checkpoints = saved.checkpoints; pending = last.pending
                self.request = saved.request.coordinated(); events = saved.events; composition = saved.composition; version = saved.version; textDone = saved.textDone ?? false
                if request.action == saved.request.action && request.selectedOnly == saved.request.selectedOnly {
                    self.request = request.coordinated()
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
                layoutRegions = []; visualRevision = nil; confirmationScope = nil
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
                let siblings = document.objects[session.contentID]?.layers ?? []
                let bounds = DiaryPageRenderer.bounds(outer, document: document, siblings: siblings)
                    .applying(DiaryPageRenderer.matrix(outer, siblings: siblings))
                if bounds.width > 0 && bounds.height > 0 {
                    var thumbnailDocument = document
                    thumbnailDocument.objects[session.contentID]?.layers = siblings.filter { $0.id == outer.id || $0.frameTargetID == outer.id }
                    thumbnailDocument.objects[session.contentID]?.background = nil
                    thumbnailDocument.objects[session.contentID]?.drawing = Data()
                    let ratio = min(1, 240 / max(bounds.width, bounds.height))
                    let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = false
                    thumbnails[object.id] = UIGraphicsImageRenderer(size: CGSize(width: bounds.width * ratio, height: bounds.height * ratio), format: format).image { output in
                        output.cgContext.scaleBy(x: ratio, y: ratio)
                        output.cgContext.translateBy(x: -bounds.minX, y: -bounds.minY)
                        DiaryPageRenderer.draw(thumbnailDocument, contentID: session.contentID, images: images, in: output.cgContext, cacheObjects: false)
                    }
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
        updateDisplaySession()
    }
    private func updateDisplaySession() {
        if let working {
            var document = working.document
            let hidden = Set(pending)
            document.objects[working.contentID]?.layers.removeAll { hidden.contains($0.id) || $0.frameTargetID.map(hidden.contains) == true }
            let display = DiaryEditorSession(document: document, images: working.images, store: working.store, contentID: working.contentID)
            display.aiTransientSession = true
            displaySession = display
        }
    }
    /// Add to the working version so save/restore and pending masks stay coherent.
    @discardableResult
    func addMaterials(_ data: [Data], sticker: Bool = false, name: String = "贴纸", material: DiaryMaterialSource? = nil) async -> Bool {
        while addingMaterials {
            do { try await Task.sleep(for: .milliseconds(30)) } catch { return false }
        }
        guard active, !running, !saving, let working else { return false }
        if sticker && stickerCount >= Self.maximumStickers {
            error = "最多添加8张贴纸，请先移除不需要的贴纸。"
            return false
        }
        addingMaterials = true
        defer { addingMaterials = false }
        let candidate = DiaryEditorSession(document: working.document, images: working.images, store: working.store, contentID: working.contentID)
        candidate.aiTransientSession = true
        let before = Set(DiaryEditorAIBridge(candidate).objectChoices.map(\.id))
        let success: Bool
        if sticker {
            guard let bytes = data.first else { return false }
            success = await candidate.importPhoto(bytes, asSticker: true, stickerName: name, materialSource: material)
        } else { success = await candidate.importPhotos(data) }
        guard success else { error = candidate.errorMessage ?? "素材添加失败，请重试"; return false }
        let previousPending = pending
        let previousCheckpoints = checkpoints
        let previousComposition = composition
        let previousRegions = layoutRegions
        let previousVersion = version
        let previousAwaiting = awaitingConfirmation
        let previousRevision = visualRevision
        let previousConfirmation = confirmationScope
        do {
            let added = DiaryEditorAIBridge(candidate).objectChoices.filter { !before.contains($0.id) && $0.role != "background" }.map(\.id)
            pending += added
            checkpoints.append(.init(candidate.document, pending: pending))
            composition = ""; layoutRegions = []; awaitingConfirmation = false; visualRevision = nil; confirmationScope = nil
            version += 1
            try await persist()
            try await setup(candidate.document)
            try await refresh()
            log("import", sticker ? "已添加贴纸" : "已添加照片", "新增 \(added.count) 项到待排区；点击开始排版后制作。")
            try await persist()
            return true
        } catch {
            pending = previousPending; checkpoints = previousCheckpoints
            composition = previousComposition; layoutRegions = previousRegions; version = previousVersion
            awaitingConfirmation = previousAwaiting; visualRevision = previousRevision; confirmationScope = previousConfirmation
            try? await setup(working.document); try? await refresh(); try? await persist()
            self.error = error.localizedDescription
            return false
        }
    }

    func prepareLayoutAdjustment() async {
        guard active, !running, !addingMaterials, let working else { return }
        pending = objects.filter { $0.editable && $0.role != "background" }.map(\.id)
        composition = ""; layoutRegions = []; awaitingConfirmation = false; visualRevision = nil; confirmationScope = nil
        checkpoints.append(.init(working.document, pending: pending))
        do { try await persist(); try await refresh() }
        catch { self.error = error.localizedDescription }
    }

    func removePendingMaterial(_ id: UUID) async {
        guard active, !running, !addingMaterials, pending.contains(id), let working else { return }
        let originalDocument = working.document
        let originalPending = pending
        do {
            var document = working.document
            document.objects[working.contentID]?.layers.removeAll { $0.id == id || $0.frameTargetID == id }
            pending.removeAll { $0 == id }; selected.remove(id)
            checkpoints.append(.init(document, pending: pending))
            try await persist(); try await setup(document); try await refresh()
            version += 1
            composition = ""; layoutRegions = []
            log("remove", "已移除待排素材", "原始恢复点保留，可回退上一批。")
            try await persist()
        } catch {
            pending = originalPending
            if checkpoints.count > 1 { checkpoints.removeLast() }
            try? await setup(originalDocument); try? await refresh(); try? await persist()
            self.error = error.localizedDescription
        }
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
        generation = UUID(); task?.cancel(); albumTask?.cancel(); backgroundTask?.cancel(); backgroundTask = nil; watchdog?.cancel(); task = nil; watchdog = nil; running = false; processing = []
        stage = "已暂停"; log("pause", "已暂停", "已提交批次保留，未提交操作丢弃。")
        Task { do { try await persist() } catch { self.error = error.localizedDescription } }
    }
    /// Cancel and join writers before the creation directory can be removed.
    func discardForNewPage() async {
        discarded = true
        generation = UUID()
        active = false
        let previousTask = task, previousBackground = backgroundTask
        previousTask?.cancel(); previousBackground?.cancel(); albumTask?.cancel(); watchdog?.cancel()
        task = nil; backgroundTask = nil; watchdog = nil
        await previousTask?.value
        _ = try? await previousBackground?.value
        running = false; processing = []; queue = []
        if let working { await working.discardCreationSession() }
        if let displaySession { await displaySession.discardCreationSession() }
        working = nil; displaySession = nil; bridge = nil
        source?.aiWorkspacePresented = false
    }

    func rollback() async {
        guard canRollback, checkpoints.count > 1 else { return }
        do {
            let old = checkpoints.removeLast()
            guard let previous = checkpoints.last else { checkpoints.append(old); return }
            let previousIDs = Set(previous.restoredDocument.objects.values.flatMap(\.layers).map(\.id))
            if old.restoredDocument.objects.values.flatMap(\.layers).contains(where: { $0.kind == .text && !previousIDs.contains($0.id) }) { textDone = false }
            awaitingConfirmation = false; visualRevision = nil; confirmationScope = nil
            pending = previous.pending; version += 1
            try await setup(previous.restoredDocument)
            if let id = backgroundRecord?.layerID, previous.restoredDocument.layer(id) == nil { backgroundRecord = nil; backgroundPreview = nil }
            try await persist(); try await refresh()
            log("rollback", "已回退上一批")
        } catch { self.error = error.localizedDescription }
    }
    func exitRestoringOriginal() async {
        guard !addingMaterials, preparingPhotos.isEmpty else { return }
        pause()
        do { try await removeArchive(); active = false; source?.aiWorkspacePresented = false; working = nil; bridge = nil }
        catch { self.error = error.localizedDescription }
    }
    func save() async -> Bool {
        guard !running, !addingMaterials, preparingPhotos.isEmpty, !saving, let source, let baseline, let working else { return false }
        saving = true
        defer { saving = false }
        await albumTask?.value
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
            try await source.creationPublish?()
            let needsBackgroundRecovery = request.background != nil && (backgroundRecord?.layerID == nil || (request.background?.saveToAlbum == true && backgroundRecord?.albumState != "saved"))
            if pending.isEmpty && !needsTextCompletion && !needsBackgroundRecovery && visualRevision == nil && !awaitingConfirmation { try await removeArchive() }
            active = false; source.aiWorkspacePresented = false; return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func keepForLater() async {
        guard !addingMaterials, preparingPhotos.isEmpty else { return }
        pause()
        do { try await persist(); active = false; source?.aiWorkspacePresented = false }
        catch { self.error = error.localizedDescription }
    }
    private func persist() async throws {
        await thumbnailTask?.value
        guard !discarded else { return }
        try await productionLog.flush()
        guard !discarded, let baseline else { return }
        storageSequence += 1
        let value = DiaryAIWorkspaceArchive(parallelExecution: parallelExecution, awaitingConfirmation: awaitingConfirmation, logSession: productionLog.directory.lastPathComponent, baseline: baseline, checkpoints: checkpoints, request: request, events: events, composition: composition, version: version, textDone: textDone, background: backgroundRecord, layoutRegions: layoutRegions, visualRevision: visualRevision, confirmationScope: confirmationScope)
        try await storage.save(value, sequence: storageSequence)
    }
    private func removeArchive() async throws {
        storageSequence += 1
        try await storage.remove(sequence: storageSequence)
    }
    private func run(all: Bool) {
        guard active, !running, !addingMaterials, preparingPhotos.isEmpty else { return }
        if isBackgroundOnly || (hasBackgroundRequest && pending.isEmpty && !composition.isEmpty && !needsTextCompletion && visualRevision == nil && !awaitingConfirmation) { generateBackground(); return }
        if hasBackgroundRequest && objects.contains(where: { $0.role == "background" && $0.locked }) {
            error = "背景已锁定：请退出后解除背景锁定，或关闭生成背景再开始。尚未发起模型请求。"
            log("error", "开始前检查未通过", error!); return
        }
        if request.action == .relayout, !isBackgroundOnly, request.instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !objects.contains(where: { $0.editable && $0.role != "background" }) {
            error = "请先添加照片、文字或贴纸，或在制作选项中补充创作要求。尚未发起模型请求。"
            log("error", "画布没有可排版内容", error!); return
        }
        if model is DiaryArkResponsesClient && !isBackgroundOnly {
            do { _ = try DiaryAITestConfig.requireAPIKey() }
            catch { self.error = error.localizedDescription; stage = "AI 服务配置不可用"; return }
        }
        autoAll = all; running = true; error = nil
        if request.action != .relayout && queue.isEmpty {
            queue = objects.filter { $0.editable && $0.role != "background" && (!request.selectedOnly || $0.id == source?.selectedID) && (request.action != .writing || $0.role == "text") }.map(\.id)
        }
        let token = UUID(); generation = token
        task = Task {
            defer { if generation == token { running = false; processing = []; backgroundTask?.cancel(); backgroundTask = nil; watchdog?.cancel() } }
            do {
                if awaitingConfirmation { try await confirmSavedBatch(token: token) }
                if composition.isEmpty {
                    if request.action == .writing {
                        composition = "仅处理文字，按用户指定的文字形式、字体、颜色和位置执行；保留所有照片、贴纸和背景。优先空白区域，不做整页重排。"
                        log("plan", "进入文字处理", "跳过整页构图规划，直接创建或修改可编辑文字。")
                    } else { try await plan(token: token) }
                }
                if parallelExecution && autoAll && request.background != nil && !isBackgroundOnly { try await startBackgroundBranch(token: token) }
                if model is DiaryArkResponsesClient && request.action == .relayout && pending.filter({ id in objects.first(where: { $0.id == id })?.role == "photo" }).count > Self.maximumBatchLayers {
                    try await verifySourceOrientations(token: token)
                }
                var batches = 0
                while generation == token && batches < 60 {
                    try Task.checkCancellation()
                    if let revision = visualRevision {
                        processing = revision.ids; stage = "正在修复排版"
                        try await batch(ids: revision.ids, token: token, revision: revision)
                        batches += 1
                        continue
                    }
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
                    if parallelExecution && efficientExecution && autoAll && request.action == .relayout && needsTextCompletion && ids.isEmpty && model is DiaryArkResponsesClient {
                        let decorations = pending.filter { id in objects.first { $0.id == id }?.role == "decoration" }
                        if !decorations.isEmpty {
                            do {
                                try await parallelForeground(ids: decorations, token: token)
                                queue.removeAll { decorations.contains($0) }; batches += 1
                                continue
                            } catch is CancellationError { throw CancellationError() }
                            catch { log("recovery", "并行提案未提交，按原批次继续", error.localizedDescription) }
                        }
                    }
                    processing = ids; stage = ids.isEmpty ? "正在添加文字" : "正在处理 \(ids.compactMap { id in objects.first { $0.id == id }?.shortID }.joined(separator: "、"))"
                    try await batch(ids: ids, token: token)
                    queue.removeAll { ids.contains($0) }; batches += 1
                    if ids.isEmpty || request.action == .writing { textDone = true }
                    if !autoAll && queue.isEmpty && visualRevision == nil { break }
                }
                if efficientExecution && awaitingConfirmation && !parallelExecution {
                    for _ in 0..<3 {
                        try await confirmSavedBatch(token: token)
                        guard let revision = visualRevision else { break }
                        try await batch(ids: revision.ids, token: token, revision: revision)
                    }
                    guard !awaitingConfirmation else { throw DiaryAIError.invalid("整体视觉验收尚未完成，已提交结果保留。") }
                }
                if generation == token && pending.isEmpty && !needsTextCompletion && request.background != nil { try await createBackground(token: token) }
                if parallelExecution && efficientExecution && awaitingConfirmation {
                    for _ in 0..<3 {
                        try await confirmSavedBatch(token: token)
                        guard let revision = visualRevision else { break }
                        try await batch(ids: revision.ids, token: token, revision: revision)
                    }
                    guard !awaitingConfirmation else { throw DiaryAIError.invalid("整体视觉验收尚未完成，结果已保留。") }
                }

                if generation == token { stage = needsTextCompletion ? "照片排版已保留，待补充文字" : pending.isEmpty ? (events.contains { $0.kind == "warning" } ? "处理完成，仍有视觉问题需检查" : "本轮处理完成，可以保存") : "等待选择下一批素材"; log("complete", stage); try await persist() }
            } catch is CancellationError {} catch {
                if generation == token {
                    if visualRevision != nil { stage = "局部修复未完成，已提交排版保留" }
                    else if awaitingConfirmation { stage = "排版已保存，待确认效果" }
                    else if canContinueText || (request.action == .writing && !textDone) { stage = "文字未完成，已提交排版保留；待排素材 \(pending.count) 项" }
                    else { stage = "已提交排版保留；待排素材 \(pending.count) 项" }
                    let message = (error as? URLError)?.code == .timedOut ? "模型连接等待超时，已提交批次保留。手动重试会发起新请求，可能再次计费。" : error.localizedDescription; self.error = message; log("error", needsTextCompletion && pending.isEmpty ? "文字阶段未完成，已有排版保留" : pending.isEmpty && hasBackgroundRequest ? "背景阶段未完成，已有排版保留" : "当前批次未完成，已提交批次保留", message); try? await persist() }
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
        guard active, !running, canContinueText else { return }
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
    /// Capture input once before editing; the branch never writes foreground layers.
    private func startBackgroundBranch(token: UUID) async throws {
        guard backgroundTask == nil, backgroundRecord?.remoteURL == nil,
              let options = request.background, let working else { return }
        let inputBridge = DiaryEditorAIBridge(working)
        inputBridge.excludedRenderIDs = Set(objects.filter { $0.role == "background" }.map(\.id))
        _ = try await inputBridge.capture(request)
        let reference = try await inputBridge.originalPreview()
        let size = working.content.referenceSize
        let plannedObjects = objects.map { object -> DiaryAIObject in
            var copy = object
            if let region = layoutRegions.first(where: { $0.objectID == object.id.uuidString || $0.objectID == object.shortID }) { copy.bounds = region.bounds }
            return copy
        }
        let textRegions = layoutRegions.filter { $0.role == "text" }.map(\.bounds)
        let guide = try await DiaryAIImageWork.run { try DiaryAIBackgroundImaging.occupancyGuide(canvas: size, objects: plannedObjects, textRegions: textRegions) }
        let style = DiaryAIBackgroundStyle.resolve(options.style)
        let context = "整页设计：\(request.designBrief)。共同构图：\(composition)。区域：\(try DiaryAIDraftController.json(layoutRegions))。场景：\(request.scene)。用户要求：\(request.instruction)。创作资料：\(request.creationBrief?.modelInstructions ?? "")。风格：\(style.name)，\(style.brief)。\(style.sceneDirection(options.strength))。这是排版前的素材参考，背景空间必须按共同构图预留，不按旧照片坐标。"
        backgroundRecord = .init(inputDigest: try DiaryEditorAIBridge.digest(working.document))
        log("parallel", "背景与图层排版同时开始", "按同一构图区域生成背景；前景继续分批处理。")
        backgroundTask = Task { [self] in
            let design = try await backgroundProvider.design(reference: reference, context: context)
            try Task.checkCancellation(); guard generation == token else { throw CancellationError() }
            backgroundRecord?.designBrief = design.brief; backgroundRecord?.generationPrompt = design.prompt
            try await persist()
            let prepared: String
            do { prepared = try DiarySeedreamBackgroundProvider.preparePrompt(design.prompt) }
            catch { prepared = try await (backgroundProvider as? DiarySeedreamBackgroundProvider)?.repairPrompt(design.prompt) ?? design.prompt }
            let url = try await backgroundProvider.generate(reference: guide, prompt: DiaryAIBackgroundStyle.generationPrompt(design: prepared, style: style, strength: options.strength, size: size))
            try Task.checkCancellation(); guard generation == token else { throw CancellationError() }
            backgroundRecord?.remoteURL = url; try await persist()
            log("parallel", "并行背景已生成", "立即下载并检查纯背景，前景继续排版。")
            guard let recordID = backgroundRecord?.id else { throw CancellationError() }
            let downloaded = try await backgroundProvider.download(url)
            try Task.checkCancellation(); guard generation == token else { throw CancellationError() }
            let rawName = "\(recordID).original"
            let rawURL = backgroundFile(rawName)
            try await DiaryAIImageWork.run {
                try FileManager.default.createDirectory(at: rawURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try downloaded.write(to: rawURL, options: .atomic)
            }
            guard generation == token, backgroundRecord?.id == recordID else { throw CancellationError() }
            backgroundRecord?.filename = rawName
            try await persist()
            let filename = "\(recordID).png"
            let outputURL = backgroundFile(filename)
            let bytes = try await DiaryAIImageWork.run {
                let prepared = try DiaryAIBackgroundImaging.prepare(downloaded, canvas: size)
                try prepared.write(to: outputURL, options: .atomic)
                return prepared
            }
            try Task.checkCancellation(); guard generation == token else { throw CancellationError() }
            backgroundRecord?.filename = filename
            backgroundPreview = UIImage(data: bytes)
            log("inspect", "并行检查生成的纯背景", "依据冻结构图与来源照片检查；合成后的遮挡与文字可读性仍由最终验收检查。", images: [.init(id: "background", caption: "生成背景", data: bytes)])
            try await backgroundProvider.validate(reference: reference, background: bytes, style: style)
            try Task.checkCancellation()
            guard generation == token, backgroundRecord?.id == recordID else { throw CancellationError() }
            backgroundRecord?.verified = true
            try await persist()
            log("parallel", "背景下载与检查完成", "等待协调器加入画布。")
        }
    }
    private func createBackground(token: UUID) async throws {
        if let branch = backgroundTask { defer { backgroundTask = nil }; try await branch.value }

        guard let options = request.background, let working, let bridge, pending.isEmpty else { return }
        guard !needsTextCompletion else { throw DiaryAIError.invalid("新增文字尚未完成，请重试文字或明确跳过后再生成背景。") }
        if let id = backgroundRecord?.layerID, working.document.layer(id) != nil { return }
        guard !objects.contains(where: { $0.role == "background" && $0.locked }) else { throw DiaryAIError.invalid("当前背景已锁定，请先解除锁定后再生成。") }
        let started = Date(), expected = working.document
        let digest = try DiaryEditorAIBridge.digest(expected)
        if backgroundRecord?.inputDigest != digest && !(parallelExecution && backgroundRecord?.remoteURL != nil) { backgroundRecord = .init(inputDigest: digest) }
        if let design = pendingBackgroundDesign, backgroundRecord?.generationPrompt == nil {
            backgroundRecord?.designBrief = design.brief; backgroundRecord?.generationPrompt = design.prompt
        }
        guard let recordID = backgroundRecord?.id else { return }
        watchdog?.cancel()
        watchdog = Task { do { try await Task.sleep(for: .seconds(600)); if generation == token { pause(); error = "背景任务达到总时限，已保留排版与已下载图片。手动重试可能再次计费。" } } catch {} }
        defer { if generation == token { watchdog?.cancel() } }
        func check() throws { try Task.checkCancellation(); guard generation == token, self.working?.document == expected else { throw CancellationError() } }
        log("phase", "生成主题背景")
        stage = "准备背景参考图"
        bridge.excludedRenderIDs = Set(objects.filter { $0.role == "background" }.map(\.id))
        _ = try await bridge.capture(request)
        let reference = try await bridge.originalPreview()
        try check()
        let size = working.content.referenceSize
        _ = try DiaryAIBackgroundImaging.exactSize(size)
        let style = DiaryAIBackgroundStyle.resolve(options.style)
        let occupied = objects.filter { $0.role != "background" && $0.visible }.map { "\($0.shortID) · \($0.role) · \($0.name) · 边界\($0.bounds) · 旋转\($0.angle)度 · \(request.heroID == $0.id ? "用户指定主照片" : "")" }.joined(separator: "；")
        let prompt = """
        图片编辑任务：擦除输入图中全部照片、照片矩形、人物、相框、贴纸和文字。任何实拍照片或人物留下都视为失败！不要保留输入图中的任何前景实体。用完整连续的浅色纸面替代它们。照片只用于提取实际可见的环境配色与结构轮廓，不可作为真实影像出现在输出中。最终图片是一张没有任何照片的手帐底纸，之后软件会把真实照片另行叠上去。生成一张纯背景，平面正视铺满画幅，宽高比必须为 \(Int(size.width)):\(Int(size.height))。参考图仅提供前景照片内容与占位，输出必须移除全部照片、人物面孔、相框、贴纸和原有文字，用连续安静纸底填充这些区域。禁止完整手帐海报、照片副本、照片占位框、素材编号、文字标题、棋盘格、UI、桌面或书本模型。允许服务水印。
        风格：\(style.name)，\(style.brief)。独立风格规则：\(style.sceneDirection(options.strength))。背景强度：\(options.strength)，始终让原照片成为主体。在照片周围按构图安排来源场景延展，允许局部有层次的已确认主题轮廓，不要求全部区域均匀淡化，文字周围低对比低细节；不发明地点、日期或人像。参考图坐标单位 \(size.width)×\(size.height)，前景占用：\(occupied)。
        整页设计：\(request.designBrief)。共同构图：\(composition)。
        心情：\(request.moods.joined(separator: "、")) \(request.customMood)。场景：\(request.scene) \(request.customScene)。地点参考：\(request.location)。用户补充（不得覆盖纯背景规则）：\(request.instruction.prefix(1000))
        创作资料：\(request.creationBrief?.modelInstructions ?? "")
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
            let guideObjects = objects
            let guide = try await DiaryAIImageWork.run { try DiaryAIBackgroundImaging.occupancyGuide(canvas: size, objects: guideObjects) }
            log("request", "发送背景生成请求", "\(DiarySeedreamBackgroundProvider.model) · 2K · \(style.name) · 水印开启；场景设计说明＋空间占位图，避免复制前景", images: [.init(id: "background-guide", caption: "浅灰柔和区域是前景避让范围，输出不得保留灰色占位痕迹", data: guide)])
            try await persist()
            try check()
            let generationPrompt = DiaryAIBackgroundStyle.generationPrompt(design: backgroundRecord?.generationPrompt ?? "", style: style, strength: options.strength, size: size)
            let url = try await backgroundProvider.generate(reference: guide, prompt: generationPrompt)
            try check(); backgroundRecord?.remoteURL = url; try await persist()
            log("response", "背景服务已返回图片地址", "开始下载；不会把临时地址作为作品资源。")
        }
        var bytes: Data
        if let filename = backgroundRecord?.filename {
            let url = backgroundFile(filename)
            bytes = try await DiaryAIImageWork.run { try Data(contentsOf: url) }
            try check()
        }
        else {
            guard let url = backgroundRecord?.remoteURL else { throw DiaryAIError.invalid("背景下载地址缺失") }
            stage = "正在下载并匹配画布比例"
            try check()
            let downloaded = try await backgroundProvider.download(url); try check()
            // Keep the original download so a proportion/quality failure does not pay for a second generation.
            let rawName = "\(recordID).original"
            let rawURL = backgroundFile(rawName)
            try await DiaryAIImageWork.run {
                try FileManager.default.createDirectory(at: rawURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try downloaded.write(to: rawURL, options: .atomic)
            }
            try check()
            backgroundRecord?.filename = rawName; try await persist(); bytes = downloaded
        }
        let downloadedBytes = bytes
        let filename = "\(recordID).png"
        let outputURL = backgroundFile(filename)
        bytes = try await DiaryAIImageWork.run {
            let prepared = try DiaryAIBackgroundImaging.prepare(downloadedBytes, canvas: size)
            try prepared.write(to: outputURL, options: .atomic)
            return prepared
        }
        try check()
        backgroundRecord?.filename = filename
        backgroundPreview = UIImage(data: bytes); try await persist()
        if backgroundRecord?.verified != true {
            stage = "检查背景主题与风格"
            log("inspect", "检查生成的纯背景", "对照参考图检查重复照片、文字、占位框、主题及\(style.name)的明显媒介错配。", images: [.init(id: "background", caption: "生成背景", data: bytes)])
            try check()
            try await backgroundProvider.validate(reference: reference, background: bytes, style: style); try check()
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
        if options.saveToAlbum {
            albumTask?.cancel()
            albumTask = Task { [weak self] in await self?.writeBackgroundAlbum(token: token) }
        }
    }
    func retryBackgroundAlbum() {
        guard canRetryAlbum else { return }
        running = true; error = nil; let token = UUID(); generation = token
        task = Task { await writeBackgroundAlbum(token: token); if generation == token { running = false } }
    }
    private func writeBackgroundAlbum(token: UUID) async {
        guard generation == token, let recordID = backgroundRecord?.id, backgroundRecord?.albumState != "saved", let filename = backgroundRecord?.filename else { return }
        do {
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
    static func executionPermissions(_ request: DiaryAIRequest) throws -> String {
        var raw = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as! [String: Any]
        if let brief = request.creationBrief { raw["creationBrief"] = brief.modelInstructions }
        // Design has its own stage brief; empty optional prose carries no permissions.
        raw.removeValue(forKey: "design")
        for key in ["customMood", "customScene", "location", "instruction"] where raw[key] as? String == "" { raw.removeValue(forKey: key) }
        return String(decoding: try JSONSerialization.data(withJSONObject: raw, options: [.sortedKeys]), as: UTF8.self)
    }
    private func modelContext(_ context: DiaryAIContext, text: Bool) throws -> String {
        guard efficientExecution else { return try DiaryAIDraftController.json(context) }
        var raw = try JSONSerialization.jsonObject(with: JSONEncoder().encode(context)) as! [String: Any]
        for key in ["digest", "baseDigest", "id", "contentID", "frameStyles"] { raw.removeValue(forKey: key) }
        if var objects = raw["objects"] as? [[String: Any]] {
            for i in objects.indices { objects[i].removeValue(forKey: "assetIDs") }
            raw["objects"] = objects
        }
        if let fonts = raw["fonts"] as? [[String: Any]] {
            let ids = ["calligraphy.ma-shan-zheng", "calligraphy.long-cang", "handwriting.lxgw.wenkai", "handwriting.yozai", "handwriting.xiaolai", "system"]
            raw["fonts"] = text ? fonts.filter { ids.contains($0["id"] as? String ?? "") || (($0["name"] as? String).map { !$0.isEmpty && request.instruction.contains($0) } ?? false) } : []
        }
        return String(decoding: try JSONSerialization.data(withJSONObject: raw, options: [.sortedKeys]), as: UTF8.self)
    }
    private func plan(token: UUID) async throws {
        log("phase", "整体构图规划")
        guard let bridge else { return }
        bridge.allowedBatchIDs = nil; bridge.excludedRenderIDs = Set(pending).union(request.background == nil ? [] : objects.filter { $0.role == "background" }.map(\.id))
        (model as? DiaryArkResponsesClient)?.planning = true
        var req = request; req.selectedOnly = false
        let context = try await bridge.capture(req)
        (model as? DiaryArkResponsesClient)?.allowedLayerReferences = context.objects.filter { $0.role == "photo" && $0.editable }.map { $0.id.uuidString }
        var images = try await bridge.initialImages(req)
        if !images.isEmpty { images[0].id = "layout-base"; images[0].caption = "排版基础画布：待排照片、贴纸及绑定相框全部移出；只显示背景和不参与本轮的固定内容。不是原版布局图。素材板与画布分开提供。" }
        if !hasRetainedVisualContent { images.removeAll { $0.id == "layout-base" } }
        if request.background != nil, !images.isEmpty { images[0].caption = "旧背景将替换，参考图已移除旧背景；不要为旧背景图案保留空间，只保护锁定内容。" }
        let prompt = (request.background != nil ? "本轮将在排版后生成新背景，旧背景不参与构图，不保护它的文字/人物。" : "") + "若没有 layout-base，则画布为空白；按尺寸和素材规划。若有，第一张 layout-base 是清理待排素材后的排版基础，不是原来的布局。素材板只用于识别素材，不代表素材已放在页面上。先看清背景的图案、主体和留白，再规划构图。先规划整体构图，不执行图层修改。只调用 plan_composition，\(versionInstruction) 有照片时用heroID明确主照UUID；用户指定主照优先，主照区域要按原图比例实际容纳，实际面积大于辅助照片。summary 用80～160字说明左右页分区、主照片、照片大小比例、文字预留区和贴纸依附关系；只调用此工具一次。重新排版时同时提供regions：每个photo区域提供rotation（0/90/-90/180），根据素材板中原照片实际像素方向判断：正常竖照/横照为0；横倒的人物、动物或地平线必须给纠正角度，不因区域横竖形状而旋转。rotation是最终绝对角度，后续不得擅自改变。每张真实照片恰好一个带objectID的photo区域，不能重复照片或给贴纸分配photo区域，授权文字时按文字密度预留区域：简短补充1至2个text区域，丰富记录3至5个有主次的text区域（标题、引题、照片旁注、结语），优先保留照片主体，空间不足减少文字角色；文字区域需容纳真实文字和纸卡内边距，标题区高度建议400至550、旁注区320至450，不能仅按裸文字高度预留。区域用设计单位x/y/width/height，必须在单页内避开书脊24单位，照片区域不占文字区域。已有图层只规划可编辑对象。禁止输出JSON排版文件、操作数组和长篇正文。避免所有对象缩小聚在中央。背景不可遮挡的主体也需预留。全部图层：\(try modelContext(context, text: false))。用户要求：\(try DiaryAIDraftController.json(request))。风格：\(request.designBrief)。后续每批最多8个图层，同类素材优先一起处理。"
        var planningFeedback = ""
        let planningAttempts = efficientExecution ? 2 : 3
        for attempt in 0..<planningAttempts {
            let response = try await timedRequest(prompt: prompt + planningFeedback, images: images, continuation: nil, results: [], token: token)
            do {
                guard response.calls.count == 1, let call = response.calls.first, call.name == "plan_composition",
                      let raw = try JSONSerialization.jsonObject(with: Data(call.arguments.utf8)) as? [String: Any], raw["expectedVersion"] as? Int == version,
                      let summary = raw["summary"] as? String, !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw DiaryAIError.invalid("请仅调用一次plan_composition，提供构图说明") }
                let plannedHero = (raw["heroID"] as? String).flatMap { reference in context.objects.first { $0.role == "photo" && $0.editable && ($0.shortID == reference || $0.id.uuidString.caseInsensitiveCompare(reference) == .orderedSame) }?.id.uuidString }
                var adoptedSummary = summary
                var regions: [DiaryAILayoutRegion] = []
                if request.action == .relayout, let value = raw["regions"] {
                    var decoded = try JSONDecoder().decode([DiaryAILayoutRegion].self, from: JSONSerialization.data(withJSONObject: value))
                    for index in decoded.indices {
                        if let reference = decoded[index].objectID, let object = context.objects.first(where: { $0.shortID == reference || $0.id.uuidString.caseInsensitiveCompare(reference) == .orderedSame }) { decoded[index].objectID = object.id.uuidString }
                    }
                    if efficientExecution {
                        var seen = Set<String>()
                        decoded = decoded.filter { region in
                            guard region.role == "photo" else { return true }
                            guard let id = region.objectID, context.objects.contains(where: { $0.id.uuidString == id && $0.role == "photo" && $0.editable }) else { return false }
                            return seen.insert(id).inserted
                        }
                    }
                    let fitted = Self.fitPlanningRegions(decoded, context: context)
                    if zip(decoded, fitted).contains(where: { $0.x != $1.x }) {
                        adoptedSummary += "区域已由客户端小幅避开书脊，具体位置以regions为准。"
                    }
                    regions = try Self.validatedRegions(fitted, context: context, allowsText: request.canCreateText)
                }
                let sourceRotations = Dictionary(uniqueKeysWithValues: regions.compactMap { region -> (String, Double)? in
                    guard region.role == "photo", let id = region.objectID, let rotation = region.rotation else { return nil }
                    return (id, rotation)
                })
                if efficientExecution, request.action == .relayout {
                    let photos = context.objects.filter { $0.role == "photo" && $0.editable }
                    let occupied = regions.filter { $0.role == "photo" }.reduce(0.0) { total, region in
                        guard let photo = photos.first(where: { $0.id.uuidString == region.objectID }), photo.bounds.width > 0 else { return total }
                        let ratio = photo.bounds.height / photo.bounds.width
                        let width = min(region.width, region.height / ratio)
                        return total + width * width * ratio
                    }
                    if let design = request.design, !photos.isEmpty, occupied < context.size.width * context.size.height * 0.25 {
                        var fallbackContext = context
                        let hero = request.heroID?.uuidString ?? plannedHero ?? regions.filter { $0.role == "photo" }.max { $0.width * $0.height < $1.width * $1.height }?.objectID
                        fallbackContext.objects.sort { ($0.id.uuidString == hero ? 0 : 1) < ($1.id.uuidString == hero ? 0 : 1) }
                        regions = try Self.validatedRegions(design.fallbackRegions(context: fallbackContext, allowsText: request.canCreateText), context: context, allowsText: request.canCreateText)
                        adoptedSummary = "客户端已按\(design.layout.name)修正原规划。以结构化regions为唯一位置依据；原模型说明中的位置和照片尺寸已失效，不按旧位置修复。主照优先保留\(hero ?? "首张照片")，标题在顶部安静文字区，旁注依附对应照片，背景围绕实际照片组连接。整页风格\(design.style.name)。"
                        log("quality", "按所选排版扩大照片区域", "原规划照片过小，使用对应安全构图，保留全部照片与文字区。")
                    }
                    if request.design == nil, (1...4).contains(photos.count), occupied < context.size.width * context.size.height * 0.2 {
                        let w = context.size.width, h = context.size.height
                        regions = photos.enumerated().map { index, photo in
                            let right = index >= 2, lower = index % 2 == 1
                            return DiaryAILayoutRegion(role: "photo", objectID: photo.id.uuidString, x: Double(w * (right ? 0.55 : 0.06)), y: Double(h * (lower ? 0.55 : 0.24)), width: Double(w * 0.36), height: Double(h * 0.30))
                        }
                        if request.canCreateText {
                            regions += [.init(role: "text", x: Double(w * 0.06), y: Double(h * 0.035), width: Double(w * 0.36), height: Double(h * 0.16)), .init(role: "text", x: Double(w * 0.55), y: Double(h * 0.035), width: Double(w * 0.36), height: Double(h * 0.16))]
                        }
                        regions = try Self.validatedRegions(regions, context: context, allowsText: request.canCreateText)
                        log("quality", "照片占比过小，采用本地可读布局", "保留原照片比例与文字区，不发起额外模型请求。")
                    }
                }
                for index in regions.indices {
                    if let id = regions[index].objectID, let rotation = sourceRotations[id] { regions[index].rotation = rotation }
                }
                layoutRegions = regions; composition = adoptedSummary
            } catch {
                if attempt == planningAttempts - 1, efficientExecution, request.action == .relayout {
                    let photos = context.objects.filter { $0.role == "photo" && $0.editable }
                    if let design = request.design, !photos.isEmpty {
                        layoutRegions = try Self.validatedRegions(design.fallbackRegions(context: context, allowsText: request.canCreateText), context: context, allowsText: request.canCreateText)
                        composition = request.designBrief + "采用客户端安全分区，保留所选排版的主次关系，照片等比容纳，背景与文字按这些实际区域制作。"
                        log("quality", "采用所选排版的安全分区", error.localizedDescription)
                        try await persist(); return
                    }
                    if (1...4).contains(photos.count) {
                        let w = Double(context.size.width), h = Double(context.size.height)
                        var safe = photos.enumerated().map { index, photo in
                            DiaryAILayoutRegion(role: "photo", objectID: photo.id.uuidString, x: w * (index >= 2 ? 0.55 : 0.06), y: h * (index % 2 == 1 ? 0.55 : 0.24), width: w * 0.36, height: h * 0.30)
                        }
                        if request.canCreateText {
                            for x in [0.06, 0.55] {
                                safe.append(.init(role: "text", x: w * x, y: h * 0.035, width: w * 0.36, height: h * 0.19))
                                if request.textDensity == "丰富记录" { safe.append(.init(role: "text", x: w * x, y: h * 0.87, width: w * 0.36, height: h * 0.10)) }
                            }
                        }
                        layoutRegions = try Self.validatedRegions(safe, context: context, allowsText: request.canCreateText)
                        composition = "采用客户端校验通过的主次分区；照片保持原比例，文字按主标题、引题、照片旁注与结语占用预留区，实际尺寸由客户端测量摆放。"
                        log("quality", "构图重试后采用安全分区", error.localizedDescription)
                        try await persist(); return
                    }
                }
                guard attempt < planningAttempts - 1 else { throw error }
                planningFeedback = "\n上次构图未通过检查，请修正规划：" + error.localizedDescription
                log("recovery", "正在修正构图区域", error.localizedDescription)
                continue
            }
            log("plan", "整体构图已确定", composition); try await persist()
            return
        }
    }

    private func scheduleVisualRevision(_ raw: [String: Any], scope: DiaryAIVisualRevision) async throws {
        guard let references = (raw["objectIDs"] as? [String]) ?? (raw["objectID"] as? String).map({ [$0] }), !references.isEmpty,
              references.count <= Self.maximumBatchLayers, let reason = raw["reason"] as? String,
              !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw DiaryAIError.invalid("修复需提供本批对象和具体原因，最多两轮") }
        let targets = references.compactMap { reference in objects.first { ($0.shortID == reference || $0.id.uuidString.caseInsensitiveCompare(reference) == .orderedSame) && scope.ids.contains($0.id) }?.id }
        guard targets.count == references.count, Set(targets).count == targets.count else { throw DiaryAIError.invalid("只能修复本批已提交对象，不允许重复或外部对象") }
        if scope.attempt >= 2 {
            log("warning", "仍有视觉问题，需要人工检查", reason)
            try await finishConfirmation()
            error = "局部修复已达两轮，仍有问题：" + reason
            return
        }
        let previousRevision = visualRevision, previousScope = confirmationScope
        visualRevision = .init(ids: targets, reason: reason, attempt: scope.attempt + 1)
        // Keep the complete review scope across a local repair; subsequent whole-page
        // review may discover a different previously committed object.
        awaitingConfirmation = false; confirmationScope = scope
        do { try await persist() } catch {
            visualRevision = previousRevision; confirmationScope = previousScope; awaitingConfirmation = true; throw error
        }
        log("revision", "已安排局部视觉修复", reason)
    }
    private func finishConfirmation() async throws {
        let previousRevision = visualRevision, previousScope = confirmationScope
        awaitingConfirmation = false; visualRevision = nil; confirmationScope = nil
        do { try await persist() } catch {
            visualRevision = previousRevision; confirmationScope = previousScope; awaitingConfirmation = true; throw error
        }
    }
    private func confirmSavedBatch(token: UUID) async throws {
        let scope = confirmationScope
        var tools: Set<String> = ["finish_batch"]
        if scope != nil { tools.insert("request_batch_revision") }
        if let client = model as? DiaryArkResponsesClient {
            client.allowedWorkspaceTools = tools; client.planning = false
            client.requiresBackgroundDesign = efficientExecution && request.background != nil && backgroundRecord?.layerID == nil
            client.allowedLayerReferences = objects.filter { scope?.ids.contains($0.id) == true }.flatMap { [$0.shortID, $0.id.uuidString] }
        }
        let appliedBackgroundRule = backgroundRecord?.layerID != nil ? "背景已生成并加入，不再提出背景设计；检查实际合成结果的背景与前景呼应，不替换真实照片。" : ""
        let qualityRules = efficientExecution ? "这是最终整页验收。检查每张照片是否横倒/倒置，发现时只请求该图层以place_layer旋转纠正，不能保留侧倒的人物、动物或地平线。检查所选排版是否落实：主照是否有尺寸反差、大字主题的标题是否成为重心、旁注是否靠近对应照片、纸刊是否有阅读顺序。文字若猜测未提供的日期/地点/亲属/仪式/行程顺序则修订对应文字，不整页重做。只在具体可见问题时修复，说明对象与证据。只修复主体遮挡、文字不可读、严重碰撞或越界；照片区域是最大容纳范围，不要求铺满，禁止把原始竖照拉成横照。allowsDecorations=false表示不能隐藏已有贴纸，并非禁止摆放已有贴纸；不能要求移除、缩成零或移出画布。贴纸不协调时只要求依附照片组摆放，禁止无法由开放工具实现的修复。保留所有用户原照片，不因场景不统一要求替换原照片；没有替换、删除或拉伸工具。生成新背景时旧背景的图案与文字将被替换，不为旧背景重新移动照片。有限装饰压边允许，不因主观偏好反复修复。标题纸卡、下划线是否使用是视觉选择：只要主题层级、可读性和空间合格，不能仅因与规划中“直接写在纸上”的建议不同而反复要求去纸卡；用户明确要求无纸卡时仍必须遵从。结构化regions是最终位置依据，若文字构图描述与regions冲突，以regions为准，不要求对象回到已失效的文字坐标。通过时只finish_batch。如开启生成背景且尚未生成、也未并行设计，同时在finish_batch给出backgroundBrief（真实照片的共同主题与来源线索）及backgroundPrompt（150至250字纯正向场景底图，绝对位置，按指定视觉语言组织一处主题意象、少量来源呼应与主动留白，不强制写实景深或撕纸，不写照片、人物、贴纸、书页，不复制旧背景）。不合格时只request_batch_revision。" : ""
        let backgroundStyleRules = request.background.map { options in let style = DiaryAIBackgroundStyle.resolve(options.style); return "背景视觉语言：\(style.name)，\(style.brief)。\(style.sceneDirection(options.strength))。这些规则同时约束backgroundBrief与backgroundPrompt。" } ?? ""
        let prompt = request.designBrief + appliedBackgroundRule + qualityRules + backgroundStyleRules + "上一批已提交，当前版本\(version)。\(versionInstruction) 检查图片，有问题且允许时调用request_batch_revision，无问题finish_batch；不直接修改图层。允许工具：\(tools.sorted())。用户要求：\(try DiaryAIDraftController.json(request))。构图：\(composition)。结构化区域：\(try DiaryAIDraftController.json(layoutRegions))。确认范围：\(try DiaryAIDraftController.json(scope))。当前图层：\(try DiaryAIDraftController.json(objects))。"
        var reviewImages: [DiaryAIImage] = []
        if let preview { reviewImages = [.init(id: "confirmed-canvas", caption: "已提交结果", data: try await DiaryAIImageWork.jpeg(preview, quality: 0.8))] }
        if efficientExecution, request.background != nil, backgroundRecord?.layerID == nil, let bridge {
            bridge.allowedBatchIDs = nil
            bridge.excludedRenderIDs = Set(objects.filter { $0.role == "background" }.map(\.id)).union(pending)
            var reviewRequest = request; reviewRequest.selectedOnly = false
            _ = try await bridge.capture(reviewRequest)
            reviewImages = [.init(id: "foreground-review", caption: "实际前景布局，旧背景已移除。背景主题仅从这些照片推导，不引用旧背景图案。", data: try await bridge.originalPreview())]
        }
        let reply = try await timedRequest(prompt: prompt, images: reviewImages, continuation: nil, results: [], token: token)
        guard reply.calls.count == 1, let call = reply.calls.first, tools.contains(call.name),
              let args = try JSONSerialization.jsonObject(with: Data(call.arguments.utf8)) as? [String: Any], args["expectedVersion"] as? Int == version else { throw DiaryAIError.invalid("结果已保存，视觉确认未完成；可继续确认当前版本。") }
        if call.name == "request_batch_revision", let scope { try await scheduleVisualRevision(args, scope: scope) }
        else {
            if efficientExecution, request.background != nil, let brief = args["backgroundBrief"] as? String, let prompt = args["backgroundPrompt"] as? String,
               brief.count <= 1500, let prepared = try? DiarySeedreamBackgroundProvider.preparePrompt(prompt) {
                pendingBackgroundDesign = .init(brief: brief, prompt: prepared)
                log("design", "整页验收复用背景设计", brief + "\n" + prepared)
            }
            try await finishConfirmation()
        }
    }
    private var versionInstruction: String {
        model is DiaryArkResponsesClient ? "版本由客户端注入，不输出expectedVersion。" : "expectedVersion必须为整数\(version)。"
    }
    /// Translate an otherwise valid region out of the spine without resizing or losing identities.
    static func fitPlanningRegions(_ regions: [DiaryAILayoutRegion], context: DiaryAIContext) -> [DiaryAILayoutRegion] {
        guard let spine = context.spineX else { return regions }
        let pages = [(24.0, spine - 24), (spine + 24, Double(context.size.width) - 24)]
        return regions.map { region in
            guard region.x.isFinite, region.width.isFinite, region.width > 0,
                  region.x < spine + 24, region.x + region.width > spine - 24 else { return region }
            let candidates = pages.compactMap { lo, hi -> Double? in
                guard region.width <= hi - lo else { return nil }
                return min(max(region.x, lo), hi - region.width)
            }
            guard let x = candidates.min(by: { abs($0 - region.x) < abs($1 - region.x) }), abs(x - region.x) <= region.width * 0.55 else { return region }
            var fitted = region; fitted.x = x; return fitted
        }
    }
    static func validatedRegions(_ regions: [DiaryAILayoutRegion], context: DiaryAIContext, allowsText: Bool) throws -> [DiaryAILayoutRegion] {
        guard regions.count <= 20 else { throw DiaryAIError.invalid("构图区域过多") }
        var result: [DiaryAILayoutRegion] = []
        for var region in regions {
            if let rotation = region.rotation { guard [-90.0, 0, 90, 180].contains(rotation) else { throw DiaryAIError.invalid("来源照片纠正角度无效") } }
            guard [region.x, region.y, region.width, region.height].allSatisfy(\.isFinite), region.width > 0, region.height > 0,
                  CGRect(origin: .zero, size: context.size).contains(region.bounds), ["photo", "text"].contains(region.role) else { throw DiaryAIError.invalid("构图区域无效或越界") }
            if let spine = context.spineX, region.bounds.minX < spine + 24 && region.bounds.maxX > spine - 24 { throw DiaryAIError.invalid("构图区域跨越书脊，请分配到左右页") }
            if region.role == "photo" {
                guard let object = context.objects.first(where: { ($0.shortID == region.objectID || $0.id.uuidString == region.objectID) && $0.role == "photo" && $0.editable }),
                      !result.contains(where: { $0.objectID == object.id.uuidString }) else { throw DiaryAIError.invalid("照片规划区域必须对应唯一可编辑照片") }
                region.objectID = object.id.uuidString
            } else {
                guard allowsText else { throw DiaryAIError.invalid("未授权文字预留区") }
                region.objectID = nil
            }
            result.append(region)
        }
        // Regions are advisory envelopes. Actual card/photo geometry is resolved by the native tool.
        return result
    }
    static func toolsForBatchStage(base: Set<String>, hasOperations: Bool, committed: Bool) -> Set<String> {
        if committed { return base.intersection(["finish_batch", "request_batch_revision"]) }
        var tools = base
        tools.subtract(["finish_batch", "request_batch_revision"])
        if !hasOperations { tools.subtract(["commit_batch", "rollback_batch", "validate_layout"]) }
        else { tools.subtract(["get_workspace", "get_canvas_image", "list_fonts", "list_frame_styles", "inspect_layers", "validate_layout"]) }
        return tools
    }
    /// Dense contact sheets can hide sideways source pixels. Review full assets once
    /// while background generation runs, before any photo batch is committed.
    private func verifySourceOrientations(token: UUID) async throws {
        guard let bridge else { return }
        let context = try await bridge.capture(request)
        let photos = context.objects.filter { $0.role == "photo" && $0.editable && pending.contains($0.id) }
        var images: [DiaryAIImage] = []
        for offset in stride(from: 0, to: photos.count, by: Self.maximumBatchLayers) {
            images += try await bridge.inspect(.init(contextID: context.id, objectIDs: Array(photos.dropFirst(offset).prefix(Self.maximumBatchLayers).map(\.id)), view: "fullAsset"))
        }
        let client = DiaryArkResponsesClient()
        client.workspaceMode = true; client.productionLog = productionLog
        client.allowedWorkspaceTools = ["report_photo_orientations"]; client.expectedWorkspaceVersion = version
        let reply = try await client.respond(prompt: "逐张检查原照片像素的正立方向，只调用report_photo_orientations，完整返回每张照片objectID和最终绝对angle。正常照片0；侧倒的动物/人物/树木/地平线必须纠正90或-90；倒置180。不要为排版改变方向，不以长宽比判断正立。对象：\(try DiaryAIDraftController.json(photos))", images: images, continuation: nil, results: [])
        try Task.checkCancellation(); guard generation == token else { throw CancellationError() }
        guard reply.calls.count == 1, let call = reply.calls.first, call.name == "report_photo_orientations",
              let raw = try JSONSerialization.jsonObject(with: Data(call.arguments.utf8)) as? [String: Any], let values = raw["rotations"] as? [[String: Any]] else { throw DiaryAIError.invalid("来源照片方向检查未完成") }
        var rotations: [UUID: Double] = [:]
        for value in values {
            guard let reference = value["objectID"] as? String,
                  let photo = photos.first(where: { $0.id.uuidString == reference || $0.shortID == reference }),
                  let angle = value["angle"] as? Double, [-90.0, 0, 90, 180].contains(angle), rotations[photo.id] == nil else { throw DiaryAIError.invalid("来源照片方向结果无效") }
            rotations[photo.id] = angle
        }
        guard rotations.count == photos.count else { throw DiaryAIError.invalid("来源照片方向检查遗漏素材") }
        for i in layoutRegions.indices {
            if let reference = layoutRegions[i].objectID, let photo = photos.first(where: { $0.id.uuidString == reference || $0.shortID == reference }) { layoutRegions[i].rotation = rotations[photo.id] }
        }
        log("quality", "来源照片方向检查完成", "\(photos.count)张原图逐张检查；纠正角度：\(rotations)")
        try await persist()
    }

    private struct BranchProposal {
        let runID: UUID
        let planID: UUID
        let baseVersion: Int
        let operations: [DiaryAIOperation]
    }

    /// Branches own separate clients and immutable inputs. Only this coordinator writes the canvas.
    private func parallelForeground(ids: [UUID], token: UUID) async throws {
        guard let working else { throw CancellationError() }
        let expected = working.document, baseVersion = version, planID = UUID()
        let candidate = DiaryEditorSession(document: expected, images: working.images, store: working.store, contentID: working.contentID)
        candidate.aiTransientSession = true
        let adapter = DiaryEditorAIBridge(candidate)
        adapter.allowedBatchIDs = Set(ids)
        adapter.excludedRenderIDs = Set(pending)
        adapter.layoutRegions = layoutRegions
        adapter.autoFitPhotoRegions = true
        var req = request; req.selectedOnly = false
        let context = try await adapter.capture(req)
        let canvas = try await adapter.originalPreview()
        let assets = try await adapter.inspect(.init(contextID: context.id, objectIDs: ids, view: "fullAsset"))
        let shared = """
        本轮runID=\(token)，planID=\(planID)，基础版本=\(baseVersion)。
        \(req.designBrief)
        共同构图：\(composition)
        用户创作资料：\(req.creationBrief?.modelInstructions ?? "")
        写入地点权限writesLocation=\(req.writesLocation)。\(!req.writesLocation && !req.location.isEmpty ? "严禁在任何文字中出现地点「" + req.location + "」，即便共同构图引用过它，必须改为不带地点的标题与旁注。" : "")
        冻结画布上下文：\(try modelContext(context, text: true))
        规划区域：\(try DiaryAIDraftController.json(layoutRegions))
        只生成本分支操作，不提交画布、不改变共同构图、不修改其他分支对象。
        照片实际边界为保护区；文字区域按数组顺序标识textRegion-0等，是贴纸禁入区。
        保持共同字体、配色、阅读方向。只输出工具调用，客户端原生测量与合并。
        """
        @MainActor @Sendable func propose(text: Bool) async throws -> BranchProposal {
            let started = Date()
            let client = DiaryArkResponsesClient()
            client.workspaceMode = true; client.productionLog = productionLog
            client.expectedWorkspaceVersion = baseVersion
            client.allowedWorkspaceTools = text ? ["create_text"] : ["place_layer"]
            client.allowedLayerReferences = text ? [] : context.objects.filter { ids.contains($0.id) }.flatMap { [$0.shortID, $0.id.uuidString] }
            let direction = text ? """
            文字分支：创建可编辑文字，使用稳定clientObjectKey、textRole和sourceIDs。
            使用规划文字区域，标题4至10字，正文横排每行8至16字，最多两种字体和纸卡。
            遵从用户指定数量与篇幅；适量记录默认1标题及2处有区别的照片旁注。
            仅陈述照片可见细节或用户明确提供事实；禁止推断地点、日期、亲属、季节和行程顺序。禁止风吹、风很大、溪声、声音、温度、气味等照片无法证明的感官事实；看见经幡只能写经幡，不能写经幡被风吹动。
            用户原话完整保留，仅供理解资料不得印出。writesLocation=false时不得写地点。
            标题优先paper=none，正文清楚可读，不通过缩小字号塞满区域。
            """ : """
            贴纸分支：完整摆放本批全部对象\(ids)，只使用place_layer。
            依附共同构图指定照片组或文字区域边缘，承担强调、连接、固定或导读用途。
            以照片边缘或textRegion边缘为锚点计算最终中心；文字区域内部禁止进入。
            保留全部贴纸，不遮照片主体、不越画布或书脊，不排成素材清单。
            保持原素材尺寸比例；只提供最终center、width、angle，不改其他对象。
            """
            var correction = ""
            for attempt in 0..<2 {
                do {
                let reply = try await client.respond(prompt: shared + direction + correction, images: [.init(id: "frozen-canvas", caption: "同一冻结画布", data: canvas)] + (text ? [] : assets), continuation: nil, results: [])
                try Task.checkCancellation()
                guard generation == token else { throw CancellationError() }
                var operations: [DiaryAIOperation] = []
                for original in reply.calls {
                    let call = DiaryAIWorkspaceTools.normalized(original)
                    guard call.name == (text ? "create_text" : "place_layer") else { throw DiaryAIError.invalid("分支工具越权") }
                    guard let raw = try JSONSerialization.jsonObject(with: Data(call.arguments.utf8)) as? [String: Any] else { throw DiaryAIError.invalid("提案参数无效") }
                    if text { try DiaryAIWorkspaceTools.validateTextEvidence(raw, request: req) }
                    guard var operation = try DiaryAIWorkspaceTools.parse(call, version: baseVersion, context: context) else { throw DiaryAIError.invalid("提案操作无效") }
                    guard text ? operation.type == "createText" : operation.objectID.map(ids.contains) == true else { throw DiaryAIError.invalid("分支对象越权") }
                    if text && req.design != nil && req.instruction.isEmpty {
                        let title = operation.textRole == "title"
                        let width = Double(context.size.width)
                        let minimum = width * (title ? 0.045 : 0.016)
                        operation.fontSize = min(max(operation.fontSize ?? minimum, minimum), min(300, width * (title ? 0.068 : 0.026)))
                        let size = operation.fontSize ?? minimum
                        let chars = Double((operation.text ?? "").split(separator: "\n").map(\.count).max() ?? 4)
                        let target = title ? max(size * min(chars, 9), width * 0.32) : max(size * 10, width * 0.24)
                        operation.width = min(max(operation.width ?? 0, target), width * 0.44)
                        if title && raw["paper"] == nil { operation.paper = "none" }
                    }
                    operations.append(operation)
                }
                guard !operations.isEmpty, operations.count <= 30 else { throw DiaryAIError.invalid("提案为空或过多") }
                log("parallel-proposal", text ? "文字提案完成" : "贴纸提案完成", "planID=\(planID)，操作\(operations.count)项，用时\(String(format: "%.2f", Date().timeIntervalSince(started)))秒")
                return .init(runID: token, planID: planID, baseVersion: baseVersion, operations: operations)
                } catch is CancellationError { throw CancellationError() }
                catch {
                    guard attempt == 0 else { throw error }
                    correction = "\n上次本分支提案校验失败：\(error.localizedDescription)。保留共同构图，只重新输出本分支的完整有效操作；不要重复未确认事实。"
                    log("repair", text ? "仅重试文字提案" : "仅重试贴纸提案", error.localizedDescription)
                }
            }
            throw DiaryAIError.invalid("分支提案校验未通过")
        }
        log("parallel", "文字与贴纸并行生成提案", "runID=\(token)，planID=\(planID)，baseVersion=\(baseVersion)；两路使用同一照片画布。")
        let textBranch = Task { @MainActor in try await propose(text: true) }
        let decorationBranch = Task { @MainActor in try await propose(text: false) }
        let text: BranchProposal
        let decoration: BranchProposal
        do {
            (text, decoration) = try await withTaskCancellationHandler {
                try await (textBranch.value, decorationBranch.value)
            } onCancel: {
                textBranch.cancel(); decorationBranch.cancel()
            }
        } catch {
            textBranch.cancel(); decorationBranch.cancel()
            throw error
        }
        try Task.checkCancellation()
        guard generation == token, version == baseVersion, self.working?.document == expected,
              [text, decoration].allSatisfy({ $0.runID == token && $0.planID == planID && $0.baseVersion == baseVersion }) else { throw CancellationError() }
        guard Set(ids).isSubset(of: Set(decoration.operations.compactMap(\.objectID))) else { throw DiaryAIError.invalid("贴纸提案遗漏对象") }
        adapter.excludedRenderIDs = Set(pending).subtracting(ids)
        let draft = try await adapter.propose(.init(schemaVersion: 1, contextID: context.id, baseDigest: context.digest, summary: "合并文字与贴纸提案", operations: text.operations + decoration.operations))
        try Task.checkCancellation()
        guard generation == token, version == baseVersion, self.working?.document == expected else { throw CancellationError() }
        let oldPending = pending, oldTextDone = textDone, oldScope = confirmationScope, oldConfirmation = awaitingConfirmation
        if let backgroundTask { try await backgroundTask.value }
        try Task.checkCancellation()
        guard generation == token, version == baseVersion, self.working?.document == expected else { throw CancellationError() }
        try adapter.apply()
        let oldBackground = backgroundRecord
        if backgroundRecord?.verified == true, backgroundRecord?.layerID == nil, let filename = backgroundRecord?.filename {
            let url = backgroundFile(filename)
            let bytes = try await DiaryAIImageWork.run { try Data(contentsOf: url) }
            guard await candidate.importMaterialBackground(bytes, name: "AI背景") else { throw DiaryAIError.invalid(candidate.errorMessage ?? "背景导入失败") }
            try Task.checkCancellation()
            guard generation == token, version == baseVersion, self.working?.document == expected else { throw CancellationError() }
            backgroundRecord?.layerID = candidate.selectedID
        }
        self.working = candidate
        pending.removeAll { ids.contains($0) }; textDone = true; version += 1
        let created = adapter.objectChoices.filter { expected.layer($0.id) == nil }.map(\.id)
        confirmationScope = .init(ids: Array(Set(ids + created + (oldScope?.ids ?? []))), reason: "", attempt: 0)
        awaitingConfirmation = true
        checkpoints.append(.init(candidate.document, pending: pending))
        do { try await persist() } catch {
            checkpoints.removeLast(); pending = oldPending; textDone = oldTextDone; version = baseVersion
            confirmationScope = oldScope; awaitingConfirmation = oldConfirmation; backgroundRecord = oldBackground
            try await setup(expected)
            throw error
        }
        bridge = DiaryEditorAIBridge(candidate)
        try await refresh()
        if request.background?.saveToAlbum == true, backgroundRecord?.layerID != nil {
            albumTask = Task { [weak self] in await self?.writeBackgroundAlbum(token: token) }
        }
        log("commit", "文字、贴纸与已验证背景统一提交", "版本\(version)；原生测量与几何校验通过，保留最终整页视觉验收。")
    }

    private func batch(ids: [UUID], token: UUID, revision: DiaryAIVisualRevision? = nil) async throws {
        let names = ids.compactMap { id in objects.first { $0.id == id }?.shortID }.joined(separator: "、")
        let count = events.filter { $0.kind == "phase" && $0.title.hasPrefix("第 ") }.count + 1
        log("phase", "第 \(count) 批 · \(ids.isEmpty ? "新增文字" : names)", "本批\(ids.count)个已有图层；逐项操作、统一提交后确认。")
        guard let bridge, let working else { return }
        (model as? DiaryArkResponsesClient)?.planning = false
        (model as? DiaryArkResponsesClient)?.requiresBackgroundDesign = false
        let batchStarted = Date()
        batchExpires = batchStarted.addingTimeInterval(DiaryAIRequestLimits.batchDeadline)
        defer { batchExpires = nil }
        bridge.autoFitPhotoRegions = efficientExecution && request.action == .relayout
        bridge.allowedBatchIDs = Set(ids); bridge.excludedRenderIDs = Set(pending)
        bridge.layoutRegions = revision == nil ? layoutRegions : layoutRegions.filter { region in
            region.role != "photo" || !ids.contains { id in region.objectID == id.uuidString || region.objectID == objects.first(where: { $0.id == id })?.shortID }
        }
        var req = request; req.selectedOnly = false
        if !ids.isEmpty && request.action == .relayout { req.allowsText = false }
        let originalObjectIDs = Set(bridge.objectChoices.map(\.id))
        var context = try await bridge.capture(req)
        context.objects = context.objects.filter { ids.contains($0.id) || (!pending.contains($0.id) && $0.visible) }
        var images = [DiaryAIImage(id: "current-canvas", caption: "最新排版画布：背景＋已完成摆放的对象；未完成照片、贴纸、相框不在画布中。本批素材单独附图。", data: try await bridge.originalPreview())]
        if !hasRetainedVisualContent { images = [] }
        if !ids.isEmpty { images += try await bridge.inspect(.init(contextID: context.id, objectIDs: ids, view: "fullAsset")) }
        var batchTools: Set<String> = ["get_workspace", "get_canvas_image", "list_fonts", "list_frame_styles", "rollback_batch", "commit_batch", "finish_batch"]
        if !ids.isEmpty {
            batchTools.insert("inspect_layers")
            if req.canMove || context.objects.contains(where: { ids.contains($0.id) && $0.role == "text" }) { batchTools.insert("place_layer") }
            if context.objects.contains(where: { ids.contains($0.id) && $0.role == "text" }) { batchTools.insert("update_text") }
            if req.allowsCrop { batchTools.insert("set_photo_crop") }
            if req.allowsFrames { batchTools.insert("set_photo_frame") }
            if req.allowsDecorations { batchTools.insert("set_decoration_visibility") }
        }
        if req.canCreateText && revision == nil { batchTools.insert("create_text") }
        batchTools.insert("request_batch_revision")
        if let client = model as? DiaryArkResponsesClient {
            client.allowedLayerReferences = context.objects.filter { ids.contains($0.id) }.flatMap { [$0.shortID, $0.id.uuidString] }
        }
        var operations: [DiaryAIOperation] = [], continuation: Data?, results: [DiaryAIToolResult] = []
        var committed = false, committedRound: Int?, seen: [String: String] = [:]
        var commitFailed = false
        var inspections = 0
        var missingCallRetries = 0
        var repeatedErrors = 0
        var recoveryPrompt: String?
        var resetContext = false
        var noProgressRounds = 0
        var confirmationIDs = ids
        for round in 0..<(efficientExecution ? (ids.isEmpty ? 5 : 3) : 16) {
            guard Date().timeIntervalSince(batchStarted) < DiaryAIRequestLimits.batchDeadline else { throw DiaryAIError.invalid("本批达到总时限，已提交操作保留。手动重试可能产生新请求和费用。") }
            var offeredTools = Self.toolsForBatchStage(base: batchTools, hasOperations: !operations.isEmpty, committed: committed)
            if !committed && ids.isEmpty && !operations.isEmpty {
                offeredTools = commitFailed ? ["rollback_batch", "create_text"] : ["commit_batch", "create_text", "rollback_batch"]
            }
            if noProgressRounds >= 2 && !committed {
                offeredTools.subtract(["get_workspace", "get_canvas_image", "list_fonts", "list_frame_styles", "inspect_layers"])
            }
            if efficientExecution && !committed {
                offeredTools.subtract(["commit_batch", "finish_batch", "request_batch_revision", "rollback_batch"])
                if !operations.isEmpty { offeredTools = batchTools.subtracting(["commit_batch", "finish_batch", "request_batch_revision", "rollback_batch"]) }
            }
            (model as? DiaryArkResponsesClient)?.allowedWorkspaceTools = offeredTools
            let initialPrompt = """
            \(req.designBrief)
            文字工具附textRole(title/lead/caption/body/closing)及sourceIDs对应照片编号。标题默认直接书写，纸卡用于少量强调或正文承托；正文横排，禁止每行一至三字的细长纸条。照片只能证明可见内容；禁止推断行程先后、风速、声音、季节、亲属关系；祝愿可写，事实须用户明确提供。
            输出约定：只通过工具调用完成操作，不输出正文说明、Markdown、完整排版JSON、operations数组或任何文件。只传工具必填参数和确实要改的字段。客户端负责UUID解析、坐标换算、字体测量、资源和保存，你不需要生成这些数据。图层objectID优先使用本批L编号，版本号从工具返回读取。
            最短流程：新增文字批次先create_text；已有图层批次先place_layer或update_text。然后commit_batch；下一轮查看提交返回图片后finish_batch。必要时先裁剪或调整相框。已有图片、字体和版本足够时不要重复查询；不要输出长篇设计说明。commit_batch失败保留已暂存操作，按错误修订对应图层后再次提交。只有需要清空整批重做才用rollback_batch，清空后必须补齐全部对象。
            你在图层工作台中逐步设计手帐。仅使用工具处理本批对象，不返回完整文件或全页计划。先调用单项图层工具，修改暂存；commit_batch 原子执行并显示画布，返回图片用于确认已执行结果，提交后检查图片，无问题调用finish_batch；有主体遮挡、留白被占等问题调用request_batch_revision指定对象和原因。禁止同轮提交和确认。\(versionInstruction) 当前版本\(version)。提交后版本加1。
            操作权限：\(try DiaryAIDraftController.json(request))。照片默认等比缩放；width 表示当前旋转可见边界的目标宽度，center={x,y} 是设计单位的视觉中心。set_photo_crop 只在授权时使用。create_text 必须有稳定 clientObjectKey；同key再次create_text表示修订暂存文字，可调整位置和文本框，不要用update_text修改尚未提交的新文字。文字不能放在spineX中央，左右各留24设计单位；使用左右页空白区。create_text必须使用目录中的fontID；用户指定字体与纸卡时遵从指定，否则按标题、旁注角色选择目录内字体和承托。主标题用短句与语义换行，正文/旁注与标题形成字号层级；完整词语不能被拆到两行。可用paper选择文字承托，标题优先titleParchment，短注可用warmHeart、blueTape、kraftStrip，心愿可用pinkWish，植物场景botanicalLine；不为所有文字都加纸卡，避免装饰堆积。禁止虚构事实：静态照片不能证明停留时长、声音、具体日期或未提供的地名；地点未提供时不猜测。文字卡片超出规划时先修正位置或精简文案，保留用户默认字体与纸卡，不连续缩字或去掉纸卡。不要移动本批之外的对象。不删除、解锁，不修改背景。单项工具参数未知时调用查询。
            批次类型：\(revision != nil ? "visualRevision" : ids.isEmpty ? "createText（没有已有ID是正常的，必须根据构图和用户要求创作文案）" : "layout")。修复要求：\(revision?.reason ?? "无")。
            结构化构图区域：\(try DiaryAIDraftController.json(layoutRegions))。照片须在所属区域内，文字须在文字区内；按照片宽高比同时计算宽高，可用maxHeight限制旋转换框后的高度。
            本批ID：\(ids.map(\.uuidString))。待排ID：\(pending.map(\.uuidString))。
            全局构图：\(composition)。本批定位不能把所有照片缩小到页面中心，要形成主次、留白和阅读顺序。
            place_layer 的 width 是换框、旋转后的最终可见包围盒宽度，center 是最终可见中心；客户端先完成裁剪与相框再统一定位，无需重复补偿相框尺寸。
            贴纸应贴近有语义关联的照片边缘或文字，避开人脸、建筑主体、文字和重要物体；不把相机、邮票等排成孤立的素材清单。优先装饰照片外缘空白，不以覆盖主体来填空。左右页须有连贯的阅读路径；底部大块留白要对应预留标题、旁注或明确的呼吸区，不把全部元素挤到上半页。
            已授权新增文字时，本批照片保持文字预留区；文字阶段必须实际创建可编辑文字，不能仅在说明中声称完成。
            页面及每个图层详细数据（只读输入，绝不复述或原样输出）：\(try DiaryAIDraftController.json(context))
            不能把素材编号、透明底板写入作品。先提交本批后再看最新整页图。需要新增文字且本批为空时只创建文字。已有文字按权限保留正文。
            """
            let rebuilding = resetContext || round == 0
            let state = "当前版本\(version)，已提交=\(committed)；允许工具：\(offeredTools.sorted())。暂存操作（修订时复用clientObjectKey）：\(try DiaryAIDraftController.json(operations))。待确认对象：\(confirmationIDs)。"
            var prompt: String? = rebuilding ? initialPrompt + "\n" + state : recoveryPrompt
            if efficientExecution {
                let writing = ids.isEmpty || ids.contains { id in objects.first { $0.id == id }?.role == "text" }
                let stageRules = writing ? "文字用textRole和sourceIDs绑定角色与照片。主标题4至10字，1至2行，不强制换行，优先paper=none；正文横排每行约8至16字，标题字号约正文2倍。同页最多两种字体、两种纸卡，墨色对比清楚。禁止依据照片推断日期地点、先后行程、季节、风速、声音、仪式和亲属关系；不能将不同照片中的人编成同一家，姐姐弟弟爸爸妈妈等称谓须用户明确提供；可描述可见物或明确祝愿。writesLocation=false不写地点。用户提供creationBrief时：围绕用户主题，至少一处旁注结合对应照片的可见细节或用户逐图说明，不把故事原文逐条变成标签，不重复风、脚步、收藏此刻等通用句。原话必须完整原样使用；仅供理解的资料禁止直接印出。适量记录使用1标题、2处有区分的照片旁注，空间允许再加1句结语。用户指定数量、文字形式与篇幅优先；否则简短补充1标题1旁注，丰富记录按空间3至5项（总照片不超过2张时2至3项，角色为标题、引题、对应照片旁注、结语），不重复抒情；空间不足减角色，不缩成细字。" : "本批只摆放已有素材，不创建文字。先检查原照片内容方向，明显横倒或倒置时以place_layer的angle=90/-90/180纠正；正常竖照不能因版面而横倒。照片等比容纳所属region，保持主照与辅助组的尺寸反差；允许在范围内错落，不拉伸。不移动本批以外对象。贴纸承担强调、连接或固定作用，依附照片组边缘，不遮人脸和正文，不把贴纸独立排成清单。"
                prompt = req.executionDesignBrief + stageRules + "只调用开放的工具，一次返回本批必要操作；客户端自动测量、校验和提交，不调用commit/finish，不返回文件或操作JSON数组。width是旋转换框后的可见宽度，center={x,y}为设计单位中心。create_text以稳定clientObjectKey修订；文字和纸卡必须避开中缝。保留全部照片、锁定内容和用户指定样式。" +
                    "构图：\(composition)。区域：\(try DiaryAIDraftController.json(layoutRegions))。本批：\(ids)。修复：\(revision?.reason ?? "无")。权限与用户要求：\(try Self.executionPermissions(req))。上下文：\(try modelContext(context, text: writing))。已暂存：\(try DiaryAIDraftController.json(operations))。最近错误：\(recoveryPrompt ?? results.map(\.text).joined(separator: "\n"))"
                continuation = nil; results = []
            }
            if rebuilding, let recoveryPrompt { prompt! += "\n最近反馈：" + recoveryPrompt }
            if resetContext {
                // A new conversation must not contain orphan function_call_output records.
                prompt! += "\n最近工具结果：" + results.map(\.text).joined(separator: "\n")
                continuation = nil; results = []
            }
            recoveryPrompt = nil; resetContext = false
            var recoveryImages = images
            if committed, let preview { recoveryImages = [.init(id: "confirmed-canvas", caption: "最新已提交画布", data: try await DiaryAIImageWork.jpeg(preview))] }
            var reply = try await timedRequest(prompt: prompt, images: (rebuilding || efficientExecution) ? recoveryImages : [], continuation: continuation, results: results, token: token)
            if efficientExecution && reply.calls.contains(where: { DiaryAIWorkspaceTools.operationNames[$0.name] != nil }) {
                log("client", "客户端自动提交本批", "已完整接收工具参数；不额外调用模型决定提交。")
                let args = try DiaryAIDraftController.json(["expectedVersion": version])
                reply.calls.append(.init(id: "auto-" + UUID().uuidString, name: "commit_batch", arguments: args))
                offeredTools.insert("commit_batch")
            }
            continuation = reply.continuation; results = []
            if reply.calls.isEmpty {
                guard missingCallRetries < 2 else { throw DiaryAIError.invalid(committed ? "本批已保存，模型未完成结果确认；请检查画布后继续。" : "模型未完成必要操作，当前批次未提交，已完成批次保留。") }
                missingCallRetries += 1
                let next = committed ? "已提交并附上最新画布，当前版本\(version)，检查后通过finish_batch，有问题且允许时request_batch_revision。" : operations.isEmpty ? "尚未暂存操作；新增文字请先create_text，已有图层请先place_layer/update_text。禁止finish_batch。" : "已有\(operations.count)项暂存操作，请调用commit_batch。禁止finish_batch。"
                recoveryPrompt = "请继续完成本批，必须调用当前允许的工具，不要回复说明文字。" + next
                resetContext = true; noProgressRounds += 1
                log("recovery", "正在纠正模型调用顺序", next)
                continue
            }
            var madeProgress = false
            var automaticInputFailed = false
            for originalCall in reply.calls {
                let call = DiaryAIWorkspaceTools.normalized(originalCall)
                if let previous = seen[call.id] {
                    guard previous == call.arguments else { throw DiaryAIError.invalid("重复工具调用内容冲突") }
                    results.append(.init(callID: call.id, text: "此前调用已执行；不要重复提交。")); continue
                }
                seen[call.id] = call.arguments
                log("tool", "调用 \(call.name)", call.arguments)
                do {
                    guard offeredTools.contains(call.name) else { throw DiaryAIError.invalid("工具不属于当前阶段；本批类型：\(ids.isEmpty ? "新增文字，请create_text" : "已有图层")；允许：\(offeredTools.sorted().joined(separator: ","))") }
                    if committed && !["finish_batch", "request_batch_revision"].contains(call.name) { throw DiaryAIError.invalid("本批已提交，当前版本\(version)；下一轮检查图片，通过finish_batch，有问题且允许时request_batch_revision，不要直接移动或回滚。") }
                    guard let raw = try JSONSerialization.jsonObject(with: Data(call.arguments.utf8)) as? [String: Any] else { throw DiaryAIError.invalid("参数必须为JSON对象") }
                    guard raw["expectedVersion"] != nil else { throw DiaryAIError.invalid("缺少expectedVersion字段") }
                    guard raw["expectedVersion"] is NSNumber, !(raw["expectedVersion"] is String) else { throw DiaryAIError.invalid("expectedVersion类型错误：必须是整数\(version)，不能是字符串") }
                    guard raw["expectedVersion"] as? Int == version else { throw DiaryAIError.invalid("版本不匹配，当前版本 \(version)") }
                    for key in ["width", "maxHeight", "angle", "fontSize"] where raw[key] != nil { guard raw[key] is NSNumber else { throw DiaryAIError.invalid("\(key)必须是数字，不能是字符串") } }
                    if let center = raw["center"] { guard let point = center as? [String: Any], point["x"] is NSNumber, point["y"] is NSNumber else { throw DiaryAIError.invalid("center必须是包含数字x、y的对象，不能是JSON字符串") } }
                    var text = "", feedback: [DiaryAIImage] = []
                    if ["create_text", "update_text"].contains(call.name) { try DiaryAIWorkspaceTools.validateTextEvidence(raw, request: req) }
                    if var operation = try DiaryAIWorkspaceTools.parse(call, version: version, context: context) {
                        guard !committed, operations.count < 30 else { throw DiaryAIError.invalid("本批已提交或操作数过多") }
                        if operation.type != "createText" { guard let id = operation.objectID, ids.contains(id) else { throw DiaryAIError.invalid("只能处理本批对象") } }
                        if req.design != nil, req.instruction.isEmpty, operation.type == "updateText",
                           let reason = revision?.reason, ["对比不足", "对比度", "不可读", "几乎同明度"].contains(where: reason.contains),
                           operation.paper == nil || operation.paper == "none" {
                            operation.paper = "note"
                            log("quality", "为低对比文字增加浅色承托", "仅修复本批文字，保持字号、内容与位置意图；原生测量会重新避让照片。")
                        }
                        if efficientExecution && revision == nil && req.action == .relayout && req.instruction.isEmpty,
                           operation.type == "setPlacement", let id = operation.objectID,
                           context.objects.first(where: { $0.id == id })?.role == "photo",
                           let rotation = layoutRegions.first(where: { $0.role == "photo" && ($0.objectID == id.uuidString || $0.objectID == context.objects.first(where: { $0.id == id })?.shortID) })?.rotation {
                            operation.angle = rotation
                            log("quality", "采用已规划的来源照片方向", "按原始像素内容判断纠正角度，不因容纳区域形状横倒照片；最终验收仍可修复。")
                        }
                        if efficientExecution && operation.type == "createText" && req.instruction.isEmpty {
                            if req.design != nil {
                                let role = raw["textRole"] as? String ?? ((operation.clientObjectKey ?? "").lowercased().contains("title") ? "title" : "caption")
                                let w = Double(context.size.width)
                                let title = role == "title"
                                let minSize = w * (title ? 0.045 : 0.016)
                                let maxSize = min(300, w * (title ? 0.068 : 0.026))
                                operation.fontSize = min(max(operation.fontSize ?? minSize, minSize), maxSize)
                                let size = operation.fontSize ?? minSize
                                let chars = Double((operation.text ?? "").split(separator: "\n").map(\.count).max() ?? 4)
                                let targetWidth = title ? max(size * min(chars, 9), w * 0.32) : max(size * 10, w * 0.24)
                                operation.width = min(max(operation.width ?? 0, targetWidth), w * 0.44)
                                if title && raw["paper"] == nil { operation.paper = "none" }
                            } else {
                                operation.fontSize = max(operation.fontSize ?? 72, min(72, max(12, ceil(Double(context.size.width) * 0.014))))
                                if req.textDensity == "丰富记录" {
                                    operation.fontSize = min(operation.fontSize ?? 72, max(72, Double(context.size.width) * 0.04))
                                    operation.width = min(max(operation.width ?? 0, (operation.fontSize ?? 72) * 8), Double(context.size.width) * 0.36)
                                }
                                if operation.paper == "none" { operation.paper = "blueTape" }
                            }
                        }
                        if operation.type == "setPlacement", let id = operation.objectID,
                           let region = layoutRegions.first(where: { $0.role == "photo" && $0.objectID == id.uuidString }) {
                            operation.maxHeight = min(operation.maxHeight ?? region.height, region.height)
                            if req.design != nil {
                                operation.width = min(max(operation.width ?? region.width, region.width * 0.72), region.width)
                                operation.maxHeight = region.height
                            }
                        }
                        if req.design != nil, operation.type == "setPlacement", let id = operation.objectID,
                           let object = context.objects.first(where: { $0.id == id }), object.role == "decoration",
                           var center = operation.center, let width = operation.width, object.bounds.width > 0 {
                            let height = width * object.bounds.height / object.bounds.width
                            if width <= context.size.width, height <= context.size.height {
                                center.x = min(max(center.x, CGFloat(width / 2 + 1)), context.size.width - CGFloat(width / 2 + 1))
                                center.y = min(max(center.y, CGFloat(height / 2 + 1)), context.size.height - CGFloat(height / 2 + 1))
                                operation.center = center
                            }
                        }
                        if let index = operations.firstIndex(where: { $0.type == operation.type && (($0.objectID != nil && $0.objectID == operation.objectID) || ($0.clientObjectKey != nil && $0.clientObjectKey == operation.clientObjectKey)) }) {
                            let old = operations[index]
                            if operation.type == "setPlacement", let previous = old.scale, let next = operation.scale, next < previous * 0.5 {
                                throw DiaryAIError.invalid("同一图层已暂存摆放，本次缩小超过一半，可能混淆图层。请核对编号；确需重设时rollback_batch后明确重新排版本批。")
                            }
                            operations[index] = operation
                            log("revision", "修订已暂存图层", "同一图层的同类操作已替换，不重复执行。")
                        } else { operations.append(operation) }
                        commitFailed = false; madeProgress = true; repeatedErrors = 0; missingCallRetries = 0
                        text = "操作已暂存（\(operations.count)项），当前版本\(version)。下一步：完成本批必要操作后立即commit_batch；不要重复查询；如需修订文字，使用同clientObjectKey替换暂存内容。"
                    } else {
                        switch call.name {
                        case "get_workspace": text = state + "\n" + initialPrompt
                        case "list_fonts": text = try DiaryAIDraftController.json(context.fonts)
                        case "list_frame_styles": text = context.frameStyles.joined(separator: "、")
                        case "inspect_layers":
                            guard inspections < 2 else { throw DiaryAIError.invalid("本批补图次数已用完") }; inspections += 1
                            guard let values = raw["objectIDs"] as? [String] else { throw DiaryAIError.invalid("缺少对象ID") }
                            let wanted = values.compactMap { reference in context.objects.first { $0.shortID == reference || $0.id.uuidString.caseInsensitiveCompare(reference) == .orderedSame }?.id }; guard wanted.count <= Self.maximumBatchLayers && wanted.allSatisfy(ids.contains) else { throw DiaryAIError.invalid("补图超出本批范围") }
                            feedback = try await bridge.inspect(.init(contextID: context.id, objectIDs: wanted, view: "fullAsset")); text = "素材图片已附"
                        case "get_canvas_image":
                            let bytes: Data
                            if committed, let preview { bytes = try await DiaryAIImageWork.jpeg(preview) }
                            else { bytes = try await bridge.originalPreview() }
                            feedback = [.init(id: "canvas-v\(version)", caption: "当前已提交画布", data: bytes)]; text = "当前画布"
                        case "rollback_batch": guard !committed else { throw DiaryAIError.invalid("已提交批次需用户回退") }; operations = []; commitFailed = false; text = ids.isEmpty ? "已清空本批新增文字；请按原文字计划重新创建，复用原clientObjectKey。" : "已清空本批全部未提交操作（不只失败的一项）。必须重新摆放全部对象：\(ids.compactMap { id in context.objects.first { $0.id == id }?.shortID }.joined(separator: "、"))，全部暂存后才能commit_batch。"
                        case "commit_batch":
                            guard !efficientExecution || !automaticInputFailed else { throw DiaryAIError.invalid("本轮有操作参数无效，未自动提交；先修正失败操作") }
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
                            let previousScope = confirmationScope
                            confirmationIDs = ids + bridge.objectChoices.filter { !originalObjectIDs.contains($0.id) && $0.role == "text" }.map(\.id)
                            confirmationScope = .init(ids: efficientExecution ? Array(Set(confirmationIDs + (previousScope?.ids ?? []))) : confirmationIDs, reason: revision?.reason ?? "", attempt: revision?.attempt ?? 0)
                            checkpoints.append(.init(working.document, pending: pending)); version += 1; awaitingConfirmation = true
                            do { try await persist() } catch {
                                checkpoints.removeLast(); pending = previous; textDone = previousTextDone; version -= 1
                                confirmationScope = previousScope; awaitingConfirmation = false
                                if let last = checkpoints.last { try await setup(last.restoredDocument) }
                                throw error
                            }
                            committed = true; committedRound = round; preview = UIImage(data: draft.preview); objects = bridge.objectChoices
                            updateDisplaySession()
                            madeProgress = true; repeatedErrors = 0; missingCallRetries = 0
                            (model as? DiaryArkResponsesClient)?.allowedLayerReferences = objects.filter { confirmationIDs.contains($0.id) }.flatMap { [$0.shortID, $0.id.uuidString] }
                            feedback = [.init(id: "canvas-v\(version)", caption: "本批已提交，检查主体遮挡和文字留白；通过finish_batch，有问题request_batch_revision", data: draft.preview)]
                            text = "提交成功，版本 \(version)。\(draft.summary)；\(draft.warnings.joined(separator: "；"))。实际位置：\(objects.filter { confirmationIDs.contains($0.id) }.map { "\($0.shortID)中心\($0.center)，可见宽高\($0.bounds.size)" }.joined(separator: "；"))。对照规划检查贴纸是否依附对应照片，禁止把贴纸排成左上素材清单；检查文字换行与下方留白用途。"
                        case "validate_layout": text = committed ? "本批已通过原生文档和几何校验，请结合图片检查效果。" : "请先 commit_batch，失败会返回具体校验错误。"
                        case "request_batch_revision":
                            guard committed, let committedRound, round > committedRound else { throw DiaryAIError.invalid("修复须在提交后的下一轮看图后请求") }
                            try await scheduleVisualRevision(raw, scope: .init(ids: confirmationIDs, reason: revision?.reason ?? "", attempt: revision?.attempt ?? 0))
                            return
                        case "finish_batch":
                            guard committed, let committedRound, round > committedRound else { throw DiaryAIError.invalid(committed ? "本批已提交；下一轮查看返回图片后确认或请求修复，版本\(version)" : operations.isEmpty ? "尚未创建或修改图层；请先create_text或place_layer，再commit_batch" : "已有暂存操作，请先commit_batch；下一轮看图后再finish_batch") }
                            try await finishConfirmation()
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
                        resetContext = true
                        recoveryPrompt = "当前版本\(version)，已提交=\(committed)。只处理本批ID：\(ids)。\(committed ? "检查最新图片；通过finish_batch，有问题且允许时request_batch_revision。" : "参数用原生数字与对象，仅提交本批必要操作。") 最近错误：\(error.localizedDescription)"
                        repeatedErrors = 0
                    }
                    if efficientExecution && call.name != "commit_batch" { automaticInputFailed = true }
                    if call.name == "commit_batch" { commitFailed = true }; log("error", "\(call.name) 未执行", error.localizedDescription); results.append(.init(callID: call.id, text: "ERROR: \(error.localizedDescription)。请修复参数。")) }
            }
            if efficientExecution && committed {
                log("batch", "本批已自动提交，整页统一验收", "版本\(version)，最新画布将作为下一批输入；保留最终视觉检查。")
                visualRevision = nil
                try await persist()
                return
            }
            noProgressRounds = madeProgress ? 0 : noProgressRounds + 1
            if noProgressRounds >= 2 { resetContext = true }
            if noProgressRounds >= 5 { throw DiaryAIError.invalid("连续纠错仍未推进，已提交内容保留；可从当前阶段继续，或恢复排版前版本。") }
        }
        throw DiaryAIError.invalid(committed ? "本批已保存，但视觉确认未完成；请检查画布后继续。" : "本批达到调用上限，已提交内容保留；可从当前阶段继续，或恢复排版前版本。")
    }
}
