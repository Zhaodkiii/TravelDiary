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

    /// 先移到锚点，再缩放旋转，最后放到父坐标；不能保存屏幕拖动像素作为位置。
    var matrix: CGAffineTransform {
        CGAffineTransform(translationX: position.x, y: position.y)
            .rotated(by: rotationDegrees * .pi / 180)
            .scaledBy(x: scale, y: scale)
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
    var assetID: UUID?
    var contentID: UUID?
    var frameTargetID: UUID?
    var frameColor: DiaryColor?
    var frameWidth: CGFloat?
    var text = ""
    var fontSize: CGFloat = 36
    var font: DiaryFontReference?
    var photoCrop: DiaryPhotoCrop?
    var crop = DiaryCrop()
    var visible = true
    var locked = false
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

nonisolated enum DiaryBlendMode: String, Codable, Sendable {
    case normal, multiply, darken, linearBurn, lighten
}

extension DiaryDocument {
    func layer(_ id: UUID?) -> DiaryLayer? {
        guard let id else { return nil }
        return objects.values.lazy.compactMap { $0.layers.first { $0.id == id } }.first
    }

    /// 稳定 ID 定位，不将数组下标当作图层身份。
    mutating func update(_ id: UUID, _ mutation: (inout DiaryLayer) -> Void) {
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
    var originalCrop: DiaryCrop
    var parameters: ImageCropParameters
}

extension DiaryLayer {
    nonisolated var referencedAssetIDs: [UUID] { [assetID, photoCrop?.originalAssetID].compactMap { $0 } }
}
