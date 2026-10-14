import SwiftUI
import Combine
import PencilKit

/// 单份打开文档的唯一编辑入口。界面不直接写文件，所有修改先进入统一历史再触发保存。
@MainActor
final class DiaryEditorSession: ObservableObject, Identifiable {
    struct Snapshot: Equatable {
        var document: DiaryDocument
        var ink: Data
    }
    let id: UUID
    let store: DiaryDocumentStore
    @Published private(set) var document: DiaryDocument
    @Published private(set) var images: [UUID: UIImage]
    @Published private(set) var drawing: PKDrawing
    @Published var selectedID: UUID?
    @Published var groupID: UUID?
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

    init(document: DiaryDocument, images: [UUID: UIImage], drawing: PKDrawing = PKDrawing(), store: DiaryDocumentStore) {
        self.id = document.id
        self.document = document
        self.images = images
        self.drawing = drawing
        self.store = store
        selectedID = document.page.layers.first?.id
    }

    var selected: DiaryLayer? { document.layer(selectedID) }
    var scopeLayers: [DiaryLayer] { document.layer(groupID)?.children ?? document.page.layers }
    var parentMatrix: CGAffineTransform { document.layer(groupID)?.transform.matrix ?? .identity }
    var snapshot: Snapshot { Snapshot(document: document, ink: drawing.dataRepresentation()) }

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
        drawing = (try? PKDrawing(data: state.ink)) ?? PKDrawing()
        if document.layer(groupID) == nil { groupID = nil }
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
        saveStatus = "待保存"
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            guard let self else { return }
            do { try await self.save() } catch { self.errorMessage = error.localizedDescription }
        }
    }
    func save() async throws {
        let state = snapshot
        let savingRevision = revision
        saveStatus = "保存中…"
        do {
            try await store.save(state.document, drawing: state.ink)
            if savingRevision == revision { saveStatus = "已保存" }
        } catch {
            saveStatus = "保存失败"; throw error
        }
    }
    func close() async -> Bool {
        finishInteraction()
        saveTask?.cancel()
        do { try await save(); return true }
        catch { errorMessage = error.localizedDescription; return false }
    }

    func enterGroup() {
        guard selected?.kind == .group else { return }
        groupID = selectedID; selectedID = nil
    }
    func leaveGroup() { finishInteraction(); selectedID = groupID; groupID = nil }
    func select(_ id: UUID?) { finishInteraction(); selectedID = id }

    func previewPosition(_ point: CGPoint) {
        guard let id = selectedID else { return }
        document.update(id) { $0.transform.position = point }
    }
    func previewScale(_ value: CGFloat) {
        guard let id = selectedID else { return }
        document.update(id) { $0.transform.scale = value }
    }
    func previewAngle(_ value: CGFloat) {
        guard let id = selectedID else { return }
        document.update(id) { $0.transform.rotationDegrees = value }
    }
    func applyCrop(_ crop: DiaryCrop) {
        guard let id = selectedID else { return }
        edit { document.update(id) { $0.crop = crop } }
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
            edit { document.editLayers(in: groupID) { $0.append(layer) }; selectedID = layer.id }
        }
    }
    var scopeCenter: CGPoint {
        if let group = document.layer(groupID) { return group.transform.pivot }
        return CGPoint(x: 500, y: 700)
    }

    func importPhoto(_ data: Data, replacing: UUID? = nil, asSticker: Bool = false) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        let targetGroup = groupID
        do {
            let (asset, image) = try await store.importImage(data, documentID: id)
            guard replacing == nil || document.layer(replacing) != nil else { return }
            images[asset.id] = image
            edit {
                document.assets[asset.id] = asset
                if let replacing {
                    document.update(replacing) { $0.assetID = asset.id; $0.crop = DiaryCrop() }
                } else if asSticker {
                    let size = CGSize(width: 180, height: 180 * asset.pixelSize.height / asset.pixelSize.width)
                    let center = document.layer(targetGroup)?.transform.pivot ?? CGPoint(x: 500, y: 700)
                    let sticker = DiaryLayer(name: "贴纸", kind: .sticker,
                                             transform: DiaryTransform(position: center, pivot: CGPoint(x: size.width / 2, y: size.height / 2)),
                                             size: size, assetID: asset.id)
                    document.editLayers(in: targetGroup) { $0.append(sticker) }; selectedID = sticker.id
                } else {
                    let group = DiaryLayer.photoGroup(asset: asset)
                    document.page.layers.append(group); groupID = nil; selectedID = group.id
                }
            }
        } catch { errorMessage = error.localizedDescription }
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
        guard let layer = selected, layer.kind != .photo else { return }
        edit { document.editLayers(in: groupID) { $0.removeAll { $0.id == layer.id } }; selectedID = nil }
    }
    func reorderSelected(forward: Bool) {
        guard let id = selectedID else { return }
        edit {
            document.editLayers(in: groupID) { nodes in
                guard let index = nodes.firstIndex(where: { $0.id == id }) else { return }
                let target = index + (forward ? 1 : -1)
                guard nodes.indices.contains(target) else { return }
                nodes.swapAt(index, target)
            }
        }
    }
    func toggleVisibility(_ id: UUID) { edit { document.update(id) { $0.visible.toggle() } } }
    func toggleLock(_ id: UUID) { edit { document.update(id) { $0.locked.toggle() } } }
    func previewDrawing(_ value: PKDrawing) { drawing = value }
    func clearDrawing() { edit { drawing = PKDrawing() } }
    func export() async -> URL? {
        guard !busy else { return nil }
        finishInteraction(); busy = true
        defer { busy = false }
        let state = snapshot
        do {
            let exportImages = try await store.exportImages(for: state.document)
            return try DiaryPageRenderer.export(state.document, images: exportImages,
                                                drawing: PKDrawing(data: state.ink))
        } catch { errorMessage = error.localizedDescription; return nil }
    }
}
