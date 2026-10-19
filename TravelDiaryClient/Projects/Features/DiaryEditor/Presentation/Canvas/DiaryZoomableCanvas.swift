import SwiftUI
import UIKit

/// 整个内容树共用一个缩放视口，照片、选框和原生画笔始终同步。
/// 单指交给素材编辑，双指交给视口平移，避免 zoomable 的拖动与素材手势冲突。
struct DiaryZoomableCanvas<Content: View>: UIViewRepresentable {
    let contentSize: CGSize
    let sessionID: UUID
    let inkMode: Bool
    var minimumScale: CGFloat = 1
    var toolViewport = false
    var refreshContent = false
    @ViewBuilder let content: () -> Content

    func makeCoordinator() -> Coordinator { Coordinator(content: content()) }

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = DiaryZoomScrollView()
        scroll.onLayout = { [weak coordinator = context.coordinator] scroll in
            coordinator?.center(scroll)
        }
        scroll.delegate = context.coordinator
        scroll.minimumZoomScale = minimumScale
        scroll.maximumZoomScale = 8
        scroll.bouncesZoom = true
        scroll.showsVerticalScrollIndicator = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.panGestureRecognizer.minimumNumberOfTouches = 2
        scroll.backgroundColor = .clear
        scroll.contentInsetAdjustmentBehavior = .never
        let canvas = context.coordinator.host.view!
        canvas.backgroundColor = .clear
        scroll.addSubview(canvas)
        configure(scroll, coordinator: context.coordinator)
        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {
        let coordinator = context.coordinator
        // 内部画布自行观察 Session；只有结构、尺寸或会话改变才替换宿主树。
        if refreshContent || coordinator.sessionID != sessionID || coordinator.inkMode != inkMode || coordinator.size != contentSize || coordinator.toolViewport != toolViewport {
            coordinator.host.rootView = content()
            coordinator.sessionID = sessionID; coordinator.inkMode = inkMode
        }
        configure(scroll, coordinator: context.coordinator)
    }

    private func configure(_ scroll: UIScrollView, coordinator: Coordinator) {
        // 工具面板改变可用区域时重新适配，素材选择不会改变尺寸或浏览倍率。
        if coordinator.toolViewport != toolViewport {
            coordinator.toolViewport = toolViewport
            coordinator.needsInitialCenter = true
        }
        if coordinator.size != contentSize {
            scroll.setZoomScale(1, animated: false)
            coordinator.size = contentSize
            coordinator.needsInitialCenter = true
            coordinator.host.view.frame = CGRect(origin: .zero, size: contentSize)
            scroll.contentSize = contentSize
        }
        coordinator.center(scroll)
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        let host: UIHostingController<Content>
        var size = CGSize.zero
        var needsInitialCenter = true
        var sessionID: UUID?
        var inkMode = false
        var toolViewport = false
        init(content: Content) { host = UIHostingController(rootView: content) }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { host.view }
        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            center(scrollView)
            // 缩放后重画屏幕尺寸恒定的控制点，不修改任何作品坐标。
            func redraw(_ view: UIView) {
                if let canvas = view as? DiaryCanvasSurface { canvas.viewportDidZoom() }
                view.subviews.forEach(redraw)
            }
            redraw(host.view)
        }
        func center(_ scroll: UIScrollView) {
            let horizontal = max(0, (scroll.bounds.width - size.width * scroll.zoomScale) / 2)
            let vertical = toolViewport ? 0 : max(0, (scroll.bounds.height - size.height * scroll.zoomScale) / 2)
            let inset = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
            if scroll.contentInset != inset { scroll.contentInset = inset }
            guard needsInitialCenter, scroll.bounds.width > 0, scroll.bounds.height > 0 else { return }
            // 初始将页面主体居中；横向内容略宽于视口时，用滚动偏移把两侧手柄留白均分。
            let x = max(-inset.left, (size.width * scroll.zoomScale - scroll.bounds.width) / 2)
            let y = toolViewport ? -inset.top : max(-inset.top, (size.height * scroll.zoomScale - scroll.bounds.height) / 2)
            scroll.setContentOffset(CGPoint(x: x, y: y), animated: false)
            needsInitialCenter = false
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
