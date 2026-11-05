import SwiftUI
import Combine
import PhotosUI
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

nonisolated struct DiaryCreationPhoto: Codable, Identifiable {
    var id = UUID()
    var filename: String
    var digest: String
    var name: String
}
nonisolated struct DiaryCreationSticker: Codable, Identifiable {
    var item: CloudMaterial
    var filename: String
    var kept: Bool
    var id: String { item.id }
}
nonisolated struct DiaryCreationDraft: Codable {
    var schema = 1
    var id = UUID()
    var owner: String
    var documentID: UUID
    var baseline: String
    var photos: [DiaryCreationPhoto] = []
    var stickers: [DiaryCreationSticker] = []
    var heroID: UUID?
    var photoNotes: [String: String]? = nil
    var request: DiaryAIRequest
    var story = ""
    var step = 0
    var didDraw = false
    var seed = UInt64.random(in: 1...UInt64.max)
    var batch = 0
    var excluded: Set<String> = []
    var history: [[String]] = []
    var theme = "全部"
    var submitted = false
}

@MainActor final class DiaryAICreationFlow: ObservableObject, Identifiable {
    var id: UUID { draft.id }
    let directory: URL
    @Published var draft: DiaryCreationDraft
    @Published var images: [String: UIImage] = [:]
    @Published var candidates: [CloudMaterial] = []
    @Published var personalItems: [PersonalSticker] = []
    @Published var personalCursor: Int?
    @Published var loadingPersonal = false
    @Published var busy = false
    @Published private(set) var isSubmitting = false
    @Published private(set) var pendingStickerIDs: Set<String> = []
    @Published private(set) var stickerLoadFailed = false
    var selectedStickerCount: Int { draft.stickers.count + pendingStickerIDs.count }
    @Published private(set) var pendingPhotoIDs: [UUID] = []
    typealias PhotoLoader = @MainActor () async throws -> Data
    private var photoTask: Task<Void, Never>?
    private var photoGeneration = UUID()
    private var failedPhotoLoads: [UUID: PhotoLoader] = [:]
    var selectedPhotoCount: Int { draft.photos.count + pendingPhotoIDs.count }

    @Published var loadingCatalog = false
    @Published var error: String?
    @Published var saveError: String?
    @Published var status = ""
    @Published var failures: [UUID: String] = [:]
    @Published var undoAvailable = false
    private var failedItems: [UUID: PhotosPickerItem] = [:]
    private var failedProviders: [UUID: NSItemProvider] = [:]
    private var undo: DiaryCreationDraft?
    private var operation = UUID()
    private var job: Task<Void, Never>?
    private var catalogJob: Task<Void, Never>?
    private var catalogOperation = UUID()
    private var catalogCursor: String?
    @Published var hasMoreCatalog = false
    private let session: DiaryEditorSession
    private var preparationTask: Task<Void, Never>?
    private var preparationGeneration = UUID()
    private var preparedMaterials: [String: DiaryCreationPreparedMaterial] = [:]
    @Published private(set) var preparationFailures: [String: String] = [:]
    @Published private(set) var preparedCount = 0
    @Published private(set) var preparingMaterials = false
    private(set) var preparationBuildCount = 0
    private var preparationSuspended = false

    var canContinue: Bool { !isSubmitting && selectedPhotoCount > 0 && saveError == nil }
    var allKept: Bool { !draft.stickers.isEmpty && draft.stickers.allSatisfy(\.kept) }
    var design: DiaryAIDesignSelection { draft.request.design ?? .init() }
    var ownerValid: Bool { MaterialCatalogRepository.shared.owner == draft.owner }
    var photoPreviews: [UIImage] {
        var photos = draft.photos
        if let index = photos.firstIndex(where: { $0.id == draft.heroID }), design.layout == .hero { photos.insert(photos.remove(at: index), at: 0) }
        return photos.compactMap { images[$0.filename] }
    }
    var hasDraft: Bool { !draft.photos.isEmpty && !draft.submitted }

    init(session: DiaryEditorSession) throws {
        self.session = session
        let key = SHA256.hash(data: Data((session.store.ownerID + ":" + session.document.id.uuidString).utf8)).map { String(format: "%02x", $0) }.joined()
        directory = StoragePaths.system.support.appendingPathComponent("DiaryCreationDrafts/" + key, isDirectory: true)
        let url = directory.appendingPathComponent("draft.json")
        if FileManager.default.fileExists(atPath: url.path) {
            draft = try JSONDecoder().decode(DiaryCreationDraft.self, from: Data(contentsOf: url))
            guard draft.schema == 1, draft.owner == session.store.ownerID, draft.documentID == session.document.id else { throw DiaryAIError.invalid("制作草稿版本或账号不匹配") }
        } else {
            var request = session.canvasAI.form(.relayout)
            if request.design == nil { request.design = .init() }
            draft = .init(owner: session.store.ownerID, documentID: session.document.id,
                          baseline: try DiaryEditorAIBridge.digest(session.document), request: request)
        }
        if draft.submitted && session.aiWorkspace.objects.isEmpty {
            draft = .init(owner: session.store.ownerID, documentID: session.document.id,
                          baseline: try DiaryEditorAIBridge.digest(session.document), request: session.canvasAI.form(.relayout))
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for file in draft.photos.map(\.filename) + draft.stickers.map(\.filename) {
            if let data = try? Data(contentsOf: directory.appendingPathComponent(file)), let image = Self.thumbnail(data) { images[file] = image }
            else { error = "部分草稿素材缺失，请删除后重新添加。" }
        }
    }
    nonisolated static func thumbnail(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 480] as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }
    @discardableResult func save() -> Bool {
        do {
            try JSONEncoder().encode(draft).write(to: directory.appendingPathComponent("draft.json"), options: .atomic)
            saveError = nil
            if !busy && pendingPhotoIDs.isEmpty {
                let used = Set(draft.photos.map(\.filename) + draft.stickers.map(\.filename) + (undo?.stickers.map(\.filename) ?? []))
                for file in (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [] where ["photo", "sticker"].contains(file.pathExtension) && !used.contains(file.lastPathComponent) {
                    try? FileManager.default.removeItem(at: file)
                }
            }
            schedulePreparation()
            return true
        } catch { saveError = "草稿保存失败：" + error.localizedDescription; return false }
    }
    func cancelOperation() {
        photoGeneration = UUID(); photoTask?.cancel(); photoTask = nil; pendingPhotoIDs = []
        preparationSuspended = true
        preparationGeneration = UUID(); preparationTask?.cancel(); preparationTask = nil
        preparingMaterials = false
        operation = UUID(); job?.cancel(); job = nil; busy = false; pendingStickerIDs = []; stickerLoadFailed = false
        catalogOperation = UUID(); catalogJob?.cancel(); catalogJob = nil; loadingCatalog = false
        _ = save()
    }
    func discardDraft() {
        cancelOperation()
        draft = .init(owner: session.store.ownerID, documentID: session.document.id,
                      baseline: (try? DiaryEditorAIBridge.digest(session.document)) ?? draft.baseline,
                      request: draft.request)
        preparedMaterials = [:]; preparationFailures = [:]; preparedCount = 0
        images = [:]; undo = nil; undoAvailable = false; failures = [:]; failedItems = [:]; failedProviders = [:]; failedPhotoLoads = [:]
        save()
    }
    func resumePreparation() { preparationSuspended = false; schedulePreparation() }
    func setStep(_ step: Int) { draft.step = step; resumePreparation(); save() }
    func setDesign(_ value: DiaryAIDesignSelection) { draft.request.design = value; save() }
    func setStory(_ value: String) { draft.story = value; save() }
    func setTheme(_ value: String) { draft.theme = value; save() }
    func setHero(_ id: UUID) { draft.heroID = id; save() }
    func setPhotoNote(_ id: UUID, value: String) {
        if draft.photoNotes == nil { draft.photoNotes = [:] }
        draft.photoNotes?[id.uuidString] = value; save()
    }
    func removePhoto(_ id: UUID) {
        guard !isSubmitting else { return }
        pendingPhotoIDs.removeAll { $0 == id }
        draft.photos.removeAll { $0.id == id }; draft.photoNotes?[id.uuidString] = nil
        if draft.heroID == id {
            draft.heroID = draft.photos.first?.id
            if draft.heroID != nil { UIAccessibility.post(notification: .announcement, argument: "已将第一张照片设为主照") }
        }
        save()
    }
    func movePhoto(_ id: UUID, offset: Int) {
        guard !isSubmitting, let i = draft.photos.firstIndex(where: { $0.id == id }), draft.photos.indices.contains(i + offset) else { return }
        draft.photos.swapAt(i, i + offset); save()
    }
    func movePhoto(_ id: UUID, before target: UUID) {
        guard !isSubmitting, id != target, let i = draft.photos.firstIndex(where: { $0.id == id }), let j = draft.photos.firstIndex(where: { $0.id == target }) else { return }
        let value = draft.photos.remove(at: i); draft.photos.insert(value, at: j - (i < j ? 1 : 0)); save()
    }
    func removeFailure(_ id: UUID) {
        failures[id] = nil; failedItems[id] = nil; failedProviders[id] = nil; failedPhotoLoads[id] = nil
    }
    func retryFailure(_ id: UUID) {
        guard !isSubmitting, let loader = failedPhotoLoads[id] else { return }
        removeFailure(id); enqueuePhotoLoads([loader])
    }
    /// Register selections synchronously; reading bytes never locks navigation or editing.
    func enqueuePhotoLoads(_ loaders: [PhotoLoader]) {
        guard !isSubmitting, ownerValid else { return }
        let selected = loaders.prefix(max(0, 30 - selectedPhotoCount)).map { (UUID(), $0) }
        guard !selected.isEmpty else { return }
        pendingPhotoIDs += selected.map { $0.0 }
        let generation = photoGeneration, previous = photoTask
        photoTask = Task {
            await previous?.value
            for (id, load) in selected {
                guard !Task.isCancelled, photoGeneration == generation, ownerValid else { return }
                guard pendingPhotoIDs.contains(id) else { continue }
                do {
                    let data = try await load()
                    guard !Task.isCancelled, photoGeneration == generation, ownerValid, pendingPhotoIDs.contains(id) else { continue }
                    try await appendPhoto(data, selectionID: id)
                } catch {
                    guard !Task.isCancelled, photoGeneration == generation, ownerValid else { return }
                    if pendingPhotoIDs.contains(id) { failures[id] = "照片读取失败，请重试或移除"; failedPhotoLoads[id] = load }
                }
                guard photoGeneration == generation else { return }
                pendingPhotoIDs.removeAll { $0 == id }
                save()
            }
        }
    }
    func importProviders(_ providers: [NSItemProvider]) {
        enqueuePhotoLoads(providers.map { provider in
            {
                guard let type = provider.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .image) == true }) else { throw DiaryEditorError.invalidImage }
                return try await withCheckedThrowingContinuation { continuation in
                    provider.loadDataRepresentation(forTypeIdentifier: type) { data, error in
                        if let data { continuation.resume(returning: data) }
                        else { continuation.resume(throwing: error ?? DiaryEditorError.invalidImage) }
                    }
                }
            }
        })
    }
    func importPhotos(_ items: [PhotosPickerItem]) {
        enqueuePhotoLoads(items.map { item in
            {
                guard let data = try await item.loadTransferable(type: Data.self) else { throw DiaryEditorError.invalidImage }
                return data
            }
        })
    }
    func importCamera(_ data: [Data]) async {
        enqueuePhotoLoads(data.map { bytes in { bytes } })
        await photoTask?.value
    }
    private func appendPhoto(_ data: Data, selectionID: UUID) async throws {
        let prepared = try await DiaryAIImageWork.run { () -> (String, UIImage) in
            guard let image = Self.thumbnail(data) else { throw DiaryEditorError.invalidImage }
            return (SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), image)
        }
        try Task.checkCancellation()
        guard ownerValid, pendingPhotoIDs.contains(selectionID) else { throw CancellationError() }
        guard !draft.photos.contains(where: { $0.digest == prepared.0 }), draft.photos.count < 30 else { return }
        let file = prepared.0 + ".photo"
        let url = directory.appendingPathComponent(file)
        try await DiaryAIImageWork.run { try data.write(to: url, options: .atomic) }
        guard ownerValid, pendingPhotoIDs.contains(selectionID) else { throw CancellationError() }
        let photo = DiaryCreationPhoto(id: selectionID, filename: file, digest: prepared.0, name: "照片")
        draft.photos.append(photo); images[file] = prepared.1
        if draft.heroID == nil { draft.heroID = photo.id }
        save()
    }
    func loadCatalog(more: Bool = false) {
        guard !loadingCatalog, more || candidates.isEmpty else { return }
        loadingCatalog = true; error = nil
        let owner = draft.owner
        let stamp = UUID(); catalogOperation = stamp
        catalogJob = Task {
            defer { if catalogOperation == stamp { loadingCatalog = false } }
            do {
                var values: [CloudMaterial] = []
                var cursor: String? = more ? catalogCursor : nil
                var visited = Set<String>()
                repeat {
                    var params = ["schema": "2", "type": "sticker", "limit": "100"]
                    params["cursor"] = cursor
                    let page: MaterialListPage<CloudMaterial> = try await MaterialCatalogRepository.shared.request(MaterialRoutes.path("items/", params))
                    try Task.checkCancellation()
                    guard MaterialCatalogRepository.shared.owner == owner else { throw CancellationError() }
                    values += page.items; cursor = page.next_cursor
                    if let cursor, !visited.insert(cursor).inserted { break }
                } while cursor != nil && values.count < 500
                guard catalogOperation == stamp else { return }
                catalogCursor = cursor; hasMoreCatalog = cursor != nil
                var seen = Set<String>()
                candidates = (more ? candidates + values : values).filter { $0.availability != "unavailable" && $0.revision > 0 && seen.insert($0.id).inserted }
                if !draft.didDraw { draw() }
            } catch {
                if !Task.isCancelled, catalogOperation == stamp { self.error = "贴纸目录暂不可用，可以重试或不用贴纸继续。" }
            }
        }
    }
    var themes: [String] {
        ["全部"] + ["旅行", "自然", "生活"].filter { theme in
            candidates.contains { ($0.name + $0.keywords.joined(separator: " ")).localizedCaseInsensitiveContains(theme) }
        }
    }
    var filteredCandidates: [CloudMaterial] {
        candidates.filter { draft.theme == "全部" || ($0.name + $0.keywords.joined(separator: " ")).localizedCaseInsensitiveContains(draft.theme) }
    }
    private func remember() { undo = draft; undoAvailable = true }
    func cancelStickerOperation() {
        operation = UUID(); job?.cancel(); job = nil; busy = false; pendingStickerIDs = []; stickerLoadFailed = false
    }
    func undoLast() {
        guard !isSubmitting, let undo else { return }
        cancelStickerOperation()
        draft.stickers = undo.stickers; draft.excluded = undo.excluded
        draft.seed = undo.seed; draft.batch = undo.batch; draft.history = undo.history; draft.didDraw = undo.didDraw
        self.undo = nil; undoAvailable = false; save()
    }
    func toggleKeep(_ id: String) {
        guard !isSubmitting, let i = draft.stickers.firstIndex(where: { $0.id == id }) else { return }
        cancelStickerOperation(); remember(); draft.stickers[i].kept.toggle(); save()
    }
    func removeSticker(_ id: String) {
        guard !isSubmitting else { return }; cancelStickerOperation(); remember()
        draft.excluded.insert(id); draft.stickers.removeAll { $0.id == id }; save()
    }
    func skipStickers() {
        guard !isSubmitting else { return }; cancelStickerOperation(); remember()
        draft.excluded.formUnion(draft.stickers.map(\.id)); draft.stickers = []; draft.didDraw = true; save()
    }
    private func prepareSticker(_ item: CloudMaterial, kept: Bool) async throws -> (DiaryCreationSticker, UIImage) {
        let data = try await PresetDownloadManager.shared.materialData(item) { _ in }
        try Task.checkCancellation()
        guard ownerValid else { throw CancellationError() }
        guard let image = try await DiaryAIImageWork.run({ Self.thumbnail(data) }) else { throw DiaryEditorError.invalidImage }
        let file = item.sha256 + ".sticker"
        let url = directory.appendingPathComponent(file)
        try await DiaryAIImageWork.run { try data.write(to: url, options: .atomic) }
        try Task.checkCancellation()
        return (.init(item: item, filename: file, kept: kept), image)
    }
    func loadPersonal(more: Bool = false) async {
        guard !loadingPersonal else { return }
        loadingPersonal = true
        defer { loadingPersonal = false }
        do {
            let page = try await PersonalStickerService.list(offset: more ? personalCursor ?? 0 : 0)
            guard ownerValid, !Task.isCancelled else { return }
            var seen = Set<String>()
            personalItems = (more ? personalItems + page.items : page.items).filter { seen.insert($0.id).inserted }
            personalCursor = page.next
        } catch { if !Task.isCancelled { self.error = "我的贴纸加载失败，请重试。" } }
    }
    func addPersonal(_ item: PersonalSticker, completed: @escaping () -> Void) {
        let id = "personal." + item.id
        guard !isSubmitting, !pendingStickerIDs.contains(id), selectedStickerCount < 8, !draft.stickers.contains(where: { $0.id == id }) else { return }
        pendingStickerIDs.insert(id); stickerLoadFailed = false; completed()
        busy = true; status = "正在准备我的贴纸…"
        let token = operation, previous = job
        job = Task {
            await previous?.value
            guard operation == token, !Task.isCancelled, ownerValid else { return }
            defer {
                if operation == token { pendingStickerIDs.remove(id); busy = !pendingStickerIDs.isEmpty }
            }
            do {
                let data = try await PersonalStickerService.image(item)
                let prepared = try await DiaryAIImageWork.run { () -> (String, UIImage) in
                    guard let image = Self.thumbnail(data) else { throw DiaryEditorError.invalidImage }
                    return (SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), image)
                }
                let hash = prepared.0, image = prepared.1
                let file = hash + ".sticker", url = directory.appendingPathComponent(hash + ".sticker")
                try await DiaryAIImageWork.run { try data.write(to: url, options: .atomic) }
                guard operation == token, !Task.isCancelled, ownerValid else { return }
                let material = CloudMaterial(id: id, revision: 0, name: "我的贴纸", keywords: [], aliases: [], kind: "illustration", subcategory: "", thumbnail_sha256: hash, thumbnail_url: "", sha256: hash, byte_size: data.count, favorite_count: 0, is_favorited: false)
                remember(); draft.stickers.append(.init(item: material, filename: file, kept: true))
                images[file] = image; draft.didDraw = true; draft.excluded.remove(id); save()
            } catch { if operation == token, !Task.isCancelled { stickerLoadFailed = true; self.error = "我的贴纸准备失败，请重试。" } }
        }
    }
    func addSticker(_ item: CloudMaterial, completed: @escaping () -> Void) {
        guard !isSubmitting, !pendingStickerIDs.contains(item.id), selectedStickerCount < 8, !draft.stickers.contains(where: { $0.id == item.id }) else { return }
        pendingStickerIDs.insert(item.id); stickerLoadFailed = false; completed()
        busy = true; status = "正在准备贴纸…"; error = nil
        let token = operation, previous = job
        job = Task {
            await previous?.value
            guard operation == token, !Task.isCancelled, ownerValid else { return }
            defer {
                if operation == token { pendingStickerIDs.remove(item.id); busy = !pendingStickerIDs.isEmpty }
            }
            do {
                let (sticker, image) = try await prepareSticker(item, kept: true)
                guard operation == token, !Task.isCancelled else { return }
                remember(); draft.stickers.append(sticker); draft.excluded.remove(item.id); draft.didDraw = true
                images[sticker.filename] = image; MaterialRecentStore.record(item, owner: draft.owner); save()
            } catch { if operation == token, !Task.isCancelled { stickerLoadFailed = true; self.error = "贴纸准备失败，请重试。" } }
        }
    }
    func draw() {
        guard !isSubmitting, !busy, !allKept else { return }
        busy = true; stickerLoadFailed = false; error = nil; status = "正在准备新一批贴纸…"
        let token = UUID(); operation = token
        job = Task {
            defer { if operation == token { busy = false } }
            do {
                let kept = draft.stickers.filter(\.kept)
                let target = kept.count >= 6 ? draft.stickers.count : max(Int.random(in: 3...6), kept.count)
                let excluded = draft.excluded.union(draft.stickers.map(\.id)).filter { UUID(uuidString: $0) != nil }
                var params = ["schema": "2", "type": "sticker", "sort": "random", "limit": String(max(1, target - kept.count)), "exclude": excluded.sorted().joined(separator: ",")]
                if draft.theme != "全部" { params["q"] = draft.theme }
                // Ordinary catalog pages also contain items. Require an explicit draw receipt
                // so an older server cannot silently pass its first page off as a random batch.
                struct DrawResponse: Decodable { let items: [CloudMaterial]; let draw_scope: String? }
                let repository = MaterialCatalogRepository.shared
                guard let engine = repository.engine else { throw URLError(.userAuthenticationRequired) }
                let path = MaterialRoutes.path("items/", params)
                let request = SupportNetworkRequest(method: .get, path: "/api/v1/materials/items/", queryItems: URLComponents(string: path)?.queryItems, strategy: NetworkStrategy(requiresAuth: true, allowETag: false))
                let response = try await engine.sendRaw(request)
                let page = try JSONDecoder().decode(DrawResponse.self, from: response.data)
                guard page.draw_scope == "published_stickers" else {
                    if operation == token && ownerValid { stickerLoadFailed = true; self.error = "当前服务尚未提供全库随机贴纸，请更新服务后重试。" }
                    return
                }
                try Task.checkCancellation()
                guard operation == token, ownerValid else { return }
                let fresh = page.items.filter { $0.availability != "unavailable" && $0.revision > 0 && !excluded.contains($0.id) }
                guard !fresh.isEmpty else { stickerLoadFailed = true; self.error = "服务端暂时没有更多可用贴纸，已保留当前搭配。"; return }
                var seen = Set<String>()
                let incoming = fresh.filter { seen.insert($0.id).inserted }.prefix(max(0, target - kept.count))
                candidates = candidates.filter { old in !incoming.contains { $0.id == old.id } } + incoming
                let result = DiaryStickerDrawEngine.Result(ids: kept.map(\.id) + incoming.map(\.id), seed: draft.seed &+ 1)
                var prepared: [DiaryCreationSticker] = []
                var previews: [String: UIImage] = [:]
                for id in result.ids {
                    if let existing = draft.stickers.first(where: { $0.id == id }) { prepared.append(existing); continue }
                    guard let item = candidates.first(where: { $0.id == id }) else { throw DiaryEditorError.invalidImage }
                    let (sticker, image) = try await prepareSticker(item, kept: false)
                    prepared.append(sticker); previews[sticker.filename] = image
                }
                guard operation == token, !Task.isCancelled, ownerValid else { return }
                remember(); draft.history.append(draft.stickers.map(\.id)); draft.history = Array(draft.history.suffix(2))
                draft.stickers = prepared; draft.seed = result.seed; draft.batch += 1; draft.didDraw = true
                images.merge(previews) { _, new in new }; save()
                UIAccessibility.post(notification: .announcement, argument: "已换好 \(prepared.count) 张贴纸")
            } catch { if operation == token, !Task.isCancelled { stickerLoadFailed = true; self.error = "换批失败，已保留原来的贴纸。请重试或不用贴纸继续。" } }
        }
    }
    private struct PreparationInput {
        let key: String
        let filename: String
        let sticker: DiaryCreationSticker?
    }
    private var preparationInputs: [PreparationInput] {
        draft.photos.map { .init(key: "photo:" + $0.id.uuidString + ":" + $0.digest + ":" + $0.filename, filename: $0.filename, sticker: nil) } +
        draft.stickers.map { .init(key: "sticker:" + $0.id + ":" + String($0.item.revision) + ":" + $0.filename, filename: $0.filename, sticker: $0) }
    }
    private func preparationCacheURL(_ key: String) -> URL {
        let identity = "v2:" + draft.id.uuidString + ":" + draft.baseline + ":" + key
        let hash = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent("prepared", isDirectory: true).appendingPathComponent(hash + ".json")
    }
    private func restorePrepared(_ url: URL) async throws -> DiaryCreationPreparedMaterial {
        let cached = try await DiaryAIImageWork.run { try JSONDecoder().decode(DiaryCreationPreparedArchive.self, from: Data(contentsOf: url)) }
        guard cached.document.id == session.document.id,
              cached.document.objects[session.contentID] != nil else { throw DiaryEditorError.invalidDocument }
        _ = try DiaryDocumentStore.validate(cached.document)
        var loaded = session.images
        for (id, asset) in cached.document.assets where loaded[id] == nil {
            loaded[id] = try await session.store.loadAILayoutImage(asset, documentID: cached.document.id)
        }
        let thumbs = try await DiaryAIImageWork.run { cached.thumbnails.compactMapValues { UIImage(data: $0) } }
        return .init(document: cached.document, images: loaded, thumbnails: thumbs)
    }
    private func cachePrepared(_ prepared: DiaryCreationPreparedMaterial, at url: URL) async throws {
        let document = prepared.document, thumbnails = prepared.thumbnails
        try await DiaryAIImageWork.run {
            let archive = DiaryCreationPreparedArchive(document: document, thumbnails: thumbnails.compactMapValues { $0.pngData() })
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(archive).write(to: url, options: .atomic)
        }
    }
    private func schedulePreparation() {
        guard !preparationSuspended, !draft.submitted, ownerValid,
              (try? DiaryEditorAIBridge.digest(session.document)) == draft.baseline else { return }
        let inputs = preparationInputs
        let keys = Set(inputs.map(\.key))
        preparedMaterials = preparedMaterials.filter { keys.contains($0.key) }
        preparationFailures = preparationFailures.filter { keys.contains($0.key) }
        preparedCount = inputs.filter { preparedMaterials[$0.key] != nil }.count
        guard preparationTask == nil, preparedCount < inputs.count else { return }
        let generation = preparationGeneration
        preparingMaterials = true
        preparationTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.preparationGeneration == generation {
                    self.preparationTask = nil; self.preparingMaterials = false
                }
            }
            // One material at a time bounds decoding memory and observes the latest selection.
            var attempted = Set<String>()
            while !Task.isCancelled, self.ownerValid, self.preparationGeneration == generation,
                  let input = self.preparationInputs.first(where: { self.preparedMaterials[$0.key] == nil && !attempted.contains($0.key) }) {
                attempted.insert(input.key)
                do {
                    let cacheURL = self.preparationCacheURL(input.key)
                    if let restored = try? await self.restorePrepared(cacheURL) {
                        guard !Task.isCancelled, self.ownerValid, self.preparationGeneration == generation,
                              self.preparationInputs.contains(where: { $0.key == input.key }) else { continue }
                        self.preparedMaterials[input.key] = restored
                        self.preparationFailures[input.key] = nil
                        self.preparedCount = self.preparationInputs.filter { self.preparedMaterials[$0.key] != nil }.count
                        continue
                    }
                    let url = self.directory.appendingPathComponent(input.filename)
                    let bytes = try await DiaryAIImageWork.run { try Data(contentsOf: url) }
                    let candidate = DiaryEditorSession(document: self.session.document, images: self.session.images,
                                                       store: self.session.store, contentID: self.session.contentID)
                    candidate.aiTransientSession = true
                    let success: Bool
                    if let sticker = input.sticker {
                        let item = sticker.item
                        let source = item.revision > 0 ? DiaryMaterialSource(materialID: item.id, revision: item.revision, libraryID: item.library_id, libraryVersion: item.library_version) : nil
                        success = await candidate.importPhoto(bytes, asSticker: true, stickerName: item.name, materialSource: source)
                    } else { success = await candidate.importPhotos([bytes]) }
                    guard success else { throw DiaryAIError.invalid(candidate.errorMessage ?? "素材准备失败") }
                    try Task.checkCancellation()
                    await Task.yield()
                    let thumbnailDocument = candidate.document, thumbnailImages = candidate.images
                    let contentID = candidate.contentID
                    let thumbnails = try await DiaryAIImageWork.run {
                        DiaryCreationMaterialPreview.render(thumbnailDocument, contentID: contentID, images: thumbnailImages)
                    }
                    guard !Task.isCancelled, self.ownerValid, self.preparationGeneration == generation,
                          self.preparationInputs.contains(where: { $0.key == input.key }) else { continue }
                    let prepared = DiaryCreationPreparedMaterial(document: candidate.document, images: candidate.images, thumbnails: thumbnails)
                    // Disk cache is optional; an encoding or disk-space failure must not discard usable originals.
                    try? await self.cachePrepared(prepared, at: cacheURL)
                    guard !Task.isCancelled, self.ownerValid, self.preparationGeneration == generation,
                          self.preparationInputs.contains(where: { $0.key == input.key }) else { continue }
                    self.preparedMaterials[input.key] = prepared
                    self.preparationBuildCount += 1
                    self.preparationFailures[input.key] = nil
                    self.preparedCount = self.preparationInputs.filter { self.preparedMaterials[$0.key] != nil }.count
                } catch {
                    guard !Task.isCancelled, self.preparationGeneration == generation else { return }
                    if self.preparationInputs.contains(where: { $0.key == input.key }) { self.preparationFailures[input.key] = error.localizedDescription }
                }
            }
        }
    }
    func waitForPreparation() async {
        resumePreparation()
        await preparationTask?.value
    }
    private func preparedSubmission() throws -> DiaryCreationPreparedSubmission {
        var document = session.document
        var images = session.images
        var thumbnails: [UUID: UIImage] = [:]
        var photoIDs: [UUID] = []
        let baselineIDs = Set(document.objects.keys)
        let baselineLayers = Set(document.objects[session.contentID]!.layers.map(\.id))
        for input in preparationInputs {
            guard let prepared = preparedMaterials[input.key] else {
                throw DiaryAIError.invalid(preparationFailures[input.key] ?? "素材尚未准备完成，请重试。")
            }
            document.assets.merge(prepared.document.assets) { _, new in new }
            for (id, object) in prepared.document.objects where !baselineIDs.contains(id) { document.objects[id] = object }
            let added = prepared.document.objects[session.contentID]!.layers.filter { !baselineLayers.contains($0.id) }
            document.objects[session.contentID]!.layers += added
            images.merge(prepared.images) { _, new in new }
            thumbnails.merge(prepared.thumbnails) { _, new in new }
            if input.sticker == nil { photoIDs += added.map(\.id) }
        }
        _ = try DiaryDocumentStore.validate(document)
        return .init(document: document, contentID: session.contentID, images: images, thumbnails: thumbnails, photoIDs: photoIDs)
    }
    func submit() async -> Bool {
        guard canContinue, ownerValid else { return false }
        isSubmitting = true; error = nil; status = "正在准备制作任务…"
        defer { isSubmitting = false }
        do {
            await photoTask?.value
            await job?.value
            try Task.checkCancellation()
            guard !stickerLoadFailed else { throw DiaryAIError.invalid("贴纸读取失败，请返回重试或选择不用贴纸。") }
            guard ownerValid, !draft.photos.isEmpty, failures.isEmpty else {
                throw DiaryAIError.invalid("有照片读取失败或尚未选入，请返回照片页重试或移除。")
            }
            guard try DiaryEditorAIBridge.digest(session.document) == draft.baseline else { throw DiaryAIError.invalid("原页面已发生变化，请关闭本次准备后重新打开制作。") }
            status = "正在核验素材…"
            // Re-authorize cloud assets at the final boundary. Downloads reuse verified cache bytes.
            for sticker in draft.stickers where sticker.item.revision > 0 { _ = try await PresetDownloadManager.shared.materialData(sticker.item) { _ in } }
            guard ownerValid else { throw CancellationError() }
            var request = draft.request
            request.selectedOnly = false
            if !draft.story.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { request.instruction += "\n用户故事：" + draft.story }
            let photoURLs = draft.photos.map { directory.appendingPathComponent($0.filename) }
            let stickerValues = draft.stickers
            let sourceDirectory = directory
            let photos = try await DiaryAIImageWork.run { try photoURLs.map { try Data(contentsOf: $0) } }
            let stickers = try await DiaryAIImageWork.run {
                try stickerValues.map { value in
                    (try Data(contentsOf: sourceDirectory.appendingPathComponent(value.filename)), value.item.name,
                     value.item.revision > 0 ? DiaryMaterialSource(materialID: value.id, revision: value.item.revision, libraryID: value.item.library_id, libraryVersion: value.item.library_version) : nil)
                }
            }
            let heroIndex = draft.photos.firstIndex { $0.id == draft.heroID } ?? 0
            preparationSuspended = false
            schedulePreparation()
            status = "正在准备素材…"
            await preparationTask?.value
            try Task.checkCancellation()
            guard ownerValid else { throw CancellationError() }
            guard try DiaryEditorAIBridge.digest(session.document) == draft.baseline else {
                throw DiaryAIError.invalid("原页面已发生变化，请关闭本次准备后重新打开制作。")
            }
            let prepared = try preparedSubmission()
            status = "正在保存制作任务…"
            let accepted = await session.aiWorkspace.commitCreation(id: draft.id, photos: photos, stickers: stickers, heroIndex: heroIndex, photoNotes: draft.photos.map { draft.photoNotes?[$0.id.uuidString] ?? "" }, request: request, prepared: prepared)
            guard accepted else { throw DiaryAIError.invalid(session.aiWorkspace.error ?? "制作任务未能保存，请重试。") }
            draft.submitted = true; save()
            session.canvasAI.setForm(session.aiWorkspace.currentRequest)
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
}

@MainActor struct DiaryCreationPreparedMaterial {
    let document: DiaryDocument
    let images: [UUID: UIImage]
    let thumbnails: [UUID: UIImage]
}
@MainActor struct DiaryCreationPreparedSubmission {
    let document: DiaryDocument
    let contentID: UUID
    let images: [UUID: UIImage]
    let thumbnails: [UUID: UIImage]
    let photoIDs: [UUID]
}

nonisolated private struct DiaryCreationPreparedArchive: Codable, Sendable {
    let document: DiaryDocument
    let thumbnails: [UUID: Data]
}

/// Initial creation materials are unedited photos (with optional frames) or stickers.
/// Rasterize their list previews off the UI executor; full canvas rendering stays in the editor.
nonisolated private enum DiaryCreationMaterialPreview {
    static func render(_ document: DiaryDocument, contentID: UUID, images: [UUID: UIImage]) -> [UUID: UIImage] {
        var result: [UUID: UIImage] = [:]
        for outer in document.objects[contentID]?.layers ?? [] {
            guard let childID = outer.contentID, let child = document.objects[childID],
                  let primary = child.layers.first(where: { $0.id == child.primaryLayerID }) ?? child.layers.first,
                  let assetID = primary.assetID, let photo = images[assetID] else { continue }
            let frame = child.layers.first { $0.frameTargetID == primary.id }
            let frameImage = frame?.assetID.flatMap { images[$0] }
            let opening = frame?.frameOpening ?? CGRect(x: 0, y: 0, width: 1, height: 1)
            let sourceSize = frameImage?.size ?? photo.size
            guard sourceSize.width > 0, sourceSize.height > 0 else { continue }
            let ratio = min(1, 240 / max(sourceSize.width, sourceSize.height))
            let size = CGSize(width: sourceSize.width * ratio, height: sourceSize.height * ratio)
            let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = false
            result[outer.id] = UIGraphicsImageRenderer(size: size, format: format).image { output in
                let rect = CGRect(origin: .zero, size: size)
                let photoRect = CGRect(x: opening.minX * size.width, y: opening.minY * size.height,
                                       width: opening.width * size.width, height: opening.height * size.height)
                output.cgContext.saveGState()
                output.cgContext.clip(to: photoRect)
                photo.draw(in: photoRect)
                output.cgContext.restoreGState()
                frameImage?.draw(in: rect)
            }
        }
        return result
    }
}
