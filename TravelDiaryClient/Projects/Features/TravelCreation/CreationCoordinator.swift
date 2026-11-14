import SwiftUI
import Combine

@MainActor
final class CreationCoordinator: ObservableObject {
    @Published var draft: CreationDraft
    @Published var thumbnails: [UUID: UIImage] = [:]
    @Published var busy = false
    @Published var error: String?
    @Published var status = ""
    let store: CreationDraftStore
    private var lease: StorageActivity.Lease?
    private var destination: DiaryDocumentStore?
    private var activeSession: DiaryEditorSession?
    init(owner: String, draft: CreationDraft? = nil, bookID: UUID? = nil, store: CreationDraftStore? = nil) {
        self.store = store ?? CreationDraftStore(owner: owner)
        self.draft = draft ?? CreationDraft(owner: owner, targetBookID: bookID)
        lease = StorageActivity.shared.acquire(self.store.directory(self.draft.id))
    }
    func persist() async {
        var snapshot = draft; snapshot.updatedAt = Date()
        do { try await store.save(snapshot) } catch { self.error = "草稿保存失败：" + error.localizedDescription }
    }
    func loadThumbnails() async {
        for asset in draft.assets {
            if let bytes = try? await store.thumbnail(asset, draftID: draft.id) { thumbnails[asset.id] = UIImage(data: bytes) }
        }
    }
    func add(_ bytes: Data, name: String, sticker: Bool = false, material: DiaryMaterialSource? = nil) async {
        do {
            draft = try await store.add(bytes, to: draft, name: name, sticker: sticker, material: material)
            if let item = draft.assets.last, let bytes = try await store.thumbnail(item, draftID: draft.id) { thumbnails[item.id] = UIImage(data: bytes) }
        } catch { self.error = error.localizedDescription }
    }
    func remove(_ asset: CreationAsset) async {
        do { draft = try await store.removeAsset(asset.id, from: draft); thumbnails[asset.id] = nil }
        catch { self.error = error.localizedDescription }
    }
    func addAutomaticStickers() async throws {
        guard draft.stickerMode == "自动搭配", draft.stickers.isEmpty else { return }
        let theme = draft.brief.theme + draft.brief.scene
        let category = theme.contains("庆祝") ? "庆祝" : theme.contains("山") || theme.contains("海") ? "自然" : "旅行"
        let candidates = DiaryStickerCatalog.items.filter { $0.category == category && $0.title != "生日蛋糕" }.prefix(3)
        for item in candidates {
            guard let data = item.image()?.pngData() else { continue }
            draft = try await store.add(data, to: draft, name: item.title, sticker: true)
        }
    }
    /// A stable page ID plus persisted per-object mapping makes interrupted import resumable.
    func prepare(allowEmpty: Bool = false) async -> DiaryEditorSession? {
        guard !busy else { return nil }
        if let activeSession { return activeSession }
        busy = true; defer { busy = false }
        do {
            if !allowEmpty, let error = draft.preflightError { throw DiaryAIError.invalid(error) }
            if !allowEmpty { try await addAutomaticStickers() }
            if !allowEmpty, let error = draft.preflightError { throw DiaryAIError.invalid(error) }
            for asset in draft.photos + draft.stickers { _ = try await store.data(asset, draftID: draft.id) }
            status = "正在建立制作工作台…"
            if draft.handoffID == nil { draft.handoffID = UUID(); try await store.save(draft) }
            let nativeStore = DiaryDocumentStore(ownerID: draft.owner, baseDirectory: store.directory(draft.id).appendingPathComponent("Work"))
            var session: DiaryEditorSession
            if let loaded = try? await nativeStore.load(draft.documentID) {
                session = DiaryEditorSession(document: loaded.document, images: loaded.images, store: nativeStore)
                draft.mapping = loaded.document.creation?.assetObjects ?? draft.mapping
            } else {
                var document = DiaryDocument(); document.id = draft.documentID
                document.objects[document.rootContentID]?.referenceSize = DiaryPagePreset.spread.size
                session = DiaryEditorSession(document: document, images: [:], store: nativeStore)
            }
            session.aiTransientSession = true
            for asset in draft.photos + draft.stickers where draft.mapping[asset.id] == nil {
                status = "正在准备：\(asset.name)"
                let old = session.document
                let bytes = try await store.data(asset, draftID: draft.id)
                let success = asset.isSticker
                    ? await session.importPhoto(bytes, asSticker: true, stickerName: asset.name)
                    : await session.importPhotos([bytes])
                guard success, let layer = session.document.root.layers.last(where: { next in !old.root.layers.contains { $0.id == next.id } }) else {
                    throw DiaryAIError.invalid(session.errorMessage ?? "素材导入失败，原文件已保留。")
                }
                draft.mapping[asset.id] = layer.id
                var updated = session.document
                if let material = asset.material { updated.update(layer.id) { $0.materialSource = material } }
                updated.creation = provenance()
                guard session.applyAIDraft(updated, expected: session.document, additionalImages: [:]) else { throw DiaryEditorError.invalidDocument }
                try await nativeStore.save(session.document)
                try await store.save(draft)
            }
            var updated = session.document
            updated.creation = provenance()
            _ = session.applyAIDraft(updated, expected: session.document, additionalImages: [:])
            try await nativeStore.save(session.document)
            let canonical = try await nativeStore.load(draft.documentID)
            await session.discardCreationSession()
            session = DiaryEditorSession(document: canonical.document, images: canonical.images, store: nativeStore)
            session.aiTransientSession = false
            session.creationPublish = { [weak self, weak session] in
                guard let self, let session else { throw DiaryEditorError.invalidDocument }
                try await self.publish(session)
            }
            activeSession = session
            try await store.save(draft)
            return session
        } catch { self.error = error.localizedDescription; return nil }
    }
    func discardIfEmpty(_ session: DiaryEditorSession) async throws -> Bool {
        guard session === activeSession else { throw DiaryEditorError.invalidDocument }
        if let brief = session.canvasAI.form(.relayout).creationBrief, brief != draft.brief {
            var updated = draft
            updated.brief = brief
            try await store.save(updated)
            draft = updated
        }
        let root = session.document.root
        guard draft.publishedDigest == nil, draft.assets.isEmpty, draft.brief == CreationBrief(),
              session.aiWorkspace.objects.isEmpty, root.layers.isEmpty, root.drawing.isEmpty,
              root.background == nil, (session.aiWorkspace.currentCreationBrief ?? CreationBrief()) == CreationBrief()
        else { return false }
        try await discardForNewPage()
        return true
    }

    func discardForNewPage() async throws {
        guard !busy, let session = activeSession,
              !session.busy, !session.aiWorkspace.addingMaterials else {
            throw DiaryAIError.invalid("正在处理素材，请稍后新建页。")
        }
        busy = true
        defer { busy = false }
        await session.aiWorkspace.discardForNewPage()
        await session.canvasAI.stopForDiscard()
        await session.discardCreationSession()
        activeSession = nil
        lease?.release()
        lease = nil
        do { try await store.remove(draft.id) }
        catch {
            lease = StorageActivity.shared.acquire(store.directory(draft.id))
            activeSession = session
            session.resumeAfterFailedDiscard()
            throw error
        }
    }

    func claimLaunch() async throws -> Bool {
        guard !draft.launchClaimed else { return false }
        draft.launchClaimed = true
        try await store.save(draft)
        return true
    }
    private func provenance() -> CreationProvenance {
        .init(draftID: draft.id, brief: draft.brief, design: draft.design, assetObjects: draft.mapping, photoNotes: draft.request().creationNotes ?? [:])
    }
    private func publish(_ session: DiaryEditorSession) async throws {
        let root = session.document.root
        guard !root.layers.isEmpty || !root.drawing.isEmpty || root.background != nil else { return }
        if destination == nil {
            if draft.targetBookID == nil {
                let book = try await DiaryDocumentStore(ownerID: draft.owner).createBook(title: "旅行随记", preset: .spread)
                draft.targetBookID = book.id
                try await store.save(draft)
            }
            let target = DiaryDocumentStore(ownerID: draft.owner, bookID: draft.targetBookID)
            // A prior successful publication may have outlived the app process.
            if let existing = try? await target.load(draft.documentID) {
                guard existing.document.creation?.draftID == draft.id else { throw DiaryEditorError.pageConflict }
                var comparable = existing.document; comparable.bookID = nil
                let digest = try DiaryEditorAIBridge.digest(comparable)
                guard draft.publishedDigest.map({ $0 == digest }) ?? (comparable == session.document) else { throw DiaryEditorError.pageConflict }
            }
            destination = target
        }
        guard let destination else { throw DiaryEditorError.invalidDocument }
        try await destination.publishCreation(session.document, from: session.store)
        try await store.retainRemaining(draft)
        draft.publishedDigest = try DiaryEditorAIBridge.digest(session.document)
        let workspace = session.aiWorkspace
        // Opening the AI panel alone does not create a new unfinished production.
        let hasProduction = workspace.hasStartedWork || !workspace.pending.isEmpty || workspace.requiresResultRecording
        draft.published = !(hasProduction && workspace.hasUnfinishedWork)
        try await store.save(draft)
    }
}
