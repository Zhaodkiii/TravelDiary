import SwiftUI
import UIKit

/// 阅读投影不修改目录：内封皮与第一页组成首跨页，之后按目录顺序连续配对。
struct DiaryPhysicalBookScreen: View {
    let book: DiaryBook
    let store: DiaryDocumentStore
    private let onShowList: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var opened = false
    @State private var spread = 0
    @State private var turningCover = false
    private var innerPages: [DiaryPageEntry] { book.contentPages }
    private var spreadCount: Int { innerPages.isEmpty ? 0 : (innerPages.count + 2) / 2 }
    private var paperRatio: CGFloat {
        let size = innerPages.first?.size ?? book.defaultPageSize
        return max(size.width, 1) / max(size.height, 1)
    }

    init(book: DiaryBook, store: DiaryDocumentStore, onShowList: (() -> Void)? = nil) {
        self.book = book
        self.store = store
        self.onShowList = onShowList
        _opened = State(initialValue: book.shell == nil)
    }

    var body: some View {
        if onShowList != nil {
            readerContent
        } else {
            NavigationStack { readerContent }
        }
    }

    private var readerContent: some View {
            VStack(spacing: 16) {
                GeometryReader { geometry in
                    DiaryBookZoomViewport(contentSize: geometry.size,
                                          resetToken: opened ? spread + 1 : 0) {
                        DiaryBookOpeningStage(progress: opened ? 1 : 0, viewport: geometry.size,
                                              paperRatio: paperRatio, cover: book.shell,
                                              firstPage: innerPages.first, store: store) {
                            DiaryCurlBook(pages: innerPages, store: store, spread: $spread, reduceMotion: reduceMotion)
                                .overlay { bindingRings.allowsHitTesting(false).accessibilityHidden(true) }
                        }
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.85), value: opened)
                        .onTapGesture { if !opened { openBook() } }
                    }
                    .allowsHitTesting(!turningCover)
                }.clipped()
                HStack {
                    Button { if spread > 0 { spread -= 1 } else { closeBook() } } label: {
                        Image(systemName: "chevron.left")
                    }.disabled(!opened || (spread == 0 && book.shell == nil)).accessibilityLabel(spread == 0 ? "合上手帐" : "上一跨页")
                    Spacer()
                    Text(opened ? "\(spreadTitle(spread)) / \(innerPages.count)" : "外壳")
                        .font(.subheadline.monospacedDigit())
                    Spacer()
                    Button { if opened { spread += 1 } else { openBook() } } label: {
                        Image(systemName: "chevron.right")
                    }.disabled(spreadCount == 0 || (opened && spread >= spreadCount - 1))
                        .accessibilityLabel(opened ? "下一跨页" : "展开手帐")
                }.padding(.horizontal, 28).disabled(turningCover)
                thumbnailRail.disabled(turningCover)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(book.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if onShowList == nil {
                    ToolbarItem(placement: .topBarLeading) { Button("完成") { dismiss() } }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if let onShowList {
                        Button(action: onShowList) { Image(systemName: "list.bullet") }
                            .accessibilityLabel("列表模式")
                            .disabled(turningCover)
                    } else if book.shell != nil {
                        Button(opened ? "合上" : "展开") { if opened { closeBook() } else { openBook() } }
                            .disabled(spreadCount == 0 || turningCover)
                    }
                }
            }
    }

    private var bindingRings: some View {
        GeometryReader { geometry in
            // 九扣按三组三枚排列；固定在书脊，翻页时不跟随纸张旋转。
            ForEach(0..<9) { index in
                let fraction = 0.10 + Double(index / 3) * 0.31 + Double(index % 3) * 0.075
                Image("DiaryBookRing").resizable().scaledToFit()
                    .frame(width: min(geometry.size.width * 0.075, 56))
                    .position(x: geometry.size.width / 2, y: geometry.size.height * fraction)
            }
        }
    }

    private var thumbnailRail: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    if let cover = book.shell {
                        Button { closeBook() } label: {
                            DiaryPagePreview(page: cover, store: store).frame(width: 54, height: 76)
                                .padding(5).background(.background, in: RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(!opened ? Color.accentColor : .clear, lineWidth: 3))
                        }.buttonStyle(.plain).id(-1).accessibilityLabel("外壳")
                            .accessibilityAddTraits(!opened ? .isSelected : [])
                    }
                    ForEach(0..<spreadCount, id: \.self) { index in
                        Button { spread = index; openBook() } label: {
                            HStack(spacing: 2) {
                                thumbnail(index * 2 - 1)
                                thumbnail(index * 2)
                            }
                            .padding(5).background(.background, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(opened && spread == index ? Color.accentColor : .clear, lineWidth: 3))
                        }.buttonStyle(.plain).id(index)
                            .accessibilityLabel(spreadTitle(index))
                            .accessibilityAddTraits(opened && spread == index ? .isSelected : [])
                    }
                }.padding(12)
            }
            .frame(height: 110)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
            .padding(.horizontal, 16).padding(.bottom, 8)
            .onChange(of: spread) { _, _ in scrollToSelection(proxy) }
            .onChange(of: opened) { _, _ in scrollToSelection(proxy) }
        }
    }

    @ViewBuilder private func thumbnail(_ index: Int) -> some View {
        if index == -1 {
            DiaryBookLining().frame(width: 50, height: 76)
        } else if innerPages.indices.contains(index) {
            DiaryPagePreview(page: innerPages[index], store: store).frame(width: 50, height: 76)
        } else {
            Color(red: 0.96, green: 0.92, blue: 0.82).frame(width: 50, height: 76)
        }
    }
    private func spreadTitle(_ index: Int) -> String {
        if index == 0 { return "第 1 页" }
        let first = index * 2
        let last = min(first + 1, innerPages.count)
        return first == last ? "第 \(first) 页" : "第 \(first)–\(last) 页"
    }
    private func scrollToSelection(_ proxy: ScrollViewProxy) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
            proxy.scrollTo(opened ? spread : -1, anchor: .center)
        }
    }
    private func openBook() {
        guard spreadCount > 0, !turningCover else { return }
        setOpened(true)
    }
    private func closeBook() {
        guard !turningCover, book.shell != nil else { return }
        // 合书前回到内封皮，保证封面背面始终对应书本起始位置。
        spread = 0
        setOpened(false)
    }
    private func setOpened(_ value: Bool) {
        guard opened != value else { return }
        turningCover = !reduceMotion
        opened = value
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            turningCover = false
        }
    }
}

/// UIKit 中置书脊始终显示两个控制器，内封皮占首位，末尾缺页时补齐留白。
/// 原生 pageCurl 提供交互卷页、取消回弹和纸张背面，无需模拟整张跨页滑动。
private struct DiaryCurlBook: UIViewControllerRepresentable {
    let pages: [DiaryPageEntry]
    let store: DiaryDocumentStore
    @Binding var spread: Int
    let reduceMotion: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> UIPageViewController {
        let controller = UIPageViewController(
            transitionStyle: .pageCurl,
            navigationOrientation: .horizontal,
            options: [.spineLocation: UIPageViewController.SpineLocation.mid.rawValue]
        )
        controller.isDoubleSided = true
        controller.dataSource = context.coordinator
        controller.delegate = context.coordinator
        controller.view.backgroundColor = .clear
        // 单指用于卷页，双指捏合留给外层缩放手势。
        for case let pan as UIPanGestureRecognizer in controller.gestureRecognizers {
            pan.maximumNumberOfTouches = 1
        }
        context.coordinator.show(spread, in: controller, animated: false)
        return controller
    }
    func updateUIViewController(_ controller: UIPageViewController, context: Context) {
        context.coordinator.parent = self
        // 减少动态效果时关闭交互卷页，仍可通过按钮和缩略图无动画导航。
        controller.gestureRecognizers.forEach { $0.isEnabled = !reduceMotion }
        context.coordinator.show(spread, in: controller, animated: !reduceMotion)
    }

    @MainActor final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: DiaryCurlBook
        private var transitioning = false
        private var displayed = -1
        init(_ parent: DiaryCurlBook) { self.parent = parent }

        func page(_ index: Int) -> DiaryPaperController? {
            let paddedCount = ((parent.pages.count + 2) / 2) * 2
            guard (0..<paddedCount).contains(index) else { return nil }
            return DiaryPaperController(index: index, page: parent.pages.indices.contains(index - 1) ? parent.pages[index - 1] : nil, store: parent.store)
        }
        func show(_ target: Int, in controller: UIPageViewController, animated: Bool) {
            guard !transitioning, target != displayed,
                  let left = page(target * 2), let right = page(target * 2 + 1) else { return }
            let direction: UIPageViewController.NavigationDirection = target >= displayed ? .forward : .reverse
            transitioning = true
            controller.setViewControllers([left, right], direction: direction, animated: animated) { [weak self, weak controller] _ in
                guard let self, let controller else { return }
                self.displayed = target
                self.transitioning = false
                // 快速点击期间只保留最后目标，避免并发 setViewControllers 导致 UIKit 状态错乱。
                self.show(self.parent.spread, in: controller, animated: !self.parent.reduceMotion)
            }
        }
        func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
            guard let paper = viewController as? DiaryPaperController else { return nil }
            return page(paper.index - 1)
        }
        func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
            guard let paper = viewController as? DiaryPaperController else { return nil }
            return page(paper.index + 1)
        }
        func pageViewController(_ pageViewController: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) {
            transitioning = true
        }
        func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
            transitioning = false
            let requested = parent.spread
            let old = displayed
            if let first = pageViewController.viewControllers?.compactMap({ ($0 as? DiaryPaperController)?.index }).min() {
                displayed = first / 2
            }
            if requested != old {
                show(requested, in: pageViewController, animated: !parent.reduceMotion)
            } else {
                parent.spread = max(displayed, 0)
            }
        }
        func pageViewController(_ pageViewController: UIPageViewController, spineLocationFor orientation: UIInterfaceOrientation) -> UIPageViewController.SpineLocation {
            .mid
        }
    }
}

/// 每次只加载 UIKit 请求的相邻页；复用现有带版本号的预览缓存，不解码整本原图。
@MainActor private final class DiaryPaperController: UIHostingController<DiaryBookPaper> {
    let index: Int
    init(index: Int, page: DiaryPageEntry?, store: DiaryDocumentStore) {
        self.index = index
        super.init(rootView: DiaryBookPaper(page: page, store: store, left: index.isMultiple(of: 2), insideCover: index == 0))
        view.backgroundColor = .clear
        safeAreaRegions = []
    }
    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("不支持 Storyboard") }
}

private struct DiaryBookPaper: View {
    let page: DiaryPageEntry?
    let store: DiaryDocumentStore
    let left: Bool
    let insideCover: Bool
    var body: some View {
        ZStack {
            Color(red: 0.96, green: 0.92, blue: 0.82)
            if insideCover {
                DiaryBookLining()
                    .accessibilityLabel("内封皮")
            } else if let page {
                DiaryPagePreview(page: page, store: store, large: true, undecorated: true)
            } else {
                Text("留白页").font(.caption).foregroundStyle(.brown.opacity(0.5))
            }
            HStack(spacing: 0) {
                if left { Spacer(minLength: 0) }
                LinearGradient(colors: [.black.opacity(0.16), .clear], startPoint: left ? .trailing : .leading, endPoint: left ? .leading : .trailing)
                    .frame(width: 18)
                if !left { Spacer(minLength: 0) }
            }.allowsHitTesting(false)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
