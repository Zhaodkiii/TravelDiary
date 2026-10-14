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

/// 页面始终使用 1000×1400 设计坐标；UIView 只负责将其映射到当前可用屏幕区域。
final class DiaryCanvasSurface: UIView {
    weak var session: DiaryEditorSession?
    private var startPosition: CGPoint?
    private var parentAtStart = CGAffineTransform.identity
    private var fit: CGFloat { bounds.width / 1000 }

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
        DiaryPageRenderer.draw(session.document, images: session.images,
                               drawing: session.inkMode ? nil : session.drawing, in: context)
        if !session.inkMode, let layer = session.selected, layer.visible {
            context.concatenate(session.parentMatrix)
            context.concatenate(layer.transform.matrix)
            context.setStrokeColor(UIColor.systemBlue.cgColor)
            let parentScale = session.document.layer(session.groupID)?.transform.scale ?? 1
            context.setLineWidth(2 / max(0.01, fit * parentScale * layer.transform.scale))
            context.stroke(DiaryPageRenderer.bounds(layer).insetBy(dx: -3, dy: -3))
        }
        context.restoreGState()
    }

    private func hit(_ screen: CGPoint) -> UUID? {
        guard let session, fit > 0 else { return nil }
        let pagePoint = CGPoint(x: screen.x / fit, y: screen.y / fit)
        let parentPoint = pagePoint.applying(session.parentMatrix.inverted())
        // 从上到下命中；组内编辑时只检查当前组的直接子层。
        for node in session.scopeLayers.reversed() where node.visible && !node.locked {
            let local = parentPoint.applying(node.transform.matrix.inverted())
            if DiaryPageRenderer.bounds(node).contains(local) { return node.id }
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
            parentAtStart = session.parentMatrix
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
        if view.drawing != session.drawing {
            coordinator.replaying = true
            view.drawing = session.drawing
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
            session.previewDrawing(canvasView.drawing)
        }
        func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
            session.previewDrawing(canvasView.drawing)
            session.finishInteraction()
            canvasView.undoManager?.removeAllActions()
        }
    }
}
