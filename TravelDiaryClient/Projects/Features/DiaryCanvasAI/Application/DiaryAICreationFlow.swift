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
    var canContinue: Bool { !busy && failures.isEmpty && !draft.photos.isEmpty && draft.photos.allSatisfy { images[$0.filename] != nil } && saveError == nil }
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
            if !busy {
                let used = Set(draft.photos.map(\.filename) + draft.stickers.map(\.filename) + (undo?.stickers.map(\.filename) ?? []))
                for file in (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [] where ["photo", "sticker"].contains(file.pathExtension) && !used.contains(file.lastPathComponent) {
                    try? FileManager.default.removeItem(at: file)
                }
            }
            return true
        } catch { saveError = "草稿保存失败：" + error.localizedDescription; return false }
    }
    func cancelOperation() {
        operation = UUID(); job?.cancel(); job = nil; busy = false
        catalogOperation = UUID(); catalogJob?.cancel(); catalogJob = nil; loadingCatalog = false
        _ = save()
    }
    func discardDraft() {
        cancelOperation()
        draft = .init(owner: session.store.ownerID, documentID: session.document.id,
                      baseline: (try? DiaryEditorAIBridge.digest(session.document)) ?? draft.baseline,
                      request: draft.request)
        images = [:]; undo = nil; undoAvailable = false; failures = [:]; failedItems = [:]; failedProviders = [:]
        save()
    }
    func setStep(_ step: Int) { draft.step = step; save() }
    func setDesign(_ value: DiaryAIDesignSelection) { draft.request.design = value; save() }
    func setStory(_ value: String) { draft.story = value; save() }
    func setTheme(_ value: String) { draft.theme = value; save() }
    func setHero(_ id: UUID) { draft.heroID = id; save() }
    func setPhotoNote(_ id: UUID, value: String) {
        if draft.photoNotes == nil { draft.photoNotes = [:] }
        draft.photoNotes?[id.uuidString] = value; save()
    }
    func removePhoto(_ id: UUID) {
        guard !busy else { return }
        draft.photos.removeAll { $0.id == id }; draft.photoNotes?[id.uuidString] = nil
        if draft.heroID == id {
            draft.heroID = draft.photos.first?.id
            if draft.heroID != nil { UIAccessibility.post(notification: .announcement, argument: "已将第一张照片设为主照") }
        }
        save()
    }
    func movePhoto(_ id: UUID, offset: Int) {
        guard !busy, let i = draft.photos.firstIndex(where: { $0.id == id }), draft.photos.indices.contains(i + offset) else { return }
        draft.photos.swapAt(i, i + offset); save()
    }
    func movePhoto(_ id: UUID, before target: UUID) {
        guard !busy, id != target, let i = draft.photos.firstIndex(where: { $0.id == id }), let j = draft.photos.firstIndex(where: { $0.id == target }) else { return }
        let value = draft.photos.remove(at: i); draft.photos.insert(value, at: j - (i < j ? 1 : 0)); save()
    }
    func removeFailure(_ id: UUID) { failures[id] = nil; failedItems[id] = nil; failedProviders[id] = nil }
    func retryFailure(_ id: UUID) {
        if let provider = failedProviders[id] { removeFailure(id); importProviders([provider]); return }
        guard let item = failedItems[id] else { return }
        removeFailure(id); importPhotos([item])
    }
    func importProviders(_ providers: [NSItemProvider]) {
        guard !busy, !providers.isEmpty else { return }
        busy = true; error = nil
        let token = UUID(); operation = token
        job = Task {
            defer { if operation == token { busy = false; save() } }
            for (index, provider) in providers.prefix(max(0, 30 - draft.photos.count)).enumerated() {
                guard operation == token, !Task.isCancelled, ownerValid else { return }
                status = "正在准备照片 \(index + 1)/\(providers.count)…"
                do {
                    guard let type = provider.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .image) == true }) else { throw DiaryEditorError.invalidImage }
                    let data: Data = try await withCheckedThrowingContinuation { continuation in
                        provider.loadDataRepresentation(forTypeIdentifier: type) { data, error in
                            if let data { continuation.resume(returning: data) }
                            else { continuation.resume(throwing: error ?? DiaryEditorError.invalidImage) }
                        }
                    }
                    guard operation == token, !Task.isCancelled, ownerValid else { return }
                    try await appendPhoto(data)
                } catch {
                    guard operation == token, !Task.isCancelled else { return }
                    let id = UUID(); failures[id] = "第 \(index + 1) 张读取失败"; failedProviders[id] = provider
                }
            }
        }
    }
    func importPhotos(_ items: [PhotosPickerItem]) {
        guard !busy, !items.isEmpty else { return }
        busy = true; error = nil
        let token = UUID(); operation = token
        job = Task {
            defer { if operation == token { busy = false; save() } }
            for (index, item) in items.prefix(max(0, 30 - draft.photos.count)).enumerated() {
                guard operation == token, !Task.isCancelled, ownerValid else { return }
                status = "正在准备照片 \(index + 1)/\(items.count)…"
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else { throw DiaryEditorError.invalidImage }
                    try Task.checkCancellation()
                    guard operation == token, ownerValid else { return }
                    try await appendPhoto(data)
                } catch {
                    guard operation == token, !Task.isCancelled else { return }
                    let id = UUID(); failures[id] = "第 \(index + 1) 张读取失败"; failedItems[id] = item
                }
            }
        }
    }
    func importCamera(_ data: [Data]) async {
        guard !busy else { return }; busy = true
        defer { busy = false; save() }
        do { for bytes in data.prefix(max(0, 30 - draft.photos.count)) { try await appendPhoto(bytes) } }
        catch { self.error = error.localizedDescription }
    }
    private func appendPhoto(_ data: Data) async throws {
        let prepared = try await DiaryAIImageWork.run { () -> (String, UIImage) in
            guard let image = Self.thumbnail(data) else { throw DiaryEditorError.invalidImage }
            return (SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), image)
        }
        try Task.checkCancellation()
        guard ownerValid else { throw CancellationError() }
        guard !draft.photos.contains(where: { $0.digest == prepared.0 }), draft.photos.count < 30 else { return }
        let file = prepared.0 + ".photo"
        try data.write(to: directory.appendingPathComponent(file), options: .atomic)
        let photo = DiaryCreationPhoto(filename: file, digest: prepared.0, name: "照片")
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
    func undoLast() {
        guard !busy, let undo else { return }
        draft.stickers = undo.stickers; draft.excluded = undo.excluded
        draft.seed = undo.seed; draft.batch = undo.batch; draft.history = undo.history; draft.didDraw = undo.didDraw
        self.undo = nil; undoAvailable = false; save()
    }
    func toggleKeep(_ id: String) {
        guard !busy, let i = draft.stickers.firstIndex(where: { $0.id == id }) else { return }
        remember(); draft.stickers[i].kept.toggle(); save()
    }
    func removeSticker(_ id: String) {
        guard !busy else { return }; remember()
        draft.excluded.insert(id); draft.stickers.removeAll { $0.id == id }; save()
    }
    func skipStickers() {
        guard !busy else { return }; remember()
        draft.excluded.formUnion(draft.stickers.map(\.id)); draft.stickers = []; draft.didDraw = true; save()
    }
    private func prepareSticker(_ item: CloudMaterial, kept: Bool) async throws -> (DiaryCreationSticker, UIImage) {
        let data = try await PresetDownloadManager.shared.materialData(item) { _ in }
        try Task.checkCancellation()
        guard ownerValid else { throw CancellationError() }
        guard let image = try await DiaryAIImageWork.run({ Self.thumbnail(data) }) else { throw DiaryEditorError.invalidImage }
        let file = item.sha256 + ".sticker"
        try data.write(to: directory.appendingPathComponent(file), options: .atomic)
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
        guard !busy, draft.stickers.count < 8, !draft.stickers.contains(where: { $0.id == id }) else { return }
        busy = true; status = "正在准备我的贴纸…"
        let token = UUID(); operation = token
        job = Task {
            defer { if operation == token { busy = false } }
            do {
                let data = try await PersonalStickerService.image(item)
                guard operation == token, !Task.isCancelled, ownerValid, let image = Self.thumbnail(data) else { return }
                let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                let file = hash + ".sticker"
                try data.write(to: directory.appendingPathComponent(file), options: .atomic)
                let material = CloudMaterial(id: id, revision: 0, name: "我的贴纸", keywords: [], aliases: [], kind: "illustration", subcategory: "", thumbnail_sha256: hash, thumbnail_url: "", sha256: hash, byte_size: data.count, favorite_count: 0, is_favorited: false)
                remember(); draft.stickers.append(.init(item: material, filename: file, kept: true))
                images[file] = image; draft.didDraw = true; draft.excluded.remove(id); save(); completed()
            } catch { if operation == token, !Task.isCancelled { self.error = "我的贴纸准备失败，请重试。" } }
        }
    }
    func addSticker(_ item: CloudMaterial, completed: @escaping () -> Void) {
        guard !busy, draft.stickers.count < 8, !draft.stickers.contains(where: { $0.id == item.id }) else { return }
        busy = true; status = "正在准备贴纸…"; error = nil
        let token = UUID(); operation = token
        job = Task {
            defer { if operation == token { busy = false } }
            do {
                let (sticker, image) = try await prepareSticker(item, kept: true)
                guard operation == token, !Task.isCancelled else { return }
                remember(); draft.stickers.append(sticker); draft.excluded.remove(item.id); draft.didDraw = true
                images[sticker.filename] = image; MaterialRecentStore.record(item, owner: draft.owner); save(); completed()
            } catch { if operation == token, !Task.isCancelled { self.error = "贴纸准备失败，请重试。" } }
        }
    }
    func draw() {
        guard !busy, !allKept else { return }
        busy = true; error = nil; status = "正在准备新一批贴纸…"
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
                    if operation == token && ownerValid { self.error = "当前服务尚未提供全库随机贴纸，请更新服务后重试。" }
                    return
                }
                try Task.checkCancellation()
                guard operation == token, ownerValid else { return }
                let fresh = page.items.filter { $0.availability != "unavailable" && $0.revision > 0 && !excluded.contains($0.id) }
                guard !fresh.isEmpty else { self.error = "服务端暂时没有更多可用贴纸，已保留当前搭配。"; return }
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
            } catch { if operation == token, !Task.isCancelled { self.error = "换批失败，已保留原来的贴纸。请重试或不用贴纸继续。" } }
        }
    }
    func submit() async -> Bool {
        guard canContinue, ownerValid else { return false }
        busy = true; error = nil; status = "正在准备制作任务…"
        defer { busy = false }
        do {
            guard try DiaryEditorAIBridge.digest(session.document) == draft.baseline else { throw DiaryAIError.invalid("原页面已发生变化，请关闭本次准备后重新打开制作。") }
            // Re-authorize cloud assets at the final boundary. Downloads reuse verified cache bytes.
            for sticker in draft.stickers where sticker.item.revision > 0 { _ = try await PresetDownloadManager.shared.materialData(sticker.item) { _ in } }
            guard ownerValid else { throw CancellationError() }
            var request = draft.request
            request.selectedOnly = false
            if !draft.story.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { request.instruction += "\n用户故事：" + draft.story }
            let photos = try draft.photos.map { try Data(contentsOf: directory.appendingPathComponent($0.filename)) }
            let stickers = try draft.stickers.map { value in
                (try Data(contentsOf: directory.appendingPathComponent(value.filename)), value.item.name,
                 value.item.revision > 0 ? DiaryMaterialSource(materialID: value.id, revision: value.item.revision, libraryID: value.item.library_id, libraryVersion: value.item.library_version) : nil)
            }
            let heroIndex = draft.photos.firstIndex { $0.id == draft.heroID } ?? 0
            let accepted = await session.aiWorkspace.commitCreation(id: draft.id, photos: photos, stickers: stickers, heroIndex: heroIndex, photoNotes: draft.photos.map { draft.photoNotes?[$0.id.uuidString] ?? "" }, request: request)
            guard accepted else { throw DiaryAIError.invalid(session.aiWorkspace.error ?? "制作任务未能保存，请重试。") }
            draft.submitted = true; save()
            session.canvasAI.setForm(session.aiWorkspace.currentRequest)
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
}
