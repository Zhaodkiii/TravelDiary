import SwiftUI
import UIKit

/// 短按和长按交给同一 UIKit 触摸表面；长按失败后短按才能触发。
/// 不使用零距离 DragGesture，避免按下时抢走点击或列表滚动。
struct DiaryPageTouchSurface: UIViewRepresentable {
    var onTap: () -> Void
    var onBegin: (CGPoint) -> Void
    var onMove: (CGSize) -> Void
    var onEnd: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let hold = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.hold(_:)))
        hold.minimumPressDuration = 0.35
        hold.allowableMovement = 10
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:)))
        tap.require(toFail: hold)
        view.addGestureRecognizer(hold)
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) { context.coordinator.parent = self }

    final class Coordinator: NSObject {
        var parent: DiaryPageTouchSurface
        private var start = CGPoint.zero
        init(_ parent: DiaryPageTouchSurface) { self.parent = parent }

        @objc func tap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended else { return }
            parent.onTap()
        }

        @objc func hold(_ gesture: UILongPressGestureRecognizer) {
            guard let view = gesture.view else { return }
            // 用窗口坐标记录位移，卡片让位或列表滚动时不会改变拖动基准。
            let point = gesture.location(in: view.window)
            switch gesture.state {
            case .began:
                start = point
                parent.onBegin(gesture.location(in: view))
            case .changed:
                parent.onMove(CGSize(width: point.x - start.x, height: point.y - start.y))
            case .ended, .cancelled:
                parent.onEnd()
            default: break
            }
        }
    }
}
