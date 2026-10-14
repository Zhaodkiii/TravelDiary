import SwiftUI
import Combine
import PencilKit

/// 单份打开文档的唯一编辑入口。界面不直接写文件，所有修改先进入统一历史再触发保存。
@MainActor
final class DiaryEditorSession: ObservableObject, Identifiable {
    struct Snapshot: Equatable {
        var document: DiaryDocument
    }
    let id = UUID()
    let contentID: UUID
    let baseRevision: Int
    let canvasBounds: CGRect
    weak var parent: DiaryEditorSession?
    private var childOpen = false
    private var closing = false
    let store: DiaryDocumentStore
    @Published private(set) var document: DiaryDocument
    @Published private(set) var images: [UUID: UIImage]
    var drawing: PKDrawing { (try? PKDrawing(data: content.drawing)) ?? PKDrawing() }
    @Published var selectedID: UUID?
    @Published var inkMode = false
    @Published var eraser = false
    @Published var errorMessage: String?
    @Published private(set) var saveStatus = "已保存"
    @Published private(set) var busy = false
    @Published private(set) var undoStack: [Snapshot] = []
    @Published private(set) var redoStack: [Snapshot] = []
    private var interactionStart: Snapshot?
    private var saveTask: Task<Void, Never>?
    private var revision = 0

    /// 主画布和子对象共享会话类型；子会话持有值拷贝，取消时不会污染父文档。
    init(document: DiaryDocument, images: [UUID: UIImage], store: DiaryDocumentStore,
         contentID: UUID? = nil, parent: DiaryEditorSession? = nil) {
        self.document = document; self.images = images; self.store = store
        self.contentID = contentID ?? document.rootContentID
        self.parent = parent
        let content = document.objects[self.contentID]!
        baseRevision = content.revision
        let reference = CGRect(origin: .zero, size: content.referenceSize)
        canvasBounds = parent == nil ? reference :
            reference.union(DiaryPageRenderer.objectBounds(content, document: document)).insetBy(dx: -100, dy: -100)
        selectedID = content.primaryLayerID ?? content.layers.first?.id
    }
    var content: DiaryObjectContent { document.objects[contentID]! }
    var isRoot: Bool { parent == nil }
    var selected: DiaryLayer? { scopeLayers.first { $0.id == selectedID } }
    var scopeLayers: [DiaryLayer] { content.layers }
    var snapshot: Snapshot { Snapshot(document: document) }

    /// 打开新的全屏编辑页面；每一级都复用本类和同一个编辑视图。
    func openObject() -> DiaryEditorSession? {
        guard !childOpen, !closing, let layer = selected, !layer.locked, let target = layer.contentID else { return nil }
        finishInteraction()
        saveTask?.cancel()
        childOpen = true
        return DiaryEditorSession(document: document, images: images, store: store, contentID: target, parent: self)
    }
    /// 子页面完成才提交为父页面的一次修改，外部位置、缩放和角度保持原样。
    func commitToParent() async -> Bool {
        guard !closing, !busy else { return false }
        guard let parent else { return await close() }
        busy = true
        defer { busy = false }
        finishInteraction()
        closing = true
        saveTask?.cancel()
        if let saveTask { await saveTask.value }
        guard parent.document.objects[contentID]?.revision == baseRevision else {
            closing = false
            errorMessage = DiaryEditorError.staleObject.logged().localizedDescription; return false
        }
        let before = parent.snapshot
        let oldUndo = parent.undoStack
        let oldRedo = parent.redoStack
        let oldRevision = parent.revision
        parent.document = document; parent.images.merge(images) { _, new in new }
        parent.childOpen = false
        parent.saveTask?.cancel()
        if let saveTask = parent.saveTask { await saveTask.value }
        parent.record(before)
        do {
            try await parent.save()
            parent.saveTask?.cancel()
            parent.saveTask = nil
            try? await store.discardDraft(contentID: contentID, documentID: document.id)
            return true
        } catch {
            parent.saveTask?.cancel()
            parent.saveTask = nil
            parent.document = before.document
            parent.undoStack = oldUndo
            parent.redoStack = oldRedo
            parent.revision = oldRevision
            parent.saveStatus = "保存失败"
            parent.childOpen = true
            closing = false
            errorMessage = error.localizedDescription
            return false
        }
    }
    func cancelEditor() async {
        guard !closing else { return }
        closing = true
        saveTask?.cancel()
        if let saveTask { await saveTask.value }
        try? await store.discardDraft(contentID: contentID, documentID: document.id)
        parent?.childOpen = false
        parent?.scheduleSave()
    }
    func setBackground(_ color: DiaryColor?) { edit { document.objects[contentID]?.background = color } }
    func addFrame() {
        guard let layer = selected, layer.kind == .photo, !layer.locked else { return }
        let frame = DiaryLayer(name: "相框", kind: .frame, transform: layer.transform,
                               size: layer.size, frameTargetID: layer.id, frameColor: .white, frameWidth: 20)
        edit { document.objects[contentID]?.layers.append(frame) }
    }

    /// 一次拖动/滑块调节只提交一条历史；中间状态实时显示，结束后再自动保存。
    func beginInteraction() { if interactionStart == nil { interactionStart = snapshot } }
    func finishInteraction() {
        guard let before = interactionStart else { return }
        interactionStart = nil
        record(before)
    }
    func cancelInteraction() {
        guard let before = interactionStart else { return }
        interactionStart = nil
        restore(before)
    }
    private func edit(_ change: () -> Void) {
        finishInteraction()
        let before = snapshot
        change()
        record(before)
    }
    private func record(_ before: Snapshot) {
        guard before != snapshot else { return }
        undoStack.append(before)
        // 原型限定历史条数；图片仅保存资源引用，不在每次拖动时复制字节。
        if undoStack.count > 60 { undoStack.removeFirst() }
        redoStack.removeAll()
        changed()
    }
    private func restore(_ state: Snapshot) {
        document = state.document
        if document.layer(selectedID) == nil { selectedID = nil }
    }
    func undo() {
        finishInteraction()
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(snapshot); restore(previous); changed()
    }
    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(snapshot); restore(next); changed()
    }

    private func changed() {
        revision += 1
        document.objects[contentID]?.revision += 1
        saveStatus = "待保存"
        scheduleSave()
    }
    private func scheduleSave() {
        guard !closing else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            guard let self else { return }
            do { try await self.save() } catch { self.errorMessage = error.localizedDescription }
        }
    }
    func save() async throws {
        guard !closing, !childOpen else { return }
        let state = snapshot
        let savingRevision = revision
        saveStatus = "保存中…"
        do {
            if isRoot { try await store.save(state.document) }
            else { try await store.saveDraft(state.document, contentID: contentID, baseRevision: baseRevision) }
            if savingRevision == revision { saveStatus = "已保存" }
        } catch {
            saveStatus = "保存失败"; throw error
        }
    }
    func close() async -> Bool {
        guard !closing, !busy else { return false }
        busy = true
        defer { busy = false }
        finishInteraction()
        saveTask?.cancel()
        do { try await save(); closing = true; return true }
        catch { errorMessage = error.localizedDescription; return false }
    }

    func select(_ id: UUID?) { finishInteraction(); selectedID = id }

    func previewPosition(_ point: CGPoint) {
        guard let id = selectedID, selected?.locked == false, selected?.kind != .frame else { return }
        document.update(id) { $0.transform.position = point }
    }
    func previewScale(_ value: CGFloat) {
        guard let id = selectedID, selected?.locked == false, selected?.kind != .frame else { return }
        document.update(id) { $0.transform.scale = value }
    }
    func previewAngle(_ value: CGFloat) {
        guard let id = selectedID, selected?.locked == false, selected?.kind != .frame else { return }
        document.update(id) { $0.transform.rotationDegrees = value }
    }
    /// 只替换选定照片的素材；原图与参数随文档保存，整次提交进入一条撤销记录。
    func commitPhotoCrop(layerID: UUID, image: UIImage, parameters: ImageCropParameters) async -> Bool {
        guard !busy, let layer = document.layer(layerID), !layer.locked,
              let sourceID = layer.assetID, parameters.isValid else { return false }
        busy = true
        defer { busy = false }
        do {
            guard let data = image.pngData() else { throw DiaryEditorError.invalidImage.logged() }
            let (asset, preview) = try await store.importImage(data, documentID: document.id)
            var state = layer.photoCrop ?? DiaryPhotoCrop(originalAssetID: sourceID, originalSize: layer.size,
                originalPivot: layer.transform.pivot, originalCrop: layer.crop, parameters: parameters)
            state.parameters = parameters
            images[asset.id] = preview
            edit {
                document.assets[asset.id] = asset
                document.update(layerID) {
                    $0.assetID = asset.id; $0.photoCrop = state; $0.crop = DiaryCrop()
                    // 保持外部位置和宽度；高度跟随输出比例，锚点按比例映射。
                    let height = $0.size.width * asset.pixelSize.height / asset.pixelSize.width
                    $0.transform.pivot.y *= height / $0.size.height
                    $0.size.height = height
                }
            }
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }

    func restoreOriginalPhoto() {
        guard let layer = selected, !layer.locked, let state = layer.photoCrop else { return }
        edit {
            document.update(layer.id) {
                $0.assetID = state.originalAssetID; $0.size = state.originalSize
                $0.transform.pivot = state.originalPivot; $0.crop = state.originalCrop; $0.photoCrop = nil
            }
        }
    }

    func applyCrop(_ crop: DiaryCrop) {
        guard let id = selectedID, selected?.locked == false, selected?.kind != .frame else { return }
        edit { document.update(id) { $0.crop = crop } }
    }
    /// 目标 ID 在打开弹窗时固定，避免提交时修改其他选中层。
    func applyTextEdit(targetID: UUID?, text: String, fontSize: CGFloat, font: DiaryFontReference?) -> Bool {
        guard !busy, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              fontSize.isFinite, (1...300).contains(fontSize) else { return false }
        if let targetID {
            guard let layer = scopeLayers.first(where: { $0.id == targetID }), layer.kind == .text, !layer.locked else {
                errorMessage = "文字图层已不可编辑"; return false
            }
            edit { document.update(targetID) { $0.text = text; $0.fontSize = fontSize; $0.font = font } }
        } else {
            let layer = DiaryLayer(name: "文字", kind: .text,
                transform: DiaryTransform(position: scopeCenter, pivot: CGPoint(x: 200, y: 0)),
                size: CGSize(width: 400, height: 60), text: text, fontSize: fontSize, font: font)
            edit { document.appendObject(containing: layer, to: contentID); selectedID = layer.id }
        }
        return true
    }

    func applyText(_ text: String, fontSize: CGFloat) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if let layer = selected, layer.kind == .text {
            edit { document.update(layer.id) { $0.text = text; $0.fontSize = fontSize } }
        } else {
            let center = scopeCenter
            let layer = DiaryLayer(name: "文字", kind: .text,
                                   transform: DiaryTransform(position: center, pivot: CGPoint(x: 200, y: 0)),
                                   size: CGSize(width: 400, height: 60), text: text, fontSize: fontSize)
            edit { document.appendObject(containing: layer, to: contentID); selectedID = layer.id }
        }
    }
    var scopeCenter: CGPoint { CGPoint(x: content.referenceSize.width / 2, y: content.referenceSize.height / 2) }

    @discardableResult
    func importPhoto(_ data: Data, replacing: UUID? = nil, asSticker: Bool = false, stickerName: String = "贴纸") async -> Bool {
        guard !busy else { return false }
        busy = true
        defer { busy = false }
        do {
            let (asset, image) = try await store.importImage(data, documentID: document.id)
            guard replacing == nil || document.layer(replacing) != nil else { return false }
            images[asset.id] = image
            edit {
                document.assets[asset.id] = asset
                if let replacing {
                    document.update(replacing) { $0.assetID = asset.id; $0.crop = DiaryCrop(); $0.photoCrop = nil }
                } else if asSticker {
                    let edge = min(240, min(content.referenceSize.width, content.referenceSize.height) * 0.25)
                    let ratio = edge / max(asset.pixelSize.width, asset.pixelSize.height)
                    let size = CGSize(width: asset.pixelSize.width * ratio, height: asset.pixelSize.height * ratio)
                    let center = scopeCenter
                    let sticker = DiaryLayer(name: stickerName, kind: .sticker,
                                             transform: DiaryTransform(position: center, pivot: CGPoint(x: size.width / 2, y: size.height / 2)),
                                             size: size, assetID: asset.id)
                    document.appendObject(containing: sticker, to: contentID); selectedID = sticker.id
                } else {
                    let photo = DiaryLayer.photo(asset: asset, center: scopeCenter)
                    document.appendObject(containing: photo, to: contentID); selectedID = photo.id
                }
            }
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }

    func addSticker(symbol: String) async {
        let format = UIGraphicsImageRendererFormat(); format.scale = 2; format.opaque = false
        let image = UIGraphicsImageRenderer(size: CGSize(width: 160, height: 160), format: format).image { _ in
            UIImage(systemName: symbol)?.withTintColor(.systemPink, renderingMode: .alwaysOriginal)
                .draw(in: CGRect(x: 10, y: 10, width: 140, height: 140))
        }
        if let data = image.pngData() { await importPhoto(data, asSticker: true) }
    }

    func removeSelected() {
        guard let layer = selected, !layer.locked, layer.id != content.primaryLayerID else { return }
        edit { document.objects[contentID]?.layers.removeAll { $0.id == layer.id || $0.frameTargetID == layer.id }; selectedID = nil }
    }
    func reorderSelected(forward: Bool) {
        guard let id = selectedID, selected?.locked == false, selected?.kind != .frame else { return }
        edit {
            func reorder(_ nodes: inout [DiaryLayer]) {
                guard let index = nodes.firstIndex(where: { $0.id == id }) else { return }
                let target = index + (forward ? 1 : -1)
                guard nodes.indices.contains(target) else { return }
                nodes.swapAt(index, target)
            }
            reorder(&document.objects[contentID]!.layers)
        }
    }
    func toggleVisibility(_ id: UUID) { edit { document.update(id) { $0.visible.toggle() } } }
    func toggleLock(_ id: UUID) { edit { document.update(id) { $0.locked.toggle() } } }
    func previewDrawing(_ value: PKDrawing) { document.objects[contentID]?.drawing = value.dataRepresentation() }
    func clearDrawing() { edit { document.objects[contentID]?.drawing = PKDrawing().dataRepresentation() } }
    func export() async -> URL? {
        guard !busy else { return nil }
        finishInteraction(); busy = true
        defer { busy = false }
        let state = snapshot
        do {
            let exportImages = try await store.exportImages(for: state.document)
            return try DiaryPageRenderer.export(state.document, images: exportImages)
        } catch { errorMessage = error.localizedDescription; return nil }
    }
}
