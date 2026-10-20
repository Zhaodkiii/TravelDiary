import Foundation
import CoreGraphics

/// 可编辑文档只保存排版和资源引用；图片字节、原生视图和屏幕尺寸不进入模型。
nonisolated struct DiaryDocument: Codable, Equatable, Sendable {
    var id: UUID
    var title: String
    var bookID: UUID? = nil
    var rootContentID: UUID
    var assets: [UUID: DiaryAsset]
    var objects: [UUID: DiaryObjectContent]

    init() {
        id = UUID(); title = "我的手帐"; assets = [:]
        let root = DiaryObjectContent(role: .canvas, referenceSize: DiaryPagePreset.a5.size, layers: [])
        rootContentID = root.id; objects = [root.id: root]
    }

    init(id: UUID, title: String, rootContentID: UUID, assets: [UUID: DiaryAsset], objects: [UUID: DiaryObjectContent], bookID: UUID? = nil) {
        self.id = id; self.title = title; self.rootContentID = rootContentID
        self.assets = assets; self.objects = objects; self.bookID = bookID
    }

    /// 最外层同样是一个对象内容，不再维护另一套页面图层和页面画笔数据。
    var root: DiaryObjectContent { objects[rootContentID]! }
}

nonisolated struct DiaryAsset: Codable, Equatable, Sendable {
    let id: UUID
    let path: String
    /// 已考虑 EXIF 方向后的像素尺寸；解码时也必须应用相同方向。
    let pixelSize: CGSize
}

nonisolated struct DiaryTransform: Codable, Equatable, Sendable {
    var position: CGPoint
    var pivot: CGPoint
    var scale: CGFloat = 1
    var rotationDegrees: CGFloat = 0
    /// 四边手柄的单轴拉伸；旧存档没有此字段时，两轴都按 1 显示。
    var stretch: CGSize? = nil
    var warp: DiaryQuadWarp? = nil
    var flippedHorizontally: Bool? = nil
    var flippedVertically: Bool? = nil
    var stretchX: CGFloat { stretch?.width ?? 1 }
    var stretchY: CGFloat { stretch?.height ?? 1 }

    /// 沿素材自己的坐标轴拉伸，并补偿位置使对边锚点固定；旋转后也成立。
    mutating func stretchAxis(horizontal: Bool, ratio: CGFloat, anchor: CGPoint) {
        let fixed = projection.point(anchor)
        var value = CGSize(width: stretchX, height: stretchY)
        if horizontal { value.width = min(20, max(0.05, value.width * ratio)) }
        else { value.height = min(20, max(0.05, value.height * ratio)) }
        stretch = value
        let moved = projection.point(anchor)
        position.x += fixed.x - moved.x
        position.y += fixed.y - moved.y
    }

    /// 先移到锚点，再缩放旋转，最后放到父坐标；不能保存屏幕拖动像素作为位置。
    var matrix: CGAffineTransform {
        CGAffineTransform(translationX: position.x, y: position.y)
            .rotated(by: rotationDegrees * .pi / 180)
            .scaledBy(x: scale * stretchX * (flippedHorizontally == true ? -1 : 1),
                      y: scale * stretchY * (flippedVertically == true ? -1 : 1))
            .translatedBy(x: -pivot.x, y: -pivot.y)
    }
}

nonisolated struct DiaryCrop: Codable, Equatable, Sendable {
    var zoom: CGFloat = 1
    /// 偏移是外框本地坐标，和图层整体移动分开保存。
    var offset = CGPoint.zero

    func imageRect(source: CGSize, frame: CGSize) -> CGRect {
        let base = max(frame.width / source.width, frame.height / source.height)
        let size = CGSize(width: source.width * base * zoom, height: source.height * base * zoom)
        let dx = max(0, (size.width - frame.width) / 2)
        let dy = max(0, (size.height - frame.height) / 2)
        return CGRect(x: -dx + min(dx, max(-dx, offset.x)),
                      y: -dy + min(dy, max(-dy, offset.y)), width: size.width, height: size.height)
    }
}

/// 页面上的对象实例只保存外部变换，通过 contentID 打开它自己的内容。
/// 普通照片/文字是内容的基础绘制层；用户新增的元素始终包装为独立对象。
nonisolated struct DiaryLayer: Codable, Equatable, Identifiable, Sendable {
    nonisolated enum Kind: String, Codable, Sendable { case canvas, photo, sticker, text, object, frame }
    var id = UUID()
    var name: String
    var kind: Kind
    var transform: DiaryTransform
    var size: CGSize
    /// 文字图片仍使用 sticker 绘制；独立分类供后续递归隐藏文字使用。
    var category: DiaryLayerCategory? = nil
    /// 素材语义分类，与绘制类型 Kind 分开保存。
    var semanticKind: DiaryLayerSemanticKind? = nil
    var subcategory: String? = nil
    var renderType: String? = nil
    var assetID: UUID?
    var contentID: UUID?
    var frameTargetID: UUID?
    var frameColor: DiaryColor?
    var frameWidth: CGFloat?
    /// Normalized transparent opening of a decorative sticker frame.
    var frameOpening: CGRect? = nil
    /// Stable automatic frame choice; its copied image remains the rendering source.
    var photoFrameCatalogID: String? = nil
    /// Stored on the photo too, so a manually removed frame is an intentional choice.
    var photoFrameIsManual: Bool? = nil
    /// Top-level photo objects from a single insertion share a batch for re-layout.
    var photoBatchID: UUID? = nil
    /// 手动调整后的可见边界；旧作品缺省为自动计算，不拉伸对象内部素材。
    var displayBounds: CGRect? = nil
    var text = ""
    var fontSize: CGFloat = 36
    var textAppearance: DiaryTextAppearance? = nil
    var textColor: DiaryColor? = nil
    var textAlignment: DiaryTextAlignment? = nil
    var textLineHeight: Double? = nil
    var textLetterSpacing: Double? = nil
    var font: DiaryFontReference?
    /// true 启用照片槽位映射；没有槽位数据的旧作品保持整图拉伸，nil 保持旧版 cover 取景。
    var photoFill: Bool? = nil
    var photoPlacement: DiaryPhotoPlacement? = nil
    var photoSlot: DiaryPhotoSlot? = nil
    var photoCrop: DiaryPhotoCrop?
    var crop = DiaryCrop()
    var visible = true
    var locked = false
    /// nil keeps older documents fully opaque.
    var opacity: Double? = nil
    var effectiveOpacity: Double { min(1, max(0, opacity ?? 1)) }
    var isLibraryBackground: Bool? = nil
    /// PSD 混合效果。旧作品缺少该字段时按 normal 绘制。
    var blendMode: DiaryBlendMode? = nil
    static func photo(asset: DiaryAsset, center: CGPoint) -> DiaryLayer {
        let factor = min(800 / asset.pixelSize.width, 900 / asset.pixelSize.height)
        let size = CGSize(width: asset.pixelSize.width * factor, height: asset.pixelSize.height * factor)
        return DiaryLayer(name: "照片", kind: .photo,
                          transform: DiaryTransform(position: center, pivot: CGPoint(x: size.width / 2, y: size.height / 2)),
                          size: size, assetID: asset.id)
    }
}

/// 语义分类独立于绘制类型；nil 表示普通图层，不从显示名称推断。
nonisolated enum DiaryLayerCategory: String, Codable, Sendable {
    case textImage
}

nonisolated enum DiaryLayerSemanticKind: String, Codable, CaseIterable, Sendable {
    case background, photo, paper, text, illustration, branding

    /// 模板预览及导入可由用户选择的分类；品牌内容始终保留。
    static let selectablePresetCategories: [Self] = [.background, .photo, .paper, .text, .illustration]

    var title: String {
        switch self {
        case .background: return "背景"
        case .photo: return "照片"
        case .paper: return "纸卡"
        case .text: return "文字"
        case .illustration: return "装饰"
        case .branding: return "品牌"
        }
    }
}

extension DiaryDocument {
    /// 预览与导入使用相同的语义继承规则，混合组合中的独立分类不随父分类被移除。
    nonisolated func hidingPresetCategories(_ hidden: Set<DiaryLayerSemanticKind>) -> DiaryDocument {
        filteringPresetCategories(hidden, removing: false)
    }

    nonisolated func excludingPresetCategories(_ hidden: Set<DiaryLayerSemanticKind>) -> DiaryDocument {
        filteringPresetCategories(hidden, removing: true)
    }

    nonisolated func removingBackgrounds(in contentID: UUID) -> DiaryDocument {
        filteringPresetCategories([.background], removing: true, scopeID: contentID)
    }

    private nonisolated func filteringPresetCategories(_ hidden: Set<DiaryLayerSemanticKind>, removing: Bool,
                                                       scopeID: UUID? = nil) -> DiaryDocument {
        guard !hidden.isEmpty else { return self }
        var copy = self
        var visited = Set<UUID>()
        func category(_ layer: DiaryLayer, inherited: DiaryLayerSemanticKind?) -> DiaryLayerSemanticKind? {
            if let explicit = layer.semanticKind { return explicit }
            if layer.category == .textImage { return .text }
            if layer.isLibraryBackground == true { return .background }
            if let inherited { return inherited }
            // 老包只按明确的绘制类型回退，不从名称猜测素材语义。
            switch layer.kind {
            case .photo, .frame: return .photo
            case .text: return .text
            case .sticker: return .illustration
            case .object, .canvas: return nil
            }
        }
        @discardableResult func visit(_ id: UUID, inherited: DiaryLayerSemanticKind?) -> Bool {
            guard visited.insert(id).inserted, var content = copy.objects[id] else { return false }
            if hidden.contains(inherited ?? .background) { content.background = nil }
            if hidden.contains(inherited ?? .illustration) { content.drawing = Data() }
            var layers: [DiaryLayer] = []
            for var layer in content.layers {
                let kind = category(layer, inherited: inherited)
                if let child = layer.contentID {
                    let hasContent = visit(child, inherited: kind)
                    if removing && !hasContent { continue }
                } else if let kind, hidden.contains(kind) {
                    if removing { continue }
                    layer.visible = false
                }
                layers.append(layer)
            }
            if removing {
                let photoIDs = Set(layers.filter { $0.isContentPhoto }.map(\.id))
                layers.removeAll { ($0.kind == .frame || $0.frameTargetID != nil) && $0.frameTargetID.map { !photoIDs.contains($0) } != false }
                if let primary = content.primaryLayerID, !layers.contains(where: { $0.id == primary }) {
                    content.primaryLayerID = nil; content.role = .canvas
                }
            }
            content.layers = layers
            copy.objects[id] = content
            return !layers.isEmpty || content.background != nil || !content.drawing.isEmpty
        }
        visit(scopeID ?? rootContentID, inherited: nil)
        if removing {
            var reachable = Set<UUID>()
            var assets = Set<UUID>()
            func collect(_ id: UUID) {
                guard reachable.insert(id).inserted, let content = copy.objects[id] else { return }
                for layer in content.layers {
                    assets.formUnion(layer.referencedAssetIDs)
                    if let child = layer.contentID { collect(child) }
                }
            }
            collect(rootContentID)
            copy.objects = copy.objects.filter { reachable.contains($0.key) }
            copy.assets = copy.assets.filter { assets.contains($0.key) }
        }
        return copy
    }
}

nonisolated enum DiaryBlendMode: String, Codable, Sendable {
    case normal, multiply, darken, linearBurn, lighten
}

extension DiaryDocument {
    func layer(_ id: UUID?) -> DiaryLayer? {
        guard let id else { return nil }
        return objects.values.lazy.compactMap { $0.layers.first { $0.id == id } }.first
    }

    /// 稳定 ID 定位，不将数组下标当作图层身份。
    nonisolated mutating func update(_ id: UUID, _ mutation: (inout DiaryLayer) -> Void) {
        for contentID in Array(objects.keys) {
            guard let index = objects[contentID]?.layers.firstIndex(where: { $0.id == id }) else { continue }
            mutation(&objects[contentID]!.layers[index]); return
        }
    }
}

/// 保留裁剪前照片和外框，恢复时不改变组合内的其他图层。
nonisolated struct DiaryPhotoCrop: Codable, Equatable, Sendable {
    var originalAssetID: UUID
    var originalSize: CGSize
    var originalPivot: CGPoint
    var originalFill: Bool? = nil
    var originalCrop: DiaryCrop
    var parameters: ImageCropParameters
}

extension DiaryLayer {
    nonisolated var isPhotoFrame: Bool { kind == .frame || (kind == .photo && subcategory == "frame") }
    nonisolated var isContentPhoto: Bool { kind == .photo && !isPhotoFrame }
    nonisolated var referencedAssetIDs: [UUID] { [assetID, photoCrop?.originalAssetID, photoSlot?.maskAssetID].compactMap { $0 } }
}


extension DiaryDocument {
    /// 顺序固定为页面图层从底到顶、组合深度优先；同一资源的不同实例分别计数。
    /// 隐藏或锁定的整组跳过，避免改动用户明确保护的内容。
    nonisolated func replaceablePhotos() -> [DiaryLayer] {
        var result: [DiaryLayer] = []
        var visited = Set<UUID>()
        func visit(_ id: UUID) {
            guard visited.insert(id).inserted, let content = objects[id] else { return }
            for layer in content.layers where layer.visible && !layer.locked {
                if layer.isContentPhoto { result.append(layer) }
                else if let child = layer.contentID { visit(child) }
            }
        }
        visit(rootContentID)
        return result
    }

    /// 保留原框、锚点、角度、拉伸和层级，仅换资源及其取景方式。
    nonisolated mutating func replacePhoto(_ id: UUID, with asset: DiaryAsset, placement: DiaryPhotoPlacement? = nil, slot: DiaryPhotoSlot? = nil) {
        assets[asset.id] = asset
        update(id) { layer in
            layer.assetID = asset.id
            layer.crop = DiaryCrop(); layer.photoCrop = nil
            layer.photoFill = true
            layer.photoPlacement = placement ?? layer.photoPlacement
            if let slot {
                if layer.photoSlot == nil { layer.photoSlot = slot }
                else { layer.photoSlot?.fill = slot.fill }
            }
        }
    }
}

nonisolated enum DiaryTextAlignment: String, Codable, CaseIterable, Sendable {
    case left, center, right
    var title: String { switch self { case .left: "左对齐"; case .center: "居中"; case .right: "右对齐" } }
}
