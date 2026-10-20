import UIKit

extension DiaryPageRenderer {
    static func displayedText(_ layer: DiaryLayer) -> String {
        guard layer.textAppearance?.vertical == true else { return layer.text }
        return layer.text.map(String.init).joined(separator: "\n")
    }

    static func textPadding(_ layer: DiaryLayer) -> CGFloat {
        let style = layer.textAppearance ?? DiaryTextAppearance()
        if style.template != .plain { return max(20, layer.fontSize * (style.template == .burst ? 1.2 : 0.7)) }
        return style.background == nil ? 0 : layer.fontSize * 0.35
    }

    static func textBounds(_ layer: DiaryLayer) -> CGRect {
        let padding = textPadding(layer)
        let width = max(1, layer.size.width - padding * 2)
        let measured = (displayedText(layer) as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: textStyle(layer), context: nil)
        let height = max(ceil(measured.height), layer.fontSize * 1.2) + padding * 2
        let effect: CGFloat = max(CGFloat(layer.textAppearance?.shadowRadius ?? 0) * 2,
                                  layer.fontSize * CGFloat(layer.textAppearance?.strokeWidth ?? 0) / 100)
        return CGRect(x: -effect, y: -effect, width: layer.size.width + effect * 2, height: height + effect * 2)
    }

    static func drawText(_ layer: DiaryLayer, in context: CGContext) {
        let style = layer.textAppearance ?? DiaryTextAppearance()
        let bounds = textBounds(layer)
        let effect = -bounds.minX
        let rect = bounds.insetBy(dx: effect, dy: effect)
        context.saveGState()
        defer { context.restoreGState() }
        drawTextDecoration(style, rect: rect, in: context)
        (displayedText(layer) as NSString).draw(with: rect.insetBy(dx: textPadding(layer), dy: textPadding(layer)),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: textStyle(layer), context: nil)
    }

    private static func drawTextDecoration(_ style: DiaryTextAppearance, rect: CGRect, in context: CGContext) {
        guard style.template != .plain || style.background != nil else { return }
        let r = rect.insetBy(dx: 3, dy: 3)
        let path: UIBezierPath
        switch style.template {
        case .burst:
            path = UIBezierPath()
            for index in 0..<40 {
                let angle = CGFloat(index) * .pi / 20
                let scale: CGFloat = index.isMultiple(of: 2) ? 1 : 0.83
                let point = CGPoint(x: r.midX + cos(angle) * r.width / 2 * scale,
                                    y: r.midY + sin(angle) * r.height / 2 * scale)
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.close()
        case .tape:
            path = UIBezierPath()
            path.move(to: CGPoint(x: r.minX + 12, y: r.minY))
            path.addLine(to: CGPoint(x: r.maxX, y: r.minY + 5))
            path.addLine(to: CGPoint(x: r.maxX - 12, y: r.maxY))
            path.addLine(to: CGPoint(x: r.minX, y: r.maxY - 5)); path.close()
        case .bubble:
            path = UIBezierPath(roundedRect: r, cornerRadius: min(24, r.height / 5))
            path.move(to: CGPoint(x: r.width * 0.18, y: r.maxY - 1))
            path.addLine(to: CGPoint(x: r.width * 0.12, y: r.maxY - r.height * 0.16))
            path.addLine(to: CGPoint(x: r.width * 0.30, y: r.maxY - 1)); path.close()
        default:
            path = UIBezierPath(roundedRect: r, cornerRadius: style.template == .capsule ? r.height / 2 : 14)
        }
        color(style.background ?? style.template.background).setFill(); path.fill()
        if [.label, .bubble, .ticket, .postcard].contains(style.template) {
            color(.brown).withAlphaComponent(0.55).setStroke(); path.lineWidth = 2; path.stroke()
        }
        if style.template == .label {
            context.setFillColor(color(.pink).cgColor)
            context.fill(CGRect(x: r.minX + 14, y: r.minY + 8, width: r.width - 28, height: 7))
        }
        if style.template == .ticket {
            context.setStrokeColor(color(.brown).withAlphaComponent(0.35).cgColor)
            context.setLineDash(phase: 0, lengths: [5, 5])
            context.move(to: CGPoint(x: r.minX + 20, y: r.minY + 12))
            context.addLine(to: CGPoint(x: r.minX + 20, y: r.maxY - 12)); context.strokePath()
        }
        if style.template == .postcard {
            context.setFillColor(color(.yellow).withAlphaComponent(0.85).cgColor)
            context.fill(CGRect(x: r.midX - r.width * 0.16, y: r.minY, width: r.width * 0.32, height: 12))
        }
    }

    static func textTemplateThumbnail(_ template: DiaryTextTemplate) -> UIImage {
        let layer = DiaryLayer(name: template.title, kind: .text,
            transform: DiaryTransform(position: .zero, pivot: .zero), size: CGSize(width: 240, height: 100),
            text: template == .plain ? "普通文字" : "记录美好", fontSize: 28,
            textAppearance: DiaryTextAppearance(template: template, bold: template == .burst), textColor: template.textColor)
        let bounds = textBounds(layer)
        return UIGraphicsImageRenderer(size: bounds.size).image { renderer in
            renderer.cgContext.translateBy(x: -bounds.minX, y: -bounds.minY)
            drawText(layer, in: renderer.cgContext)
        }
    }
}
