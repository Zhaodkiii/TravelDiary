import SwiftUI
import UIKit
import PencilKit

struct DiaryCanvasView: UIViewRepresentable {
    @ObservedObject var session: DiaryEditorSession
    var onEdit: () -> Void = {}
    func makeUIView(context: Context) -> DiaryCanvasSurface {
        let view = DiaryCanvasSurface(); view.session = session; view.onEdit = onEdit; return view
    }
    func updateUIView(_ view: DiaryCanvasSurface, context: Context) {
        view.session = session; view.onEdit = onEdit; view.refresh()
    }
}

/// 每个对象使用独立设计坐标；视口可包含负坐标，装饰伸出照片时仍保留原位置。
final class DiaryCanvasSurface: UIView {
    weak var session: DiaryEditorSession?
    var onEdit: () -> Void = {}
    private enum Handle: CaseIterable {
        case delete, edit, duplicate, scale, top, bottom, left, right, rotate
        var symbol: String {
            switch self {
            case .delete: "xmark"
            case .edit: "pencil"
            case .duplicate: "plus.square.on.square"
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
    private var displayedSelection: DiaryLayer? { preview ?? session?.selected }
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
    private var fit: CGFloat { (bounds.width - Self.controlMargin * 2) / (session?.canvasBounds.width ?? 1000) }

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
            artwork.layer.position = CGPoint(x: Self.controlMargin, y: Self.controlMargin)
            artwork.transform = CGAffineTransform(scaleX: fit, y: fit)
            artwork.cache = renderCache
            artwork.composited = renderCache.ordered.contains { $0.source.visible && ($0.source.blendMode ?? .normal) != .normal }
            CATransaction.commit()
            let pixelsPerPoint = fit * (window?.screen.scale ?? traitCollection.displayScale) * viewportZoom
            renderCache.prepareResolution(pointsToPixels: pixelsPerPoint)
            session.requestEditorImages(longestEdge: max(session.canvasBounds.width, session.canvasBounds.height) * pixelsPerPoint)
            updateArtwork()
            scheduleRasters()
        } else {
            // 模式切换仅控制独立笔画层是否可见。
            inkLayer.isHidden = session.inkMode || artwork.composited
        }
        selectionOverlay.setNeedsDisplay()
    }

    private func updateArtwork() {
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
            layer.contents = entry.image?.cgImage
            layer.contentsGravity = .resize
            if entry.source.displayBounds != nil, let child = entry.source.contentID,
               let background = renderCache.document.objects[child]?.background {
                layer.backgroundColor = DiaryPageRenderer.color(background).cgColor
            } else { layer.backgroundColor = nil }
            place(layer, rect: entry.rect, matrix: displayMatrix(entry.source))
        }
        inkLayer.zPosition = CGFloat(renderCache.ordered.count)
        inkLayer.contents = renderCache.inkImage?.cgImage
        inkLayer.isHidden = session?.inkMode == true || artwork.composited
        place(inkLayer, rect: renderCache.inkRect.isNull ? .zero : renderCache.inkRect, matrix: .identity)
        CATransaction.commit()
        artwork.preview = preview
        artwork.invalidateContentIfNeeded()
    }

    private func place(_ layer: CALayer, rect: CGRect, matrix: CGAffineTransform) {
        layer.anchorPoint = .zero
        layer.bounds = CGRect(origin: .zero, size: rect.size)
        layer.position = rect.origin.applying(matrix)
        layer.setAffineTransform(CGAffineTransform(a: matrix.a, b: matrix.b, c: matrix.c, d: matrix.d, tx: 0, ty: 0))
    }

    private func scheduleRasters() {
        renderTask?.cancel()
        let fonts = renderCache.document.objects.values.flatMap { $0.layers.compactMap(\.font) }
        renderTask = Task { @MainActor [weak self] in
            await DiaryFontCatalog.shared.prewarm(fonts)
            // 逐个提交对象预览，在对象之间让出主线程，避免一次生成整页大位图。
            while !Task.isCancelled {
                guard let self else { return }
                guard let next = self.renderCache.ordered.first(where: { $0.source.visible && $0.needsRaster }) else {
                    self.renderCache.rasterizeInk()
                    self.updateArtwork()
                    return
                }
                self.renderCache.rasterize(next)
                self.updateArtwork()
                do { try await Task.sleep(for: .milliseconds(1)) } catch { return }
            }
        }
    }

    func viewportDidZoom() {
        selectionOverlay.setNeedsDisplay()
        resolutionTask?.cancel()
        resolutionTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
            self?.refresh(force: true)
        }
    }

    private func displayMatrix(_ source: DiaryLayer) -> CGAffineTransform {
        if let preview {
            if source.id == preview.id || source.frameTargetID == preview.id { return preview.transform.matrix }
        }
        if let id = source.frameTargetID, let target = renderCache.entries[id] { return target.source.transform.matrix }
        return source.transform.matrix
    }

    private func showPreview(_ layer: DiaryLayer) {
        preview = layer
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for entry in renderCache.ordered where entry.id == layer.id || entry.source.frameTargetID == layer.id {
            if let retained = retainedLayers[entry.id] { place(retained, rect: entry.rect, matrix: displayMatrix(entry.source)) }
        }
        CATransaction.commit()
        artwork.preview = preview
        if artwork.composited { artwork.setNeedsDisplay() }
        selectionOverlay.setNeedsDisplay()
    }

    func drawSelection(in context: CGContext) {
        guard let session, fit > 0 else { return }
        if !session.inkMode, let layer = displayedSelection, layer.visible,
           let entry = renderCache.entries[layer.id] {
            context.saveGState()
            context.translateBy(x: Self.controlMargin, y: Self.controlMargin)
            context.scaleBy(x: fit, y: fit)
            context.translateBy(x: -session.canvasBounds.minX, y: -session.canvasBounds.minY)
            context.concatenate(displayMatrix(layer))
            context.setStrokeColor(UIColor.systemBlue.cgColor)
            context.setLineWidth(2 / max(0.01, fit * viewportZoom * layer.transform.scale))
            context.stroke(entry.rect.insetBy(dx: -3, dy: -3))
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
            let local = parentPoint.applying(displayMatrix(entry.source).inverted())
            if renderCache.contains(local, entry: entry) { return entry.id }
        }
        return nil
    }
    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        guard let session, !session.inkMode, !session.busy else { return }
        if let handle = handleHit(gesture.location(in: self)) {
            switch handle {
            case .delete: session.removeSelected()
            case .duplicate: session.duplicateSelected()
            case .edit: onEdit()
            default: break
            }
            return
        }
        let target = hit(gesture.location(in: self))
        // 再次单击当前素材取消选中；选择状态仅影响编辑，不改变作品数据。
        session.select(target == session.selectedID ? nil : target)
    }
    @objc private func panned(_ gesture: UIPanGestureRecognizer) {
        guard let session, !session.inkMode, !session.busy, fit > 0 else { return }
        switch gesture.state {
        case .began:
            startPosition = nil
            draggingID = nil
            // 拖动不能顺便选中素材：必须先单击得到蓝色选框，再从该素材上开始拖动。
            // began 回调已越过手势识别阈值，用位移还原按下点，避免跨入另一素材后误命中。
            let location = gesture.location(in: self)
            let translation = gesture.translation(in: self)
            let touchOrigin = CGPoint(x: location.x - translation.x, y: location.y - translation.y)
            guard let layer = session.selected, layer.visible, !layer.locked, layer.kind != .frame else { return }
            activeHandle = handleHit(touchOrigin)
            if let handle = activeHandle, [.delete, .edit, .duplicate].contains(handle) { return }
            guard activeHandle != nil || hit(touchOrigin) == layer.id else { return }
            initialLayer = layer
            initialBounds = renderCache.entries[layer.id]?.rect ?? CGRect(origin: .zero, size: layer.size)
            initialTouch = designPoint(touchOrigin)
            let center = CGPoint(x: initialBounds.midX, y: initialBounds.midY).applying(layer.transform.matrix)
            rotationLast = atan2(initialTouch.y - center.y, initialTouch.x - center.x)
            rotationTotal = 0
            preview = layer
            draggingID = layer.id
            startPosition = layer.transform.position
            parentAtStart = .identity
        case .changed:
            guard let startPosition, let draggingID, session.selectedID == draggingID,
                  let layer = session.selected, layer.visible, !layer.locked else { return }
            if let handle = activeHandle {
                updateHandle(handle, point: designPoint(gesture.location(in: self)))
                return
            }
            let translation = gesture.translation(in: self)
            let inverse = parentAtStart.inverted()
            let origin = CGPoint.zero.applying(inverse)
            let shifted = CGPoint(x: translation.x / fit, y: translation.y / fit).applying(inverse)
            var moved = initialLayer ?? layer
            moved.transform.position = CGPoint(x: startPosition.x + shifted.x - origin.x, y: startPosition.y + shifted.y - origin.y)
            showPreview(moved)
        case .ended:
            if let preview { session.commitTransform(preview) }
            preview = nil
            startPosition = nil; draggingID = nil; activeHandle = nil; initialLayer = nil
            refresh(force: true)
        case .cancelled, .failed:
            preview = nil
            startPosition = nil; draggingID = nil; activeHandle = nil; initialLayer = nil
            updateArtwork()
            if artwork.composited { artwork.setNeedsDisplay() }
            selectionOverlay.setNeedsDisplay()
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
        CGPoint(x: (p.x - Self.controlMargin) / fit + (session?.canvasBounds.minX ?? 0),
                y: (p.y - Self.controlMargin) / fit + (session?.canvasBounds.minY ?? 0))
    }
    private func screenPoint(_ p: CGPoint) -> CGPoint {
        CGPoint(x: (p.x - (session?.canvasBounds.minX ?? 0)) * fit + Self.controlMargin,
                y: (p.y - (session?.canvasBounds.minY ?? 0)) * fit + Self.controlMargin)
    }
    private func handles() -> [(Handle, CGPoint)] {
        guard let session, !session.inkMode, let layer = displayedSelection, layer.visible, !layer.locked else { return [] }
        guard let b = renderCache.entries[layer.id]?.rect else { return [] }
        let m = displayMatrix(layer)
        var points: [(Handle, CGPoint)] = [(.delete, CGPoint(x:b.minX,y:b.minY)), (.edit, CGPoint(x:b.maxX,y:b.minY)),
            (.duplicate, CGPoint(x:b.minX,y:b.maxY)), (.scale, CGPoint(x:b.maxX,y:b.maxY))]
        if layer.kind == .frame {
            points = [(.delete, CGPoint(x:b.minX,y:b.minY))]
        } else {
            points += [(.top, CGPoint(x:b.midX,y:b.minY)), (.bottom, CGPoint(x:b.midX,y:b.maxY)),
                       (.left, CGPoint(x:b.minX,y:b.midY)), (.right, CGPoint(x:b.maxX,y:b.midY)),
                       (.rotate, CGPoint(x:b.maxX + 44 / max(0.01, fit * viewportZoom * layer.transform.scale * layer.transform.stretchX),y:b.midY))]
        }
        if layer.id == session.content.primaryLayerID { points.removeAll { $0.0 == .delete } }
        return points.map { ($0.0, screenPoint($0.1.applying(m))) }
    }
    private func handleHit(_ p: CGPoint) -> Handle? {
        // 控制点优先于素材命中；相邻触摸区重叠时选择最近的中心。
        handles().map { ($0.0, hypot(p.x-$0.1.x, p.y-$0.1.y)) }
            .filter { $0.1 <= 22 / viewportZoom }.min { $0.1 < $1.1 }?.0
    }
    private static let symbols: [String: UIImage] = Dictionary(uniqueKeysWithValues:
        Set(Handle.allCases.map(\.symbol)).compactMap { symbol in
            UIImage(systemName: symbol).map { (symbol, $0.withTintColor(.systemBlue, renderingMode: .alwaysOriginal)) }
        })
    private func drawHandles(in context: CGContext) {
        let radius: CGFloat = 12 / viewportZoom
        for (handle, point) in handles() {
            let rect = CGRect(x:point.x-radius,y:point.y-radius,width:radius*2,height:radius*2)
            context.setFillColor(UIColor.white.cgColor); context.fillEllipse(in:rect)
            context.setStrokeColor(UIColor.systemBlue.cgColor); context.setLineWidth(1 / viewportZoom); context.strokeEllipse(in:rect)
            context.saveGState()
            if handle == .left || handle == .right {
                context.translateBy(x: point.x, y: point.y)
                context.rotate(by: .pi / 2)
                context.translateBy(x: -point.x, y: -point.y)
            }
            Self.symbols[handle.symbol]?.draw(in:rect.insetBy(dx:5 / viewportZoom,dy:5 / viewportZoom))
            context.restoreGState()
        }
        if activeHandle == .rotate, let layer = displayedSelection {
            let point = handles().first { $0.0 == .rotate }?.1 ?? .zero
            (String(format:"%.0f°", layer.transform.rotationDegrees) as NSString).draw(
                at:CGPoint(x:point.x+18 / viewportZoom,y:point.y),
                withAttributes:[.font:UIFont.systemFont(ofSize:14 / viewportZoom),.foregroundColor:UIColor.systemBlue])
        }
    }
    private func updateHandle(_ handle: Handle, point: CGPoint) {
        guard var layer = initialLayer, layer.kind != .frame else { return }
        let b = initialBounds
        let oldMatrix = layer.transform.matrix
        let localStart = initialTouch.applying(oldMatrix.inverted())
        let local = point.applying(oldMatrix.inverted())
        if handle == .scale {
            // 左上角固定，以对角线投影决定等比倍率，反向拖过锚点时停止于最小尺寸。
            let diagonal = CGPoint(x:b.width,y:b.height)
            let delta = CGPoint(x:local.x-localStart.x,y:local.y-localStart.y)
            let ratio = max(0.05, 1 + (delta.x*diagonal.x+delta.y*diagonal.y) / max(1,diagonal.x*diagonal.x+diagonal.y*diagonal.y))
            let anchor = CGPoint(x:b.minX,y:b.minY)
            let fixed = anchor.applying(oldMatrix)
            layer.transform.scale = min(20,max(0.05,layer.transform.scale*ratio))
            let moved = anchor.applying(layer.transform.matrix)
            layer.transform.position.x += fixed.x-moved.x; layer.transform.position.y += fixed.y-moved.y
        } else if handle == .rotate {
            let center = CGPoint(x:b.midX,y:b.midY)
            let fixed = center.applying(oldMatrix)
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
            let moved = center.applying(layer.transform.matrix)
            layer.transform.position.x += fixed.x-moved.x; layer.transform.position.y += fixed.y-moved.y
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
        showPreview(layer)
    }

}

/// 原生绘画画布以设计尺寸布局，再整体缩放显示，保存的笔画始终是页面坐标。
struct DiaryDrawingCanvasView: UIViewRepresentable {
    @ObservedObject var session: DiaryEditorSession
    func makeCoordinator() -> Coordinator { Coordinator(session: session) }
    func makeUIView(context: Context) -> PKCanvasView {
        let view = PKCanvasView()
        view.backgroundColor = .clear; view.isOpaque = false
        view.overrideUserInterfaceStyle = .light
        view.isScrollEnabled = false; view.drawingPolicy = .anyInput
        view.delegate = context.coordinator
        context.coordinator.canvas = view
        session.flushDrawingInteraction = { [weak coordinator = context.coordinator] in coordinator?.flush() }
        configure(view, coordinator: context.coordinator)
        return view
    }
    func updateUIView(_ view: PKCanvasView, context: Context) { configure(view, coordinator: context.coordinator) }
    static func dismantleUIView(_ uiView: PKCanvasView, coordinator: Coordinator) {
        coordinator.session.finishInteraction()
        coordinator.session.flushDrawingInteraction = nil
        uiView.delegate = nil
    }
    private func configure(_ view: PKCanvasView, coordinator: Coordinator) {
        let data = session.content.drawing
        if !coordinator.dirty && coordinator.lastData != data {
            var displayed = session.drawing
            displayed.transform(using: CGAffineTransform(translationX: -session.canvasBounds.minX, y: -session.canvasBounds.minY))
            coordinator.replaying = true
            view.drawing = displayed
            view.undoManager?.removeAllActions()
            coordinator.lastData = data
            coordinator.replaying = false
        }
        if coordinator.lastEraser != session.eraser {
            view.tool = session.eraser ? PKEraserTool(.vector) : PKInkingTool(.pen, color: .systemPink, width: 8)
            coordinator.lastEraser = session.eraser
        }
    }
    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let session: DiaryEditorSession
        weak var canvas: PKCanvasView?
        var replaying = false
        var dirty = false
        var lastData: Data?
        var lastEraser: Bool?
        init(session: DiaryEditorSession) { self.session = session }
        func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) { session.beginInteraction() }
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !replaying else { return }
            session.beginInteraction()
            dirty = true
        }
        func flush() {
            guard dirty, let canvas else { return }
            dirty = false
            var local = canvas.drawing
            local.transform(using: CGAffineTransform(translationX: session.canvasBounds.minX, y: session.canvasBounds.minY))
            session.previewDrawing(local)
            lastData = session.content.drawing
        }
        func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
            flush()
            session.finishInteraction()
            canvasView.undoManager?.removeAllActions()
        }
    }
}
