import Foundation
import CoreGraphics

/// 素材预览按当前编辑范围的屏幕占用分配像素，总解码预算约 40 MiB。
/// 隐藏/范围外素材保留小预览，显示或进入对象时由后台队列提升清晰度。
nonisolated enum DiaryEditorImageSizing {
    static func plan(_ document: DiaryDocument, contentID: UUID, longestEdge: CGFloat,
                     maximumDimension: CGFloat = 1800, pixelBudget: CGFloat = 40 * 1024 * 1024 / 4) -> [UUID: Int] {
        guard let content = document.objects[contentID] else { return [:] }
        let viewportScale = max(0.01, longestEdge / max(1, max(content.referenceSize.width, content.referenceSize.height)))
        var requested: [UUID: CGFloat] = [:]
        for object in document.objects.values {
            for layer in object.layers {
                for id in layer.referencedAssetIDs { requested[id] = 96 }
            }
        }
        var visited = Set<UUID>()
        func visit(_ id: UUID, parent: CGAffineTransform) {
            guard visited.insert(id).inserted, let object = document.objects[id] else { return }
            for layer in object.layers where layer.visible {
                let matrix = layer.transform.matrix.concatenating(parent)
                if let child = layer.contentID { visit(child, parent: matrix) }
                guard let assetID = layer.assetID, let asset = document.assets[assetID] else { continue }
                var size = layer.size
                if layer.kind == .photo && layer.photoFill != true {
                    size = layer.crop.imageRect(source: asset.pixelSize, frame: layer.size).size
                } else if let placement = layer.photoPlacement, layer.photoFill == true {
                    let frame = layer.displayBounds?.size ?? layer.size
                    size = CGSize(width: frame.width * placement.size.width, height: frame.height * placement.size.height)
                }
                let pixels = max(size.width * hypot(matrix.a, matrix.b), size.height * hypot(matrix.c, matrix.d)) * viewportScale
                requested[assetID] = max(requested[assetID] ?? 96, min(maximumDimension, pixels))
            }
        }
        visit(contentID, parent: .identity)
        var area: CGFloat = 0
        for (id, edge) in requested {
            guard let size = document.assets[id]?.pixelSize else { continue }
            let scale = min(1, edge / max(1, max(size.width, size.height)))
            area += size.width * size.height * scale * scale
        }
        let reduction = min(1, sqrt(pixelBudget / max(1, area)))
        return requested.mapValues { max(64, Int(($0 * reduction / 32).rounded(.down)) * 32) }
    }
}
