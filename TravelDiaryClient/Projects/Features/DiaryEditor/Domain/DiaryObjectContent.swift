import Foundation
import CoreGraphics

/// 可序列化颜色，避免把 SwiftUI.Color / UIColor 写入文件协议。
nonisolated struct DiaryColor: Codable, Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double = 1
    static let paper = DiaryColor(red: 1, green: 0.973, blue: 0.933)
    static let yellow = DiaryColor(red: 1, green: 0.91, blue: 0.58)
    static let pink = DiaryColor(red: 1, green: 0.82, blue: 0.86)
    static let mint = DiaryColor(red: 0.77, green: 0.94, blue: 0.86)
    static let white = DiaryColor(red: 1, green: 1, blue: 1)
    static let brown = DiaryColor(red: 0.40, green: 0.24, blue: 0.12)
}

/// 智能对象内部的独立文档。外部位置/角度放在页面图层中，内部编辑绝不改写外部变换。
nonisolated struct DiaryObjectContent: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var revision = 1
    var role: DiaryLayer.Kind
    var primaryLayerID: UUID? = nil
    var referenceSize: CGSize
    var background: DiaryColor?
    var layers: [DiaryLayer]
    /// Optional template-authored photo area in this object's local canvas coordinates.
    var photoLayoutRegion: CGRect? = nil
    /// 运行时绘画字节；正式存档单独写 .drawing，不把二进制塞进内容 JSON。
    var drawing = Data()

    private enum CodingKeys: String, CodingKey {
        case id, revision, role, primaryLayerID, referenceSize, background, layers, photoLayoutRegion
    }
}

extension DiaryDocument {
    /// 每层都使用相同的对象工厂。外部摆放留在实例中，内部主内容回到本地坐标。
    @discardableResult
    nonisolated mutating func appendObject(containing layer: DiaryLayer, to destination: UUID? = nil) -> UUID {
        let parentID = destination ?? rootContentID
        var primary = layer
        primary.id = UUID(); primary.visible = true; primary.locked = false; primary.opacity = nil
        primary.transform = DiaryTransform(position: layer.transform.pivot, pivot: layer.transform.pivot)
        let content = DiaryObjectContent(role: layer.kind, primaryLayerID: primary.id,
                                         referenceSize: layer.size, layers: [primary])
        let object = DiaryLayer(id: layer.id, name: layer.name, kind: .object,
                                transform: layer.transform, size: layer.size, contentID: content.id,
                                visible: layer.visible, locked: layer.locked, opacity: layer.opacity)
        objects[content.id] = content
        objects[parentID]?.layers.append(object)
        return object.id
    }
}
