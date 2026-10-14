import SwiftUI
import UIKit

/// 整个内容树共用一个缩放视口，照片、选框和原生画笔始终同步。
/// 单指交给素材编辑，双指交给视口平移，避免 zoomable 的拖动与素材手势冲突。
struct DiaryZoomableCanvas<Content: View>: UIViewRepresentable {
    let contentSize: CGSize
    @ViewBuilder let content: () -> Content

    func makeCoordinator() -> Coordinator { Coordinator(content: content()) }

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = DiaryZoomScrollView()
        scroll.onLayout = { [weak coordinator = context.coordinator] scroll in
            coordinator?.center(scroll)
        }
        scroll.delegate = context.coordinator
        scroll.minimumZoomScale = 1
        scroll.maximumZoomScale = 8
        scroll.bouncesZoom = true
        scroll.showsVerticalScrollIndicator = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.panGestureRecognizer.minimumNumberOfTouches = 2
        scroll.backgroundColor = .clear
        let canvas = context.coordinator.host.view!
        canvas.backgroundColor = .clear
        scroll.addSubview(canvas)
        configure(scroll, coordinator: context.coordinator)
        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {
        context.coordinator.host.rootView = content()
        configure(scroll, coordinator: context.coordinator)
    }

    private func configure(_ scroll: UIScrollView, coordinator: Coordinator) {
        // 同一个对象编辑过程中保留查看倍率；参考尺寸变化时恢复适应视口状态。
        if coordinator.size != contentSize {
            scroll.setZoomScale(1, animated: false)
            coordinator.size = contentSize
            coordinator.host.view.frame = CGRect(origin: .zero, size: contentSize)
            scroll.contentSize = contentSize
        }
        coordinator.center(scroll)
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        let host: UIHostingController<Content>
        var size = CGSize.zero
        init(content: Content) { host = UIHostingController(rootView: content) }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { host.view }
        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            center(scrollView)
            // 缩放后重画屏幕尺寸恒定的控制点，不修改任何作品坐标。
            func redraw(_ view: UIView) {
                if view is DiaryCanvasSurface { view.setNeedsDisplay() }
                view.subviews.forEach(redraw)
            }
            redraw(host.view)
        }
        func center(_ scroll: UIScrollView) {
            let horizontal = max(0, (scroll.bounds.width - size.width * scroll.zoomScale) / 2)
            let vertical = max(0, (scroll.bounds.height - size.height * scroll.zoomScale) / 2)
            let inset = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
            if scroll.contentInset != inset { scroll.contentInset = inset }
        }
    }
}

/// SwiftUI 初次布局时视口可能仍为零尺寸，实际布局完成后再校正居中边距。
private final class DiaryZoomScrollView: UIScrollView {
    var onLayout: ((UIScrollView) -> Void)?
    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?(self)
    }
}
