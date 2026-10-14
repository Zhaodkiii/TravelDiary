import PencilKit
import SwiftUI

struct TelegramDrawingCanvasView: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    let color: UIColor
    let lineWidth: CGFloat
    let selectedTool: TelegramPhotoDrawingTool
    let isEnabled: Bool
    let action: TelegramDrawingCanvasAction
    let historyChanged: (Bool, Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(drawing: $drawing, historyChanged: historyChanged)
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.delegate = context.coordinator
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawingPolicy = .anyInput
        canvas.alwaysBounceVertical = false
        canvas.alwaysBounceHorizontal = false
        configure(canvas)
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        context.coordinator.drawing = $drawing
        context.coordinator.historyChanged = historyChanged
        if canvas.drawing.dataRepresentation() != drawing.dataRepresentation() {
            canvas.drawing = drawing
        }
        configure(canvas)
        if context.coordinator.lastAction != action {
            context.coordinator.lastAction = action
            switch action {
            case .none:
                break
            case .undo:
                canvas.undoManager?.undo()
            case .redo:
                canvas.undoManager?.redo()
            }
            historyChanged(canvas.undoManager?.canUndo == true, canvas.undoManager?.canRedo == true)
        }
    }

    private func configure(_ canvas: PKCanvasView) {
        canvas.isUserInteractionEnabled = isEnabled
        switch selectedTool {
        case .pen:
            canvas.tool = PKInkingTool(.pen, color: color, width: lineWidth)
        case .marker:
            canvas.tool = PKInkingTool(.marker, color: color.withAlphaComponent(0.72), width: lineWidth * 2.2)
        case .pencil:
            canvas.tool = PKInkingTool(.pencil, color: color, width: lineWidth)
        case .monoline:
            canvas.tool = PKInkingTool(.monoline, color: color, width: lineWidth)
        case .fountain:
            canvas.tool = PKInkingTool(.fountainPen, color: color, width: lineWidth)
        case .eraser:
            canvas.tool = PKEraserTool(.vector)
        }
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var drawing: Binding<PKDrawing>
        var lastAction: TelegramDrawingCanvasAction = .none
        var historyChanged: (Bool, Bool) -> Void

        init(drawing: Binding<PKDrawing>, historyChanged: @escaping (Bool, Bool) -> Void) {
            self.drawing = drawing
            self.historyChanged = historyChanged
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            drawing.wrappedValue = canvasView.drawing
            historyChanged(canvasView.undoManager?.canUndo == true, canvasView.undoManager?.canRedo == true)
        }
    }
}
