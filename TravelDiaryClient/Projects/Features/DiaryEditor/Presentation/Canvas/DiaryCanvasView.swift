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
        view.session = session; view.onEdit = onEdit; view.setNeedsDisplay()
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
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
        let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        pan.maximumNumberOfTouches = 1
        addGestureRecognizer(pan)
        accessibilityLabel = "手帐画布，可在图层面板选择元素"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ rect: CGRect) {
        guard let session, let context = UIGraphicsGetCurrentContext(), fit > 0 else { return }
        context.saveGState()
        context.translateBy(x: Self.controlMargin, y: Self.controlMargin)
        context.scaleBy(x: fit, y: fit)
        context.translateBy(x: -session.canvasBounds.minX, y: -session.canvasBounds.minY)
        // 棋盘格只用于显示透明区域，不写入导出图片。
        let viewport = session.canvasBounds
        UIColor.white.setFill(); context.fill(viewport)
        UIColor(white: 0.92, alpha: 1).setFill()
        for x in stride(from: viewport.minX, to: viewport.maxX, by: 30) {
            for y in stride(from: viewport.minY, to: viewport.maxY, by: 30) {
                if (Int((x - viewport.minX) / 30) + Int((y - viewport.minY) / 30)) % 2 == 0 {
                    context.fill(CGRect(x: x, y: y, width: 30, height: 30).intersection(viewport))
                }
            }
        }
        DiaryPageRenderer.draw(session.document, contentID: session.contentID, images: session.images,
                               in: context, viewport: viewport, includeInk: !session.inkMode)
        if !session.inkMode, let layer = session.selected, layer.visible {
            context.concatenate(DiaryPageRenderer.matrix(layer, siblings: session.scopeLayers))
            context.setStrokeColor(UIColor.systemBlue.cgColor)
            context.setLineWidth(2 / max(0.01, fit * viewportZoom * layer.transform.scale))
            context.stroke(DiaryPageRenderer.bounds(layer, document: session.document, siblings: session.scopeLayers).insetBy(dx: -3, dy: -3))
        }
        context.restoreGState()
        drawHandles(in: context)
    }

    private func hit(_ screen: CGPoint) -> UUID? {
        guard let session, fit > 0 else { return nil }
        let pagePoint = designPoint(screen)
        let parentPoint = pagePoint
        // 从上到下命中；组内编辑时只检查当前组的直接子层。
        for node in session.scopeLayers.reversed() where node.visible && !node.locked {
            let local = parentPoint.applying(DiaryPageRenderer.matrix(node, siblings: session.scopeLayers).inverted())
            if DiaryPageRenderer.bounds(node, document: session.document, siblings: session.scopeLayers).contains(local) { return node.id }
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
            guard let layer = session.selected, layer.visible, !layer.locked else { return }
            activeHandle = handleHit(touchOrigin)
            if let handle = activeHandle, [.delete, .edit, .duplicate].contains(handle) { return }
            guard activeHandle != nil || hit(touchOrigin) == layer.id else { return }
            initialLayer = layer
            initialBounds = DiaryPageRenderer.bounds(layer, document: session.document, siblings: session.scopeLayers)
            initialTouch = designPoint(touchOrigin)
            let center = CGPoint(x: initialBounds.midX, y: initialBounds.midY).applying(layer.transform.matrix)
            rotationLast = atan2(initialTouch.y - center.y, initialTouch.x - center.x)
            rotationTotal = 0
            session.beginInteraction()
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
            session.previewPosition(CGPoint(x: startPosition.x + shifted.x - origin.x,
                                            y: startPosition.y + shifted.y - origin.y))
        case .ended:
            if draggingID != nil { session.finishInteraction() }
            startPosition = nil; draggingID = nil; activeHandle = nil; initialLayer = nil
            setNeedsDisplay()
        case .cancelled, .failed:
            if draggingID != nil { session.cancelInteraction() }
            startPosition = nil; draggingID = nil; activeHandle = nil; initialLayer = nil
            setNeedsDisplay()
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
        guard let session, !session.inkMode, let layer = session.selected, layer.visible, !layer.locked else { return [] }
        let b = DiaryPageRenderer.bounds(layer, document: session.document, siblings: session.scopeLayers)
        let m = DiaryPageRenderer.matrix(layer, siblings: session.scopeLayers)
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
            UIImage(systemName:handle.symbol)?.withTintColor(.systemBlue, renderingMode:.alwaysOriginal)
                .draw(in:rect.insetBy(dx:5 / viewportZoom,dy:5 / viewportZoom))
            context.restoreGState()
        }
        if activeHandle == .rotate, let layer = session?.selected {
            let point = handles().first { $0.0 == .rotate }?.1 ?? .zero
            (String(format:"%.0f°", layer.transform.rotationDegrees) as NSString).draw(
                at:CGPoint(x:point.x+18 / viewportZoom,y:point.y),
                withAttributes:[.font:UIFont.systemFont(ofSize:14 / viewportZoom),.foregroundColor:UIColor.systemBlue])
        }
    }
    private func updateHandle(_ handle: Handle, point: CGPoint) {
        guard var layer = initialLayer, let session, layer.kind != .frame else { return }
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
        session.previewLayer(layer)
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
        configure(view, coordinator: context.coordinator)
        return view
    }
    func updateUIView(_ view: PKCanvasView, context: Context) { configure(view, coordinator: context.coordinator) }
    private func configure(_ view: PKCanvasView, coordinator: Coordinator) {
        var displayed = session.drawing
        displayed.transform(using: CGAffineTransform(translationX: -session.canvasBounds.minX, y: -session.canvasBounds.minY))
        if view.drawing != displayed {
            coordinator.replaying = true
            view.drawing = displayed
            view.undoManager?.removeAllActions()
            coordinator.replaying = false
        }
        view.tool = session.eraser ? PKEraserTool(.vector) : PKInkingTool(.pen, color: .systemPink, width: 8)
    }
    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let session: DiaryEditorSession
        var replaying = false
        init(session: DiaryEditorSession) { self.session = session }
        func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) { session.beginInteraction() }
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !replaying else { return }
            var local = canvasView.drawing
            local.transform(using: CGAffineTransform(translationX: session.canvasBounds.minX, y: session.canvasBounds.minY))
            session.previewDrawing(local)
        }
        func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
            var local = canvasView.drawing
            local.transform(using: CGAffineTransform(translationX: session.canvasBounds.minX, y: session.canvasBounds.minY))
            session.previewDrawing(local)
            session.finishInteraction()
            canvasView.undoManager?.removeAllActions()
        }
    }
}
