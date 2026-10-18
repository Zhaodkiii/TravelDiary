import Foundation

/// UI capabilities are resolved from content, not the wrapper's `.object` kind or its display name.
nonisolated enum DiaryLayerEditingKind: Equatable {
    case photo, text, textImage, sticker, paper, background, frame, group
}

extension DiaryEditorSession {
    var selectedEditingLayer: DiaryLayer? {
        guard var layer = selected else { return nil }
        var visited = Set<UUID>()
        while let id = layer.contentID, visited.insert(id).inserted,
              let object = document.objects[id], object.layers.count == 1,
              object.drawing.isEmpty, object.background == nil,
              let primary = object.layers.first, primary.kind != .frame {
            layer = primary
        }
        return layer
    }

    var selectedEditingKind: DiaryLayerEditingKind? {
        guard let outer = selected, let layer = selectedEditingLayer else { return nil }
        if outer.semanticKind == .background || outer.isLibraryBackground == true || layer.semanticKind == .background { return .background }
        if layer.contentID != nil { return .group }
        if layer.kind == .frame { return .frame }
        if layer.kind == .text { return .text }
        if layer.category == .textImage || layer.semanticKind == .text || outer.category == .textImage || outer.semanticKind == .text { return .textImage }
        if layer.semanticKind == .paper || outer.semanticKind == .paper { return .paper }
        if layer.kind == .photo { return .photo }
        return .sticker
    }

    /// A semantic background may itself be an object; replace an actual image leaf.
    var selectedMaterialLayer: DiaryLayer? {
        guard let selected, !selected.locked else { return nil }
        var visited = Set<UUID>()
        func resolve(_ layer: DiaryLayer) -> DiaryLayer? {
            guard !layer.locked else { return nil }
            if layer.assetID != nil, layer.contentID == nil { return layer }
            guard let id = layer.contentID, visited.insert(id).inserted, let content = document.objects[id] else { return nil }
            let candidates = content.layers.sorted {
                ($0.id == content.primaryLayerID ? 0 : $0.semanticKind == .background ? 1 : 2)
                < ($1.id == content.primaryLayerID ? 0 : $1.semanticKind == .background ? 1 : 2)
            }
            for candidate in candidates { if let found = resolve(candidate) { return found } }
            return nil
        }
        return resolve(selected)
    }

    /// All ancestors participate in lock checks; IDs are scoped to this editor.
    func editableLayer(_ id: UUID) -> DiaryLayer? {
        var visited = Set<UUID>()
        func find(_ content: UUID) -> DiaryLayer? {
            guard visited.insert(content).inserted, let object = document.objects[content] else { return nil }
            for layer in object.layers where !layer.locked {
                if layer.id == id { return layer }
                if let child = layer.contentID, let found = find(child) { return found }
            }
            return nil
        }
        return find(contentID)
    }

    var selectedPhotos: [DiaryLayer] {
        guard let selected, !selected.locked else { return [] }
        var result: [DiaryLayer] = []
        var visited = Set<UUID>()
        func collect(_ layer: DiaryLayer) {
            guard !layer.locked else { return }
            if layer.kind == .photo { result.append(layer) }
            if let id = layer.contentID, visited.insert(id).inserted, let object = document.objects[id] {
                object.layers.forEach(collect)
            }
        }
        collect(selected)
        return result
    }
}

/// Stable tool ordering shared by the toolbar and capability tests.
nonisolated enum DiaryContextAction: String, Identifiable {
    case background, layers, replacePhoto, crop, frame, opacity, arrange
    case editText, font, fontSize, textColor, typography, replaceMaterial, flip
    case replaceBackground, placement, lock, unlock, frameColor, frameWidth, editContent
    var id: Self { self }
    var title: String {
        switch self {
        case .background: "背景"
        case .layers: "图层"
        case .replacePhoto, .replaceMaterial: "替换"
        case .crop: "裁剪"
        case .frame: "相框"
        case .opacity: "透明度"
        case .arrange: "排列"
        case .editText: "编辑文字"
        case .font: "字体"
        case .fontSize: "字号"
        case .textColor: "颜色"
        case .typography: "排版"
        case .flip: "翻转"
        case .replaceBackground: "替换背景"
        case .placement: "位置与大小"
        case .lock: "锁定"
        case .unlock: "解锁"
        case .frameColor: "边框颜色"
        case .frameWidth: "边框粗细"
        case .editContent: "编辑内容"
        }
    }
    var symbol: String {
        switch self {
        case .background, .replaceBackground: "photo.fill"
        case .layers, .arrange: "square.3.layers.3d"
        case .replacePhoto, .replaceMaterial: "arrow.triangle.2.circlepath"
        case .crop: "crop"
        case .frame, .frameWidth: "square.dashed"
        case .opacity: "circle.lefthalf.filled"
        case .editText: "square.and.pencil"
        case .font: "textformat"
        case .fontSize: "textformat.size"
        case .textColor, .frameColor: "paintpalette"
        case .typography: "text.alignleft"
        case .flip: "arrow.left.and.right.righttriangle.left.righttriangle.right"
        case .placement: "arrow.up.left.and.arrow.down.right"
        case .lock: "lock"
        case .unlock: "lock.open"
        case .editContent: "square.stack.3d.up"
        }
    }
}

extension DiaryEditorSession {
    var contextActions: [DiaryContextAction] {
        guard let selected else { return [.background, .layers] }
        guard !selected.locked else { return [.unlock, .layers] }
        switch selectedEditingKind {
        case .photo: return [.replacePhoto, .crop, .frame, .opacity, .arrange]
        case .text: return [.editText, .font, .fontSize, .textColor, .typography]
        case .textImage, .paper: return [.replaceMaterial, .opacity, .arrange]
        case .sticker: return [.replaceMaterial, .flip, .opacity, .arrange]
        case .background: return [.replaceBackground, .placement, .opacity, .lock]
        case .frame: return [.frameColor, .frameWidth, .opacity]
        case .group: return [.editContent] + (selectedPhotos.isEmpty ? [] : [.replacePhoto]) + [.opacity, .arrange]
        case nil: return [.background, .layers]
        }
    }
}
