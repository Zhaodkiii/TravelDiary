import UIKit
import CryptoKit

/// 阅读专用派生图。永远不写回可编辑文档；内容寻址支持旧版本、撤销和并发读取。
@MainActor enum DiaryPhotoComposite {
    private nonisolated static let encodingQueue = DispatchQueue(label: "TravelDiary.PhotoCompositeEncoding", qos: .utility)

    static func prepare(_ source: DiaryDocumentStore.Loaded, store: DiaryDocumentStore) async -> DiaryDocumentStore.Loaded {
        var document = source.document
        var images = source.images
        for content in source.document.objects.values {
            var layers = content.layers
            for photo in content.layers where photo.isContentPhoto && photo.visible && photo.contentID == nil {
                let frames = content.layers.filter { $0.isPhotoFrame && $0.frameTargetID == photo.id && $0.visible }
                guard !frames.isEmpty, let index = layers.firstIndex(where: { $0.id == photo.id }),
                      index + frames.count < layers.count,
                      Array(layers[(index + 1)...(index + frames.count)].map(\.id)) == frames.map(\.id),
                      ([photo] + frames).allSatisfy({ ($0.blendMode ?? .normal) == .normal }),
                      photo.assetID.flatMap({ images[$0] }) != nil,
                      frames.allSatisfy({ $0.assetID == nil || images[$0.assetID!] != nil }) else { continue }
                // 烘焙局部坐标，摆放、翻转、透视留给外层绘制。
                var local = photo
                local.transform = DiaryTransform(position: .zero, pivot: .zero)
                var locals = [local] + frames
                for i in 1..<locals.count { locals[i].transform = local.transform }
                let rect = locals.reduce(CGRect.null) { $0.union(DiaryPageRenderer.bounds($1, document: source.document, siblings: locals)) }
                guard !rect.isNull, rect.width.isFinite, rect.height.isFinite, rect.width > 0, rect.height > 0 else { continue }
                let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
                guard let encoded = try? encoder.encode(locals) else { continue }
                let key = SHA256.hash(data: Data("photo-composite-v1-1800".utf8) + encoded).map { String(format: "%02x", $0) }.joined()
                var image = await store.readPhotoComposite(key, documentID: document.id)
                if image == nil {
                    let format = UIGraphicsImageRendererFormat(); format.opaque = false
                    format.scale = min(1800 / max(rect.width, rect.height), sqrt(4_000_000 / (rect.width * rect.height)))
                    let rendered = UIGraphicsImageRenderer(size: rect.size, format: format).image { output in
                        output.cgContext.translateBy(x: -rect.minX, y: -rect.minY)
                        for layer in locals {
                            DiaryPageRenderer.drawHitLayer(layer, document: source.document, siblings: locals, images: source.images, in: output.cgContext)
                        }
                    }
                    image = rendered
                    let data: Data? = await withCheckedContinuation { continuation in
                        encodingQueue.async {
                            continuation.resume(returning: autoreleasepool { rendered.pngData() })
                        }
                    }
                    if let data { await store.writePhotoComposite(data, key: key, documentID: document.id) }
                }
                guard let image else { continue }
                let id = UUID()
                images[id] = image
                document.assets[id] = DiaryAsset(id: id, path: "derived/photo-composites/\(key).png", pixelSize: image.size)
                var baked = photo
                baked.kind = .sticker
                baked.semanticKind = photo.semanticKind ?? (photo.isLibraryBackground == true ? .background : .photo)
                baked.assetID = id; baked.opacity = nil; baked.photoFill = true
                baked.photoSlot = nil; baked.photoPlacement = nil; baked.photoCrop = nil
                baked.crop = DiaryCrop(); baked.displayBounds = rect
                layers[index] = baked
                layers.removeAll { layer in frames.contains { $0.id == layer.id } }
            }
            document.objects[content.id]?.layers = layers
        }
        return DiaryDocumentStore.Loaded(document: document, images: images)
    }
}
