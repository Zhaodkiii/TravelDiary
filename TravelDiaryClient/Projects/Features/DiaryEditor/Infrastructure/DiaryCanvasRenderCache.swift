import UIKit
import PencilKit

/// 每个画布独占的保留渲染状态。仅作品代数变化时比较内容，绘制和命中不编码 JSON。
@MainActor
final class DiaryCanvasRenderCache {
    struct ContentStamp: Equatable {
        var content: DiaryObjectContent
        var children: [UUID: UInt64]
        var resources: [UUID: ObjectIdentifier]
        var assets: [UUID: DiaryAsset]
    }
    struct LayerStamp: Equatable {
        var local: DiaryLayer
        var contentVersion: UInt64?
        var resource: ObjectIdentifier?
        var maskResource: ObjectIdentifier?
        var asset: DiaryAsset?
        var frameSize: CGSize?
    }
    private struct Placement: Equatable {
        var id: UUID
        var version: UInt64
        var transform: DiaryTransform
        var visible: Bool
        var blend: DiaryBlendMode?
        var opacity: Double
    }
    private var placements: [Placement] = []
    private var background: DiaryColor?
    private var referenceSize = CGSize.zero
    private(set) var visualVersion: UInt64 = 0
    final class Entry {
        let id: UUID
        var source: DiaryLayer
        var stamp: LayerStamp
        var version: UInt64
        var rect: CGRect
        var image: UIImage?
        var renderedVersion: UInt64 = 0
        var pixelScale: CGFloat = 0
        var requestedScale: CGFloat = 1
        var alpha: [UInt8]?
        var alphaWidth = 0
        var alphaHeight = 0
        init(source: DiaryLayer, stamp: LayerStamp, version: UInt64, rect: CGRect) {
            id = source.id; self.source = source; self.stamp = stamp; self.version = version; self.rect = rect
        }
        var needsRaster: Bool {
            guard rect.width > 0, rect.height > 0, rect.width.isFinite, rect.height.isFinite else { return false }
            return image == nil || renderedVersion != version || abs(pixelScale - requestedScale) > max(0.01, requestedScale * 0.15)
        }
    }
    private var stamps: [UUID: ContentStamp] = [:]
    private var versions: [UUID: UInt64] = [:]
    private var serial: UInt64 = 0
    private(set) var entries: [UUID: Entry] = [:]
    private(set) var ordered: [Entry] = []
    private(set) var document = DiaryDocument()
    private(set) var images: [UUID: UIImage] = [:]
    private(set) var contentID: UUID?
    private(set) var rasterCount = 0
    private(set) var synchronizationCount = 0
    private(set) var drawing = PKDrawing()
    private var drawingData: Data?
    private(set) var inkImage: UIImage?
    private(set) var inkRect = CGRect.zero
    private var inkScale: CGFloat = 0
    private var inkDirty = true
    // 预留独立预算给笔画；对象图片总预算随可见图层面积分配，而非每层固定 1800。
    static let pixelBudget: CGFloat = 24 * 1024 * 1024 / 4

    private func nextVersion() -> UInt64 { serial &+= 1; return serial }

    func synchronize(document: DiaryDocument, images: [UUID: UIImage], contentID: UUID) {
        synchronizationCount += 1
        self.document = document; self.images = images; self.contentID = contentID
        guard let content = document.objects[contentID] else { ordered = []; entries = [:]; return }
        var visited = Set<UUID>()
        @discardableResult func visit(_ id: UUID) -> UInt64 {
            if visited.contains(id) { return versions[id] ?? 0 }
            visited.insert(id)
            guard var object = document.objects[id] else { return 0 }
            var children: [UUID: UInt64] = [:]
            var resources: [UUID: ObjectIdentifier] = [:]
            var assets: [UUID: DiaryAsset] = [:]
            for layer in object.layers {
                if let child = layer.contentID { children[child] = visit(child) }
                for asset in layer.referencedAssetIDs {
                    resources[asset] = images[asset].map(ObjectIdentifier.init)
                    assets[asset] = document.assets[asset]
                }
            }
            // 名称、锁定、存档 revision 不影响像素；子层的变换仍属于父对象内容。
            object.revision = 0
            for i in object.layers.indices { object.layers[i].name = ""; object.layers[i].locked = false }
            let stamp = ContentStamp(content: object, children: children, resources: resources, assets: assets)
            if stamps[id] != stamp { stamps[id] = stamp; versions[id] = nextVersion() }
            return versions[id] ?? 0
        }
        visit(contentID)
        stamps = stamps.filter { visited.contains($0.key) }
        versions = versions.filter { visited.contains($0.key) }
        let siblings = Dictionary(content.layers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var retained: [UUID: Entry] = [:]
        ordered = content.layers.map { layer in
            var local = layer
            local.transform = DiaryTransform(position: .zero, pivot: .zero)
            local.name = ""; local.locked = false; local.visible = true; local.blendMode = .normal; local.opacity = nil
            let stamp = LayerStamp(local: local, contentVersion: layer.contentID.flatMap { versions[$0] },
                resource: layer.assetID.flatMap { images[$0] }.map(ObjectIdentifier.init),
                maskResource: layer.photoSlot?.maskAssetID.flatMap { images[$0] }.map(ObjectIdentifier.init),
                asset: layer.assetID.flatMap { document.assets[$0] },
                frameSize: layer.frameTargetID.flatMap { siblings[$0]?.size })
            let entry: Entry
            if let previous = entries[layer.id], previous.stamp == stamp {
                entry = previous; entry.source = layer
            } else {
                entry = Entry(source: layer, stamp: stamp, version: nextVersion(),
                    rect: DiaryPageRenderer.bounds(layer, document: document, siblings: content.layers))
                // 资源或内容更新时保留同一局部区域的旧位图，待新位图完成后再替换。
                // renderedVersion 仍为 0，因此旧图只作过渡，不会被当成最新内容。
                if let previous = entries[layer.id], previous.rect == entry.rect {
                    entry.image = previous.image
                    entry.pixelScale = previous.pixelScale
                }
            }
            if !layer.visible { entry.image = nil; entry.alpha = nil }
            retained[layer.id] = entry
            return entry
        }
        entries = retained
        let nextPlacements = ordered.map { Placement(id: $0.id, version: $0.version, transform: $0.source.transform,
                                                     visible: $0.source.visible, blend: $0.source.blendMode, opacity: $0.source.effectiveOpacity) }
        if placements != nextPlacements || background != content.background || referenceSize != content.referenceSize || drawingData != content.drawing {
            placements = nextPlacements; background = content.background; referenceSize = content.referenceSize
            visualVersion &+= 1
        }
        if drawingData != content.drawing {
            drawingData = content.drawing
            drawing = (try? PKDrawing(data: content.drawing)) ?? PKDrawing()
            inkRect = drawing.bounds
            inkImage = nil; inkDirty = true
        }
    }

    func prepareResolution(pointsToPixels: CGFloat) {
        var total: CGFloat = 0
        for entry in ordered where entry.source.visible {
            let transform = entry.source.transform
            let projected = transform.projection.bounds(entry.rect)
            let magnification = max(max(abs(transform.scale * transform.stretchX), abs(transform.scale * transform.stretchY)),
                                    max(projected.width/max(1,entry.rect.width), projected.height/max(1,entry.rect.height)))
            let edge = max(1, max(entry.rect.width, entry.rect.height))
            entry.requestedScale = max(1 / edge, min(1800 / edge, pointsToPixels * magnification))
            total += entry.rect.width * entry.rect.height * entry.requestedScale * entry.requestedScale
        }
        let reduction = min(1, sqrt(Self.pixelBudget / max(1, total)))
        for entry in ordered { entry.requestedScale *= reduction }
        let scale = max(0.01, min(pointsToPixels, 1600 / max(1, max(inkRect.width, inkRect.height))))
        if abs(inkScale - scale) > max(0.01, scale * 0.15) { inkScale = scale; inkDirty = true }
    }

    @discardableResult
    func rasterize(_ entry: Entry) -> Bool {
        guard entry.source.visible, entry.needsRaster, entry.rect.width > 0, entry.rect.height > 0,
              entry.rect.width.isFinite, entry.rect.height.isFinite,
              let contentID, let content = document.objects[contentID] else { return false }
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false; format.scale = entry.requestedScale
        format.preferredRange = .standard
        // 外层变换、混合由合成器处理；位图只包含本地像素。
        var local = entry.source
        local.blendMode = .normal; local.opacity = nil
        let image = UIGraphicsImageRenderer(size: entry.rect.size, format: format).image { renderer in
            renderer.cgContext.translateBy(x: -entry.rect.minX, y: -entry.rect.minY)
            if local.kind == .object, let child = local.contentID {
                if local.displayBounds != nil, let background = document.objects[child]?.background {
                    renderer.cgContext.setFillColor(DiaryPageRenderer.color(background).cgColor)
                    renderer.cgContext.fill(entry.rect)
                }
                DiaryPageRenderer.draw(document, contentID: child, images: images, in: renderer.cgContext,
                                       viewport: entry.rect, cacheObjects: false)
            } else {
                DiaryPageRenderer.drawHitLayer(local, document: document, siblings: content.layers,
                                               images: images, in: renderer.cgContext)
            }
        }
        entry.image = image; entry.renderedVersion = entry.version; entry.pixelScale = entry.requestedScale
        entry.alpha = nil
        rasterCount += 1
        return true
    }

    func rasterizeInk() {
        guard inkDirty else { return }
        inkDirty = false
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            inkImage = drawing.strokes.isEmpty ? nil : drawing.image(from: inkRect, scale: inkScale)
        }
        rasterCount += 1
    }

    /// 复用显示位图做 Alpha 命中；只在首次命中时提取低分辨率掩码。
    func contains(_ point: CGPoint, entry: Entry) -> Bool {
        guard entry.rect.contains(point), entry.rect.width > 0, entry.rect.height > 0 else { return false }
        if entry.source.displayBounds != nil, let child = entry.source.contentID,
           let background = document.objects[child]?.background, background.alpha >= 10.0 / 255 { return true }
        if entry.needsRaster { rasterize(entry) }
        guard let cgImage = entry.image?.cgImage else { return false }
        if entry.alpha == nil {
            let ratio = min(1, 512 / CGFloat(max(cgImage.width, cgImage.height)))
            let width = max(1, Int(CGFloat(cgImage.width) * ratio))
            let height = max(1, Int(CGFloat(cgImage.height) * ratio))
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
                guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                    bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
                // CGImage 的原始顶行与这里的掩码顶行一致。
                context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
                return true
            }
            guard rendered else { return false }
            entry.alpha = stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] }
            entry.alphaWidth = width; entry.alphaHeight = height
            var maskBytes = ordered.reduce(0) { $0 + ($1.alpha?.count ?? 0) }
            for other in ordered where other !== entry && maskBytes > 8 * 1024 * 1024 {
                maskBytes -= other.alpha?.count ?? 0
                other.alpha = nil
            }
        }
        let x = min(entry.alphaWidth - 1, max(0, Int((point.x - entry.rect.minX) / entry.rect.width * CGFloat(entry.alphaWidth))))
        let y = min(entry.alphaHeight - 1, max(0, Int((point.y - entry.rect.minY) / entry.rect.height * CGFloat(entry.alphaHeight))))
        return (entry.alpha?[y * entry.alphaWidth + x] ?? 0) >= 10
    }
}
