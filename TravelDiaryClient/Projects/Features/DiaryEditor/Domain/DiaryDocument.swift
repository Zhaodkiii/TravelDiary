import Foundation
import CoreGraphics

/// 可编辑文档只保存排版和资源引用；图片字节、原生视图和屏幕尺寸不进入模型。
nonisolated struct DiaryDocument: Codable, Equatable, Sendable {
    var id = UUID()
    var title = "我的手帐"
    var page = DiaryPage()
    var assets: [UUID: DiaryAsset] = [:]
}

nonisolated struct DiaryPage: Codable, Equatable, Sendable {
    var id = UUID()
    var size = CGSize(width: 1000, height: 1400)
    /// 数组从底到顶绘制；移动层级只改变数组顺序。
    var layers: [DiaryLayer] = []
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

/// 组是唯一有子图层的节点。size 对组只是稳定的初始坐标范围，不用于裁剪装饰。
nonisolated struct DiaryLayer: Codable, Equatable, Identifiable, Sendable {
    nonisolated enum Kind: String, Codable, Sendable { case group, photo, sticker, text }
    var id = UUID()
    var name: String
    var kind: Kind
    var transform: DiaryTransform
    var size: CGSize
    var assetID: UUID?
    var text = ""
    var fontSize: CGFloat = 36
    var crop = DiaryCrop()
    var visible = true
    var locked = false
    var children: [DiaryLayer] = []

    static func photoGroup(asset: DiaryAsset) -> DiaryLayer {
        let factor = min(800 / asset.pixelSize.width, 900 / asset.pixelSize.height)
        let size = CGSize(width: asset.pixelSize.width * factor, height: asset.pixelSize.height * factor)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let photo = DiaryLayer(name: "照片", kind: .photo,
                              transform: DiaryTransform(position: center, pivot: center),
                              size: size, assetID: asset.id)
        return DiaryLayer(name: "照片组合", kind: .group,
                          transform: DiaryTransform(position: CGPoint(x: 500, y: 620), pivot: center),
                          size: size, children: [photo])
    }
}

extension DiaryDocument {
    func layer(_ id: UUID?) -> DiaryLayer? {
        guard let id else { return nil }
        func find(_ nodes: [DiaryLayer]) -> DiaryLayer? {
            for node in nodes {
                if node.id == id { return node }
                if let match = find(node.children) { return match }
            }
            return nil
        }
        return find(page.layers)
    }

    /// 根据稳定 ID 更新节点，不使用会随排序而变化的数组下标作为身份。
    mutating func update(_ id: UUID, _ mutation: (inout DiaryLayer) -> Void) {
        func visit(_ nodes: inout [DiaryLayer]) {
            for index in nodes.indices {
                if nodes[index].id == id { mutation(&nodes[index]); return }
                visit(&nodes[index].children)
            }
        }
        visit(&page.layers)
    }

    mutating func editLayers(in groupID: UUID?, _ mutation: (inout [DiaryLayer]) -> Void) {
        if let groupID { update(groupID) { mutation(&$0.children) } }
        else { mutation(&page.layers) }
    }
}
