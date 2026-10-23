import Foundation
import CoreGraphics

nonisolated enum DiaryAlbumSaveError: LocalizedError {
    case invalidPage(Int)
    var errorDescription: String? {
        switch self {
        case .invalidPage(let number): "第 \(number) 页的排版数据未通过保存校验，制作草稿仍保留。请重试或更换该页版式。"
        }
    }
}

nonisolated enum DiaryAlbumDocumentBuilder {
    static func document(page: DiaryAlbumPage, draft: DiaryAlbumDraft, assets: [UUID: DiaryAsset], pageSize: CGSize? = nil, pageNumber: Int? = nil) -> DiaryDocument {
        var document = DiaryDocument()
        document.id = page.id; document.bookID = draft.id
        document.title = page.title.isEmpty ? page.role.title : page.title
        let size = pageSize ?? draft.pageSize
        document.objects[document.rootContentID]?.referenceSize = size
        document.objects[document.rootContentID]?.background = page.theme.palette(page.paletteID).paper
        let palette = page.theme.palette(page.paletteID)
        let pageNumber = pageNumber ?? (draft.pages.firstIndex(where: { $0.id == page.id }) ?? 0) + 1
        if page.theme == .zine, page.paletteID != nil, page.paletteID != "0", pageNumber.isMultiple(of: 3), page.spreadID == nil {
            addBlock(CGRect(x: 0, y: 0, width: 0.035, height: 1), color: palette.accent, name: "主题色条", size: size, document: &document)
        }
        let frames = DiaryAlbumGeometry.frames(page: page, photos: draft.photos)
        for (index, placement) in page.placements.enumerated() {
            guard let asset = assets[placement.photoID], frames.indices.contains(index) else { continue }
            let f = frames[index]
            let rect = CGRect(x: f.minX * size.width, y: f.minY * size.height, width: f.width * size.width, height: f.height * size.height)
            document.assets[asset.id] = asset
            var layer = DiaryLayer(name: "照片 \(index + 1)", kind: .photo,
                transform: DiaryTransform(position: CGPoint(x: rect.midX, y: rect.midY), pivot: CGPoint(x: rect.width / 2, y: rect.height / 2)),
                size: rect.size, assetID: asset.id)
            let scale = max(rect.width / asset.pixelSize.width, rect.height / asset.pixelSize.height) * CGFloat(placement.zoom)
            layer.crop = DiaryCrop(zoom: CGFloat(placement.zoom), offset: CGPoint(
                x: CGFloat(placement.offsetX) * max(0, (asset.pixelSize.width * scale - rect.width) / 2),
                y: CGFloat(placement.offsetY) * max(0, (asset.pixelSize.height * scale - rect.height) / 2)))
            layer.semanticKind = .photo
            if page.theme == .scrapbook && page.layout != .fullBleed {
                layer.transform.rotationDegrees = index.isMultiple(of: 2) ? -1.2 : 1.2
            }
            if (page.theme == .scrapbook || page.theme == .film) && page.layout != .fullBleed {
                let pad: CGFloat = page.theme == .scrapbook ? 0.012 : 0.004
                addBlock(f.insetBy(dx: -pad, dy: -pad), color: page.theme == .scrapbook ? .white : palette.ink,
                         name: "照片纸卡", size: size, document: &document)
            }
            document.appendObject(containing: layer)
            if page.theme == .film && page.layout != .fullBleed {
                addText(String(format: "%02d", index + 1), name: "照片编号", rect: CGRect(x: f.minX, y: f.maxY + 0.004, width: 0.12, height: 0.018),
                        font: 0.014, page: page, size: size, document: &document)
            }
        }
        if page.role == .cover && page.theme == .magazine {
            addText("TRAVEL JOURNAL", name: "刊头", rect: CGRect(x: 0.08, y: 0.025, width: 0.84, height: 0.025), font: 0.017, page: page, size: size, document: &document)
            addBlock(CGRect(x: 0.08, y: 0.208, width: 0.84, height: 0.002), color: palette.accent, name: "分隔线", size: size, document: &document)
        }
        if !page.title.isEmpty {
            let centered = page.role == .chapter || page.role == .ending || page.role == .introduction
            addText(page.title, name: "标题", rect: CGRect(x: 0.08, y: centered ? 0.32 : 0.06, width: 0.84, height: centered ? 0.20 : 0.14),
                    font: page.theme == .zine ? 0.085 : page.role == .cover || centered ? 0.055 : 0.035, page: page, size: size, document: &document)
        }
        if !page.caption.isEmpty {
            let y: CGFloat = page.role == .chapter || page.role == .ending || page.role == .introduction ? 0.55 : page.role == .cover ? 0.85 : 0.79
            addText(page.caption, name: "说明", rect: CGRect(x: 0.08, y: y, width: 0.84, height: 0.17), font: 0.025,
                    page: page, size: size, document: &document)
        }
        if page.role == .photos && page.layout != .fullBleed {
            let footer = [page.dateLabel, String(format: "%02d", pageNumber)].compactMap { $0 }.joined(separator: "   /   ")
            addText(footer, name: "日期与页码", rect: CGRect(x: 0.08, y: 0.966, width: 0.84, height: 0.025), font: 0.016,
                    page: page, size: size, document: &document)
        }
        return document
    }
    private static func addBlock(_ rect: CGRect, color: DiaryColor, name: String, size: CGSize, document: inout DiaryDocument) {
        // 独立装饰的外层实例是 object，内部内容必须是合法 canvas；
        // object 是引用节点类型，不是存储协议允许的内容角色。
        let content = DiaryObjectContent(role: .canvas, referenceSize: CGSize(width: rect.width * size.width, height: rect.height * size.height), background: color, layers: [])
        document.objects[content.id] = content
        document.objects[document.rootContentID]?.layers.append(DiaryLayer(name: name, kind: .object,
            transform: DiaryTransform(position: CGPoint(x: rect.minX * size.width, y: rect.minY * size.height), pivot: .zero),
            size: content.referenceSize, contentID: content.id))
    }
    private static func addText(_ text: String, name: String, rect: CGRect, font: CGFloat, page: DiaryAlbumPage, size: CGSize, document: inout DiaryDocument) {
        var layer = DiaryLayer(name: name, kind: .text,
            transform: DiaryTransform(position: CGPoint(x: rect.minX * size.width, y: rect.minY * size.height), pivot: .zero),
            size: CGSize(width: rect.width * size.width, height: rect.height * size.height))
        layer.text = text
        let glyphUnits = text.unicodeScalars.reduce(0.0) { $0 + ($1.value > 255 ? 1 : 0.6) }
        let fit = sqrt(rect.width * rect.height / max(1, glyphUnits * 1.5))
        layer.fontSize = size.width * min(font, fit)
        layer.textColor = page.theme.palette(page.paletteID).ink
        layer.textAlignment = [.magazine, .zine, .editorial].contains(page.theme) ? .left : .center
        if name == "标题", page.theme == .magazine || page.theme == .zine {
            var appearance = DiaryTextAppearance(); appearance.bold = true; layer.textAppearance = appearance
        }
        layer.semanticKind = .text
        document.appendObject(containing: layer)
    }
}
