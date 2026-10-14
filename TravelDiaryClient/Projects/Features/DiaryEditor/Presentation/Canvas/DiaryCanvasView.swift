import SwiftUI
import UIKit
import PencilKit

struct DiaryCanvasView: UIViewRepresentable {
    @ObservedObject var session: DiaryEditorSession
    func makeUIView(context: Context) -> DiaryCanvasSurface {
        let view = DiaryCanvasSurface(); view.session = session; return view
    }
    func updateUIView(_ view: DiaryCanvasSurface, context: Context) {
        view.session = session; view.setNeedsDisplay()
    }
}

/// 每个对象使用独立设计坐标；视口可包含负坐标，装饰伸出照片时仍保留原位置。
final class DiaryCanvasSurface: UIView {
    weak var session: DiaryEditorSession?
    private var startPosition: CGPoint?
    private var parentAtStart = CGAffineTransform.identity
    private var fit: CGFloat { bounds.width / (session?.canvasBounds.width ?? 1000) }

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
            context.setLineWidth(2 / max(0.01, fit * layer.transform.scale))
            context.stroke(DiaryPageRenderer.bounds(layer, document: session.document, siblings: session.scopeLayers).insetBy(dx: -3, dy: -3))
        }
        context.restoreGState()
    }

    private func hit(_ screen: CGPoint) -> UUID? {
        guard let session, fit > 0 else { return nil }
        let pagePoint = CGPoint(x: screen.x / fit + session.canvasBounds.minX, y: screen.y / fit + session.canvasBounds.minY)
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
        session.select(hit(gesture.location(in: self)))
    }
    @objc private func panned(_ gesture: UIPanGestureRecognizer) {
        guard let session, !session.inkMode, !session.busy, fit > 0 else { return }
        switch gesture.state {
        case .began:
            session.select(hit(gesture.location(in: self)))
            guard let layer = session.selected else { return }
            session.beginInteraction()
            startPosition = layer.transform.position
            parentAtStart = .identity
        case .changed:
            guard let startPosition else { return }
            let translation = gesture.translation(in: self)
            let inverse = parentAtStart.inverted()
            let origin = CGPoint.zero.applying(inverse)
            let shifted = CGPoint(x: translation.x / fit, y: translation.y / fit).applying(inverse)
            session.previewPosition(CGPoint(x: startPosition.x + shifted.x - origin.x,
                                            y: startPosition.y + shifted.y - origin.y))
        case .ended:
            session.finishInteraction(); startPosition = nil
        case .cancelled, .failed:
            session.cancelInteraction(); startPosition = nil
        default: break
        }
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
