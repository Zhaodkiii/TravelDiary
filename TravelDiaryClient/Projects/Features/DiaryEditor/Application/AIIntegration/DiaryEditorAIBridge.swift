import UIKit
import CryptoKit
import CoreText

/// All knowledge of the native document, renderer, fonts and transactions stays on this side.
@MainActor final class DiaryEditorAIBridge: DiaryAIEditorBridge {
    private weak var session: DiaryEditorSession?
    var autoFitPhotoRegions = false
    var fitsTextToPlannedRegions = false
    var fitsNativeStickerSizes = false
    var limitsTextToAvailableRegions = false
    var rendersDraftPreview = true
    private struct StickerSpaceUnavailable: Error {}
    private var pendingStickerPlacements = Set<UUID>()
    var layoutRegions: [DiaryAILayoutRegion] = []
    var allowedBatchIDs: Set<UUID>?
    var excludedRenderIDs: Set<UUID> = []
    private var base: DiaryDocument?
    private var context: DiaryAIContext?
    private var request: DiaryAIRequest?
    private var images: [UUID: UIImage] = [:]
    private var candidate: DiaryDocument?
    private var draft: DiaryAIDraft?
    private var createdIDs: [String: UUID] = [:]
    private var imageCache: [String: Data] = [:]
    private var newImages: [UUID: Data] = [:]
    init(_ session: DiaryEditorSession) { self.session = session }
    var storageKey: String {
        guard let session else { return "closed" }
        return Self.hash(Data("\(session.store.ownerID)/\(session.document.bookID?.uuidString ?? "single")/\(session.document.id)/\(session.contentID)".utf8))
    }
    var canvasSize: CGSize? { session?.content.referenceSize }
    var scopeTitle: String { session?.isRoot == true ? "当前页 / 跨页" : "当前对象画布" }
    var selectionAvailable: Bool { session?.selectedID != nil }
    var gesturesActive: Bool { session?.aiViewportInteracting == true }
    var objectChoices: [DiaryAIObject] {
        guard let session else { return [] }
        return describe(session.document, contentID: session.contentID, selected: nil)
    }
    nonisolated static func hash(_ bytes: Data) -> String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }
    nonisolated static func digest(_ document: DiaryDocument) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        var bytes = Data("\(document.id)|\(document.bookID?.uuidString ?? "")|\(document.rootContentID)|\(document.title)".utf8)
        for key in document.assets.keys.sorted(by: { $0.uuidString < $1.uuidString }) { bytes += try encoder.encode(document.assets[key]!) }
        for key in document.objects.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            bytes += try encoder.encode(document.objects[key]!); bytes += document.objects[key]!.drawing
        }
        return hash(bytes)
    }
    private func descendants(_ layer: DiaryLayer, in document: DiaryDocument, visited: Set<UUID> = []) -> [DiaryLayer] {
        guard let id = layer.contentID, !visited.contains(id), let content = document.objects[id] else { return [layer] }
        return [layer] + content.layers.flatMap { descendants($0, in: document, visited: visited.union([id])) }
    }
    private func primary(_ layer: DiaryLayer, in document: DiaryDocument) -> DiaryLayer {
        guard let id = layer.contentID, let content = document.objects[id],
              content.drawing.isEmpty, content.background == nil,
              let first = content.layers.first(where: { $0.id == content.primaryLayerID }) ?? content.layers.first,
              content.layers.allSatisfy({ $0.id == first.id || $0.frameTargetID == first.id }) else { return layer }
        return primary(first, in: document)
    }
    private func role(_ layer: DiaryLayer, in document: DiaryDocument) -> String {
        let nodes = descendants(layer, in: document)
        if nodes.contains(where: { $0.semanticKind == .background || $0.isLibraryBackground == true }) { return "background" }
        let leaf = primary(layer, in: document)
        if leaf.kind == .text { return "text" }
        if nodes.contains(where: { $0.category == .textImage || $0.semanticKind == .text }) { return "textImage" }
        if leaf.isContentPhoto { return "photo" }
        if leaf.isPhotoFrame { return "frame" }
        if leaf.contentID != nil { return "group" }
        return "decoration"
    }
    private func describe(_ document: DiaryDocument, contentID: UUID, selected: UUID?) -> [DiaryAIObject] {
        let siblings = document.objects[contentID]?.layers ?? []
        return siblings.enumerated().map { index, layer in
            let nodes = descendants(layer, in: document)
            let leaf = primary(layer, in: document)
            let bounds = DiaryPageRenderer.bounds(layer, document: document, siblings: siblings).applying(DiaryPageRenderer.matrix(layer, siblings: siblings))
            let locked = nodes.contains { $0.locked || $0.semanticKind == .branding || $0.contentID.flatMap { document.objects[$0] }.map { !$0.drawing.isEmpty } == true }
            return DiaryAIObject(id: layer.id, shortID: "L\(index + 1)", name: layer.name, role: role(layer, in: document),
                center: CGPoint(x: bounds.midX, y: bounds.midY), bounds: bounds, scale: layer.transform.scale,
                angle: layer.transform.rotationDegrees, locked: locked, visible: layer.visible,
                editable: !locked && layer.visible && (selected == nil || selected == layer.id) && (allowedBatchIDs == nil || allowedBatchIDs!.contains(layer.id)) && !layer.isPhotoFrame,
                text: leaf.kind == .text ? leaf.text : nil, assetIDs: Array(Set(nodes.compactMap(\.assetID))).sorted { $0.uuidString < $1.uuidString })
        }
    }
    func capture(_ request: DiaryAIRequest) async throws -> DiaryAIContext {
        guard let session else { throw DiaryAIError.invalid("编辑器已关闭") }
        session.finishInteraction()
        guard !request.selectedOnly || session.selectedID != nil else { throw DiaryAIError.invalid("请先在画布中选中要调整的对象，或改为当前页范围。") }
        let source = session.document
        let objects = describe(source, contentID: session.contentID, selected: request.selectedOnly ? session.selectedID : nil)
        guard objects.count <= 100 else { throw DiaryAIError.invalid("本页超过 100 个对象，请在对象内部编辑。") }
        let catalog = DiaryFontCatalog.shared; catalog.prepare()
        let refs = catalog.entries.filter { $0.category != "cloud" }.map { DiaryFontReference(id: $0.id, version: $0.version) }
        await catalog.prewarm(refs)
        try Task.checkCancellation()
        let fonts = refs.filter { catalog.available($0) }.map { DiaryAIFont(id: $0.id, version: $0.version, name: catalog.entry($0)?.displayName ?? $0.id) }
        let size = source.objects[session.contentID]!.referenceSize
        let digest = try await DiaryAIImageWork.run { try Self.digest(source) }
        let value = DiaryAIContext(id: UUID(), digest: digest, contentID: session.contentID, size: size,
            spineX: abs(size.width / size.height - 4370.0 / 3130.0) < 0.001 ? size.width / 2 : nil, objects: objects, fonts: fonts)
        base = source; context = value; self.request = request; images = session.images
        candidate = nil; draft = nil; newImages = [:]; createdIDs = [:]
        let required = Set(objects.filter(\.visible).flatMap(\.assetIDs))
        for id in required {
            try Task.checkCancellation()
            guard let asset = source.assets[id] else { throw DiaryAIError.invalid("图片资源引用缺失") }
            let needed = min(1800, max(asset.pixelSize.width, asset.pixelSize.height))
            let current = images[id].map { max($0.size.width * $0.scale, $0.size.height * $0.scale) } ?? 0
            if current + 1 < needed { images[id] = try await session.store.loadAILayoutImage(asset, documentID: source.id) }
        }
        guard required.allSatisfy({ images[$0] != nil }) else { throw DiaryAIError.invalid("本页图片尚未加载完整") }
        return value
    }
    private func waitForViewport() async throws {
        while gesturesActive { try await Task.sleep(for: .milliseconds(80)) }
        try Task.checkCancellation()
    }
    private func jpeg(size: CGSize, draw: (CGContext) -> Void) async throws -> Data {
        guard size.width > 0, size.height > 0 else { throw DiaryAIError.invalid("预览尺寸无效") }
        let image = autoreleasepool {
            let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
            let image = UIGraphicsImageRenderer(size: size, format: format).image { output in
                UIColor.systemBackground.setFill(); output.fill(CGRect(origin: .zero, size: size)); draw(output.cgContext)
            }
            return image
        }
        return try await DiaryAIImageWork.jpeg(image)
    }

    private func pageImage(_ document: DiaryDocument) async throws -> Data {
        guard let context else { throw DiaryAIError.invalid("页面快照缺失") }
        await Task.yield(); try await waitForViewport()
        let excluded = excludedRenderIDs
        let key = try await DiaryAIImageWork.run { try Self.digest(document) } + "-1536-v2-" + excluded.map(\.uuidString).sorted().joined()
        if let cached = imageCache[key] { return cached }
        var visibleDocument = document
        visibleDocument.objects[context.contentID]?.layers.removeAll { excluded.contains($0.id) || $0.frameTargetID.map(excluded.contains) == true }
        let image = try await DiaryPageRenderer.aiPreview(visibleDocument, contentID: context.contentID, images: images, size: context.size)
        let bytes = try await DiaryAIImageWork.jpeg(image)
        if imageCache.count > 16 { imageCache.removeAll() }
        imageCache[key] = bytes
        return bytes
    }
    func originalPreview() async throws -> Data {
        guard let base else { throw DiaryAIError.invalid("快照缺失") }
        return try await pageImage(base)
    }
    func backgroundCompositePreview(_ bytes: Data) async throws -> Data {
        guard var document = base, let context, let underlay = UIImage(data: bytes)?.cgImage else {
            throw DiaryAIError.invalid("无法预览背景与前景的合成效果")
        }
        let excluded = excludedRenderIDs
        document.objects[context.contentID]?.layers.removeAll {
            excluded.contains($0.id) || $0.frameTargetID.map(excluded.contains) == true
        }
        document.objects[context.contentID]?.background = nil
        let image = try await DiaryPageRenderer.aiPreview(document, contentID: context.contentID,
                                                          images: images, size: context.size, underlay: underlay)
        return try await DiaryAIImageWork.jpeg(image)
    }

    func initialImages(_ request: DiaryAIRequest) async throws -> [DiaryAIImage] {
        guard let base, let context else { throw DiaryAIError.invalid("页面快照缺失") }
        if request.action == .writing && !request.understandsPhotos && request.selectedOnly { return [] }
        var result = [DiaryAIImage(id: "page", caption: "当前画布，坐标与图层数据对应", data: try await pageImage(base))]
        if request.action == .relayout || (request.action == .writing && request.understandsPhotos) {
            let photos = context.objects.filter { $0.visible && $0.role == "photo" }
            for start in stride(from: 0, to: min(photos.count, 18), by: 9) {
                try await waitForViewport(); await Task.yield()
                let group = Array(photos[start..<min(start + 9, photos.count)])
                let bytes = try await jpeg(size: CGSize(width: 1200, height: ceil(Double(group.count) / 3) * 440)) { output in
                    for (i, object) in group.enumerated() {
                        let rect = CGRect(x: (i % 3) * 400 + 8, y: (i / 3) * 440 + 8, width: 384, height: 384)
                        if let outer = base.layer(object.id), let asset = primary(outer, in: base).assetID, let image = images[asset] {
                            let ratio = min(rect.width / image.size.width, rect.height / image.size.height)
                            image.draw(in: CGRect(x: rect.midX - image.size.width * ratio / 2, y: rect.midY - image.size.height * ratio / 2, width: image.size.width * ratio, height: image.size.height * ratio))
                        }
                        ("\(object.shortID) · \(object.id)" as NSString).draw(at: CGPoint(x: rect.minX, y: rect.maxY + 8), withAttributes: [.font: UIFont.systemFont(ofSize: 13), .foregroundColor: UIColor.label])
                    }
                }
                result.append(.init(id: "board-\(start / 9)", caption: "完整照片；编号在图像外，留白非素材。其余对象按需 inspect_assets。", data: bytes))
            }
        }
        return result
    }
    func inspect(_ arguments: DiaryAIToolArguments) async throws -> [DiaryAIImage] {
        guard let base, let context, let ids = arguments.objectIDs, (1...DiaryAIWorkspace.maximumBatchLayers).contains(ids.count),
              ids.allSatisfy({ id in context.objects.contains { $0.id == id && $0.visible } }) else { throw DiaryAIError.invalid("补图对象不在本次范围内") }
        var result: [DiaryAIImage] = []
        for id in ids {
            await Task.yield(); try await waitForViewport()
            guard let layer = base.layer(id), let object = context.objects.first(where: { $0.id == id }) else { continue }
            let bytes: Data
            if arguments.view == "fullAsset", let asset = primary(layer, in: base).assetID, let image = images[asset] {
                let ratio = min(1, 1024 / max(image.size.width, image.size.height))
                let size = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
                bytes = try await jpeg(size: size) { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
            } else {
                let rect = object.bounds.insetBy(dx: -24, dy: -24).intersection(CGRect(origin: .zero, size: context.size))
                guard !rect.isNull, rect.width > 0, rect.height > 0 else { throw DiaryAIError.invalid("对象不在可见画布内") }
                let ratio = min(1, 1024 / max(rect.width, rect.height))
                bytes = try await jpeg(size: CGSize(width: rect.width * ratio, height: rect.height * ratio)) { output in
                    output.scaleBy(x: ratio, y: ratio); output.translateBy(x: -rect.minX, y: -rect.minY)
                    if arguments.view == "currentCrop" {
                        DiaryPageRenderer.drawHitLayer(layer, document: base, siblings: base.objects[context.contentID]!.layers, images: images, in: output)
                    } else { DiaryPageRenderer.draw(base, contentID: context.contentID, images: images, in: output) }
                }
            }
            result.append(.init(id: id.uuidString, caption: "\(arguments.view ?? "canvasRegion") \(object.shortID); canvas bounds \(object.bounds)", data: bytes))
        }
        return result
    }

    private func require(_ condition: Bool, _ message: String) throws { if !condition { throw DiaryAIError.invalid(message) } }
    private func color(_ hex: String) throws -> DiaryColor {
        let clean = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard clean.count == 6, let value = UInt32(clean, radix: 16) else { throw DiaryAIError.invalid("颜色必须是六位十六进制") }
        return DiaryColor(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }
    /// Widen a naturally wrapped text card only; preserve content, explicit breaks and font size.
    static func avoidOrphanLine(_ layer: inout DiaryLayer, maximumWidth: CGFloat) {
        if layer.text.contains("\n") {
            // Explicit semantic lines must fit inside the paper insets; avoid an extra 1–2 character visual line.
            let insets = DiaryPageRenderer.textInsets(layer)
            let style = DiaryPageRenderer.textStyle(layer)
            let needed = layer.text.components(separatedBy: "\n").map { ( $0 as NSString).size(withAttributes: style).width }.max() ?? 0
            if needed > layer.size.width - insets.left - insets.right {
                layer.size.width = min(maximumWidth, max(layer.size.width, ceil(needed + insets.left + insets.right + layer.fontSize * 0.15)))
            }
            return
        }
        guard layer.text.count > 6, layer.size.width < maximumWidth else { return }
        let attributed = NSAttributedString(string: layer.text, attributes: DiaryPageRenderer.textStyle(layer))
        let typesetter = CTTypesetterCreateWithAttributedString(attributed)
        let text = layer.text as NSString
        for _ in 0..<12 {
            let insets = DiaryPageRenderer.textInsets(layer)
            let width = max(1, layer.size.width - insets.left - insets.right)
            var offset = 0, last = NSRange(location: 0, length: 0), lines = 0
            while offset < text.length {
                let length = CTTypesetterSuggestLineBreak(typesetter, offset, Double(width))
                guard length > 0 else { return }
                last = NSRange(location: offset, length: length); offset += length; lines += 1
            }
            let tail = text.substring(with: last).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            guard lines > 1, tail.count < 4, layer.size.width < maximumWidth else { break }
            layer.size.width = min(maximumWidth, layer.size.width + layer.fontSize * 0.5)
        }
    }
    private static func safeTextPages(_ context: DiaryAIContext) -> [CGRect] {
        let canvas = CGRect(origin: .zero, size: context.size)
        let pages = context.spineX.map { spine in
            [CGRect(x: 0, y: 0, width: max(0, spine - 24), height: canvas.height),
             CGRect(x: spine + 24, y: 0, width: max(0, canvas.width - spine - 24), height: canvas.height)]
        } ?? [canvas]
        let margin = min(canvas.width, canvas.height) * 0.02
        return pages.map { $0.insetBy(dx: margin, dy: margin) }
    }

    static func freeTextRects(_ regions: [CGRect], excluding obstacle: CGRect, minimum: CGSize) -> [CGRect] {
        regions.flatMap { region -> [CGRect] in
            let overlap = region.intersection(obstacle)
            guard !overlap.isEmpty else { return [region] }
            return [
                CGRect(x: region.minX, y: region.minY, width: overlap.minX - region.minX, height: region.height),
                CGRect(x: overlap.maxX, y: region.minY, width: region.maxX - overlap.maxX, height: region.height),
                CGRect(x: region.minX, y: region.minY, width: region.width, height: overlap.minY - region.minY),
                CGRect(x: region.minX, y: overlap.maxY, width: region.width, height: region.maxY - overlap.maxY)
            ].filter { $0.width >= minimum.width && $0.height >= minimum.height }
        }
    }

    static func availableTextRegions(_ planned: [DiaryAILayoutRegion], context: DiaryAIContext,
                                     excluding excludedIDs: Set<UUID>) -> [DiaryAILayoutRegion] {
        let unit = min(context.size.width, context.size.height)
        let minimum = CGSize(width: max(64, unit * 0.08), height: max(48, unit * 0.045))
        func area(_ rect: CGRect) -> CGFloat { rect.isEmpty ? 0 : rect.width * rect.height }
        func subtract(_ obstacle: CGRect, from regions: [CGRect]) -> [CGRect] {
            Array(freeTextRects(regions, excluding: obstacle.insetBy(dx: -8, dy: -8), minimum: minimum)
                .sorted { area($0) > area($1) }.prefix(128))
        }

        let pages = safeTextPages(context)
        var free = pages.filter { $0.width >= minimum.width && $0.height >= minimum.height }
        for item in context.objects where item.visible && !excludedIDs.contains(item.id) && ["photo", "text", "textImage"].contains(item.role) {
            free = subtract(item.bounds, from: free)
        }

        var slots: [DiaryAILayoutRegion] = []
        for hint in planned where hint.role == "text" {
            // Stay on the hinted page, preferring a free rectangle that preserves its anchor.
            let page = pages.first { $0.intersects(hint.bounds) }
            guard let page, let slot = free.filter({ page.contains($0) }).max(by: { lhs, rhs in
                let leftOverlap = area(lhs.intersection(hint.bounds)), rightOverlap = area(rhs.intersection(hint.bounds))
                if leftOverlap != rightOverlap { return leftOverlap < rightOverlap }
                return area(lhs) < area(rhs)
            }) else { continue }
            // Keep the intended dimensions where possible without discarding room for the renderer.
            let width = min(slot.width, max(minimum.width, hint.width))
            let height = min(slot.height, max(minimum.height, hint.height))
            let x = min(max(hint.bounds.minX, slot.minX), slot.maxX - width)
            let y = min(max(hint.bounds.minY, slot.minY), slot.maxY - height)
            let allocated = CGRect(x: x, y: y, width: width, height: height)
            slots.append(.init(role: "text", x: x, y: y, width: width, height: height))
            free = subtract(allocated, from: free)
        }
        return slots
    }

    private func configureText(_ operation: DiaryAIOperation, layer: inout DiaryLayer, context: DiaryAIContext) throws {
        if let text = operation.text { try require(!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.count <= 1000, "文字为空或过长"); layer.text = text }
        if let fontID = operation.fontID {
            guard let font = context.fonts.first(where: { $0.id == fontID }) else { throw DiaryAIError.invalid("字体不在可用目录中") }
            layer.font = DiaryFontReference(id: font.id, version: font.version)
        }
        if let size = operation.fontSize { try require(size.isFinite && (12...300).contains(size), "字号超出范围"); layer.fontSize = size }
        if let width = operation.width { try require(width.isFinite && (40...context.size.width).contains(width), "文本宽度无效"); layer.size.width = width }
        if let hex = operation.color { layer.textColor = try color(hex) }
        if let paper = operation.paper {
            guard let kind = DiaryTextPaper.Kind(rawValue: paper) else { throw DiaryAIError.invalid("文字纸张样式无效") }
            var appearance = layer.textAppearance ?? DiaryTextAppearance(); appearance.paper = DiaryTextPaper(kind: kind); layer.textAppearance = appearance
        }
        if operation.type == "createText", operation.textRole == "title" { layer.name = "AI 标题" }
        if request?.design != nil, request?.instruction.isEmpty == true, operation.textRole == "title" || layer.name == "AI 标题" {
            var style = layer.textAppearance ?? DiaryTextAppearance()
            style.vertical = false; style.titleLayout = .headline; layer.textAppearance = style
            let longest = layer.text.split(separator: "\n").map(\.count).max() ?? 4
            let insets = DiaryPageRenderer.textInsets(layer)
            if !fitsTextToPlannedRegions && !limitsTextToAvailableRegions {
                layer.size.width = min(context.size.width * 0.44, max(layer.size.width, layer.fontSize * CGFloat(min(longest, 9)) + insets.left + insets.right))
            }
        }
        try require(DiaryFontCatalog.shared.warning(layer.font, text: layer.text) == nil, "所选字体不可用或缺少字符，请选择另一字体")
        if request?.design != nil, request?.background != nil, request?.instruction.isEmpty == true,
           layer.textAppearance?.paper?.kind == DiaryTextPaper.Kind.none,
           operation.textRole == "title" || layer.name == "AI 标题" {
            var style = layer.textAppearance ?? DiaryTextAppearance()
            if style.strokeWidth == 0 {
                let ink = layer.textColor ?? DiaryColor(red: 0.1, green: 0.1, blue: 0.1)
                let luminance = ink.red * 0.2126 + ink.green * 0.7152 + ink.blue * 0.0722
                style.strokeColor = luminance < 0.5 ? .white : DiaryColor(red: 0.12, green: 0.12, blue: 0.12)
                style.strokeWidth = 2.0
                layer.textAppearance = style
            }
        }
        if limitsTextToAvailableRegions, operation.type == "createText", let center = operation.center,
           let region = layoutRegions.first(where: { $0.role == "text" && $0.bounds.contains(center) }) {
            let maximumWidth = max(40, region.width - 24)
            layer.size.width = min(layer.size.width, maximumWidth)
            if DiaryPageRenderer.textBounds(layer).height > region.height - 24 {
                layer.size.width = maximumWidth
            }
        } else if fitsTextToPlannedRegions, let center = operation.center,
           let region = layoutRegions.first(where: { $0.role == "text" && $0.bounds.contains(center) }) {
            // Keep the measured paper inside its allocated box, including shadow and padding.
            layer.size.width = max(40, min(layer.size.width, region.width - 24))
            let preferred = layer.fontSize
            let minimum = min(preferred, context.size.width * (operation.textRole == "title" ? 0.03 : 0.014))
            while DiaryPageRenderer.textBounds(layer).height > region.height - 24 && layer.fontSize > minimum {
                layer.fontSize = max(minimum, layer.fontSize - 2)
            }
        } else if request?.design != nil, request?.instruction.isEmpty == true {
            Self.avoidOrphanLine(&layer, maximumWidth: context.size.width * 0.44)
        }
        layer.size.height = DiaryPageRenderer.textBounds(layer).height
    }
    static func nearbyStickerPlacement(_ bounds: CGRect, in page: CGRect, text: [CGRect],
                                      photoCores: [CGRect], stickers: [CGRect]) -> CGRect {
        let fit = min(1, page.width / bounds.width, page.height / bounds.height)
        let obstacles = text + photoCores + stickers
        let distanceUnit = max(1, min(page.width, page.height))
        var best: (rect: CGRect, score: CGFloat)?
        for factor: CGFloat in [1, 0.82, 0.68] {
            let scale = fit * factor
            let width = bounds.width * scale, height = bounds.height * scale
            let maxX = max(page.minX, page.maxX - width), maxY = max(page.minY, page.maxY - height)
            let xs: [CGFloat] = [page.minX, maxX, bounds.midX - width / 2] + obstacles.flatMap { [$0.minX - width - 1, $0.maxX + 1] }
            let ys: [CGFloat] = [page.minY, maxY, bounds.midY - height / 2] + obstacles.flatMap { [$0.minY - height - 1, $0.maxY + 1] }
            for x in Set(xs.map { min(max($0, page.minX), maxX) }).sorted() {
                for y in Set(ys.map { min(max($0, page.minY), maxY) }).sorted() {
                    let candidate = CGRect(x: x, y: y, width: width, height: height)
                    func overlap(_ areas: [CGRect]) -> CGFloat {
                        areas.reduce(0) { result, area in
                            let intersection = candidate.intersection(area)
                            guard !intersection.isNull else { return result }
                            return result + intersection.width * intersection.height / max(1, min(width * height, area.width * area.height))
                        }
                    }
                    let distance = hypot(candidate.midX - bounds.midX, candidate.midY - bounds.midY) / distanceUnit
                    let score = distance + (1 - scale) * 0.7 + overlap(stickers) * 0.35
                        + overlap(photoCores) * 3 + overlap(text) * 20
                    if best.map({ score < $0.score }) ?? true { best = (candidate, score) }
                }
            }
        }
        return best?.rect ?? bounds
    }

    private func place(_ operation: DiaryAIOperation, id: UUID, document: inout DiaryDocument, context: DiaryAIContext, finalStickerPlacement: Bool = false, allowsStickerOverlap: Bool = false) throws {
        guard var layer = document.layer(id) else { throw DiaryAIError.invalid("对象不存在") }
        let siblings = document.objects[context.contentID]!.layers
        try require(layer.transform.warp == nil, "透视变形对象需保留原位置，请先在编辑器内调整")
        if let scale = operation.scale { try require(scale.isFinite && (0.05...20).contains(scale), "缩放无效"); layer.transform.scale = scale }
        if let angle = operation.angle { try require(angle.isFinite && abs(angle) <= 180, "角度无效"); layer.transform.rotationDegrees = angle }
        if operation.type == "setPlacement", let width = operation.width {
            let bounds = DiaryPageRenderer.bounds(layer, document: document, siblings: siblings).applying(layer.transform.matrix)
            try require(width.isFinite && width > 0 && bounds.width > 0, "最终可见宽度无效")
            var factor = width / bounds.width
            if let maxHeight = operation.maxHeight {
                try require(maxHeight.isFinite && maxHeight > 0 && bounds.height > 0, "最终可见高度上限无效")
                factor = min(factor, maxHeight / bounds.height)
            }
            layer.transform.scale *= factor
            try require(layer.transform.scale.isFinite && (0.05...20).contains(layer.transform.scale), "最终缩放超出范围")
        }
        if let center = operation.center {
            try require(center.x.isFinite && center.y.isFinite, "位置无效")
            let bounds = DiaryPageRenderer.bounds(layer, document: document, siblings: siblings).applying(layer.transform.matrix)
            layer.transform.position.x += center.x - bounds.midX
            layer.transform.position.y += center.y - bounds.midY
        }
        if autoFitPhotoRegions, let region = layoutRegions.first(where: { $0.role == "photo" && $0.objectID == id.uuidString })?.bounds {
            let bounds = DiaryPageRenderer.bounds(layer, document: document, siblings: siblings).applying(layer.transform.matrix)
            let factor = min(1, region.width / max(1, bounds.width), region.height / max(1, bounds.height))
            layer.transform.scale *= factor
            try require(layer.transform.scale >= 0.05, "规划区域太小，无法保留照片可读尺寸")
            let fitted = DiaryPageRenderer.bounds(layer, document: document, siblings: siblings).applying(layer.transform.matrix)
            layer.transform.position.x += min(max(fitted.minX, region.minX), region.maxX - fitted.width) - fitted.minX
            layer.transform.position.y += min(max(fitted.minY, region.minY), region.maxY - fitted.height) - fitted.minY
        }
        if autoFitPhotoRegions && (finalStickerPlacement || operation.type != "setPlacement") && role(layer, in: document) == "decoration" {
            let page = CGRect(origin: .zero, size: context.size)
            let blockers = siblings.filter { $0.id != id && $0.visible && !excludedRenderIDs.contains($0.id) && role($0, in: document) == "decoration" && !pendingStickerPlacements.contains($0.id) }.map {
                DiaryPageRenderer.bounds($0, document: document, siblings: siblings).applying($0.transform.matrix)
            }
            let bounds = DiaryPageRenderer.bounds(layer, document: document, siblings: siblings).applying(layer.transform.matrix)
            let textAreas = siblings.filter { $0.id != id && $0.visible && !excludedRenderIDs.contains($0.id) && role($0, in: document) == "text" }.map {
                DiaryPageRenderer.bounds($0, document: document, siblings: siblings).applying(DiaryPageRenderer.matrix($0, siblings: siblings))
            }
            // Keep stickers on photo edges; protect the central subject area even
            // when the visual reviewer misses a face beneath a sticker.
            let photoBounds = siblings.filter { $0.visible && !excludedRenderIDs.contains($0.id) && role($0, in: document) == "photo" }.map { photo in
                DiaryPageRenderer.bounds(photo, document: document, siblings: siblings).applying(DiaryPageRenderer.matrix(photo, siblings: siblings))
            }
            let photoCores = photoBounds.map { $0.insetBy(dx: $0.width * 0.12, dy: $0.height * 0.12) }
            func clear(_ rect: CGRect, preferStaggered: Bool = true) -> Bool {
                let rowPeers = blockers.filter {
                    abs($0.midY - rect.midY) < min($0.height, rect.height) * 0.45
                        && abs($0.midX - rect.midX) < max($0.width, rect.width) * 3
                }
                let columnPeers = blockers.filter {
                    abs($0.midX - rect.midX) < min($0.width, rect.width) * 0.45
                        && abs($0.midY - rect.midY) < max($0.height, rect.height) * 3
                }
                return (!preferStaggered || (rowPeers.count < 2 && columnPeers.count < 2)) && page.contains(rect) && !photoCores.contains(where: { $0.intersects(rect) }) && !(context.spineX.map { rect.minX < $0 + 24 && rect.maxX > $0 - 24 } ?? false) && !textAreas.contains(where: { $0.intersects(rect) }) && !blockers.contains { other in
                    let overlap = rect.intersection(other)
                    return !overlap.isNull && overlap.width * overlap.height / max(1, min(rect.width * rect.height, other.width * other.height)) > 0.3
                }
            }
            if !clear(bounds) {
                var options = [CGRect]()
                // Preserve size and rotation; repair small edge overflow before another model round.
                if bounds.width <= page.width && bounds.height <= page.height {
                    let dx = min(max(bounds.minX, page.minX), page.maxX - bounds.width) - bounds.minX
                    let dy = min(max(bounds.minY, page.minY), page.maxY - bounds.height) - bounds.minY
                    if hypot(dx, dy) <= min(page.width, page.height) * 0.03 {
                        options.append(bounds.offsetBy(dx: dx, dy: dy))
                    }
                }
                for other in blockers + textAreas + photoCores where bounds.intersects(other) {
                    options += [bounds.offsetBy(dx: other.maxX + 12 - bounds.minX, dy: 0), bounds.offsetBy(dx: other.minX - 12 - bounds.maxX, dy: 0), bounds.offsetBy(dx: 0, dy: other.maxY + 12 - bounds.minY), bounds.offsetBy(dx: 0, dy: other.minY - 12 - bounds.maxY)]
                }
                if let associatedPhoto = photoBounds.min(by: {
                    hypot($0.midX - bounds.midX, $0.midY - bounds.midY) < hypot($1.midX - bounds.midX, $1.midY - bounds.midY)
                }) {
                    let anchors = [CGPoint(x: associatedPhoto.minX, y: associatedPhoto.minY), CGPoint(x: associatedPhoto.midX, y: associatedPhoto.minY),
                                   CGPoint(x: associatedPhoto.maxX, y: associatedPhoto.minY), CGPoint(x: associatedPhoto.minX, y: associatedPhoto.midY),
                                   CGPoint(x: associatedPhoto.maxX, y: associatedPhoto.midY), CGPoint(x: associatedPhoto.minX, y: associatedPhoto.maxY),
                                   CGPoint(x: associatedPhoto.midX, y: associatedPhoto.maxY), CGPoint(x: associatedPhoto.maxX, y: associatedPhoto.maxY)]
                    options += anchors.map { bounds.offsetBy(dx: $0.x - bounds.midX, dy: $0.y - bounds.midY) }
                }
                // A corner can require moving on both axes (e.g. clear a title
                // horizontally and bring the rotated bottom edge onto the page).
                let margin: CGFloat = 1
                var safePage = page
                if let spine = context.spineX {
                    safePage = bounds.midX < spine
                        ? CGRect(x: 0, y: 0, width: spine - 24, height: page.height)
                        : CGRect(x: spine + 24, y: 0, width: page.width - spine - 24, height: page.height)
                }
                let obstacles = blockers + textAreas + photoCores
                var xs = [bounds.minX, safePage.minX + margin, safePage.maxX - bounds.width - margin]
                var ys = [bounds.minY, margin, page.height - bounds.height - margin]
                for obstacle in obstacles {
                    xs += [obstacle.minX - bounds.width - 12, obstacle.maxX + 12]
                    ys += [obstacle.minY - bounds.height - 12, obstacle.maxY + 12]
                }
                for x in xs {
                    for y in ys {
                        options.append(CGRect(origin: CGPoint(x: x, y: y), size: bounds.size))
                    }
                }
                // Tight gaps may fit the sticker but not the preferred 12-point gutter.
                // Include close-fitting corners while still validating the whole transformed rect.
                var tightX = [bounds.minX, safePage.minX, safePage.maxX - bounds.width]
                var tightY = [bounds.minY, safePage.minY, safePage.maxY - bounds.height]
                for obstacle in obstacles {
                    tightX += [obstacle.minX - bounds.width - 0.01, obstacle.maxX + 0.01]
                    tightY += [obstacle.minY - bounds.height - 0.01, obstacle.maxY + 0.01]
                }
                func nearestSafe(in candidates: [CGRect], preferStaggered: Bool = true) -> CGRect? {
                    candidates.filter { safePage.contains($0) && clear($0, preferStaggered: preferStaggered) }.min {
                        hypot($0.minX - bounds.minX, $0.minY - bounds.minY)
                            < hypot($1.minX - bounds.minX, $1.minY - bounds.minY)
                    }
                }
                var nearest = nearestSafe(in: options)
                if nearest == nil {
                    for x in Set(tightX).sorted() {
                        for y in Set(tightY).sorted() {
                            options.append(CGRect(origin: CGPoint(x: x, y: y), size: bounds.size))
                        }
                    }
                    nearest = nearestSafe(in: options) ?? nearestSafe(in: options, preferStaggered: false)
                }
                if let nearest {
                    layer.transform.position.x += nearest.midX - bounds.midX
                    layer.transform.position.y += nearest.midY - bounds.midY
                } else if allowsStickerOverlap {
                    let nearby = Self.nearbyStickerPlacement(bounds, in: safePage, text: textAreas,
                                                            photoCores: photoCores, stickers: blockers)
                    layer.transform.scale *= nearby.width / bounds.width
                    let resized = DiaryPageRenderer.bounds(layer, document: document, siblings: siblings).applying(layer.transform.matrix)
                    layer.transform.position.x += nearby.midX - resized.midX
                    layer.transform.position.y += nearby.midY - resized.midY
                } else if finalStickerPlacement {
                    throw StickerSpaceUnavailable()
                }
            }
        }
        if finalStickerPlacement { pendingStickerPlacements.remove(id) }
        document.update(id) { $0 = layer }
    }
    func propose(_ plan: DiaryAIPlan) async throws -> DiaryAIDraft {
        pendingStickerPlacements = Set(plan.operations.filter { $0.type == "setPlacement" }.compactMap(\.objectID))
        guard let base, let context, let request, let session else { throw DiaryAIError.invalid("快照已失效") }
        try require(plan.schemaVersion == 1 && plan.contextID == context.id && plan.baseDigest == context.digest, "计划基础版本不匹配")
        try require(plan.operations.count <= 200 && Set(plan.operations.map(\.operationID)).count == plan.operations.count, "操作重复或过多")
        var copy = base, changed = Set<UUID>(), warnings: [String] = []
        var localNew = newImages
        var nextOrder: [UUID]?
        // Geometry-changing operations precede placement, independent of tool arrival order.
        let operations = plan.operations.filter { $0.type != "setPlacement" } + plan.operations.filter { $0.type == "setPlacement" }
        for operation in operations {
            try Task.checkCancellation()
            try validateFields(operation)
            let descriptor = context.objects.first { $0.id == operation.objectID }
            let outer = operation.objectID.flatMap { copy.layer($0) }
            if operation.type != "createText" && operation.type != "placeExistingMaterial" && operation.type != "setZOrder" {
                try require(descriptor?.editable == true && outer != nil, "对象不在可编辑范围或包含锁定内容")
                if descriptor?.role == "background" { try require(!request.preservesBackground && request.action == .relayout, "不允许改变背景") }
            }
            switch operation.type {
            case "setPlacement":
                try require(request.canMove || descriptor?.role == "text", "当前功能不能移动照片或装饰")
                try require(operation.center != nil && operation.scale != nil && operation.angle != nil, "位置参数不完整")
                try place(operation, id: outer!.id, document: &copy, context: context); changed.insert(outer!.id)
                if request.action == .beautify, let descriptor {
                    let factor = request.strength == "保守" ? 1.0 : 2.0
                    try require(abs(operation.center!.x - descriptor.center.x) <= context.size.width * 0.05 * factor && abs(operation.center!.y - descriptor.center.y) <= context.size.height * 0.05 * factor && abs(operation.scale! / descriptor.scale - 1) <= 0.1 * factor && abs(operation.angle! - descriptor.angle) <= 3 * factor, "美化超出轻量调整范围，请使用重新排版")
                }
            case "setZOrder":
                try require(allowedBatchIDs == nil, "分批模式请保持既有层级，不提交全页顺序")
                try require(request.canMove && !request.selectedOnly, "当前功能或范围不允许改变层级")
                nextOrder = operation.order
                try require(nextOrder != nil, "缺少完整层级顺序")
            case "createText":
                try require(request.canCreateText && operation.text != nil && operation.center != nil, "未授权新增文字或文字参数不完整")
                guard let key = operation.clientObjectKey, !key.isEmpty else { throw DiaryAIError.invalid("新增文字缺少稳定 key") }
                let id = createdIDs[key] ?? UUID(); createdIDs[key] = id
                try require(copy.layer(id) == nil, "重复新增文字 key")
                var layer = DiaryLayer(id: id, name: "AI 文字", kind: .text, transform: DiaryTransform(position: .zero, pivot: .zero), size: CGSize(width: operation.width ?? 500, height: 80), textAppearance: DiaryNewTextDefaults.appearance, font: DiaryNewTextDefaults.font)
                if key.hasPrefix("story-"), let sourceID = UUID(uuidString: String(key.dropFirst(6))),
                   request.creationBrief?.storyEntries?.contains(where: { $0.id == sourceID }) == true {
                    layer.storySourceID = sourceID
                }
                try configureText(operation, layer: &layer, context: context)
                if !request.writesLocation && !request.location.isEmpty { try require(!layer.text.contains(request.location), "地点未授权写入文字") }
                copy.appendObject(containing: layer, to: context.contentID)
                try place(operation, id: id, document: &copy, context: context); changed.insert(id)
            case "updateText":
                try require(descriptor?.role == "text", "目标不是可编辑文字")
                try require(operation.text == nil || request.canRewrite, "未授权修改原文")
                var leaf = primary(outer!, in: copy)
                try require(context.objects.filter { item in base.layer(item.id).map { descendants($0, in: base).contains { $0.id == leaf.id } } ?? false }.count == 1, "文字内容被多个对象共享，请先独立编辑")
                try configureText(operation, layer: &leaf, context: context)
                copy.update(leaf.id) { $0 = leaf }
                if let owner = outer!.contentID { copy.objects[owner]?.referenceSize = leaf.size }
                copy.update(outer!.id) { $0.size = leaf.size }
                try place(operation, id: outer!.id, document: &copy, context: context); changed.insert(outer!.id)
            case "setPhotoCrop":
                try require(request.allowsCrop && request.action != .beautify && request.action != .writing && descriptor?.role == "photo", "未授权照片取景")
                var leaf = primary(outer!, in: copy)
                try require(leaf.photoSlot == nil && leaf.photoCrop == nil && leaf.photoPlacement == nil, "此照片使用特殊槽位或已烘焙裁剪，请保留现有取景")
                guard let zoom = operation.cropZoom, let x = operation.cropX, let y = operation.cropY else { throw DiaryAIError.invalid("取景参数不完整") }
                try require([zoom, x, y].allSatisfy(\.isFinite) && (1...3).contains(zoom) && abs(x) <= leaf.size.width && abs(y) <= leaf.size.height, "取景参数超出安全范围")
                leaf.crop = DiaryCrop(zoom: zoom, offset: CGPoint(x: x, y: y)); leaf.photoFill = nil
                copy.update(leaf.id) { $0 = leaf }; changed.insert(outer!.id)
            case "setFrameStyle":
                try require(request.allowsFrames && request.action != .beautify && request.action != .writing && descriptor?.role == "photo", "未授权相框调整")
                guard let style = operation.frameStyle, let index = DiaryPhotoFrameCatalog.names.firstIndex(of: style) else { throw DiaryAIError.invalid("相框样式不存在") }
                let leaf = primary(outer!, in: copy)
                guard let owner = copy.objects.values.first(where: { $0.layers.contains { $0.id == leaf.id } })?.id else { throw DiaryAIError.invalid("相框所属对象丢失") }
                let item = DiaryPhotoFrameCatalog.generated(style: index, ratio: leaf.size.width / leaf.size.height)
                try await waitForViewport()
                guard let image = item.image else { throw DiaryAIError.invalid("相框生成失败") }
                let bytes = try await DiaryAIImageWork.run {
                    guard let data = image.pngData() else { throw DiaryAIError.invalid("相框生成失败") }
                    return data
                }
                let (asset, decoded) = try await session.store.importImage(bytes, documentID: base.id)
                images[asset.id] = decoded; localNew[asset.id] = bytes; copy.assets[asset.id] = asset
                copy.objects[owner]?.layers.removeAll { $0.frameTargetID == leaf.id }
                copy.objects[owner]?.layers.append(DiaryEditorSession.photoFrame(item, asset: asset, photo: leaf, manual: true))
                changed.insert(outer!.id)
            case "setDecorationVisibility":
                try require(request.allowsDecorations && request.action != .writing && request.action != .beautify && ["decoration", "frame"].contains(descriptor?.role ?? ""), "只能调整已授权装饰的可见性")
                guard let visible = operation.visible else { throw DiaryAIError.invalid("缺少可见性") }
                copy.update(outer!.id) { $0.visible = visible }; changed.insert(outer!.id)
            case "placeExistingMaterial":
                try require(request.allowsMaterials && request.action == .relayout, "未授权使用已有素材")
                guard let id = operation.materialID, request.materialIDs.contains(id), let source = base.layer(id), role(source, in: base) == "decoration", let asset = primary(source, in: base).assetID,
                      let resource = base.assets[asset], let key = operation.clientObjectKey else { throw DiaryAIError.invalid("素材不在明确授权列表中") }
                let newID = createdIDs[key] ?? UUID(); createdIDs[key] = newID
                try require(copy.layer(newID) == nil, "重复素材 key")
                let layer = DiaryLayer(id: newID, name: source.name, kind: .sticker, transform: DiaryTransform(position: .zero, pivot: .zero), size: resource.pixelSize, assetID: asset)
                copy.appendObject(containing: layer, to: context.contentID)
                try place(operation, id: newID, document: &copy, context: context); changed.insert(newID)
            default: throw DiaryAIError.invalid("不支持的操作 \(operation.type)")
            }
        }
        if let order = nextOrder {
            let layers = copy.objects[context.contentID]!.layers
            try require(order.count == layers.count && Set(order) == Set(layers.map(\.id)), "层级顺序必须包含全部对象且不能重复")
            for (index, layer) in base.objects[context.contentID]!.layers.enumerated() {
                if context.objects.first(where: { $0.id == layer.id })?.locked == true || role(layer, in: base) == "background" {
                    try require(order[index] == layer.id, "锁定对象和背景层级不能改变")
                }
            }
            for frame in layers where frame.frameTargetID != nil {
                if let target = frame.frameTargetID, let photoIndex = order.firstIndex(of: target), let frameIndex = order.firstIndex(of: frame.id) {
                    try require(frameIndex == photoIndex + 1, "照片和绑定相框必须保持相邻顺序")
                }
            }
            copy.objects[context.contentID]?.layers = order.compactMap { id in layers.first { $0.id == id } }
        }
        if operations.contains(where: { $0.type == "createText" }), let brief = request.creationBrief {
            let texts = (copy.objects[context.contentID]?.layers ?? []).flatMap { descendants($0, in: copy) }.filter { $0.kind == .text && $0.visible }.map(\.text)
            try DiaryAIWorkspaceTools.validateRequiredStoryTexts(texts, brief: brief)
        }
        // Measure the complete decorated card before validating planned regions. Preserve typography and paper.
        var autoPositionedText = Set<UUID>()
        let newTextIDs = operations.filter { $0.type == "createText" }.sorted {
            ($0.textRole == "title" ? 0 : 1) < ($1.textRole == "title" ? 0 : 1)
        }.compactMap { $0.clientObjectKey.flatMap { createdIDs[$0] } }
        for id in newTextIDs + changed.subtracting(newTextIDs).sorted(by: { $0.uuidString < $1.uuidString }) {
            guard let layer = copy.layer(id), role(layer, in: copy) == "text" else { continue }
            let siblings = copy.objects[context.contentID]!.layers
            let bounds = DiaryPageRenderer.bounds(layer, document: copy, siblings: siblings).applying(DiaryPageRenderer.matrix(layer, siblings: siblings))
            let canvas = CGRect(origin: .zero, size: context.size)
            let candidates = layoutRegions.filter { $0.role == "text" && ($0.objectID == nil || $0.objectID == id.uuidString) }.map { $0.bounds.intersection(canvas) }
            let newCard = operations.contains { $0.type == "createText" && $0.clientObjectKey.flatMap { createdIDs[$0] } == id }
            let fitCard = autoFitPhotoRegions || newCard
            guard fitCard || !candidates.isEmpty else { continue }
            let safePages = Self.safeTextPages(context)
            let expandedCandidates = fitCard ? candidates.map { rect -> CGRect in
                let width = max(rect.width, bounds.width), height = max(rect.height, bounds.height)
                return CGRect(x: min(rect.minX, canvas.maxX - width), y: min(rect.minY, canvas.maxY - height), width: width, height: height)
            } : candidates
            var regions = ((expandedCandidates.isEmpty ? [canvas] : expandedCandidates) + (fitCard ? safePages : [])).flatMap { region in safePages.map { region.intersection($0) } }.filter { !$0.isNull && $0.width >= bounds.width && $0.height >= bounds.height }
            if fitCard {
                let blockers = siblings.filter { $0.id != id && $0.visible && !excludedRenderIDs.contains($0.id) && ["photo", "text"].contains(role($0, in: copy)) && !(changed.contains($0.id) && role($0, in: copy) == "text" && !autoPositionedText.contains($0.id)) }.map {
                    DiaryPageRenderer.bounds($0, document: copy, siblings: siblings).applying(DiaryPageRenderer.matrix($0, siblings: siblings)).insetBy(dx: -8, dy: -8)
                }
                for obstacle in blockers {
                    regions = Self.freeTextRects(regions, excluding: obstacle, minimum: bounds.size)
                    if regions.count > 128 { regions = Array(regions.prefix(128)) }
                }
            }
            func moveDistance(_ rect: CGRect) -> CGFloat {
                let x = min(max(bounds.minX, rect.minX), rect.maxX - bounds.width)
                let y = min(max(bounds.minY, rect.minY), rect.maxY - bounds.height)
                return hypot(x - bounds.minX, y - bounds.minY)
            }
            guard let region = regions.min(by: { moveDistance($0) < moveDistance($1) }) else {
                if fitCard {
                    let key = operations.first { $0.clientObjectKey.flatMap { createdIDs[$0] } == id }?.clientObjectKey ?? id.uuidString
                    throw DiaryAIError.invalid("纸卡\(key)在同页没有可容纳的无照片遮挡空隙，真实纸卡尺寸\(bounds.size)。保留其他操作，只精简此处文案或调整此卡宽度，不移动照片、不取消纸卡。")
                }
                continue
            }
            if fitCard { autoPositionedText.insert(id) }
            let dx = min(max(bounds.minX, region.minX), region.maxX - bounds.width) - bounds.minX
            let dy = min(max(bounds.minY, region.minY), region.maxY - bounds.height) - bounds.minY
            if abs(dx) > 0.01 || abs(dy) > 0.01 {
                copy.update(id) { $0.transform.position.x += dx; $0.transform.position.y += dy }
                autoPositionedText.insert(id)
                warnings.append("文字纸卡按真实尺寸移入预留区，字体、字号与纸卡保持不变")
            }
        }
        if autoFitPhotoRegions {
            let stickers = changed.filter { id in
                copy.layer(id).map { role($0, in: copy) == "decoration" } == true
                    && operations.contains { $0.objectID == id && $0.type == "setPlacement" }
            }.sorted { left, right in
                let a = copy.layer(left)!, b = copy.layer(right)!
                let siblings = copy.objects[context.contentID]!.layers
                let first = DiaryPageRenderer.bounds(a, document: copy, siblings: siblings).applying(a.transform.matrix)
                let second = DiaryPageRenderer.bounds(b, document: copy, siblings: siblings).applying(b.transform.matrix)
                let areaA = first.width * first.height, areaB = second.width * second.height
                return areaA == areaB ? left.uuidString < right.uuidString : areaA > areaB
            }
            let original = copy
            var needsOverlapFallback = false
            // Retry bounded orderings from the same candidate so an early small
            // sticker cannot permanently consume the only large free region.
            let attemptsPerSize = max(1, stickers.count * 2)
            let sizeFactors = fitsNativeStickerSizes ? [1.0, 0.82, 0.68] : [1.0]
            for attempt in 0..<(attemptsPerSize * sizeFactors.count) {
                try Task.checkCancellation()
                copy = original
                pendingStickerPlacements = Set(stickers)
                let orderAttempt = attempt % attemptsPerSize
                let sizeFactor = sizeFactors[attempt / attemptsPerSize]
                var order = orderAttempt < stickers.count ? stickers : Array(stickers.reversed())
                if !order.isEmpty {
                    let offset = orderAttempt % order.count
                    order = Array(order.dropFirst(offset)) + Array(order.prefix(offset))
                }
                do {
                    for id in order {
                        var resolved = operations.last { $0.objectID == id && $0.type == "setPlacement" }!
                        resolved.scale = nil
                        resolved.width = sizeFactor == 1 ? nil : resolved.width.map { $0 * sizeFactor }
                        resolved.angle = nil; resolved.center = nil
                        try place(resolved, id: id, document: &copy, context: context, finalStickerPlacement: true)
                    }
                    needsOverlapFallback = false
                    break
                } catch is CancellationError { throw CancellationError() }
                catch is StickerSpaceUnavailable { needsOverlapFallback = true }
            }
            if needsOverlapFallback {
                copy = original
                pendingStickerPlacements = Set(stickers)
                for id in stickers {
                    try Task.checkCancellation()
                    let operation = DiaryAIOperation(operationID: id.uuidString, type: "setPlacement", objectID: id)
                    try place(operation, id: id, document: &copy, context: context,
                              finalStickerPlacement: true, allowsStickerOverlap: true)
                }
                warnings.append("部分贴纸已移到附近空位或与周围图层轻叠，请在预览确认。")
            }
        }
        let siblings = copy.objects[context.contentID]!.layers
        for id in changed {
            guard let layer = copy.layer(id), layer.visible else { continue }
            let bounds = DiaryPageRenderer.bounds(layer, document: copy, siblings: siblings).applying(DiaryPageRenderer.matrix(layer, siblings: siblings))
            let originalRole = role(layer, in: copy)
            func reject(_ code: String, _ suggestion: String) throws -> Never {
                let key = operations.first { $0.type == "createText" && $0.clientObjectKey.map { createdIDs[$0] == id } == true }?.clientObjectKey
                let feedback: [String: Any] = ["code": code, "objectID": id.uuidString,
                    "clientObjectKey": key ?? "", "bounds": [bounds.minX, bounds.minY, bounds.width, bounds.height],
                    "canvas": [context.size.width, context.size.height], "spineX": context.spineX as Any? ?? NSNull(),
                    "suggestion": suggestion, "matchingRegions": layoutRegions.filter { $0.role == originalRole }.map { ["x": $0.bounds.minX, "y": $0.bounds.minY, "width": $0.bounds.width, "height": $0.bounds.height] }, "measuredCardSize": [bounds.width, bounds.height]]
                throw DiaryAIError.invalid(String(decoding: try JSONSerialization.data(withJSONObject: feedback, options: [.sortedKeys]), as: UTF8.self))
            }
            if originalRole != "background" {
                if !bounds.width.isFinite || !bounds.height.isFinite || !CGRect(origin: .zero, size: context.size).insetBy(dx: -1, dy: -1).contains(bounds) {
                    try reject("out_of_bounds", "保留暂存操作，缩小或移动此对象到画布内")
                }
                if let spine = context.spineX, ["text", "photo"].contains(originalRole) {
                    if bounds.minX < spine + 24 && bounds.maxX > spine - 24 {
                        try reject("spine_overlap", "文字或照片跨越书脊安全区；保留暂存操作，将此对象移入左页或右页，离书脊至少24单位")
                    }
                }
            }
            let regions = layoutRegions.filter { $0.role == originalRole && ($0.objectID == nil || $0.objectID == id.uuidString) }
            if !regions.isEmpty && !regions.contains(where: { $0.bounds.insetBy(dx: -1, dy: -1).contains(bounds) }) && !autoFitPhotoRegions && !autoPositionedText.contains(id) {
                try reject("outside_planned_region", "完整对象超出规划区域，measuredCardSize包含纸卡内边距。优先缩短正文、语义换行或选择能容纳的matchingRegions；保留字体、字号和纸卡，不以取消纸卡或连续缩字作为修复。")
            }
            if originalRole == "photo" {
                if layoutRegions.contains(where: { $0.role == "text" && $0.bounds.intersects(bounds) }) {
                    warnings.append("照片与建议文字区域相交；文字纸卡将依据实际照片边界自动避让")
                }
                for upper in siblings.dropFirst((siblings.firstIndex(where: { $0.id == id }) ?? 0) + 1) where upper.visible && !excludedRenderIDs.contains(upper.id) && upper.frameTargetID != id {
                    let other = DiaryPageRenderer.bounds(upper, document: copy, siblings: siblings).applying(DiaryPageRenderer.matrix(upper, siblings: siblings))
                    if bounds.intersects(other) { warnings.append("照片\(id)与上方对象\(upper.id)重叠；视觉确认须检查人物及主体遮挡，可request_batch_revision修复") }
                }
            }
            if originalRole == "text" {
                for upper in siblings.dropFirst((siblings.firstIndex(where: { $0.id == id }) ?? 0) + 1) where upper.visible {
                    let other = DiaryPageRenderer.bounds(upper, document: copy, siblings: siblings).applying(DiaryPageRenderer.matrix(upper, siblings: siblings))
                    let overlap = bounds.intersection(other)
                    if !overlap.isNull && ["photo", "text"].contains(role(upper, in: copy)) {
                        if overlap.width * overlap.height / max(1, bounds.width * bounds.height) >= 0.25 { try reject("text_occluded", "此clientObjectKey文字被上方图层遮挡；保留其他操作，只将此文字移入无冲突的文字区域。不要重复修改未报错标题。") }
                    }
                    if bounds.intersects(other) { warnings.append("文字与上方图层相交，请检查预览：\(layer.name)"); break }
                }
            }
        }
        for operation in plan.operations where operation.type == "setPlacement" && !autoPositionedText.contains(operation.objectID ?? UUID()) && !(autoFitPhotoRegions && (layoutRegions.contains { $0.role == "photo" && $0.objectID == operation.objectID?.uuidString } || operation.objectID.flatMap { copy.layer($0) }.map { role($0, in: copy) == "decoration" } == true)) {
            guard let id = operation.objectID, let expected = operation.center,
                  let layer = copy.layer(id) else { continue }
            let actual = DiaryPageRenderer.bounds(layer, document: copy, siblings: siblings).applying(DiaryPageRenderer.matrix(layer, siblings: siblings))
            try require(abs(actual.midX - expected.x) < 1 && abs(actual.midY - expected.y) < 1, "图层 \(context.objects.first { $0.id == id }?.shortID ?? id.uuidString) 实际中心 (\(actual.midX),\(actual.midY)) 与请求 (\(expected.x),\(expected.y)) 不一致；保留暂存操作，请修订该图层")
        }
        try Task.checkCancellation()
        _ = try DiaryDocumentStore.validate(copy)
        let preview = rendersDraftPreview ? try await pageImage(copy) : Data()
        let revision = (draft?.revision ?? 0) + 1
        let archiveValue = Archive(base: base, candidate: copy, drawings: base.objects.mapValues(\.drawing), request: request, context: context, revision: revision, summary: plan.summary, warnings: warnings, newImages: localNew)
        let archive = try await DiaryAIImageWork.run { try JSONEncoder().encode(archiveValue) }
        let value = DiaryAIDraft(id: draft?.id ?? UUID(), revision: revision, preview: preview, archive: archive, summary: plan.summary, warnings: warnings)
        candidate = copy; draft = value; newImages = localNew
        return value
    }
    private func validateFields(_ operation: DiaryAIOperation) throws {
        let common: Set<String> = ["operationID", "type", "objectID"]
        let fields: [String: Set<String>] = [
            "setPlacement": ["center", "scale", "angle", "width", "maxHeight"], "setZOrder": ["order"],
            "createText": ["clientObjectKey", "textRole", "text", "fontID", "fontSize", "width", "color", "paper", "center", "scale", "angle"],
            "updateText": ["textRole", "text", "fontID", "fontSize", "width", "color", "paper", "center", "scale", "angle"],
            "setPhotoCrop": ["cropZoom", "cropX", "cropY"], "setFrameStyle": ["frameStyle"],
            "setDecorationVisibility": ["visible"], "placeExistingMaterial": ["clientObjectKey", "materialID", "center", "scale", "angle"]]
        guard let allowed = fields[operation.type] else { throw DiaryAIError.invalid("未知操作") }
        let values = try JSONSerialization.jsonObject(with: JSONEncoder().encode(operation)) as! [String: Any]
        try require(Set(values.keys).isSubset(of: common.union(allowed)), "操作包含无关参数")
    }
    private nonisolated struct Archive: Codable, Sendable {
        var base: DiaryDocument; var candidate: DiaryDocument; var drawings: [UUID: Data]
        var request: DiaryAIRequest; var context: DiaryAIContext; var revision: Int
        var summary: String; var warnings: [String]; var newImages: [UUID: Data]
    }
    func restore(_ archive: Data) throws -> DiaryAIDraft {
        guard let session else { throw DiaryAIError.invalid("编辑器已关闭") }
        var value = try JSONDecoder().decode(Archive.self, from: archive)
        for (id, data) in value.drawings { value.base.objects[id]?.drawing = data; value.candidate.objects[id]?.drawing = data }
        let restoredDigest = try Self.digest(value.base)
        try require(value.context.contentID == session.contentID && value.base.id == session.document.id && restoredDigest == value.context.digest, "草稿数据不匹配")
        _ = try DiaryDocumentStore.validate(value.candidate)
        base = value.base; candidate = value.candidate; context = value.context; request = value.request; images = session.images; newImages = value.newImages
        for (id, bytes) in newImages { images[id] = UIImage(data: bytes) }
        let result = DiaryAIDraft(id: UUID(), revision: value.revision, preview: Data(), archive: archive, summary: value.summary, warnings: value.warnings)
        draft = result; return result
    }
    func apply() throws {
        guard let session, let base, let candidate else { throw DiaryAIError.invalid("草稿不存在或已应用") }
        try require(session.applyAIDraft(candidate, expected: base, additionalImages: images), "画布内容已改变，请重新生成草稿；原作品未被覆盖")
        self.candidate = nil; draft = nil
    }
    func discard() { candidate = nil; draft = nil; newImages = [:] }
}
