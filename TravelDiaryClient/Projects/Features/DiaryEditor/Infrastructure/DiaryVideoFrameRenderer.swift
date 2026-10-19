import UIKit

/// Deterministic strip mesh: the front is the current right page; the back is
/// the next left page. Only paper moves. Leather and binding remain fixed.
nonisolated enum DiaryVideoFrameRenderer {
    static let background = UIColor(red: 0.98, green: 0.975, blue: 0.96, alpha: 1)

    static func image(size: CGSize, title: String, sample: DiaryVideoTimeline.Sample,
                      current: UIImage, next: UIImage?, rings: UIImage) -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            draw(in: context.cgContext, size: size, title: title, sample: sample, current: current, next: next, rings: rings)
        }
    }

    static func bookRect(size: CGSize, spreadSize: CGSize) -> CGRect {
        let available = CGSize(width: size.width * 0.9, height: size.height * 0.82)
        let scale = min(available.width / spreadSize.width, available.height / spreadSize.height)
        let fitted = CGSize(width: spreadSize.width * scale, height: spreadSize.height * scale)
        return CGRect(x: (size.width - fitted.width) / 2, y: (size.height - fitted.height) / 2, width: fitted.width, height: fitted.height)
    }

    /// Context uses UIKit's top-left origin, both in preview and pixel buffers.
    static func draw(in ctx: CGContext, size: CGSize, title: String, sample: DiaryVideoTimeline.Sample,
                     current: UIImage, next: UIImage?, rings: UIImage) {
        background.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
        if sample.intro {
            ctx.saveGState(); ctx.setAlpha(sample.opacity)
            let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: min(size.width, size.height) * 0.047, weight: .semibold),
                .foregroundColor: UIColor(red: 0.23, green: 0.36, blue: 0.31, alpha: 1), .paragraphStyle: paragraph
            ]
            let area = CGRect(x: size.width * 0.12, y: size.height * 0.35, width: size.width * 0.76, height: size.height * 0.3)
            let text = title as NSString
            let height = text.boundingRect(with: area.size, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes, context: nil).height
            text.draw(with: CGRect(x: area.minX, y: (size.height - min(height, area.height)) / 2, width: area.width, height: area.height),
                      options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes, context: nil)
            ctx.restoreGState(); return
        }
        let book = bookRect(size: size, spreadSize: current.size)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: book.width * 0.012), blur: book.width * 0.025,
                      color: UIColor.black.withAlphaComponent(0.18).cgColor)
        current.draw(in: book)
        ctx.restoreGState()
        guard let next, sample.next != nil else { return }
        let p = max(0, min(1, sample.turn))
        if p <= 0 { return }
        if p >= 1 { next.draw(in: book); return }
        // Reveal the next right page underneath the turning sheet.
        ctx.saveGState()
        ctx.clip(to: CGRect(x: book.midX, y: book.minY, width: book.width / 2, height: book.height))
        next.draw(in: book); ctx.restoreGState()

        let rim = book.width * 0.0225
        let inner = book.width - 2 * rim
        let gap = inner * DiaryBookSpine.halfGapFraction
        let pageWidth = (inner - gap) / 2
        let pageHeight = book.height - 2 * rim
        let eased = p * p * (3 - 2 * p)
        let angle = CGFloat(eased * .pi)
        let cosine = cos(angle), lift = sin(angle)
        let back = p >= 0.5
        let source = back ? next : current
        let paper = CGRect(x: back ? book.minX + rim : book.midX + gap / 2,
                           y: book.minY + rim, width: pageWidth, height: pageHeight)
        let hinge = book.midX + (back ? -gap / 2 : gap / 2)
        // A narrowing cast shadow follows the paper across the fixed leaves.
        let shadowWidth = max(1, abs(cosine) * pageWidth)
        let shadow = CGRect(x: back ? hinge - shadowWidth : hinge, y: paper.minY,
                            width: shadowWidth, height: paper.height)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: book.width * (back ? -0.005 : 0.005), height: book.width * 0.005), blur: book.width * 0.014,
                      color: UIColor.black.withAlphaComponent(0.22 * lift).cgColor)
        UIColor.black.withAlphaComponent(0.07 * lift).setFill(); ctx.fill(shadow)
        ctx.restoreGState()

        let strips = 96
        for index in 0..<strips {
            let u0 = CGFloat(index) / CGFloat(strips), u1 = CGFloat(index + 1) / CGFloat(strips)
            // Cylinder-like bend and vertical foreshortening, pinned at the spine.
            func position(_ u: CGFloat) -> CGFloat {
                hinge + cosine * pageWidth * u + (back ? -1 : 1) * lift * pageWidth * 0.09 * sin(.pi * u)
            }
            let a = position(u0), b = position(u1)
            let width = abs(b - a)
            guard width > 0.02 else { continue }
            let inset = lift * sin(.pi * (u0 + u1) / 2) * pageHeight * 0.035
            let target = CGRect(x: min(a, b), y: paper.minY + inset, width: width + 0.6, height: pageHeight - 2 * inset)
            let sourceX = back ? paper.maxX - u1 * pageWidth : paper.minX + u0 * pageWidth
            let slice = CGRect(x: sourceX, y: paper.minY, width: pageWidth / CGFloat(strips), height: pageHeight)
            ctx.saveGState(); ctx.clip(to: target)
            ctx.translateBy(x: target.minX, y: target.minY)
            ctx.scaleBy(x: target.width / slice.width, y: target.height / slice.height)
            source.draw(in: book.offsetBy(dx: -slice.minX, dy: -slice.minY))
            ctx.restoreGState()
            UIColor.black.withAlphaComponent(lift * (0.08 + 0.14 * sin(.pi * u0))).setFill()
            ctx.fill(target)
        }
        // Transparent overlay shares the exact binding layout used by JPG exports.
        rings.draw(in: book)
    }
}
