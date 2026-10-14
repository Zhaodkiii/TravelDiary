import UIKit
import PencilKit
import ImageIO
import UniformTypeIdentifiers

/// 同一套绘制规则服务于页面、对象独立编辑和成品导出。
/// 对象缓存保存透明内容，并始终按本地 bounds 的原点放回，装饰越界不会让主体跳位。
@MainActor
enum DiaryPageRenderer {
    private static let previews: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 32 * 1024 * 1024
        return cache
    }()

    static func color(_ value: DiaryColor) -> UIColor {
        UIColor(red: value.red, green: value.green, blue: value.blue, alpha: value.alpha)
    }
    static func textStyle(_ layer: DiaryLayer) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center; paragraph.lineHeightMultiple = 1.2
        return [.font: DiaryFontCatalog.shared.font(layer.font, size: layer.fontSize), .foregroundColor: UIColor.darkText, .paragraphStyle: paragraph]
    }

    static func bounds(_ layer: DiaryLayer, document: DiaryDocument? = nil, siblings: [DiaryLayer] = []) -> CGRect {
        if layer.kind == .object, let id = layer.contentID, let content = document?.objects[id] {
            return objectBounds(content, document: document!)
        }
        if layer.kind == .frame, let target = siblings.first(where: { $0.id == layer.frameTargetID }) {
            return CGRect(origin: .zero, size: target.size).insetBy(dx: -(layer.frameWidth ?? 12), dy: -(layer.frameWidth ?? 12))
        }
        if layer.kind == .text {
            let rect = (layer.text as NSString).boundingRect(with: CGSize(width: layer.size.width, height: CGFloat.greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: textStyle(layer), context: nil)
            return CGRect(x: 0, y: 0, width: layer.size.width, height: max(ceil(rect.height), layer.fontSize * 1.2))
        }
        return CGRect(origin: .zero, size: layer.size)
    }

    /// 画框绑定照片而非页面坐标。移动或缩放照片后，画框仍使用目标照片的变换。
    static func matrix(_ layer: DiaryLayer, siblings: [DiaryLayer]) -> CGAffineTransform {
        if layer.kind == .frame, let target = siblings.first(where: { $0.id == layer.frameTargetID }) {
            return target.transform.matrix
        }
        return layer.transform.matrix
    }
    static func objectBounds(_ content: DiaryObjectContent, document: DiaryDocument) -> CGRect {
        var rect = content.background == nil ? CGRect.null : CGRect(origin: .zero, size: content.referenceSize)
        for node in content.layers where node.visible {
            rect = rect.union(bounds(node, document: document, siblings: content.layers).applying(matrix(node, siblings: content.layers)))
        }
        if let drawing = try? PKDrawing(data: content.drawing), !drawing.strokes.isEmpty { rect = rect.union(drawing.bounds) }
        return rect.isNull || rect.isEmpty ? CGRect(origin: .zero, size: content.referenceSize) : rect
    }

    static func draw(_ document: DiaryDocument, contentID: UUID? = nil, images: [UUID: UIImage],
                     in context: CGContext, viewport: CGRect? = nil, includeInk: Bool = true, cacheObjects: Bool = true) {
        guard let content = document.objects[contentID ?? document.rootContentID] else { return }
        context.saveGState()
        context.clip(to: viewport ?? CGRect(origin: .zero, size: content.referenceSize))
        drawContent(content, document: document, images: images, in: context, includeInk: includeInk, cacheObjects: cacheObjects)
        context.restoreGState()
    }

    private static func drawInk(_ drawing: PKDrawing, in rect: CGRect) {
        guard !drawing.strokes.isEmpty, !rect.isNull, !rect.isEmpty else { return }
        drawing.image(from: rect, scale: 2).draw(in: rect)
    }
    private static func drawContent(_ content: DiaryObjectContent, document: DiaryDocument,
                                    images: [UUID: UIImage], in context: CGContext, includeInk: Bool = true, cacheObjects: Bool = false) {
        if let background = content.background {
            context.setFillColor(color(background).cgColor)
            context.fill(CGRect(origin: .zero, size: content.referenceSize))
        }
        drawLayers(content.layers, document: document, images: images, in: context, cacheObjects: cacheObjects)
        if includeInk, let drawing = try? PKDrawing(data: content.drawing) { drawInk(drawing, in: objectBounds(content, document: document)) }
    }
    private static func drawLayers(_ layers: [DiaryLayer], document: DiaryDocument,
                                   images: [UUID: UIImage], in context: CGContext, cacheObjects: Bool) {
        for layer in layers where layer.visible {
            context.saveGState()
            context.concatenate(matrix(layer, siblings: layers))
            switch layer.blendMode ?? .normal {
            case .normal: context.setBlendMode(.normal)
            case .multiply: context.setBlendMode(.multiply)
            case .darken: context.setBlendMode(.darken)
            // Core Graphics 的加深相加模式使用 plusDarker 命名。
            case .linearBurn: context.setBlendMode(.plusDarker)
            case .lighten: context.setBlendMode(.lighten)
            }
            switch layer.kind {
            case .object:
                if let id = layer.contentID, let content = document.objects[id] {
                    if cacheObjects {
                        let rect = objectBounds(content, document: document)
                        // 同一版本在撤销分支可能有不同内容，因此缓存还纳入内容与绘画指纹。
                        let fingerprint = fingerprint(content, document: document)
                        let key = "\(id)-\(content.revision)-\(fingerprint)-\(content.drawing.hashValue)" as NSString
                        if let cached = previews.object(forKey: key) { cached.draw(in: rect) }
                        else if rect.width < 10000, rect.height < 10000 {
                            let format = UIGraphicsImageRendererFormat()
                            format.opaque = false; format.scale = min(2, 1800 / max(rect.width, rect.height))
                            let image = UIGraphicsImageRenderer(size: rect.size, format: format).image { renderer in
                                renderer.cgContext.translateBy(x: -rect.minX, y: -rect.minY)
                                drawContent(content, document: document, images: images, in: renderer.cgContext)
                            }
                            previews.setObject(image, forKey: key, cost: (image.cgImage?.bytesPerRow ?? 0) * (image.cgImage?.height ?? 0))
                            image.draw(in: rect)
                        } else { drawContent(content, document: document, images: images, in: context) }
                    } else { drawContent(content, document: document, images: images, in: context) }
                }
            case .canvas: break
            case .text:
                (layer.text as NSString).draw(with: bounds(layer), options: [.usesLineFragmentOrigin, .usesFontLeading],
                                             attributes: textStyle(layer), context: nil)
            case .frame:
                if let target = layers.first(where: { $0.id == layer.frameTargetID }) {
                    let width = layer.frameWidth ?? 12
                    context.setStrokeColor(color(layer.frameColor ?? .white).cgColor)
                    context.setLineWidth(width)
                    context.stroke(CGRect(origin: .zero, size: target.size).insetBy(dx: -width / 2, dy: -width / 2))
                }
            case .photo, .sticker:
                if let id = layer.assetID, let image = images[id], let asset = document.assets[id] {
                    let frame = CGRect(origin: .zero, size: layer.size)
                    context.clip(to: frame)
                    image.draw(in: layer.kind == .photo ? layer.crop.imageRect(source: asset.pixelSize, frame: layer.size) : frame)
                }
            }
            context.restoreGState()
        }
    }

    /// 内层内容变化也进入缓存指纹，避免撤销分支复用 revision 后命中旧预览。
    private static func fingerprint(_ content: DiaryObjectContent, document: DiaryDocument) -> Int {
        var hash = Hasher()
        hash.combine(try? JSONEncoder().encode(content)); hash.combine(content.drawing)
        for layer in content.layers {
            if let id = layer.contentID, let child = document.objects[id] { hash.combine(fingerprint(child, document: document)) }
        }
        return hash.finalize()
    }

    static func export(_ document: DiaryDocument, images: [UUID: UIImage]) throws -> URL {
        let isA5 = document.root.referenceSize == DiaryPagePreset.a5.size
        // A5 已使用目标像素作为坐标，不再乘屏幕倍率，避免导出尺寸翻倍。
        let format = UIGraphicsImageRendererFormat(); format.scale = isA5 ? 1 : 2; format.opaque = false
        let image = UIGraphicsImageRenderer(size: document.root.referenceSize, format: format).image { renderer in
            draw(document, images: images, in: renderer.cgContext, cacheObjects: false)
        }
        guard let cgImage = image.cgImage else { throw DiaryEditorError.exportFailed.logged() }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw DiaryEditorError.exportFailed.logged()
        }
        // PNG 写入打印分辨率；毫米尺寸换算为像素后存在整数取整误差。
        let properties: [CFString: Any] = isA5 ? [kCGImagePropertyDPIWidth: 300, kCGImagePropertyDPIHeight: 300] : [:]
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw DiaryEditorError.exportFailed.logged() }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("手帐-\(UUID().uuidString).png")
        try (data as Data).write(to: url, options: .atomic)
        return url
    }
}
