import SwiftUI
import UIKit

/// 缩放完全由 UIScrollView 管理，不把逐帧倍率写回 SwiftUI，也不在手势期间重设布局。
struct DiaryBookZoomViewport<Content: View>: UIViewControllerRepresentable {
    let contentSize: CGSize
    let resetToken: Int
    var focusSpreadSize: CGSize? = nil
    @ViewBuilder let content: () -> Content

    func makeUIViewController(context: Context) -> DiaryBookZoomController<Content> {
        DiaryBookZoomController(content: content())
    }

    func updateUIViewController(_ controller: DiaryBookZoomController<Content>, context: Context) {
        controller.update(content: content(), size: contentSize, token: resetToken, focusSpreadSize: focusSpreadSize)
    }
}

final class DiaryBookZoomController<Content: View>: UIViewController, UIScrollViewDelegate {
    private let scroll = UIScrollView()
    private let host: UIHostingController<Content>
    private var size = CGSize.zero
    private var token: Int?
    private var focusSpreadSize: CGSize?
    private lazy var doubleTap = UITapGestureRecognizer(target: self, action: #selector(focusPage(_:)))
    private var needsCenter = true
    private var suspended: [DiaryCurlPageViewController] = []

    init(content: Content) {
        host = UIHostingController(rootView: content)
        super.init(nibName: nil, bundle: nil)
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("不支持 Storyboard") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        scroll.backgroundColor = .clear
        scroll.delegate = self
        scroll.minimumZoomScale = 1
        scroll.maximumZoomScale = 4
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false
        scroll.panGestureRecognizer.minimumNumberOfTouches = 2
        doubleTap.numberOfTapsRequired = 2
        doubleTap.isEnabled = false
        scroll.addGestureRecognizer(doubleTap)
        view.addSubview(scroll)
        addChild(host)
        host.safeAreaRegions = []
        host.view.backgroundColor = .clear
        scroll.addSubview(host.view)
        host.didMove(toParent: self)
    }

    func update(content: Content, size: CGSize, token: Int, focusSpreadSize: CGSize? = nil) {
        loadViewIfNeeded()
        self.focusSpreadSize = focusSpreadSize
        doubleTap.isEnabled = focusSpreadSize != nil
        host.rootView = content
        guard self.size != size || self.token != token else { return }
        suspendPageGestures(false)
        self.size = size
        self.token = token
        scroll.setZoomScale(1, animated: false)
        scroll.panGestureRecognizer.minimumNumberOfTouches = 2
        host.view.frame = CGRect(origin: .zero, size: size)
        scroll.contentSize = size
        needsCenter = true
        view.setNeedsLayout()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if scroll.frame != view.bounds { scroll.frame = view.bounds }
        center()
        if needsCenter && scroll.bounds.width > 0 && scroll.bounds.height > 0 {
            scroll.contentOffset = CGPoint(x: -scroll.contentInset.left, y: -scroll.contentInset.top)
            needsCenter = false
        }
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { host.view }
    func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
        suspendPageGestures(true)
    }
    func scrollViewDidZoom(_ scrollView: UIScrollView) { center() }
    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        let enlarged = scale > 1.001
        scroll.panGestureRecognizer.minimumNumberOfTouches = enlarged ? 1 : 2
        suspendPageGestures(enlarged)
    }

    @objc private func focusPage(_ gesture: UITapGestureRecognizer) {
        guard let focusSpreadSize else { return }
        let animated = !UIAccessibility.isReduceMotionEnabled
        if scroll.zoomScale > 1.001 {
            scroll.setZoomScale(1, animated: animated)
            if !animated { scrollViewDidEndZooming(scroll, with: host.view, atScale: 1) }
            return
        }
        guard let rect = DiaryBookFocusLayout.rect(viewport: size, spread: focusSpreadSize,
                                                   point: gesture.location(in: host.view)) else { return }
        suspendPageGestures(true)
        scroll.zoom(to: rect, animated: animated)
        if !animated { scrollViewDidEndZooming(scroll, with: host.view, atScale: scroll.zoomScale) }
    }

    private func center() {
        let x = max(0, (scroll.bounds.width - size.width * scroll.zoomScale) / 2)
        let y = max(0, (scroll.bounds.height - size.height * scroll.zoomScale) / 2)
        let inset = UIEdgeInsets(top: y, left: x, bottom: y, right: x)
        if scroll.contentInset != inset { scroll.contentInset = inset }
    }

    private func suspendPageGestures(_ suspend: Bool) {
        if !suspend {
            suspended.forEach { $0.setZoomSuspended(false) }
            suspended.removeAll()
            return
        }
        guard suspended.isEmpty else { return }
        func visit(_ controller: UIViewController) {
            if let pages = controller as? DiaryCurlPageViewController {
                suspended.append(pages)
                pages.setZoomSuspended(true)
            }
            controller.children.forEach(visit)
        }
        visit(host)
    }
}

/// 哑光内衬：细短纤维使用固定种子绘制，尺寸变化时不会随机闪烁。
struct DiaryBookLining: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.30, green: 0.25, blue: 0.19)))
            var seed: UInt64 = 87
            func random() -> CGFloat {
                seed = seed &* 6364136223846793005 &+ 1
                return CGFloat(seed >> 32) / CGFloat(UInt32.max)
            }
            for _ in 0..<18000 {
                let x = random() * size.width
                let y = random() * size.height
                let length = 0.4 + random() * 1.4
                var fiber = Path()
                fiber.move(to: CGPoint(x: x, y: y))
                fiber.addLine(to: CGPoint(x: x + length * 0.4, y: y + length))
                context.stroke(fiber, with: .color(random() > 0.5 ? .white.opacity(0.09) : .black.opacity(0.12)), lineWidth: 0.45)
            }
        }
        .overlay(LinearGradient(colors: [.black.opacity(0.08), .clear, .black.opacity(0.18)], startPoint: .leading, endPoint: .trailing))
        .accessibilityLabel("绒面内衬")
    }
}

/// 单页按宽度聚焦；纵向保留点击位置，边界处不露出书本外的空白。
nonisolated enum DiaryBookFocusLayout {
    static func rect(viewport: CGSize, spread: CGSize, point: CGPoint) -> CGRect? {
        guard viewport.width > 0, viewport.height > 0, spread.width > 0, spread.height > 0 else { return nil }
        let book = CGRect(x: (viewport.width - spread.width) / 2,
                          y: (viewport.height - spread.height) / 2,
                          width: spread.width, height: spread.height)
        guard book.contains(point) else { return nil }
        let scale = min(2.5, max(1.5, viewport.width / (spread.width / 2)))
        let width = viewport.width / scale, height = viewport.height / scale
        let centerX = book.midX + (point.x < book.midX ? -spread.width / 4 : spread.width / 4)
        return CGRect(x: min(max(centerX - width / 2, book.minX), book.maxX - width),
                      y: min(max(point.y - height / 2, book.minY), max(book.minY, book.maxY - height)),
                      width: width, height: height)
    }
}
