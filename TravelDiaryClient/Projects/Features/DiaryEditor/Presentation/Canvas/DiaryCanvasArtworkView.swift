import UIKit

/// 普通对象由独立 CALayer 合成。特殊混合模式使用已缓存的对象位图合成，保持 CG 混合语义。
final class DiaryCanvasArtworkView: UIView {
    var cache: DiaryCanvasRenderCache?
    var preview: DiaryLayer?
    var composited = false
    private var lastBackground: DiaryColor?
    private var lastReferenceSize = CGSize.zero
    private var lastBounds = CGRect.null
    private var lastVersion: UInt64?
    private var lastRasterCount = -1
    private var lastComposited = false
    func invalidateContentIfNeeded() {
        guard let cache, let id = cache.contentID, let content = cache.document.objects[id] else { return }
        let backgroundChanged = lastBackground != content.background || lastReferenceSize != content.referenceSize || lastBounds != bounds
        if backgroundChanged || lastComposited != composited || (composited && (lastVersion != cache.visualVersion || lastRasterCount != cache.rasterCount)) {
            setNeedsDisplay()
        }
        lastBackground = content.background; lastReferenceSize = content.referenceSize; lastBounds = bounds
        lastVersion = cache.visualVersion; lastRasterCount = cache.rasterCount; lastComposited = composited
    }
    var showInk = true {
        didSet { if showInk != oldValue && composited { setNeedsDisplay() } }
    }
    private static let checker: UIColor = {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: 60, height: 60), format: format).image { _ in
            UIColor.white.setFill(); UIRectFill(CGRect(x: 0, y: 0, width: 60, height: 60))
            UIColor(white: 0.92, alpha: 1).setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: 30, height: 30))
            UIRectFill(CGRect(x: 30, y: 30, width: 30, height: 30))
        }
        return UIColor(patternImage: image)
    }()
    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false; backgroundColor = .clear; clipsToBounds = true
        contentMode = .redraw
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ rect: CGRect) {
        guard let cache, let id = cache.contentID, let content = cache.document.objects[id],
              let context = UIGraphicsGetCurrentContext() else { return }
        Self.checker.setFill(); context.fill(bounds)
        if let color = content.background {
            DiaryPageRenderer.color(color).setFill()
            context.fill(CGRect(origin: .zero, size: content.referenceSize))
        }
        guard composited else { return }
        for entry in cache.ordered where entry.source.visible {
            var matrix = entry.source.transform.matrix
            if let target = entry.source.frameTargetID, let frameTarget = cache.entries[target] { matrix = frameTarget.source.transform.matrix }
            if let preview, preview.id == entry.id || entry.source.frameTargetID == preview.id { matrix = preview.transform.matrix }
            // 先粗筛；不为屏幕外对象执行合成。
            guard entry.rect.applying(matrix).intersects(bounds) else { continue }
            context.saveGState()
            context.concatenate(matrix)
            switch entry.source.blendMode ?? .normal {
            case .normal: context.setBlendMode(.normal)
            case .multiply: context.setBlendMode(.multiply)
            case .darken: context.setBlendMode(.darken)
            case .linearBurn: context.setBlendMode(.plusDarker)
            case .lighten: context.setBlendMode(.lighten)
            }
            let translucent = entry.source.effectiveOpacity < 1
            if translucent {
                context.setAlpha(entry.source.effectiveOpacity)
                context.beginTransparencyLayer(auxiliaryInfo: nil)
            }
            if entry.source.displayBounds != nil, let child = entry.source.contentID,
               let background = cache.document.objects[child]?.background {
                context.setFillColor(DiaryPageRenderer.color(background).cgColor)
                context.fill(entry.rect)
            }
            entry.image?.draw(in: entry.rect)
            if translucent { context.endTransparencyLayer() }
            context.restoreGState()
        }
        if showInk { cache.inkImage?.draw(in: cache.inkRect) }
    }
}

final class DiaryCanvasSelectionView: UIView {
    weak var owner: DiaryCanvasSurface?
    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false; backgroundColor = .clear
        contentMode = .redraw
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        owner?.drawSelection(in: context)
    }
}
