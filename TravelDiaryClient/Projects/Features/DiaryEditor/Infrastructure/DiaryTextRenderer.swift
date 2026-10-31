import UIKit

extension DiaryPageRenderer {
    static func displayedText(_ layer: DiaryLayer) -> String {
        if layer.textAppearance?.vertical == true {
            return layer.text.split(separator: "\n", omittingEmptySubsequences: false)
                .map { $0.map(String.init).joined(separator: "\n") }.joined(separator: "\n\n")
        }
        guard layer.textAppearance?.titleLayout == .balanced, !layer.text.contains("\n") else { return layer.text }
        let characters = Array(layer.text)
        guard characters.count > 2 else { return layer.text }
        // Preserve Latin words and avoid placing punctuation at the start of a line.
        let candidates = (1..<characters.count).filter { index in
            let a = characters[index-1], b = characters[index]
            let latinWord = a.isASCII && b.isASCII && a.isLetter && b.isLetter
            return !latinWord && !"，。！？、；：,.!?;:）】》".contains(b)
        }
        guard let split = candidates.min(by: { abs($0 * 2 - characters.count) < abs($1 * 2 - characters.count) }) else { return layer.text }
        return String(characters[..<split]).trimmingCharacters(in: .whitespaces) + "\n" + String(characters[split...]).trimmingCharacters(in: .whitespaces)
    }

    static func textInsets(_ layer: DiaryLayer) -> UIEdgeInsets {
        let style = layer.textAppearance ?? DiaryTextAppearance()
        if let paper = style.paper {
            guard paper.kind != .none else { return .zero }
            return UIEdgeInsets(top: layer.fontSize * paper.verticalPadding, left: layer.fontSize * paper.horizontalPadding,
                                bottom: layer.fontSize * paper.verticalPadding, right: layer.fontSize * paper.horizontalPadding)
        }
        let padding: CGFloat = style.template != .plain ? max(20, layer.fontSize * (style.template == .burst ? 1.2 : 0.7))
            : (style.background == nil ? 0 : layer.fontSize * 0.35)
        return UIEdgeInsets(top: padding, left: padding, bottom: padding, right: padding)
    }

    static func textPadding(_ layer: DiaryLayer) -> CGFloat { textInsets(layer).left }

    static func textBounds(_ layer: DiaryLayer) -> CGRect {
        let padding = textInsets(layer)
        let width = max(1, layer.size.width - padding.left - padding.right)
        let measured = (displayedText(layer) as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: textStyle(layer), context: nil)
        let naturalHeight = max(ceil(measured.height), layer.fontSize * 1.2) + padding.top + padding.bottom
        let height = max(naturalHeight, CGFloat(layer.textAppearance?.minimumCardHeight ?? 0))
        let effect: CGFloat = max(CGFloat(layer.textAppearance?.paper?.kind == DiaryTextPaper.Kind.none ? 0 : (layer.textAppearance?.paper?.shadow ?? 0)) * 24, max(CGFloat(layer.textAppearance?.shadowRadius ?? 0) * 2,
                                  layer.fontSize * CGFloat(layer.textAppearance?.strokeWidth ?? 0) / 100))
        return CGRect(x: -effect, y: -effect, width: layer.size.width + effect * 2, height: height + effect * 2)
    }

    static func drawText(_ layer: DiaryLayer, in context: CGContext, revealedCharacters: Int? = nil) {
        let style = layer.textAppearance ?? DiaryTextAppearance()
        let bounds = textBounds(layer)
        let effect = -bounds.minX
        let rect = bounds.insetBy(dx: effect, dy: effect)
        context.saveGState()
        defer { context.restoreGState() }
        drawTextDecoration(style, rect: rect, in: context)
        var textRect = rect.inset(by: textInsets(layer))
        if style.minimumCardHeight != nil {
            let measured = (displayedText(layer) as NSString).boundingRect(
                with: CGSize(width: max(1, textRect.width), height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: textStyle(layer), context: nil)
            let height = max(ceil(measured.height), layer.fontSize * 1.2)
            textRect.origin.y += max(0, (textRect.height - height) / 2)
            textRect.size.height = height
        }
        let text = displayedText(layer)
        let attributed = NSMutableAttributedString(string: text, attributes: textStyle(layer))
        if let revealedCharacters {
            let visibleLength = String(text.prefix(revealedCharacters)).utf16.count
            let remaining = NSRange(location: visibleLength, length: attributed.length - visibleLength)
            attributed.addAttributes([.foregroundColor: UIColor.clear, .strokeColor: UIColor.clear], range: remaining)
            attributed.removeAttribute(.shadow, range: remaining)
        }
        attributed.draw(with: textRect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
    }

    private static func drawTextDecoration(_ style: DiaryTextAppearance, rect: CGRect, in context: CGContext) {
        if let paper = style.paper {
            drawPaper(paper, rect: rect, in: context)
            return
        }
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

    private static func drawPaper(_ paper: DiaryTextPaper, rect: CGRect, in context: CGContext) {
        guard paper.kind != .none else { return }
        let r = rect.insetBy(dx: 2, dy: 2)
        let path: UIBezierPath
        switch paper.kind {
        case .torn:
            path = UIBezierPath()
            let corners = [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
                           CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)]
            for edge in 0..<4 {
                let a = corners[edge], b = corners[(edge+1)%4]
                let length = max(1, hypot(b.x-a.x, b.y-a.y))
                let count = max(2, Int(length / 4))
                for i in 0..<count {
                    let t = CGFloat(i)/CGFloat(count)
                    let phase = Double(i) + Double(paper.seed % 10000)*1.37 + Double(edge)*71
                    let noise = sin(phase*0.23)*0.55 + sin(phase*1.71)*0.3 + sin(phase*2.93)*0.15
                    let displacement = CGFloat(noise * paper.roughness) * min(12, r.height * 0.08) * sin(.pi*t)
                    let point = CGPoint(x: a.x+(b.x-a.x)*t-(b.y-a.y)/length*displacement,
                                        y: a.y+(b.y-a.y)*t+(b.x-a.x)/length*displacement)
                    if edge == 0 && i == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
            }
            path.close()
        case .tape:
            path = UIBezierPath()
            let cut = min(14, r.width * 0.05)
            path.move(to: CGPoint(x: r.minX+cut, y: r.minY))
            path.addLine(to: CGPoint(x: r.maxX, y: r.minY+3))
            path.addLine(to: CGPoint(x: r.maxX-cut, y: r.maxY))
            path.addLine(to: CGPoint(x: r.minX, y: r.maxY-3)); path.close()
        default:
            path = UIBezierPath(roundedRect: r, cornerRadius: min(r.height, r.width) * paper.cornerRadius * 0.5)
        }
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: paper.shadow*5), blur: paper.shadow*12,
                          color: UIColor.black.withAlphaComponent(paper.shadow*0.4).cgColor)
        color(paper.color).setFill(); path.fill()
        context.restoreGState()
    }

    static func textPreview(_ layer: DiaryLayer) -> UIImage {
        let bounds = textBounds(layer)
        let scale = min(1, 600 / max(bounds.width, bounds.height))
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: max(1, bounds.width*scale), height: max(1, bounds.height*scale)), format: format).image { renderer in
            renderer.cgContext.scaleBy(x: scale, y: scale)
            renderer.cgContext.translateBy(x: -bounds.minX, y: -bounds.minY)
            drawText(layer, in: renderer.cgContext)
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
