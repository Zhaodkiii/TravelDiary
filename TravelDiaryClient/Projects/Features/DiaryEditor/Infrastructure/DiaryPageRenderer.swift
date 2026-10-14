import UIKit
import PencilKit

/// 预览和导出共用绘制规则，避免文字换行、照片裁剪和图层顺序出现两套解释。
@MainActor
enum DiaryPageRenderer {
    static func textStyle(_ layer: DiaryLayer) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineHeightMultiple = 1.2
        return [.font: UIFont.systemFont(ofSize: layer.fontSize), .foregroundColor: UIColor.darkText,
                .paragraphStyle: paragraph]
    }

    static func bounds(_ layer: DiaryLayer) -> CGRect {
        if layer.kind == .group {
            return layer.children.filter(\.visible).reduce(CGRect.null) {
                $0.union(bounds($1).applying($1.transform.matrix))
            }
        }
        if layer.kind == .text {
            let rect = (layer.text as NSString).boundingRect(
                with: CGSize(width: layer.size.width, height: 10000),
                options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: textStyle(layer), context: nil)
            return CGRect(x: 0, y: 0, width: layer.size.width, height: max(ceil(rect.height), layer.fontSize * 1.2))
        }
        return CGRect(origin: .zero, size: layer.size)
    }

    static func draw(_ document: DiaryDocument, images: [UUID: UIImage], drawing: PKDrawing?, in context: CGContext) {
        let pageRect = CGRect(origin: .zero, size: document.page.size)
        context.saveGState()
        context.clip(to: pageRect)
        context.setFillColor(UIColor(red: 1, green: 0.973, blue: 0.933, alpha: 1).cgColor)
        context.fill(pageRect)
        for layer in document.page.layers { draw(layer, document: document, images: images, in: context) }
        if let drawing, !drawing.strokes.isEmpty {
            drawing.image(from: pageRect, scale: 2).draw(in: pageRect)
        }
        context.restoreGState()
    }

    private static func draw(_ layer: DiaryLayer, document: DiaryDocument, images: [UUID: UIImage], in context: CGContext) {
        guard layer.visible else { return }
        context.saveGState()
        context.concatenate(layer.transform.matrix)
        switch layer.kind {
        case .group:
            for child in layer.children { draw(child, document: document, images: images, in: context) }
        case .text:
            (layer.text as NSString).draw(with: bounds(layer), options: [.usesLineFragmentOrigin, .usesFontLeading],
                                         attributes: textStyle(layer), context: nil)
        case .photo, .sticker:
            if let id = layer.assetID, let image = images[id], let asset = document.assets[id] {
                let frame = CGRect(origin: .zero, size: layer.size)
                context.clip(to: frame)
                let rect = layer.kind == .photo ? layer.crop.imageRect(source: asset.pixelSize, frame: layer.size) : frame
                image.draw(in: rect)
            }
        }
        context.restoreGState()
    }

    static func export(_ document: DiaryDocument, images: [UUID: UIImage], drawing: PKDrawing) throws -> URL {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: document.page.size, format: format).image { renderer in
            draw(document, images: images, drawing: drawing, in: renderer.cgContext)
        }
        guard let data = image.pngData() else { throw DiaryEditorError.exportFailed }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("手帐-\(UUID().uuidString).png")
        try data.write(to: url, options: .atomic)
        return url
    }
}
