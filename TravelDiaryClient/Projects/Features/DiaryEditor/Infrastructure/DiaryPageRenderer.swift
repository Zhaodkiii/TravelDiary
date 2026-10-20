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
        switch layer.textAlignment ?? .center {
        case .left: paragraph.alignment = .left
        case .center: paragraph.alignment = .center
        case .right: paragraph.alignment = .right
        }
        paragraph.lineHeightMultiple = layer.textLineHeight ?? 1.2
        let style = layer.textAppearance ?? DiaryTextAppearance()
        var font = DiaryFontCatalog.shared.font(layer.font, size: layer.fontSize)
        var traits = font.fontDescriptor.symbolicTraits
        if style.bold { traits.insert(.traitBold) }
        if style.italic { traits.insert(.traitItalic) }
        if let descriptor = font.fontDescriptor.withSymbolicTraits(traits) { font = UIFont(descriptor: descriptor, size: layer.fontSize) }
        let foreground = layer.textColor.map(color) ?? UIColor.darkText
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: foreground.withAlphaComponent(foreground.cgColor.alpha * style.opacity),
            .kern: layer.textLetterSpacing ?? 0, .paragraphStyle: paragraph]
        if style.underline { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        if style.strikethrough { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        if style.strokeWidth > 0 {
            attributes[.strokeWidth] = -style.strokeWidth
            attributes[.strokeColor] = color(style.strokeColor)
        }
        if style.shadowRadius > 0 {
            let shadow = NSShadow()
            shadow.shadowColor = color(style.shadowColor)
            shadow.shadowBlurRadius = style.shadowRadius
            shadow.shadowOffset = CGSize(width: style.shadowRadius / 2, height: style.shadowRadius / 2)
            attributes[.shadow] = shadow
        }
        return attributes
    }

    static func bounds(_ layer: DiaryLayer, document: DiaryDocument? = nil, siblings: [DiaryLayer] = []) -> CGRect {
        if let rect = layer.displayBounds { return rect }
        if layer.kind == .object, let id = layer.contentID, let content = document?.objects[id] {
            return objectBounds(content, document: document!)
        }
        if layer.isContentPhoto,
           let linked = decorativeFrame(for: layer, siblings: siblings) {
            return CGRect(origin: .zero, size: layer.size).union(bounds(linked, document: document, siblings: siblings))
        }
        if layer.isPhotoFrame, let target = siblings.first(where: { $0.id == layer.frameTargetID }) {
            if let opening = layer.frameOpening, opening.width > 0, opening.height > 0 {
                let width = target.size.width / opening.width, height = target.size.height / opening.height
                return CGRect(x: -opening.minX * width, y: -opening.minY * height, width: width, height: height)
            }
            return CGRect(origin: .zero, size: target.size).insetBy(dx: -(layer.frameWidth ?? 12), dy: -(layer.frameWidth ?? 12))
        }
        if layer.kind == .text {
            return textBounds(layer)
        }
        return CGRect(origin: .zero, size: layer.size)
    }

    /// 同一照片只使用最上方可见的装饰相框；隐藏或移除相框立即恢复照片自身的取景。
    static func decorativeFrame(for photo: DiaryLayer, siblings: [DiaryLayer]) -> DiaryLayer? {
        siblings.last { $0.isPhotoFrame && $0.frameTargetID == photo.id && $0.visible && $0.assetID != nil && $0.frameOpening != nil }
    }

    /// 画框绑定照片而非页面坐标。移动或缩放照片后，画框仍使用目标照片的变换。
    static func matrix(_ layer: DiaryLayer, siblings: [DiaryLayer]) -> CGAffineTransform {
        if layer.isPhotoFrame, let target = siblings.first(where: { $0.id == layer.frameTargetID }) {
            return target.transform.matrix
        }
        return layer.transform.matrix
    }
    static func effectiveTransform(_ layer: DiaryLayer, siblings: [DiaryLayer]) -> DiaryTransform {
        if layer.isPhotoFrame, let target = siblings.first(where: { $0.id == layer.frameTargetID }) { return target.transform }
        return layer.transform
    }
    static func objectBounds(_ content: DiaryObjectContent, document: DiaryDocument) -> CGRect {
        var rect = content.background == nil ? CGRect.null : CGRect(origin: .zero, size: content.referenceSize)
        for node in content.layers where node.visible {
            rect = rect.union(effectiveTransform(node, siblings: content.layers).projection.bounds(bounds(node, document: document, siblings: content.layers)))
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

    /// 印制导出按图层让出主线程，让滚动、点击和预览在页面生成期间继续响应。
    static func drawForPrinting(_ document: DiaryDocument, images: [UUID: UIImage], in context: CGContext) async throws {
        context.saveGState()
        defer { context.restoreGState() }
        context.clip(to: CGRect(origin: .zero, size: document.root.referenceSize))
        try await drawPrintContent(document.root, document: document, images: images, in: context)
    }

    private static func drawPrintContent(_ content: DiaryObjectContent, document: DiaryDocument, images: [UUID: UIImage], in context: CGContext) async throws {
        context.saveGState()
        defer { context.restoreGState() }
        if let background = content.background {
            context.setFillColor(color(background).cgColor)
            context.fill(CGRect(origin: .zero, size: content.referenceSize))
        }
        for layer in content.layers where layer.visible {
            try Task.checkCancellation()
            if layer.kind == .object, layer.transform.warp == nil, let id = layer.contentID, let child = document.objects[id] {
                context.saveGState()
                context.concatenate(matrix(layer, siblings: content.layers))
                switch layer.blendMode ?? .normal {
                case .normal: context.setBlendMode(.normal)
                case .multiply: context.setBlendMode(.multiply)
                case .darken: context.setBlendMode(.darken)
                case .linearBurn: context.setBlendMode(.plusDarker)
                case .lighten: context.setBlendMode(.lighten)
                }
                let translucent = layer.effectiveOpacity < 1
                if translucent { context.setAlpha(layer.effectiveOpacity); context.beginTransparencyLayer(auxiliaryInfo: nil) }
                if let rect = layer.displayBounds {
                    context.clip(to: rect)
                    if let background = child.background { context.setFillColor(color(background).cgColor); context.fill(rect) }
                }
                // 嵌套对象也按图层分段；只在最外层裁切，与常规渲染一致。
                try await drawPrintContent(child, document: document, images: images, in: context)
                if translucent { context.endTransparencyLayer() }
                context.restoreGState()
            } else {
                UIGraphicsPushContext(context)
                drawLayers([layer], document: document, images: images, in: context, cacheObjects: false, siblings: content.layers)
                UIGraphicsPopContext()
            }
            // 不跨 await 保留 UIKit 的线程局部绘制上下文。
            try await Task.sleep(for: .milliseconds(2))
        }
        if let drawing = try? PKDrawing(data: content.drawing), !drawing.strokes.isEmpty {
            UIGraphicsPushContext(context)
            drawInk(drawing, in: objectBounds(content, document: document))
            UIGraphicsPopContext()
        }
    }

    private static func drawInk(_ drawing: PKDrawing, in rect: CGRect) {
        guard !drawing.strokes.isEmpty, !rect.isNull, !rect.isEmpty else { return }
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            drawing.image(from: rect, scale: 2).draw(in: rect)
        }
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
                                   images: [UUID: UIImage], in context: CGContext, cacheObjects: Bool, siblings: [DiaryLayer]? = nil) {
        let siblings = siblings ?? layers
        for layer in layers where layer.visible {
            context.saveGState()
            let transform = effectiveTransform(layer, siblings: siblings)
            context.concatenate(transform.matrix)
            switch layer.blendMode ?? .normal {
            case .normal: context.setBlendMode(.normal)
            case .multiply: context.setBlendMode(.multiply)
            case .darken: context.setBlendMode(.darken)
            // Core Graphics 的加深相加模式使用 plusDarker 命名。
            case .linearBurn: context.setBlendMode(.plusDarker)
            case .lighten: context.setBlendMode(.lighten)
            }
            let translucent = layer.effectiveOpacity < 1
            if translucent {
                context.setAlpha(layer.effectiveOpacity)
                context.beginTransparencyLayer(auxiliaryInfo: nil)
            }
            if let warp = transform.warp {
                let rect = bounds(layer, document: document, siblings: siblings)
                let warpedBounds = warp.projection.bounds(rect)
                let scale = max(hypot(context.ctm.a, context.ctm.b), hypot(context.ctm.c, context.ctm.d))
                // Render source sharply enough for the projected output, with a fixed memory ceiling.
                let ratio = max(1, max(warpedBounds.width/max(1,rect.width), warpedBounds.height/max(1,rect.height)))
                let format = UIGraphicsImageRendererFormat(); format.opaque = false
                format.scale = max(0.01, min(scale*ratio, sqrt(16*1024*1024/max(1,max(rect.width*rect.height,warpedBounds.width*warpedBounds.height)))))
                var local = layer
                local.transform = DiaryTransform(position: .zero, pivot: .zero)
                local.opacity = nil; local.blendMode = .normal
                var localSiblings = siblings
                if let target = local.frameTargetID, let index = localSiblings.firstIndex(where: { $0.id == target }) {
                    localSiblings[index].transform = local.transform
                }
                let image = UIGraphicsImageRenderer(size: rect.size, format: format).image { renderer in
                    renderer.cgContext.translateBy(x: -rect.minX, y: -rect.minY)
                    drawLayers([local], document: document, images: images, in: renderer.cgContext,
                               cacheObjects: false, siblings: localSiblings)
                }
                DiaryWarpRenderer.draw(image, rect: rect, warp: warp, in: context)
                if translucent { context.endTransparencyLayer() }
                context.restoreGState()
                continue
            }
            if let rect = layer.displayBounds { context.clip(to: rect) }
            switch layer.kind {
            case .object:
                if let id = layer.contentID, let content = document.objects[id] {
                    if let frame = layer.displayBounds, let background = content.background {
                        context.setFillColor(color(background).cgColor)
                        context.fill(frame)
                    }
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
                drawText(layer, in: context)
            case .frame:
                if let id = layer.assetID, let image = images[id] {
                    image.draw(in: bounds(layer, document: document, siblings: siblings))
                } else if let target = siblings.first(where: { $0.id == layer.frameTargetID }) {
                    let width = layer.frameWidth ?? 12
                    context.setStrokeColor(color(layer.frameColor ?? .white).cgColor)
                    context.setLineWidth(width)
                    context.stroke(CGRect(origin: .zero, size: target.size).insetBy(dx: -width / 2, dy: -width / 2))
                }
            case .photo, .sticker:
                if layer.isPhotoFrame, layer.frameTargetID != nil, let id = layer.assetID, let image = images[id] {
                    image.draw(in: bounds(layer, document: document, siblings: siblings))
                } else if let id = layer.assetID, let image = images[id], let asset = document.assets[id] {
                    if layer.isContentPhoto, let decoration = decorativeFrame(for: layer, siblings: siblings),
                       let frameID = decoration.assetID, let frameImage = images[frameID], let opening = decoration.frameOpening,
                       let aperture = DiaryPhotoFrameAperture.detect(frameImage, opening: opening) {
                        let rect = bounds(decoration, document: document, siblings: siblings)
                        var slot = aperture.slot
                        slot.fill = layer.photoSlot?.fill ?? .cover
                        if let mapped = DiaryPhotoSlotRenderer.image(image, mask: aperture.mask, slot: slot, size: rect.size,
                            crop: layer.crop, pixelScale: max(hypot(context.ctm.a, context.ctm.b), hypot(context.ctm.c, context.ctm.d))) {
                            mapped.draw(in: rect)
                        }
                    } else {
                        let frame = layer.photoFill == true ? (layer.displayBounds ?? CGRect(origin: .zero, size: layer.size)) : CGRect(origin: .zero, size: layer.size)
                        context.clip(to: frame)
                        if layer.photoFill == true, let slot = layer.photoSlot {
                            if let mapped = DiaryPhotoSlotRenderer.image(image, mask: slot.maskAssetID.flatMap { images[$0] },
                                slot: slot, size: frame.size, crop: layer.crop,
                                pixelScale: max(hypot(context.ctm.a, context.ctm.b), hypot(context.ctm.c, context.ctm.d))) { mapped.draw(in: frame) }
                        } else if layer.photoFill == true, let placement = layer.photoPlacement {
                            // 在完整素材坐标中恢复烘焙的倾斜，再由外层矩阵完成页面旋转与拉伸。
                            context.translateBy(x: frame.minX, y: frame.minY)
                            context.translateBy(x: placement.center.x * frame.width, y: placement.center.y * frame.height)
                            context.rotate(by: placement.radians)
                            image.draw(in: CGRect(x: -placement.size.width * frame.width / 2,
                                                  y: -placement.size.height * frame.height / 2,
                                                  width: placement.size.width * frame.width, height: placement.size.height * frame.height))
                        } else {
                            image.draw(in: layer.isContentPhoto && layer.photoFill != true ? layer.crop.imageRect(source: asset.pixelSize, frame: layer.size) : frame)
                        }
                    }
                }
            }
            if translucent { context.endTransparencyLayer() }
            context.restoreGState()
        }
    }

    /// 只绘制当前图层自身的可见内容，不包含下面的照片、棋盘格和选框。
    /// 复用正式绘制规则，裁剪、文字、画框、对象背景及笔画与预览保持一致。
    static func drawHitLayer(_ layer: DiaryLayer, document: DiaryDocument,
                             siblings: [DiaryLayer], images: [UUID: UIImage], in context: CGContext) {
        var local = layer
        local.transform = DiaryTransform(position: .zero, pivot: .zero)
        var localSiblings = siblings
        if let target = layer.frameTargetID, let index = localSiblings.firstIndex(where: { $0.id == target }) {
            localSiblings[index].transform = local.transform
        }
        drawLayers([local], document: document, images: images, in: context, cacheObjects: false, siblings: localSiblings)
    }

    /// 外部摆放不影响局部透明度缓存，内部编辑/撤销/替换图片则必须重新生成。
    static func hitFingerprint(_ layer: DiaryLayer, document: DiaryDocument,
                               siblings: [DiaryLayer], images: [UUID: UIImage]) -> Int {
        var local = layer
        local.transform = DiaryTransform(position: .zero, pivot: .zero)
        var hash = Hasher()
        hash.combine(try? JSONEncoder().encode(local))
        if let id = layer.contentID, let content = document.objects[id] {
            hash.combine(fingerprint(content, document: document))
        }
        if let target = siblings.first(where: { $0.id == layer.frameTargetID }) {
            hash.combine(target.size.width); hash.combine(target.size.height)
        }
        if let decoration = decorativeFrame(for: layer, siblings: siblings) {
            hash.combine(try? JSONEncoder().encode(decoration))
        }
        // UIImage 替换或由缺失变为可用时，不能继续使用旧掩码。
        for id in images.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            hash.combine(id); hash.combine(ObjectIdentifier(images[id]!))
        }
        return hash.finalize()
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
        let url = StoragePaths.system.temporaryRoot.appendingPathComponent("手帐-\(UUID().uuidString).png")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (data as Data).write(to: url, options: .atomic)
        return url
    }
}
