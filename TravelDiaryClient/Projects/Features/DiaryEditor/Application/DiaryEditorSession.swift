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
    private let parentStateBeforeOpen: Snapshot?
    let store: DiaryDocumentStore
    @Published private(set) var document: DiaryDocument {
        didSet { renderGeneration &+= 1; selectedIndex = nil }
    }
    @Published private(set) var images: [UUID: UIImage] {
        didSet {
            renderGeneration &+= 1
            if !applyingImagePlan { imagePlan = [:] }
        }
    }
    // UI 状态不推进渲染代数；撤销也会推进，避免复用历史 revision 后误命中缓存。
    private(set) var renderGeneration: UInt64 = 0
    private var selectedIndex: (id: UUID, index: Int)?
    private var cachedDrawing: (data: Data, value: PKDrawing)?
    var drawing: PKDrawing {
        let data = content.drawing
        if let cachedDrawing, cachedDrawing.data == data { return cachedDrawing.value }
        let value = (try? PKDrawing(data: data)) ?? PKDrawing()
        cachedDrawing = (data, value)
        return value
    }
    @Published var selectedID: UUID?
    @Published var inkMode = false
    @Published var layerMode = false
    @Published var eraser = false
    @Published var errorMessage: String?
    @Published private(set) var saveStatus = "已保存"
    @Published private(set) var busy = false
    @Published private(set) var undoStack: [Snapshot] = []
    @Published private(set) var redoStack: [Snapshot] = []
    private var interactionStart: Snapshot?
    // 原生画布负责实时笔画；提交、切后台或关闭工具时才序列化一次。
    var flushDrawingInteraction: (() -> Void)?
    private var saveTask: Task<Void, Never>?
    private var imageTask: Task<Void, Never>?
    private var imagePlan: [UUID: Int] = [:]
    private var imagePlanAssets: [UUID: DiaryAsset] = [:]
    private var applyingImagePlan = false
    private var revision = 0

    /// 主画布和子对象共享会话类型；子会话持有值拷贝，取消时不会污染父文档。
    init(document: DiaryDocument, images: [UUID: UIImage], store: DiaryDocumentStore,
         contentID: UUID? = nil, parent: DiaryEditorSession? = nil, parentStateBeforeOpen: Snapshot? = nil) {
        self.document = document; self.images = images; self.store = store
        self.contentID = contentID ?? document.rootContentID
        self.parent = parent
        self.parentStateBeforeOpen = parentStateBeforeOpen
        let content = document.objects[self.contentID]!
        baseRevision = content.revision
        let reference = CGRect(origin: .zero, size: content.referenceSize)
        canvasBounds = parent == nil ? reference :
            reference.union(DiaryPageRenderer.objectBounds(content, document: document)).insetBy(dx: -100, dy: -100)
        // 初次进入页面或独立对象时不预选任何图层，避免画布一打开就出现选框。
        selectedID = nil
    }
    var content: DiaryObjectContent { document.objects[contentID]! }
    var isRoot: Bool { parent == nil }
    var selected: DiaryLayer? {
        guard let selectedID else { return nil }
        if let cached = selectedIndex, cached.id == selectedID { return scopeLayers[cached.index] }
        guard let index = scopeLayers.firstIndex(where: { $0.id == selectedID }) else { return nil }
        selectedIndex = (selectedID, index)
        return scopeLayers[index]
    }
    var scopeLayers: [DiaryLayer] { content.layers }
    var snapshot: Snapshot { Snapshot(document: document) }

    func requestEditorImages(longestEdge: CGFloat) {
        let plan = DiaryEditorImageSizing.plan(document, contentID: contentID, longestEdge: longestEdge)
        guard plan != imagePlan || document.assets != imagePlanAssets else { return }
        imagePlan = plan; imagePlanAssets = document.assets
        imageTask?.cancel()
        let state = document, existing = images, store = store
        imageTask = Task { [weak self] in
            do {
                let loaded = try await store.editorImages(for: state, plan: plan, existing: existing)
                try Task.checkCancellation()
                guard let self, self.document.assets == state.assets else { return }
                let changed = loaded.count != self.images.count || loaded.contains { self.images[$0.key] !== $0.value }
                if changed {
                    self.applyingImagePlan = true
                    self.images = loaded
                    self.applyingImagePlan = false
                }
            } catch {
                // 清晰度提升失败保留现有预览；正式保存/导出仍会报告资源错误。
                if !Task.isCancelled { self?.imagePlan = [:] }
            }
        }
    }

    /// 打开新的全屏编辑页面；每一级都复用本类和同一个编辑视图。
    func openObject() -> DiaryEditorSession? {
        guard !childOpen, !closing, let layer = selected, !layer.locked, let target = layer.contentID else { return nil }
        let parentState = snapshot
        finishInteraction()
        saveTask?.cancel()
        childOpen = true
        return DiaryEditorSession(document: document, images: images, store: store, contentID: target,
                                  parent: self, parentStateBeforeOpen: parentState)
    }

    /// 组内贴纸通过铅笔进入自己的智能对象，避免涂鸦落到整张照片组上。
    func openSelectedStickerObject() -> DiaryEditorSession? {
        guard !childOpen, !closing, let selected, selected.kind == .sticker, !selected.locked else { return nil }
        let before = snapshot
        var sticker = selected
        sticker.kind = .object
        sticker.assetID = nil
        let childID = UUID()
        var primary = selected
        primary.id = UUID()
        primary.transform = DiaryTransform(position: selected.transform.pivot, pivot: selected.transform.pivot)
        document.objects[childID] = DiaryObjectContent(role: .sticker, primaryLayerID: primary.id,
            referenceSize: selected.size, layers: [primary])
        document.update(selected.id) { $0 = sticker; $0.contentID = childID }
        childOpen = true
        saveTask?.cancel()
        return DiaryEditorSession(document: document, images: images, store: store, contentID: childID,
                                  parent: self, parentStateBeforeOpen: before)
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
        let before = parentStateBeforeOpen ?? parent.snapshot
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
        if let parent {
            if let parentStateBeforeOpen { parent.document = parentStateBeforeOpen.document }
            parent.childOpen = false
            parent.scheduleSave()
        }
    }
    func setBackground(_ color: DiaryColor?) { edit { document.objects[contentID]?.background = color } }
    func addFrame() {
        guard let layer = selectedEditingLayer, layer.kind == .photo, editableLayer(layer.id) != nil,
              let owner = document.objects.values.first(where: { $0.layers.contains(where: { $0.id == layer.id }) }) else { return }
        if let existing = owner.layers.first(where: { $0.frameTargetID == layer.id }) {
            if owner.id == contentID { select(existing.id) }
            return
        }
        let frame = DiaryLayer(name: "相框", kind: .frame, transform: layer.transform,
                               size: layer.size, frameTargetID: layer.id, frameColor: .white, frameWidth: 20)
        edit {
            document.objects[owner.id]?.layers.append(frame)
            if owner.id == contentID { selectedID = frame.id }
        }
    }

    func updateFrame(_ id: UUID, color: DiaryColor, width: CGFloat) {
        guard editableLayer(id)?.kind == .frame, width.isFinite, (0...100).contains(width) else { return }
        edit { document.update(id) { $0.frameColor = color; $0.frameWidth = width } }
    }

    func setLayerOpacity(_ id: UUID, value: Double) {
        guard editableLayer(id) != nil, value.isFinite else { return }
        edit { document.update(id) { $0.opacity = min(1, max(0, value)) } }
    }

    func flipSelected(horizontal: Bool) {
        guard let layer = selected, !layer.locked, layer.kind != .frame else { return }
        edit {
            document.update(layer.id) {
                if horizontal { $0.transform.flippedHorizontally = !($0.transform.flippedHorizontally ?? false) }
                else { $0.transform.flippedVertically = !($0.transform.flippedVertically ?? false) }
            }
        }
    }

    /// A draft panel commits one operation against the captured target.
    func updatePlacement(_ id: UUID, position: CGPoint, scale: CGFloat, angle: CGFloat) {
        guard let layer = editableLayer(id), layer.kind != .frame,
              position.x.isFinite, position.y.isFinite, scale.isFinite, angle.isFinite,
              (0.05...20).contains(scale) else { return }
        edit { document.update(id) { $0.transform.position = position; $0.transform.scale = scale; $0.transform.rotationDegrees = angle } }
    }

    func restoreOriginalPhoto(_ id: UUID) {
        guard let layer = editableLayer(id), let original = layer.photoCrop else { return }
        edit { document.update(id) {
            $0.assetID = original.originalAssetID; $0.size = original.originalSize
            $0.transform.pivot = original.originalPivot; $0.photoFill = original.originalFill
            $0.crop = original.originalCrop; $0.photoCrop = nil
        } }
    }

    /// 一次拖动/滑块调节只提交一条历史；中间状态实时显示，结束后再自动保存。
    func beginInteraction() { if interactionStart == nil { interactionStart = snapshot } }
    func finishInteraction() {
        flushDrawingInteraction?()
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
        finishInteraction()
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

    func previewOpacity(_ value: Double) {
        guard value.isFinite, let layer = selected, !layer.locked else { return }
        beginInteraction()
        document.update(layer.id) { $0.opacity = min(1, max(0, value)) }
    }

    var canDeleteSelected: Bool {
        guard let layer = selected else { return false }
        return !layer.locked && layer.id != content.primaryLayerID
    }

    func canMoveSelected(forward: Bool) -> Bool {
        guard let layer = selected, !layer.locked, layer.kind != .frame,
              let index = scopeLayers.firstIndex(where: { $0.id == layer.id }) else { return false }
        return scopeLayers.indices.contains(index + (forward ? 1 : -1))
    }

    /// Interactive rail movement previews the stack, but records history only on release.
    func previewLayerOrder(_ id: UUID, to destination: Int) {
        guard let index = scopeLayers.firstIndex(where: { $0.id == id }),
              !scopeLayers[index].locked, scopeLayers[index].kind != .frame,
              scopeLayers.indices.contains(destination), index != destination else { return }
        beginInteraction()
        let layer = document.objects[contentID]!.layers.remove(at: index)
        document.objects[contentID]!.layers.insert(layer, at: destination)
    }

    /// Destination is in the current object's bottom-to-top ordering.
    func moveLayer(_ id: UUID, to destination: Int) {
        guard let index = scopeLayers.firstIndex(where: { $0.id == id }),
              !scopeLayers[index].locked, scopeLayers[index].kind != .frame,
              scopeLayers.indices.contains(destination), index != destination else { return }
        edit {
            let layer = document.objects[contentID]!.layers.remove(at: index)
            document.objects[contentID]!.layers.insert(layer, at: destination)
            selectedID = id
        }
    }

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
        guard !busy, let layer = editableLayer(layerID),
              let sourceID = layer.assetID, parameters.isValid else { return false }
        busy = true
        defer { busy = false }
        do {
            guard let data = image.pngData() else { throw DiaryEditorError.invalidImage.logged() }
            let (asset, preview) = try await store.importImage(data, documentID: document.id)
            var state = layer.photoCrop ?? DiaryPhotoCrop(originalAssetID: sourceID, originalSize: layer.size,
                originalPivot: layer.transform.pivot, originalFill: layer.photoFill, originalCrop: layer.crop, parameters: parameters)
            state.parameters = parameters
            images[asset.id] = preview
            edit {
                document.assets[asset.id] = asset
                document.update(layerID) {
                    $0.assetID = asset.id; $0.photoCrop = state; $0.crop = DiaryCrop(); $0.photoFill = nil
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
                $0.transform.pivot = state.originalPivot; $0.crop = state.originalCrop; $0.photoCrop = nil; $0.photoFill = state.originalFill
            }
        }
    }

    func applyCrop(_ crop: DiaryCrop) {
        guard let id = selectedID, selected?.locked == false, selected?.kind != .frame else { return }
        edit { document.update(id) { $0.crop = crop } }
    }
    /// 目标 ID 在打开弹窗时固定，避免提交时修改其他选中层。
    func applyTextEdit(targetID: UUID?, text: String, fontSize: CGFloat, font: DiaryFontReference?, color: DiaryColor? = nil,
                       alignment: DiaryTextAlignment? = nil, lineHeight: Double? = nil, letterSpacing: Double? = nil) -> Bool {
        guard !busy, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              fontSize.isFinite, (1...300).contains(fontSize) else { return false }
        if let targetID {
            guard let layer = editableLayer(targetID), layer.kind == .text else {
                errorMessage = "文字图层已不可编辑"; return false
            }
            edit { document.update(targetID) {
                $0.text = text; $0.fontSize = fontSize; $0.font = font
                $0.textColor = color ?? $0.textColor; $0.textAlignment = alignment ?? $0.textAlignment
                $0.textLineHeight = lineHeight ?? $0.textLineHeight; $0.textLetterSpacing = letterSpacing ?? $0.textLetterSpacing
            } }
        } else {
            let layer = DiaryLayer(name: "文字", kind: .text,
                transform: DiaryTransform(position: scopeCenter, pivot: CGPoint(x: 200, y: 0)),
                size: CGSize(width: 400, height: 60), text: text, fontSize: fontSize,
                textColor: color, textAlignment: alignment, textLineHeight: lineHeight, textLetterSpacing: letterSpacing, font: font)
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
    /// Insert an editable image at the bottom without changing canvas background or existing layers.
    func importMaterialBackground(_ data: Data, name: String = "背景") async -> Bool {
        guard !busy else { return false }
        busy = true
        defer { busy = false }
        do {
            let (asset, image) = try await store.importImage(data, documentID: document.id)
            let size = content.referenceSize
            let ratio = min(size.width / asset.pixelSize.width, size.height / asset.pixelSize.height)
            let fitted = CGSize(width: asset.pixelSize.width * ratio, height: asset.pixelSize.height * ratio)
            var layer = DiaryLayer(name: name, kind: .sticker,
                transform: DiaryTransform(position: CGPoint(x: size.width / 2, y: size.height / 2), pivot: CGPoint(x: fitted.width / 2, y: fitted.height / 2)),
                size: fitted, assetID: asset.id)
            layer.semanticKind = .background; layer.isLibraryBackground = true
            images[asset.id] = image
            edit {
                document.assets[asset.id] = asset
                document.objects[contentID]?.layers.insert(layer, at: 0)
                selectedID = layer.id
            }
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }

    func importPhoto(_ data: Data, replacing: UUID? = nil, asSticker: Bool = false, stickerName: String = "贴纸", semanticKind: DiaryLayerSemanticKind? = nil) async -> Bool {
        guard !busy else { return false }
        busy = true
        defer { busy = false }
        do {
            let (asset, image) = try await store.importImage(data, documentID: document.id)
            if let replacing {
                guard let target = editableLayer(replacing), target.assetID != nil,
                      target.kind == .photo || target.kind == .sticker else { return false }
            }
            images[asset.id] = image
            edit {
                document.assets[asset.id] = asset
                if let replacing {
                    document.update(replacing) { $0.assetID = asset.id; $0.crop = DiaryCrop(); $0.photoCrop = nil }
                } else if asSticker {
                    // Use the active canvas coordinate space, including nested object editing.
                    // Fit within 40% of each dimension so tall/wide stickers remain usable.
                    let canvas = content.referenceSize
                    let ratio = min(canvas.width * 0.4 / asset.pixelSize.width,
                                    canvas.height * 0.4 / asset.pixelSize.height)
                    let size = CGSize(width: asset.pixelSize.width * ratio, height: asset.pixelSize.height * ratio)
                    let center = scopeCenter
                    var sticker = DiaryLayer(name: stickerName, kind: .sticker,
                                             transform: DiaryTransform(position: center, pivot: CGPoint(x: size.width / 2, y: size.height / 2)),
                                             size: size, assetID: asset.id)
                    sticker.semanticKind = semanticKind
                    if semanticKind == .text { sticker.category = .textImage }
                    document.appendObject(containing: sticker, to: contentID); selectedID = sticker.id
                } else {
                    let photo = DiaryLayer.photo(asset: asset, center: scopeCenter)
                    document.appendObject(containing: photo, to: contentID); selectedID = photo.id
                }
            }
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }

    /// 当前页批量替换是一个编辑命令；完成后一次撤销恢复全部旧照片。
    func applyPhotoReplacements(_ replacements: [(UUID, DiaryAsset, UIImage, DiaryPhotoPlacement?)], expected: DiaryDocument) -> Bool {
        guard !busy, document == expected else {
            errorMessage = "页面已变化，请重新打开一键替换。"; return false
        }
        edit {
            for (id, asset, image, placement) in replacements {
                images[asset.id] = image
                document.replacePhoto(id, with: asset, placement: placement)
            }
        }
        return true
    }

    func addSticker(symbol: String) async {
        let format = UIGraphicsImageRendererFormat(); format.scale = 2; format.opaque = false
        let image = UIGraphicsImageRenderer(size: CGSize(width: 160, height: 160), format: format).image { _ in
            UIImage(systemName: symbol)?.withTintColor(.systemPink, renderingMode: .alwaysOriginal)
                .draw(in: CGRect(x: 10, y: 10, width: 140, height: 140))
        }
        if let data = image.pngData() { await importPhoto(data, asSticker: true) }
    }

    /// 手柄使用手势开始的完整状态计算，避免每帧累加导致缩放漂移。
    func previewLayer(_ value: DiaryLayer) {
        guard selectedID == value.id, selected?.locked == false else { return }
        document.update(value.id) { $0 = value }
    }

    /// 手势预览留在画布；结束时只提交一次，取消不产生历史或保存。
    func commitTransform(_ value: DiaryLayer) {
        guard let current = selected, current.id == value.id, !current.locked,
              current.kind != .frame, current.transform != value.transform else { return }
        edit {
            guard let index = document.objects[contentID]?.layers.firstIndex(where: { $0.id == value.id }) else { return }
            document.objects[contentID]!.layers[index].transform = value.transform
        }
    }

    /// 复制对象时递归复制内容和内部 ID；图片字节可共享，编辑内容彼此独立。
    func duplicateSelected() {
        guard let source = selected, !source.locked, source.kind != .frame else { return }
        let linkedFrames = content.layers.filter { $0.frameTargetID == source.id }
        guard content.layers.count + 1 + linkedFrames.count <= 200 else {
            errorMessage = "当前对象的图层数量已达上限。"; return
        }
        edit {
            @MainActor func clone(_ original: DiaryLayer) -> DiaryLayer {
                var copy = original
                copy.id = UUID()
                if let contentID = original.contentID, var object = document.objects[contentID] {
                    object.id = UUID()
                    var mapping: [UUID: UUID] = [:]
                    object.layers = object.layers.map { layer in
                        let result = clone(layer); mapping[layer.id] = result.id; return result
                    }
                    for index in object.layers.indices {
                        if let target = object.layers[index].frameTargetID {
                            object.layers[index].frameTargetID = mapping[target]
                        }
                    }
                    object.primaryLayerID = object.primaryLayerID.flatMap { mapping[$0] }
                    document.objects[object.id] = object
                    copy.contentID = object.id
                }
                return copy
            }
            var copy = clone(source)
            copy.name += " 副本"
            copy.transform.position.x += 24; copy.transform.position.y += 24
            let index = content.layers.firstIndex { $0.id == source.id } ?? 0
            var copies = [copy]
            for frame in linkedFrames {
                var duplicate = frame
                duplicate.id = UUID(); duplicate.frameTargetID = copy.id
                copies.append(duplicate)
            }
            document.objects[contentID]?.layers.insert(contentsOf: copies, at: index + 1)
            selectedID = copy.id
        }
    }

    struct ManagedPhoto: Identifiable {
        let layer: DiaryLayer
        let ownerID: UUID
        let locked: Bool
        let visible: Bool
        var id: UUID { layer.id }
    }

    /// 从当前编辑范围递归展示照片，包含隐藏和锁定的组合。
    var managedPhotos: [ManagedPhoto] {
        var result: [ManagedPhoto] = []
        var visited = Set<UUID>()
        func visit(_ id: UUID, locked: Bool, visible: Bool) {
            guard visited.insert(id).inserted, let object = document.objects[id] else { return }
            for layer in object.layers {
                let protected = locked || layer.locked
                let shown = visible && layer.visible
                if layer.kind == .photo {
                    result.append(ManagedPhoto(layer: layer, ownerID: id, locked: protected, visible: shown))
                } else if let child = layer.contentID {
                    visit(child, locked: protected, visible: shown)
                }
            }
        }
        visit(contentID, locked: false, visible: true)
        return result
    }

    func removePhoto(_ id: UUID) {
        guard !busy, let photo = managedPhotos.first(where: { $0.id == id }), !photo.locked else { return }
        edit {
            document.objects[photo.ownerID]?.layers.removeAll { $0.id == id || $0.frameTargetID == id }
            if document.objects[photo.ownerID]?.primaryLayerID == id {
                document.objects[photo.ownerID]?.primaryLayerID = nil
            }
            if photo.ownerID != contentID { document.objects[photo.ownerID]?.revision += 1 }
            if selectedID == id { selectedID = nil }
        }
    }

    func removeSelected() {
        guard let layer = selected, !layer.locked, layer.id != content.primaryLayerID else { return }
        let index = scopeLayers.firstIndex(where: { $0.id == layer.id }) ?? 0
        edit {
            document.objects[contentID]?.layers.removeAll { $0.id == layer.id || $0.frameTargetID == layer.id }
            let remaining = scopeLayers
            selectedID = layerMode && !remaining.isEmpty ? remaining[min(index, remaining.count - 1)].id : nil
        }
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
