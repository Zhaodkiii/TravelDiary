import SwiftUI
import UIKit
import PencilKit

struct DiaryCanvasView: UIViewRepresentable {
    @ObservedObject var session: DiaryEditorSession
    var compactViewport = false
    var stagesEntrance = false
    var showsSelection = true
    var editingTextLayer: DiaryLayer? = nil
    var lockedTextID: UUID? = nil
    var onTextAdjustment: ((DiaryLayer) -> Void)? = nil
    var focusedLayerID: UUID? = nil
    var onSelectionViewportRect: ((CGRect?) -> Void)? = nil
    var onEdit: () -> Void = {}
    func makeUIView(context: Context) -> DiaryCanvasSurface {
        let view = DiaryCanvasSurface(); view.stagesEntrance = stagesEntrance; view.session = session; view.compactViewport = compactViewport; view.editingTextLayer = editingTextLayer; view.lockedTextID = lockedTextID; view.onTextAdjustment = onTextAdjustment; view.showsSelection = showsSelection; view.focusedLayerID = focusedLayerID; view.onEdit = onEdit; view.onSelectionViewportRect = onSelectionViewportRect; return view
    }
    func updateUIView(_ view: DiaryCanvasSurface, context: Context) {
        view.stagesEntrance = stagesEntrance; view.session = session; view.compactViewport = compactViewport; view.editingTextLayer = editingTextLayer; view.lockedTextID = lockedTextID; view.onTextAdjustment = onTextAdjustment; view.showsSelection = showsSelection; view.focusedLayerID = focusedLayerID; view.onEdit = onEdit; view.onSelectionViewportRect = onSelectionViewportRect; view.refresh()
    }
}

/// 每个对象使用独立设计坐标；视口可包含负坐标，装饰伸出照片时仍保留原位置。
final class DiaryCanvasSurface: UIView {
    var stagesEntrance = false
    private var entranceFinished = false
    private var entrancePlaying = false
    private let entranceTextHaptic = UIImpactFeedbackGenerator(style: .light)
    private let entrancePhotoHaptic = UIImpactFeedbackGenerator(style: .medium)
    private let entranceStickerHaptic = UIImpactFeedbackGenerator(style: .rigid)
    private var lastEntranceHaptic = -Double.infinity
    private func playEntranceHaptic(_ kind: Int) {
        guard window != nil, UIApplication.shared.applicationState == .active,
              CACurrentMediaTime() - lastEntranceHaptic >= 0.075 else { return }
        lastEntranceHaptic = CACurrentMediaTime()
        let generator = kind == 0 ? entranceTextHaptic : (kind == 1 ? entrancePhotoHaptic : entranceStickerHaptic)
        generator.impactOccurred(intensity: kind == 0 ? 0.65 : 0.85)
        generator.prepare()
    }
    private var entranceWork: [DispatchWorkItem] = []
    weak var session: DiaryEditorSession?
    var compactViewport = false {
        didSet { if compactViewport != oldValue { refresh(force: true) } }
    }
    var editingTextLayer: DiaryLayer?
    var lockedTextID: UUID?
    var onTextAdjustment: ((DiaryLayer) -> Void)?
    var focusedLayerID: UUID? {
        didSet { if focusedLayerID != oldValue { refresh(force: true) } }
    }
    var showsSelection = true {
        didSet { selectionOverlay.isHidden = !showsSelection }
    }
    var onSelectionViewportRect: ((CGRect?) -> Void)?
    var onEdit: () -> Void = {}
    private enum Handle: CaseIterable {
        case delete, edit, move, scale, top, bottom, left, right, rotate
        var symbol: String {
            switch self {
            case .delete: "xmark"
            case .edit: "pencil"
            case .move: "arrow.up.and.down.and.arrow.left.and.right"
            case .scale: "arrow.up.left.and.arrow.down.right"
            case .rotate: "arrow.clockwise"
            case .left, .right: "minus"
            default: "minus"
            }
        }
    }
    let renderCache = DiaryCanvasRenderCache()
    private let artwork = DiaryCanvasArtworkView()
    private let selectionOverlay = DiaryCanvasSelectionView()
    private var retainedLayers: [UUID: CALayer] = [:]
    private let inkLayer = CALayer()
    private var renderedSessionID: UUID?
    private var renderedGeneration: UInt64?
    private var renderedSize = CGSize.zero
    private var renderTask: Task<Void, Never>?
    private var resolutionTask: Task<Void, Never>?
    private var preview: DiaryLayer?
    private var displayedSelection: DiaryLayer? { preview ?? editingTextLayer ?? session?.transformDraft?.layer ?? session?.selected }
    private var lastDraftLayer: DiaryLayer?
    private var warpHandle: Int?
    private var warpStart: DiaryLayer?
    private var warpTouch = CGPoint.zero
    private var activeHandle: Handle?
    private var initialLayer: DiaryLayer?
    private var initialBounds = CGRect.zero
    private var initialTouch = CGPoint.zero
    private var rotationLast: CGFloat = 0
    private var rotationTotal: CGFloat = 0
    private var startPosition: CGPoint?
    private var draggingID: UUID?
    private var parentAtStart = CGAffineTransform.identity
    static let controlMargin: CGFloat = 56
    static let toolControlMargin: CGFloat = 8
    private var contentMargin: CGFloat { compactViewport || session?.layerMode == true ? Self.toolControlMargin : Self.controlMargin }
    private var fit: CGFloat { (bounds.width - contentMargin * 2) / (session?.canvasBounds.width ?? 1000) }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        artwork.isUserInteractionEnabled = false
        artwork.layer.anchorPoint = .zero
        addSubview(artwork)
        selectionOverlay.isUserInteractionEnabled = false
        selectionOverlay.owner = self
        addSubview(selectionOverlay)
        artwork.layer.addSublayer(inkLayer)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
        let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        pan.maximumNumberOfTouches = 1
        addGestureRecognizer(pan)
        accessibilityLabel = "手帐画布，可在图层面板选择元素"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        selectionOverlay.frame = bounds
        refresh()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            renderTask?.cancel(); renderTask = nil
            resolutionTask?.cancel(); resolutionTask = nil
            preview = nil
        } else { refresh(force: true) }
    }

    /// 发布保存状态或选择变化时只刷新轻量选框，不访问对象树。
    func refresh(force: Bool = false) {
        guard let session, fit > 0, bounds.height > 0 else { return }
        if lastDraftLayer != nil && session.transformDraft == nil {
            preview=nil; warpStart=nil; warpHandle=nil
        }
        let changed = renderedSessionID != session.id || renderedGeneration != session.renderGeneration
        let resized = renderedSize != bounds.size
        if changed {
            renderedSessionID = session.id; renderedGeneration = session.renderGeneration
            renderCache.synchronize(document: session.document, images: session.images, contentID: session.contentID)
        }
        artwork.showInk = !session.inkMode
        if changed || resized || force {
            renderedSize = bounds.size
            CATransaction.begin(); CATransaction.setDisableActions(true)
            artwork.bounds = session.canvasBounds
            // backing store 按屏幕像素分配，不能按数千点设计尺寸乘设备倍率。
            artwork.contentScaleFactor = max(0.01, min(fit * (window?.screen.scale ?? traitCollection.displayScale) * viewportZoom,
                sqrt(4 * 1024 * 1024 / max(1, session.canvasBounds.width * session.canvasBounds.height))))
            artwork.layer.position = CGPoint(x: contentMargin, y: contentMargin)
            artwork.transform = CGAffineTransform(scaleX: fit, y: fit)
            var previewScale = fit
            // Focus changes only the viewport; the draft's size and position remain untouched.
            if let id = focusedLayerID, let entry = renderCache.entries[id] {
                let rect = entry.rect
                let projection = displayTransform(entry.source).projection
                let points = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                              CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)].map { projection.point($0) }
                let left = points.map(\.x).min() ?? 0
                let top = points.map(\.y).min() ?? 0
                let width = max(1, (points.map(\.x).max() ?? left) - left)
                let height = max(1, (points.map(\.y).max() ?? top) - top)
                let focusScale = max(0.01, min((bounds.width - 64) / width, (bounds.height - 64) / height, 2))
                artwork.transform = CGAffineTransform(scaleX: focusScale, y: focusScale)
                artwork.layer.position = CGPoint(
                    x: bounds.midX - (left + width / 2 - session.canvasBounds.minX) * focusScale,
                    y: bounds.midY - (top + height / 2 - session.canvasBounds.minY) * focusScale)
                previewScale = focusScale
            }
            artwork.cache = renderCache
            artwork.composited = renderCache.ordered.contains { $0.source.visible && ($0.source.blendMode ?? .normal) != .normal }
            CATransaction.commit()
            let pixelsPerPoint = previewScale * (window?.screen.scale ?? traitCollection.displayScale) * viewportZoom
            renderCache.prepareResolution(pointsToPixels: pixelsPerPoint)
            session.requestEditorImages(longestEdge: max(session.canvasBounds.width, session.canvasBounds.height) * pixelsPerPoint)
            updateArtwork()
            scheduleRasters()
        } else if lastDraftLayer != session.transformDraft?.layer {
            updateArtwork()
            if artwork.composited { artwork.setNeedsDisplay() }
        } else {
            // 模式切换仅控制独立笔画层是否可见。
            inkLayer.isHidden = session.inkMode || artwork.composited
        }
        lastDraftLayer = session.transformDraft?.layer
        publishSelectionViewportRect()
        selectionOverlay.setNeedsDisplay()
    }

    private func isEntranceBackground(_ layer: DiaryLayer) -> Bool {
        layer.semanticKind == .background || layer.isLibraryBackground == true
    }
    func finishEntrance() {
        entranceFinished = true
        entrancePlaying = false
        entranceWork.forEach { $0.cancel() }; entranceWork.removeAll()
        for layer in retainedLayers.values { layer.removeAnimation(forKey: "travel.materialEntrance"); layer.mask = nil }
        refresh(force: true)
    }
    /// 只改变呈现层；背景先显示，其余按文字、照片、贴纸、其他顺序入场。
    func animateMaterialEntrance() {
        guard stagesEntrance, !entranceFinished, !entrancePlaying else { return }
        guard !UIAccessibility.isReduceMotionEnabled else { finishEntrance(); return }
        entrancePlaying = true
        entranceTextHaptic.prepare(); entrancePhotoHaptic.prepare(); entranceStickerHaptic.prepare()
        let entries = renderCache.ordered.filter { !isEntranceBackground($0.source) && $0.source.visible }
        func rank(_ layer: DiaryLayer) -> Int {
            if layer.kind == .text || layer.category == .textImage || layer.semanticKind == .text { return 0 }
            if layer.isContentPhoto { return 1 }
            if layer.kind == .sticker { return 2 }
            return 3
        }
        var delay = 0.0
        for entry in entries.sorted(by: { rank($0.source) < rank($1.source) }) {
            guard let layer = retainedLayers[entry.id] else { continue }
            let text = rank(entry.source) == 0
            let count = max(1, min(100, entry.source.text.count))
            let duration = text ? min(4, Double(count) * 0.10) : 0.40
            let work = DispatchWorkItem { [weak self, weak layer] in
                guard let self, let layer, self.window != nil else { return }
                CATransaction.begin(); CATransaction.setDisableActions(true)
                layer.opacity = Float(entry.source.effectiveOpacity)
                CATransaction.commit()
                if text {
                    if entry.source.kind == .text {
                        for character in 1...count {
                            let step = DispatchWorkItem { [weak self, weak layer] in
                                guard let self, let layer else { return }
                                let format = UIGraphicsImageRendererFormat(); format.scale = min(2, 1800 / max(1, entry.rect.width))
                                let image = UIGraphicsImageRenderer(size: entry.rect.size, format: format).image { context in
                                    context.cgContext.translateBy(x: -entry.rect.minX, y: -entry.rect.minY)
                                    DiaryPageRenderer.drawText(entry.source, in: context.cgContext, revealedCharacters: character)
                                }
                                CATransaction.begin(); CATransaction.setDisableActions(true); layer.contents = image.cgImage; CATransaction.commit()
                                let characters = Array(entry.source.text)
                                if character <= characters.count, !characters[character - 1].isWhitespace { self.playEntranceHaptic(0) }
                            }
                            self.entranceWork.append(step)
                            DispatchQueue.main.asyncAfter(deadline: .now() + Double(character - 1) * duration / Double(count), execute: step)
                        }
                    } else {
                        let fade = CABasicAnimation(keyPath: "opacity"); fade.fromValue = 0; fade.toValue = layer.opacity; fade.duration = 0.4
                        layer.add(fade, forKey: "travel.materialEntrance")
                    }
                    if entry.source.kind != .text { self.playEntranceHaptic(0) }
                } else {
                    let fade = CABasicAnimation(keyPath: "opacity"); fade.fromValue = 0; fade.toValue = layer.opacity
                    let movement = CABasicAnimation(keyPath: "transform.translation.y")
                    movement.isAdditive = true; movement.fromValue = rank(entry.source) == 2 ? -5 : -12; movement.toValue = 0
                    let group = CAAnimationGroup(); group.animations = [fade, movement]; group.duration = duration
                    group.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    layer.add(group, forKey: "travel.materialEntrance")
                    let landing = DispatchWorkItem { [weak self] in self?.playEntranceHaptic(rank(entry.source) == 1 ? 1 : 2) }
                    self.entranceWork.append(landing)
                    DispatchQueue.main.asyncAfter(deadline: .now() + duration * 0.7, execute: landing)
                }
            }
            entranceWork.append(work)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
            delay += text ? duration + 0.12 : 0.18
        }
        let finish = DispatchWorkItem { [weak self] in self?.finishEntrance() }
        entranceWork.append(finish)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.5, execute: finish)
    }

    private func updateArtwork() {
        guard !entrancePlaying else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let ids = Set(renderCache.ordered.map(\.id))
        for id in Array(retainedLayers.keys) where !ids.contains(id) {
            retainedLayers.removeValue(forKey: id)?.removeFromSuperlayer()
        }
        for (index, entry) in renderCache.ordered.enumerated() {
            let layer = retainedLayers[entry.id] ?? CALayer()
            if retainedLayers[entry.id] == nil { retainedLayers[entry.id] = layer; artwork.layer.addSublayer(layer) }
            layer.name = entry.id.uuidString
            layer.zPosition = CGFloat(index)
            layer.isHidden = artwork.composited || !entry.source.visible
            layer.opacity = stagesEntrance && !entranceFinished && !isEntranceBackground(entry.source) ? 0 : Float(entry.source.effectiveOpacity)
            layer.contents = entry.image?.cgImage
            layer.contentsGravity = .resize
            if entry.source.displayBounds != nil, let child = entry.source.contentID,
               let background = renderCache.document.objects[child]?.background {
                layer.backgroundColor = DiaryPageRenderer.color(background).cgColor
            } else { layer.backgroundColor = nil }
            place(layer, rect: entry.rect, projection: displayTransform(entry.source).projection)
        }
        inkLayer.zPosition = CGFloat(renderCache.ordered.count)
        inkLayer.contents = renderCache.inkImage?.cgImage
        inkLayer.isHidden = session?.inkMode == true || artwork.composited
        place(inkLayer, rect: renderCache.inkRect.isNull ? .zero : renderCache.inkRect, matrix: .identity)
        CATransaction.commit()
        artwork.preview = lockedTextID == nil ? (preview ?? session?.transformDraft?.layer) : nil
        artwork.invalidateContentIfNeeded()
    }

    private func place(_ layer: CALayer, rect: CGRect, matrix: CGAffineTransform) {
        place(layer, rect: rect, projection: DiaryProjection(matrix))
    }
    private func place(_ layer: CALayer, rect: CGRect, projection: DiaryProjection) {
        layer.anchorPoint = .zero
        layer.bounds = CGRect(origin: .zero, size: rect.size)
        if abs(projection.g) < 1e-12, abs(projection.h) < 1e-12, abs(projection.i) > 1e-12 {
            layer.position = projection.point(rect.origin)
            layer.transform = CATransform3DMakeAffineTransform(CGAffineTransform(
                a:projection.a/projection.i,b:projection.b/projection.i,
                c:projection.c/projection.i,d:projection.d/projection.i,tx:0,ty:0))
        } else {
            layer.position = .zero
            layer.transform = projection.multiplied(by: DiaryProjection(CGAffineTransform(translationX: rect.minX, y: rect.minY))).layerTransform
        }
    }

    private func scheduleRasters() {
        renderTask?.cancel()
        let fonts = renderCache.document.objects.values.flatMap { $0.layers.compactMap(\.font) }
        let fontDocumentID = renderCache.document.id
        renderTask = Task { @MainActor [weak self] in
            await DiaryFontCatalog.shared.prewarm(fonts, documentID: fontDocumentID)
            // 逐个提交对象预览，在对象之间让出主线程，避免一次生成整页大位图。
            while !Task.isCancelled {
                guard let self else { return }
                guard let next = self.renderCache.ordered.first(where: { $0.source.visible && $0.needsRaster }) else {
                    self.renderCache.rasterizeInk()
                    self.updateArtwork()
                    return
                }
                self.renderCache.rasterize(next)
                // 保留屏幕上的完整旧画面，全部位图就绪后在同一事务里替换。
                // 对象之间仍让出主线程，但不逐层提交半更新的画面。
                do { try await Task.sleep(for: .milliseconds(1)) } catch { return }
            }
        }
    }

    func viewportDidZoom() {
        publishSelectionViewportRect()
        selectionOverlay.setNeedsDisplay()
        resolutionTask?.cancel()
        resolutionTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
            self?.refresh(force: true)
        }
    }

    private func displayTransform(_ source: DiaryLayer) -> DiaryTransform {
        if let active = preview ?? session?.transformDraft?.layer,
           source.id == active.id || source.frameTargetID == active.id { return active.transform }
        if let id = source.frameTargetID, let target = renderCache.entries[id] { return target.source.transform }
        return source.transform
    }
    private func displayMatrix(_ source: DiaryLayer) -> CGAffineTransform { displayTransform(source).matrix }

    private func showPreview(_ layer: DiaryLayer) {
        preview = layer
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for entry in renderCache.ordered where entry.id == layer.id || entry.source.frameTargetID == layer.id {
            if let retained = retainedLayers[entry.id] { place(retained, rect: entry.rect, projection: displayTransform(entry.source).projection) }
        }
        CATransaction.commit()
        artwork.preview = lockedTextID == nil ? (preview ?? session?.transformDraft?.layer) : nil
        if artwork.composited { artwork.setNeedsDisplay() }
        publishSelectionViewportRect()
        selectionOverlay.setNeedsDisplay()
    }

    /// Report the selection in viewport points so the floating tools keep their size while zooming.
    func publishSelectionViewportRect() {
        session?.stickerInsertionViewport = { [weak self] in self?.insertionViewport() }

        guard let callback = onSelectionViewportRect else { return }
        guard showsSelection, let session, !session.inkMode, !session.layerMode,
              session.transformDraft == nil, let layer = displayedSelection,
              layer.visible, let rect = selectionRect(layer) else { callback(nil); return }
        var ancestor = superview
        while let view = ancestor, !(view is UIScrollView) { ancestor = view.superview }
        guard let scroll = ancestor as? UIScrollView else { callback(nil); return }
        let points = rect.diaryCorners.map { screenPoint(displayTransform(layer).projection.point($0)) }
            .map { convert($0, to: scroll) }
        let left = points.map(\.x).min() ?? 0, top = points.map(\.y).min() ?? 0
        callback(CGRect(x: left - scroll.bounds.minX, y: top - scroll.bounds.minY,
                        width: (points.map(\.x).max() ?? left) - left,
                        height: (points.map(\.y).max() ?? top) - top))
    }

    private func insertionViewport() -> DiaryStickerPlacement.Viewport? {
        guard let session, window != nil, fit > 0 else { return nil }
        var ancestor = superview
        while let view = ancestor, !(view is UIScrollView) { ancestor = view.superview }
        guard let scroll = ancestor as? UIScrollView else { return nil }
        // 视口已由编辑器扣除贴纸面板占位，额外避开顶部导航与底部浮动工具。
        let safe = scroll.bounds.inset(by: UIEdgeInsets(top: 56, left: 0, bottom: compactViewport ? 8 : 90, right: 0))
        let local = convert(safe, from: scroll)
        let origin = designPoint(local.origin)
        let end = designPoint(CGPoint(x: local.maxX, y: local.maxY))
        return DiaryStickerPlacement.Viewport(rect: CGRect(x: origin.x, y: origin.y, width: end.x-origin.x, height: end.y-origin.y).intersection(session.canvasBounds), pointsPerUnit: fit * viewportZoom)
    }

    private func selectionRect(_ layer: DiaryLayer) -> CGRect? {
        if layer.id == lockedTextID { return DiaryPageRenderer.textBounds(layer) }
        return renderCache.entries[layer.id]?.rect
    }

    func drawSelection(in context: CGContext) {
        guard let session, fit > 0 else { return }
        if session.transformDraft != nil { drawWarpControls(in: context); return }
        if !session.inkMode, let layer = displayedSelection, layer.visible,
           let rect = selectionRect(layer) {
            context.saveGState()
            let bounds = rect.insetBy(dx: -3, dy: -3)
            let projection = displayTransform(layer).projection
            let corners = [CGPoint(x: bounds.minX, y: bounds.minY),
                           CGPoint(x: bounds.maxX, y: bounds.minY),
                           CGPoint(x: bounds.maxX, y: bounds.maxY),
                           CGPoint(x: bounds.minX, y: bounds.maxY)]
                .map { screenPoint(projection.point($0)) }
            context.addLines(between: corners)
            context.closePath()
            context.setStrokeColor(UIColor.white.cgColor)
            context.setLineWidth(1.3 / viewportZoom)
            context.setLineJoin(.round)
            context.strokePath()
            context.restoreGState()
        }
        drawHandles(in: context)
    }

    private func hit(_ screen: CGPoint) -> UUID? {
        guard session != nil, fit > 0 else { return nil }
        let pagePoint = designPoint(screen)
        let parentPoint = pagePoint
        // 从上到下命中；组内编辑时只检查当前组的直接子层。
        for entry in renderCache.ordered.reversed() where entry.source.visible && !entry.source.locked {
            let local = displayTransform(entry.source).projection.inverse.point(parentPoint)
            if renderCache.contains(local, entry: entry) { return entry.id }
        }
        return nil
    }
    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        guard let session, !session.inkMode, !session.busy, session.transformDraft == nil else { return }
        if let handle = handleHit(gesture.location(in: self)) {
            switch handle {
            case .delete: session.removeSelected()
            case .edit: onEdit()
            default: break
            }
            return
        }
        guard lockedTextID == nil else { return }
        let target = hit(gesture.location(in: self))
        // 再次单击当前素材取消选中；选择状态仅影响编辑，不改变作品数据。
        session.select(target == session.selectedID && !session.layerMode ? nil : target)
    }
    @objc private func panned(_ gesture: UIPanGestureRecognizer) {
        guard let session, !session.inkMode, !session.busy, fit > 0 else { return }
        if session.transformDraft != nil { warpPanned(gesture); return }
        switch gesture.state {
        case .began:
            startPosition = nil
            draggingID = nil
            // 手柄按可见形状命中；透明区域不抢走下方文字或素材的拖动。
            // began 回调已越过手势识别阈值，用位移还原按下点，避免跨入另一素材后误命中。
            let location = gesture.location(in: self)
            let translation = gesture.translation(in: self)
            let touchOrigin = CGPoint(x: location.x - translation.x, y: location.y - translation.y)
            guard let layer = editingTextLayer ?? session.selected, layer.visible, !layer.locked, !layer.isPhotoFrame else { return }
            activeHandle = handleHit(touchOrigin)
            if let handle = activeHandle, [.delete, .edit].contains(handle) { return }
            let selectionBounds = selectionRect(layer) ?? CGRect(origin: .zero, size: layer.size)
            let localOrigin = displayTransform(layer).projection.inverse.point(designPoint(touchOrigin))
            if activeHandle == nil {
                guard selectionBounds.contains(localOrigin), (lockedTextID == layer.id || hit(touchOrigin) == layer.id) else { return }
            }
            initialLayer = layer
            initialBounds = selectionBounds
            initialTouch = designPoint(touchOrigin)
            let center = layer.transform.projection.point(CGPoint(x: initialBounds.midX, y: initialBounds.midY))
            rotationLast = atan2(initialTouch.y - center.y, initialTouch.x - center.x)
            rotationTotal = 0
            preview = layer
            draggingID = layer.id
            startPosition = layer.transform.position
            parentAtStart = .identity
        case .changed:
            guard let startPosition, let draggingID, session.selectedID == draggingID,
                  let layer = editingTextLayer ?? session.selected, layer.visible, !layer.locked else { return }
            if let handle = activeHandle, handle != .move {
                updateHandle(handle, point: designPoint(gesture.location(in: self)))
                return
            }
            let translation = gesture.translation(in: self)
            let inverse = parentAtStart.inverted()
            let origin = CGPoint.zero.applying(inverse)
            let shifted = CGPoint(x: translation.x / fit, y: translation.y / fit).applying(inverse)
            var moved = initialLayer ?? layer
            moved.transform.position = CGPoint(x: startPosition.x + shifted.x - origin.x, y: startPosition.y + shifted.y - origin.y)
            if lockedTextID == moved.id { onTextAdjustment?(moved) }
            showPreview(moved)
        case .ended:
            if let preview {
                if lockedTextID == preview.id { onTextAdjustment?(preview) }
                else { session.commitTransform(preview) }
            }
            preview = nil
            startPosition = nil; draggingID = nil; activeHandle = nil; initialLayer = nil
            refresh(force: true)
        case .cancelled, .failed:
            preview = nil
            startPosition = nil; draggingID = nil; activeHandle = nil; initialLayer = nil
            updateArtwork()
            if artwork.composited { artwork.setNeedsDisplay() }
            publishSelectionViewportRect()
        selectionOverlay.setNeedsDisplay()
        default: break
        }
    }
    private func warpPoints(_ layer: DiaryLayer, reference: CGRect) -> [CGPoint] {
        let corners = reference.diaryCorners
        return (corners + (0..<4).map { n in
            CGPoint(x: (corners[n].x+corners[(n+1)%4].x)/2, y: (corners[n].y+corners[(n+1)%4].y)/2)
        }).map { screenPoint(layer.transform.projection.point($0)) }
    }
    private func activeWarpHandles(_ mode: DiaryTransformMode) -> [Int] {
        switch mode { case .free, .perspective: Array(0..<4); case .skew: Array(4..<8); case .stretch: Array(0..<8) }
    }
    private func drawWarpControls(in context: CGContext) {
        guard let draft=session?.transformDraft else { return }
        let layer=preview ?? draft.layer, ref=draft.reference
        let points=warpPoints(layer, reference: ref)
        let color=UIColor(DiaryLibraryStyle.accent)
        context.saveGState()
        context.setStrokeColor(color.cgColor); context.setLineWidth(1.5/viewportZoom)
        context.addLines(between: Array(points.prefix(4))); context.closePath(); context.strokePath()
        context.setStrokeColor(color.withAlphaComponent(0.5).cgColor); context.setLineWidth(0.7/viewportZoom)
        for fraction in [CGFloat(1.0/3), CGFloat(2.0/3)] {
            let lines = [[CGPoint(x: ref.minX+ref.width*fraction,y: ref.minY), CGPoint(x: ref.minX+ref.width*fraction,y: ref.maxY)],
                         [CGPoint(x: ref.minX,y: ref.minY+ref.height*fraction), CGPoint(x: ref.maxX,y: ref.minY+ref.height*fraction)]]
            for line in lines {
                context.addLines(between: line.map { screenPoint(layer.transform.projection.point($0)) }); context.strokePath()
            }
        }
        for n in activeWarpHandles(draft.mode) {
            let p=points[n], radius: CGFloat=5/viewportZoom
            context.setFillColor(color.cgColor)
            context.fillEllipse(in: CGRect(x:p.x-radius,y:p.y-radius,width:radius*2,height:radius*2))
        }
        context.restoreGState()
    }
    private func warpPanned(_ gesture: UIPanGestureRecognizer) {
        updateFreeTransformGesture(state: gesture.state, location: gesture.location(in:self), translation:gesture.translation(in:self))
    }
    func updateFreeTransformGesture(state: UIGestureRecognizer.State, location: CGPoint, translation: CGPoint) {
        guard let session, let draft=session.transformDraft else { return }
        switch state {
        case .began:
            let origin=CGPoint(x:location.x-translation.x,y:location.y-translation.y)
            let points=warpPoints(draft.layer, reference:draft.reference)
            warpHandle=activeWarpHandles(draft.mode).map { ($0,hypot(points[$0].x-origin.x,points[$0].y-origin.y)) }
                .filter { $0.1 <= 22/viewportZoom }.min { $0.1 < $1.1 }?.0
            let local=draft.layer.transform.projection.inverse.point(designPoint(origin))
            guard warpHandle != nil || draft.reference.contains(local) else { warpStart=nil; return }
            warpStart=draft.layer; warpTouch=designPoint(origin)
        case .changed:
            guard var layer=warpStart else { return }
            let current=designPoint(location)
            if let handle=warpHandle {
                let inverse=layer.transform.matrix.inverted()
                let a=warpTouch.applying(inverse), b=current.applying(inverse)
                let delta=CGPoint(x:(b.x-a.x)/draft.reference.width,y:(b.y-a.y)/draft.reference.height)
                let warp=layer.transform.warp ?? DiaryQuadWarp(reference:draft.reference)
                guard let updated=draft.mode.moving(warp, handle:handle, delta:delta) else { return }
                layer.transform.warp=updated
            } else {
                layer.transform.position.x += current.x-warpTouch.x
                layer.transform.position.y += current.y-warpTouch.y
            }
            if session.isValidFreeTransform(layer) { showPreview(layer) }
        case .ended:
            if warpStart != nil, let preview { session.previewFreeTransform(preview) }
            preview=nil; warpStart=nil; warpHandle=nil
            refresh(force:true)
        case .cancelled, .failed:
            if lockedTextID != nil, let initialLayer { onTextAdjustment?(initialLayer) }
            preview=nil; warpStart=nil; warpHandle=nil
            updateArtwork(); selectionOverlay.setNeedsDisplay()
        default: break
        }
    }

    // 控制点按屏幕点设置大小，画布放大时仍维持可点击尺寸。
    private var viewportZoom: CGFloat {
        var ancestor = superview
        while let view = ancestor {
            if let scroll = view as? UIScrollView { return scroll.zoomScale }
            ancestor = view.superview
        }
        return 1
    }
    private func designPoint(_ p: CGPoint) -> CGPoint {
        CGPoint(x: (p.x - contentMargin) / fit + (session?.canvasBounds.minX ?? 0),
                y: (p.y - contentMargin) / fit + (session?.canvasBounds.minY ?? 0))
    }
    private func screenPoint(_ p: CGPoint) -> CGPoint {
        CGPoint(x: (p.x - (session?.canvasBounds.minX ?? 0)) * fit + contentMargin,
                y: (p.y - (session?.canvasBounds.minY ?? 0)) * fit + contentMargin)
    }
    private func handles() -> [(Handle, CGPoint)] {
        guard let session, !session.inkMode, let layer = displayedSelection, layer.visible, !layer.locked else { return [] }
        guard let rect = selectionRect(layer) else { return [] }
        // 与选框共用外扩边界，角点和边中点始终落在白线上。
        let b = rect.insetBy(dx: -3, dy: -3)
        var points: [(Handle, CGPoint)] = [(.delete, CGPoint(x:b.minX,y:b.minY)), (.edit, CGPoint(x:b.maxX,y:b.minY)),
            (.move, CGPoint(x:b.minX,y:b.maxY)), (.scale, CGPoint(x:b.maxX,y:b.maxY))]
        if layer.isPhotoFrame {
            points = [(.delete, CGPoint(x:b.minX,y:b.minY))]
        } else {
            points += [(.top, CGPoint(x:b.midX,y:b.minY)), (.bottom, CGPoint(x:b.midX,y:b.maxY)),
                       (.left, CGPoint(x:b.minX,y:b.midY)), (.right, CGPoint(x:b.maxX,y:b.midY)),
                       (.rotate, CGPoint(x:b.maxX + 28 / max(0.01, fit * viewportZoom * layer.transform.scale * layer.transform.stretchX),y:b.midY))]
        }
        if lockedTextID != nil { points.removeAll { ![.left, .right, .top, .bottom, .scale].contains($0.0) } }
        if session.layerMode { points.removeAll { $0.0 != .scale && $0.0 != .rotate } }
        if layer.id == session.content.primaryLayerID { points.removeAll { $0.0 == .delete } }
        let mapped = points.map { ($0.0, screenPoint(displayTransform(layer).projection.point($0.1))) }
        guard lockedTextID != nil else { return mapped }
        // Keep controls outside tiny text boxes, with screen-space separation at every zoom.
        let center = screenPoint(displayTransform(layer).projection.point(CGPoint(x: b.midX, y: b.midY)))
        return mapped.map { handle, point in
            let dx = point.x - center.x, dy = point.y - center.y
            let distance = max(0.001, hypot(dx, dy))
            let offset: CGFloat = (handle == .scale ? 22 : 14) / viewportZoom
            return (handle, CGPoint(x: point.x + dx / distance * offset,
                                    y: point.y + dy / distance * offset))
        }
    }
    private func handleHit(_ p: CGPoint) -> Handle? {
        let matrix = displayedSelection.map { displayMatrix($0) } ?? .identity
        let insideSelection: Bool
        if let layer = displayedSelection, let rect = selectionRect(layer) {
            let local = displayTransform(layer).projection.inverse.point(designPoint(p))
            insideSelection = rect.contains(local)
        } else { insideSelection = false }
        return handles().compactMap { handle, center -> (Handle, CGFloat)? in
            let offset = CGPoint(x: (p.x - center.x) * viewportZoom, y: (p.y - center.y) * viewportZoom)
            let horizontal = handle == .top || handle == .bottom
            let isEdge = horizontal || handle == .left || handle == .right
            let angle = horizontal ? atan2(matrix.b, matrix.a) : atan2(matrix.d, matrix.c)
            guard DiaryCanvasHandleHitRegion.contains(offset, edgeAngle: isEdge ? angle : nil, allowsExpansion: !insideSelection) else { return nil }
            return (handle, hypot(offset.x, offset.y))
        }.min { $0.1 < $1.1 }?.0
    }
    private static let symbols: [String: UIImage] = Dictionary(uniqueKeysWithValues:
        Set(Handle.allCases.map(\.symbol)).compactMap { symbol in
            UIImage(systemName: symbol).map { (symbol, $0.withTintColor(controlIconColor, renderingMode: .alwaysOriginal)) }
        })
    private static let controlIconColor = UIColor(white: 0.5, alpha: 1)

    private func drawHandles(in context: CGContext) {
        let zoom = viewportZoom
        let radius: CGFloat = 10 / zoom
        let matrix = displayedSelection.map { displayMatrix($0) } ?? .identity
        for (handle, point) in handles() {
            context.saveGState()
            context.translateBy(x: point.x, y: point.y)
            context.setShadow(offset: CGSize(width: 0, height: 1 / zoom),
                              blur: 3 / zoom, color: UIColor.black.withAlphaComponent(0.18).cgColor)
            context.setFillColor(UIColor.white.cgColor)
            switch handle {
            case .top, .bottom, .left, .right:
                // 使用变换后的边方向，旋转、翻转、拉伸后短条仍与边框平行。
                let horizontal = handle == .top || handle == .bottom
                let angle = horizontal ? atan2(matrix.b, matrix.a) : atan2(matrix.d, matrix.c)
                context.rotate(by: angle)
                let rect = CGRect(x: -9 / zoom, y: -3.5 / zoom, width: 18 / zoom, height: 7 / zoom)
                context.addPath(UIBezierPath(roundedRect: rect, cornerRadius: 3.5 / zoom).cgPath)
                context.fillPath()
            default:
                let rect = CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2)
                context.fillEllipse(in: rect)
                context.setShadow(offset: .zero, blur: 0, color: nil)
                let image = Self.symbols[handle.symbol]
                let availableSize: CGFloat = 11 / zoom
                if let image {
                    let scale = availableSize / max(image.size.width, image.size.height)
                    let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                    image.draw(in: CGRect(x: -size.width / 2, y: -size.height / 2,
                                          width: size.width, height: size.height))
                }
            }
            context.restoreGState()
        }
        if activeHandle == .rotate, let layer = displayedSelection {
            let point = handles().first { $0.0 == .rotate }?.1 ?? .zero
            (String(format:"%.0f°", layer.transform.rotationDegrees) as NSString).draw(
                at:CGPoint(x:point.x+18 / zoom,y:point.y),
                withAttributes:[.font:UIFont.systemFont(ofSize:14 / zoom),.foregroundColor:Self.controlIconColor])
        }
    }
    private func updateHandle(_ handle: Handle, point: CGPoint) {
        guard var layer = initialLayer, !layer.isPhotoFrame else { return }
        let b = initialBounds
        let localStart = layer.transform.projection.inverse.point(initialTouch)
        let local = layer.transform.projection.inverse.point(point)
        if handle == .scale {
            // 左上角固定，以对角线投影决定等比倍率，反向拖过锚点时停止于最小尺寸。
            let diagonal = CGPoint(x:b.width,y:b.height)
            let delta = CGPoint(x:local.x-localStart.x,y:local.y-localStart.y)
            let ratio = max(0.05, 1 + (delta.x*diagonal.x+delta.y*diagonal.y) / max(1,diagonal.x*diagonal.x+diagonal.y*diagonal.y))
            let anchor = CGPoint(x:b.minX,y:b.minY)
            let fixed = layer.transform.projection.point(anchor)
            layer.transform.scale = min(20,max(0.05,layer.transform.scale*ratio))
            let moved = layer.transform.projection.point(anchor)
            layer.transform.position.x += fixed.x-moved.x; layer.transform.position.y += fixed.y-moved.y
        } else if handle == .rotate {
            let center = CGPoint(x:b.midX,y:b.midY)
            let fixed = layer.transform.projection.point(center)
            let angle = atan2(point.y-fixed.y,point.x-fixed.x)
            var step = angle-rotationLast
            if step > .pi { step -= 2 * .pi }; if step < -.pi { step += 2 * .pi }
            rotationTotal += step; rotationLast = angle
            var degrees = layer.transform.rotationDegrees + rotationTotal * 180 / .pi
            let snap = (degrees / 90).rounded() * 90
            if abs(degrees-snap) < 4 { degrees = snap }
            layer.transform.rotationDegrees = (degrees + 180).truncatingRemainder(dividingBy:360)
            if layer.transform.rotationDegrees < 0 { layer.transform.rotationDegrees += 360 }
            layer.transform.rotationDegrees -= 180
            let moved = layer.transform.projection.point(center)
            layer.transform.position.x += fixed.x-moved.x; layer.transform.position.y += fixed.y-moved.y
        } else if lockedTextID == layer.id && layer.kind == .text {
            let dx = local.x - localStart.x, dy = local.y - localStart.y
            let anchor = CGPoint(x: handle == .left ? b.maxX : b.minX,
                                 y: handle == .top ? b.maxY : b.minY)
            let fixed = layer.transform.projection.point(anchor)
            if handle == .left || handle == .right {
                let insets = DiaryPageRenderer.textInsets(layer)
                let minimumWidth = insets.left + insets.right + layer.fontSize
                layer.size.width = max(minimumWidth, layer.size.width + (handle == .left ? -dx : dx))
            } else {
                var appearance = layer.textAppearance ?? DiaryTextAppearance()
                let currentBounds = DiaryPageRenderer.textBounds(layer)
                let cardHeight = currentBounds.height + currentBounds.minY * 2
                appearance.minimumCardHeight = Double(min(20000, max(0, cardHeight + (handle == .top ? -dy : dy))))
                layer.textAppearance = appearance
            }
            let next = DiaryPageRenderer.textBounds(layer).insetBy(dx: -3, dy: -3)
            let nextAnchor = CGPoint(x: handle == .left ? next.maxX : next.minX,
                                     y: handle == .top ? next.maxY : next.minY)
            let moved = layer.transform.projection.point(nextAnchor)
            layer.transform.position.x += fixed.x - moved.x
            layer.transform.position.y += fixed.y - moved.y
        } else {
            // 边中点只改变一个轴的比例，不裁剪照片、不重排文字、不改内部图层。
            // 投影到手势开始时的局部坐标，避免素材旋转后手柄偏离自身方向。
            let dx = local.x - localStart.x, dy = local.y - localStart.y
            let horizontal: Bool
            let ratio: CGFloat
            let anchor: CGPoint
            switch handle {
            case .left:
                horizontal = true; ratio = 1 - dx / max(1, b.width)
                anchor = CGPoint(x: b.maxX, y: b.midY)
            case .right:
                horizontal = true; ratio = 1 + dx / max(1, b.width)
                anchor = CGPoint(x: b.minX, y: b.midY)
            case .top:
                horizontal = false; ratio = 1 - dy / max(1, b.height)
                anchor = CGPoint(x: b.midX, y: b.maxY)
            case .bottom:
                horizontal = false; ratio = 1 + dy / max(1, b.height)
                anchor = CGPoint(x: b.midX, y: b.minY)
            default: return
            }
            layer.transform.stretchAxis(horizontal: horizontal, ratio: ratio, anchor: anchor)
        }
        if lockedTextID == layer.id { onTextAdjustment?(layer); refresh(force: true) }
        showPreview(layer)
    }

}

/// 绘画草稿只在“完成”时提交；屏幕点坐标与作品坐标之间可逆转换。
struct DiaryDrawingSheet: View {
    @ObservedObject var session: DiaryEditorSession
    let editingExisting: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var drawing: PKDrawing
    @State private var clearConfirmation = false
    @State private var erasing = false
    @State private var inkColor: Color = .black
    @State private var inkWidth: Double = 5
    @State private var showWidth = false
    @State private var checkpoint: PKDrawing
    @State private var undoDrawings: [PKDrawing] = []
    @State private var redoDrawings: [PKDrawing] = []
    @State private var submitting = false

    init(session: DiaryEditorSession, editingExisting: Bool = false) {
        self.session = session
        self.editingExisting = editingExisting
        let initial = editingExisting ? session.drawing : PKDrawing()
        _drawing = State(initialValue: initial)
        _checkpoint = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let bounds = session.canvasBounds
                let scale = max(0.001, min(max(1, geometry.size.width - 24) / bounds.width,
                                          max(1, geometry.size.height - 24) / bounds.height))
                let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
                let margin = DiaryCanvasSurface.controlMargin
                DiaryZoomableCanvas(contentSize: size, sessionID: session.id, inkMode: true,
                                    minimumScale: 0.5, refreshContent: true) {
                ZStack(alignment: .topLeading) {
                    // CanvasSurface already renders artwork to fit, including its control margin.
                    DiaryCanvasView(session: session, onEdit: {})
                        .frame(width: size.width + margin * 2, height: size.height + margin * 2)
                        .offset(x: -margin, y: -margin)
                        .allowsHitTesting(false)
                    DiaryDrawingCanvasView(drawing: $drawing, bounds: bounds, displayScale: scale,
                        tool: erasing ? PKEraserTool(.bitmap, width: inkWidth) : PKInkingTool(.pen, color: UIColor(inkColor), width: inkWidth),
                        onStrokeEnded: recordStroke)
                        .frame(width: size.width, height: size.height)
                }
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .background(.white).clipped()

                }.clipped()

            }
            .background(Color(uiColor: .systemGroupedBackground))
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    if showWidth { HStack {
                        Text("粗细 \(Int(inkWidth))").font(.caption)
                        Slider(value: $inkWidth, in: 1...40, step: 1)
                    }.padding(.horizontal) }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 20) {
                            drawingButton("完成", symbol: "checkmark", action: finish)
                            drawingButton("画笔", symbol: "pencil.tip", active: !erasing) { erasing = false }
                            drawingButton("橡皮", symbol: "eraser", active: erasing) { erasing = true }
                            VStack(spacing: 4) {
                                ColorPicker("颜色", selection: $inkColor, supportsOpacity: false).labelsHidden()
                                Text("颜色").font(.caption)
                            }
                            drawingButton("粗细", symbol: "lineweight", active: showWidth) { showWidth.toggle() }
                            drawingButton("撤销", symbol: "arrow.uturn.backward") { undoDrawing() }.disabled(undoDrawings.isEmpty)
                            drawingButton("重做", symbol: "arrow.uturn.forward") { redoDrawing() }.disabled(redoDrawings.isEmpty)
                        }.padding(.horizontal, 16).padding(.vertical, 10)
                    }
                }.background(.regularMaterial)
            }
            .navigationTitle(editingExisting ? "编辑画笔图层" : "新建画笔图层").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消", action: cancel) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        finish()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("清空", role: .destructive) { clearConfirmation = true }
                }
            }
            .confirmationDialog(editingExisting ? "清空这个图层的笔迹？" : "清空本次绘画的笔迹？", isPresented: $clearConfirmation, titleVisibility: .visible) {
                Button("清空笔迹", role: .destructive) { drawing = PKDrawing(); recordStroke() }
            } message: { Text("点击完成后保存，取消可放弃本次修改。") }
            .alert("画笔", isPresented: Binding(get: { session.errorMessage != nil },
                set: { if !$0 { session.errorMessage = nil } })) {
                Button("确定") { session.errorMessage = nil }
            } message: { Text(session.errorMessage ?? "") }
        }
        .disabled(submitting || session.busy)
    }
    private func finish() {
        guard !submitting else { return }
        if editingExisting {
            submitting = true
            Task { @MainActor in
                defer { submitting = false }
                if await session.saveDrawingEdits(drawing) { dismiss() }
            }
        } else if drawing.strokes.isEmpty || session.addDrawingLayer(drawing) != nil { dismiss() }
    }
    private func cancel() {
        guard !submitting else { return }
        if editingExisting {
            submitting = true
            Task { @MainActor in
                await session.cancelEditor()
                dismiss()
                submitting = false
            }
        } else { dismiss() }
    }
    private func recordStroke() {
        guard drawing.dataRepresentation() != checkpoint.dataRepresentation() else { return }
        undoDrawings.append(checkpoint)
        if undoDrawings.count > 60 { undoDrawings.removeFirst() }
        checkpoint = drawing; redoDrawings.removeAll()
    }
    private func undoDrawing() {
        recordStroke()
        guard let previous = undoDrawings.popLast() else { return }
        redoDrawings.append(drawing); drawing = previous; checkpoint = previous
    }
    private func redoDrawing() {
        guard let next = redoDrawings.popLast() else { return }
        undoDrawings.append(drawing); drawing = next; checkpoint = next
    }
    private func drawingButton(_ title: String, symbol: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) { Image(systemName: symbol).font(.title3); Text(title).font(.caption) }
                .frame(minWidth: 40, minHeight: 48).foregroundStyle(active ? Color.purple : Color.primary)
        }.accessibilityLabel(title)
    }

}

/// PKCanvasView uses screen points, so native tool widths don't shrink with high-resolution pages.
struct DiaryDrawingCanvasView: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    let bounds: CGRect
    let displayScale: CGFloat
    let tool: PKTool
    var onStrokeEnded: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeUIView(context: Context) -> PKCanvasView {
        let view = DiaryNativeDrawingCanvas()
        view.backgroundColor = .clear; view.isOpaque = false
        view.overrideUserInterfaceStyle = .light
        view.isScrollEnabled = false; view.drawingPolicy = .anyInput
        view.delegate = context.coordinator
        context.coordinator.canvas = view
        view.onWindowChanged = { [weak coordinator = context.coordinator] in coordinator?.showTools() }
        configure(view, coordinator: context.coordinator)
        return view
    }
    func updateUIView(_ view: PKCanvasView, context: Context) { configure(view, coordinator: context.coordinator) }
    static func dismantleUIView(_ view: PKCanvasView, coordinator: Coordinator) {
        (view as? DiaryNativeDrawingCanvas)?.onWindowChanged = nil
        view.resignFirstResponder(); view.delegate = nil
    }
    private func configure(_ view: PKCanvasView, coordinator: Coordinator) {
        let data = drawing.dataRepresentation()
        let geometryChanged = coordinator.parent.displayScale != displayScale || coordinator.parent.bounds != bounds
        coordinator.parent = self
        if coordinator.lastData != data || geometryChanged {
            var displayed = drawing
            displayed.transform(using: CGAffineTransform(a: displayScale, b: 0, c: 0, d: displayScale,
                tx: -bounds.minX * displayScale, ty: -bounds.minY * displayScale))
            coordinator.replaying = true
            view.drawing = displayed
            coordinator.lastData = data
            coordinator.replaying = false
        }
        view.tool = tool
        coordinator.showTools()
    }
    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: DiaryDrawingCanvasView
        weak var canvas: PKCanvasView?
        var replaying = false
        var lastData: Data?
        init(parent: DiaryDrawingCanvasView) {
            self.parent = parent
            super.init()
        }
        func showTools() {
            guard let canvas, canvas.window != nil else { return }
            if !canvas.isFirstResponder { canvas.becomeFirstResponder() }
        }
        func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
            parent.onStrokeEnded()
        }
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !replaying else { return }
            var value = canvasView.drawing
            let scale = parent.displayScale
            value.transform(using: CGAffineTransform(a: 1 / scale, b: 0, c: 0, d: 1 / scale,
                tx: parent.bounds.minX, ty: parent.bounds.minY))
            lastData = value.dataRepresentation()
            parent.drawing = value
        }
    }
}

private final class DiaryNativeDrawingCanvas: PKCanvasView {
    var onWindowChanged: (() -> Void)?
    override func didMoveToWindow() {
        super.didMoveToWindow()
        onWindowChanged?()
    }
}
