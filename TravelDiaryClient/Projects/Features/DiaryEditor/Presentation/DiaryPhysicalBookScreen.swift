import SwiftUI
import UIKit
import PhotosUI

/// 阅读投影不修改目录：内封皮与第一页组成首跨页，之后按目录顺序连续配对。
struct DiaryPhysicalBookScreen: View {
    @State private var book: DiaryBook
    let store: DiaryDocumentStore
    private let onShowList: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isLandscape = false
    @State private var immersionDismissed = false
    @State private var showingPreviewExit = false
    private var isImmersive: Bool { isLandscape && !immersionDismissed }
    private var readerSpreadCount: Int { isImmersive ? contentSpreadCount : spreadCount }
    @State private var opened = false
    @State private var spread = 0
    @State private var turningCover = false
    @State private var editor: DiaryEditorSession?
    @State private var loadingEditor = false
    @State private var editingReaderPhotos = false
    @State private var errorMessage: String?
    @State private var pickingPhoto = false
    @State private var photo: PhotosPickerItem?
    @State private var choosingPreset = false
    @State private var showingExport = false
    private var innerPages: [DiaryPageEntry] { book.contentPages }
    private var contentSpreadCount: Int { (innerPages.count + 2) / 2 }
    // An odd number of pages needs one virtual blank spread; an even number already
    // has a padded blank leaf on its final spread. Neither case gets a spread after it.
    private var spreadCount: Int { contentSpreadCount + (innerPages.count.isMultiple(of: 2) ? 0 : 1) }
    private var paperRatio: CGFloat {
        let size = innerPages.first?.size ?? book.defaultPageSize
        return max(size.width, 1) / max(size.height, 1)
    }

    init(book: DiaryBook, store: DiaryDocumentStore, onShowList: (() -> Void)? = nil) {
        _book = State(initialValue: book)
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
            VStack(spacing: isImmersive ? 0 : 16) {
                bookViewport
                if !isImmersive {
                    HStack {
                        Button { if spread > 0 { spread -= 1 } else { closeBook() } } label: {
                            Image(systemName: "chevron.left")
                        }.disabled(!opened || (spread == 0 && book.shell == nil)).accessibilityLabel(spread == 0 ? "合上手帐" : "上一跨页")
                        Spacer()
                        Text(opened ? (spread >= contentSpreadCount ? "添加页面" : "\(spreadTitle(spread)) / \(innerPages.count)") : "外壳")
                            .font(.subheadline.monospacedDigit())
                        Spacer()
                        Button { if opened { spread += 1 } else { openBook() } } label: {
                            Image(systemName: "chevron.right")
                        }.disabled(spreadCount == 0 || (opened && spread >= spreadCount - 1))
                            .accessibilityLabel(opened ? "下一跨页" : "展开手帐")
                    }.padding(.horizontal, 28).disabled(turningCover)
                    HStack(spacing: 0) {
                        thumbnailRail
                        Menu { addActions } label: {
                            Image(systemName: "plus.circle.fill").font(.title2).padding(.trailing, 16)
                        }.accessibilityLabel("添加页面")
                    }.disabled(turningCover)
                }
            }
            .onGeometryChange(for: Bool.self) { geometry in
                // Include system insets so hiding the navigation bar cannot flip the classification.
                geometry.size.width + geometry.safeAreaInsets.leading + geometry.safeAreaInsets.trailing >
                    geometry.size.height + geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom
            } action: { landscape in
                isLandscape = landscape
                if !landscape { immersionDismissed = false }
            }
            .onChange(of: isImmersive) { _, immersive in
                showingPreviewExit = false
                if immersive {
                    spread = min(spread, max(contentSpreadCount - 1, 0))
                    openBook()
                }
            }
            .overlay(alignment: .topLeading) {
                if isImmersive && showingPreviewExit {
                    Button("退出预览", systemImage: "arrow.down.right.and.arrow.up.left") {
                        immersionDismissed = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.gray.opacity(0.8))
                    .padding(12)
                }
            }
            .task(id: showingPreviewExit) {
                guard showingPreviewExit else { return }
                do {
                    try await Task.sleep(for: .seconds(3))
                    showingPreviewExit = false
                } catch { }
            }
            .accessibilityAction(named: "退出沉浸预览") { immersionDismissed = true }
            .accessibilityAction(named: "下一跨页") {
                if opened && spread < readerSpreadCount - 1 { spread += 1 }
            }
            .accessibilityAction(named: "上一跨页") {
                if spread > 0 { spread -= 1 }
            }
            .toolbar(isImmersive ? .hidden : .visible, for: .navigationBar)
            .toolbar(isImmersive ? .hidden : .automatic, for: .tabBar)
            .statusBarHidden(isImmersive)
            .persistentSystemOverlays(isImmersive ? .hidden : .automatic)
            .disabled(loadingEditor || editingReaderPhotos)
            .overlay { if editingReaderPhotos { ProgressView("正在处理照片…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
            .overlay { if loadingEditor { ProgressView("正在打开页面…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
            .photosPicker(isPresented: $pickingPhoto, selection: $photo, matching: .images)
            .onChange(of: photo) { _, item in
                guard let item else { return }
                Task {
                    do {
                        guard let data = try await item.loadTransferable(type: Data.self) else { throw DiaryEditorError.invalidImage }
                        await createPage(data: data)
                    } catch { errorMessage = error.localizedDescription }
                    photo = nil
                }
            }
            .sheet(isPresented: $showingExport) { DiaryBookExportSheet(book: book, store: store) }
            .sheet(isPresented: $choosingPreset) {
                DiaryPresetPagePicker(ownerID: store.ownerID, targetBook: book) { updated in
                    book = updated
                    if let last = innerPages.last { reveal(last.id) }
                }
            }
            .fullScreenCover(item: $editor, onDismiss: {
                Task { await refreshAfterEditing() }
            }) { session in
                DiaryEditorScreen(session: session)
            }
            .alert("无法打开页面", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("确定") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
            .task { await refreshAfterEditing() }
            .task(id: "\(book.catalogRevision)-\(spread)-\(opened)") { await preloadNeighboringSpreads() }
            .background {
                (isImmersive ? Color.black : Color(uiColor: .systemGroupedBackground))
                    .ignoresSafeArea()
            }
            .navigationTitle(book.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingExport = true } label: { Image(systemName: "square.and.arrow.up") }
                        .accessibilityLabel("导出手帐").disabled(book.pages.isEmpty || turningCover)
                }
                if onShowList == nil {
                    ToolbarItem(placement: .topBarLeading) { Button("完成") { dismiss() } }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if let onShowList {
                        Button(action: onShowList) { Image(systemName: "list.bullet") }
                            .accessibilityLabel("页面列表")
                            .disabled(turningCover)
                    } else if book.shell != nil {
                        Button(opened ? "合上" : "展开") { if opened { closeBook() } else { openBook() } }
                            .disabled(spreadCount == 0 || turningCover)
                    }
                }
            }
    }

    private var bookViewport: some View {
        GeometryReader { geometry in
            if isImmersive {
                // Keep UIKit's interactive page curl directly under the finger.
                // Only the black side margins handle exit taps; no overlay covers the paper.
                bookStage(viewport: geometry.size)
                    .allowsHitTesting(!turningCover)
                    .overlay {
                        let size = DiaryBookStageLayout.openSize(viewport: geometry.size, paperRatio: paperRatio)
                        HStack(spacing: 0) {
                            previewExitMargin
                            Spacer(minLength: 0).frame(width: size.width).allowsHitTesting(false)
                            previewExitMargin
                        }
                    }
            } else {
                let stageViewport = CGSize(width: geometry.size.width, height: max(1, geometry.size.height - 80))
                DiaryBookZoomViewport(contentSize: stageViewport,
                                      resetToken: opened ? spread + 1 : 0) {
                    bookStage(viewport: stageViewport)
                        .simultaneousGesture(TapGesture().onEnded { if !opened { openBook() } })
                }
                .frame(width: stageViewport.width, height: stageViewport.height)
                .allowsHitTesting(!turningCover)
                .overlay(alignment: .top) {
                    if opened && !turningCover {
                        let size = DiaryBookStageLayout.openSize(viewport: stageViewport, paperRatio: paperRatio)
                        HStack(alignment: .top, spacing: 16) {
                            readerPhotos(at: spread * 2 - 1, title: "左页照片")
                            readerPhotos(at: spread * 2, title: "右页照片")
                        }
                        .padding(.horizontal, 12)
                        .frame(width: size.width)
                        .offset(y: (stageViewport.height + size.height) / 2 + 8)
                    }
                }
            }
        }.clipped()
    }

    @ViewBuilder private func readerPhotos(at index: Int, title: String) -> some View {
        if innerPages.indices.contains(index) {
            let page = innerPages[index]
            DiaryReaderPhotoStrip(page: page, store: store, title: title, readerBusy: $editingReaderPhotos,
                                  onSaved: { await refreshAfterEditing() })
                .id(page.id)
        } else {
            Color.clear.frame(maxWidth: .infinity).frame(height: 68).allowsHitTesting(false)
        }
    }

    private func bookStage(viewport: CGSize) -> some View {
        DiaryBookOpeningStage(progress: opened ? 1 : 0, viewport: viewport,
                              paperRatio: paperRatio, cover: book.shell,
                              firstPage: innerPages.first, store: store) {
            DiaryCurlBook(pages: innerPages, store: store, spreadCount: readerSpreadCount, spread: $spread,
                allowsEditing: !isImmersive, reduceMotion: reduceMotion, onSelectPage: openEditor, onAddPage: handleAdd)
                .id(book.catalogRevision)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.85), value: opened)
    }

    private var previewExitMargin: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture { showingPreviewExit.toggle() }
    }

    @ViewBuilder private var addActions: some View {
        Button("空白页", systemImage: "doc") { Task { await createPage(data: nil) } }
        Button("从照片新建", systemImage: "photo") { pickingPhoto = true }
        Button("从预设选择", systemImage: "books.vertical") { choosingPreset = true }
    }
    private func handleAdd(_ action: DiaryReaderAddAction) {
        switch action {
        case .blank: Task { await createPage(data: nil) }
        case .photo: pickingPhoto = true
        case .preset: choosingPreset = true
        }
    }
    private func reveal(_ id: UUID) {
        if let index = innerPages.firstIndex(where: { $0.id == id }) { spread = (index + 1) / 2 }
        opened = true
    }
    private func createPage(data: Data?) async {
        guard !loadingEditor else { return }
        loadingEditor = true
        defer { loadingEditor = false }
        do {
            var document = DiaryDocument()
            document.bookID = book.id
            document.objects[document.rootContentID]?.referenceSize = book.defaultPageSize
            var images: [UUID: UIImage] = [:]
            if let data {
                let (asset, image) = try await store.importImage(data, documentID: document.id)
                document.assets[asset.id] = asset; images[asset.id] = image
                document.objects[document.rootContentID]?.layers.insert(
                    DiaryLayer.photoBackground(asset: asset, pageSize: book.defaultPageSize), at: 0)
            }
            try await store.save(document)
            book = try await store.loadBook()
            reveal(document.id)
            editor = DiaryEditorSession(document: document, images: images, store: store)
        } catch { errorMessage = error.localizedDescription }
    }

    private func openEditor(_ page: DiaryPageEntry) {
        guard opened, !turningCover, !loadingEditor, editor == nil else { return }
        loadingEditor = true
        Task { @MainActor in
            defer { loadingEditor = false }
            do {
                let loaded = try await store.load(page.id)
                editor = DiaryEditorSession(document: loaded.document, images: loaded.images, store: store)
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func preloadNeighboringSpreads() async {
        guard opened else { return }
        // 当前跨页先完成，避免预取抢在可见页面之前排入素材读取队列。
        let pages = innerPages
        let current = [spread * 2 - 1, spread * 2]
        let neighbors = [spread * 2 + 1, spread * 2 + 2, spread * 2 - 3, spread * 2 - 2]
        do {
            for index in current where pages.indices.contains(index) {
                try Task.checkCancellation()
                _ = try? await DiaryPreviewService.image(page: pages[index], store: store, large: true)
            }
            // 快速连翻时不立即预取；已开始的共享请求仍可被后续页面复用。
            try await Task.sleep(for: .milliseconds(200))
            for index in neighbors where pages.indices.contains(index) {
                try Task.checkCancellation()
                _ = try? await DiaryPreviewService.image(page: pages[index], store: store, large: true)
            }
        } catch is CancellationError { }
        catch { /* 预取失败由实际打开页面时的重试入口处理。 */ }
    }

    private func refreshAfterEditing() async {
        do {
            book = try await store.loadBook()
            spread = min(spread, max(readerSpreadCount - 1, 0))
        } catch { errorMessage = error.localizedDescription }
    }

    private var thumbnailRail: some View {
        DiaryBookThumbnailRail(hasCover: book.shell != nil, spreadCount: spreadCount,
            spread: spread, opened: opened, title: spreadTitle,
            onClose: closeBook, onSelect: { spread = $0; openBook() }) {
                if let cover = book.shell { DiaryPagePreview(page: cover, store: store) }
            } leaf: { index in thumbnail(index) }
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
        if index >= contentSpreadCount { return "添加页面" }
        if index == 0 { return innerPages.isEmpty ? "添加页面" : "第 1 页" }
        let first = index * 2
        let last = min(first + 1, innerPages.count)
        return first == last ? "第 \(first) 页" : "第 \(first)–\(last) 页"
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

/// 静止时显示装订结构；卷页期间由 UIKit 协调淡出，避免覆盖在弯曲纸面上。
struct DiaryBindingRings: View {
    var body: some View {
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

}

/// UIKit 中置书脊始终显示两个控制器，内封皮占首位，末尾缺页时补齐留白。
/// 原生 pageCurl 提供交互卷页、取消回弹和纸张背面，无需模拟整张跨页滑动。
private enum DiaryReaderAddAction { case blank, photo, preset }

private struct DiaryCurlBook: View {
    let pages: [DiaryPageEntry]
    let store: DiaryDocumentStore
    let spreadCount: Int
    @Binding var spread: Int
    let allowsEditing: Bool
    let reduceMotion: Bool
    let onSelectPage: (DiaryPageEntry) -> Void
    let onAddPage: (DiaryReaderAddAction) -> Void

    var body: some View {
        DiaryPageCurlReader(spreadCount: spreadCount, spread: $spread, reduceMotion: reduceMotion, allowsPageActions: allowsEditing) { index, canSelect in
            DiaryPaperController(index: index, page: pages.indices.contains(index - 1) ? pages[index - 1] : nil,
                store: store, showsAddPlaceholder: allowsEditing, canSelect: canSelect, onAdd: { if canSelect() { onAddPage($0) } },
                onSelect: { if canSelect() { onSelectPage($0) } })
        }
    }
}

protocol DiaryIndexedPaper: AnyObject {
    var index: Int { get }
}

/// Lets the zoom viewport suspend navigation without changing UIKit gesture state.
final class DiaryCurlPageViewController: UIPageViewController {
    var onZoomSuspensionChange: ((Bool) -> Void)?

    func setZoomSuspended(_ suspended: Bool) {
        onZoomSuspensionChange?(suspended)
    }
}

/// Shared native curl engine for saved diaries and read-only preset previews.
struct DiaryPageCurlReader: UIViewControllerRepresentable {
    let spreadCount: Int
    @Binding var spread: Int
    let reduceMotion: Bool
    var allowsPageActions = true
    let makePaper: (Int, @escaping () -> Bool) -> UIViewController

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> UIPageViewController {
        let controller = DiaryCurlPageViewController(
            transitionStyle: .pageCurl,
            navigationOrientation: .horizontal,
            options: [.spineLocation: UIPageViewController.SpineLocation.mid.rawValue]
        )
        controller.isDoubleSided = true
        controller.delegate = context.coordinator
        controller.onZoomSuspensionChange = { [weak coordinator = context.coordinator, weak controller] suspended in
            guard let coordinator, let controller else { return }
            coordinator.setZoomSuspended(suspended, in: controller)
        }
        controller.view.backgroundColor = .clear
        context.coordinator.installReducedMotionSwipes(in: controller)
        context.coordinator.installRings(in: controller)
        context.coordinator.show(spread, in: controller, animated: false)
        return controller
    }
    func updateUIViewController(_ controller: UIPageViewController, context: Context) {
        context.coordinator.parent = self
        context.coordinator.updateMotionPolicy(in: controller)
        context.coordinator.show(spread, in: controller, animated: !reduceMotion)
    }

    @MainActor final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: DiaryPageCurlReader
        private var transitioning = false
        private var displayed = -1
        private var zoomSuspended = false
        private var pageSource: DiaryPageCurlReader
        private var papers: [Int: UIViewController] = [:]
        private var reducedMotionSwipes: [UISwipeGestureRecognizer] = []

        func installReducedMotionSwipes(in controller: UIPageViewController) {
            for direction in [UISwipeGestureRecognizer.Direction.left, .right] {
                let swipe = UISwipeGestureRecognizer(target: self, action: #selector(turnWithoutAnimation(_:)))
                swipe.direction = direction
                swipe.isEnabled = false
                controller.view.addGestureRecognizer(swipe)
                reducedMotionSwipes.append(swipe)
            }
        }

        @objc private func turnWithoutAnimation(_ gesture: UISwipeGestureRecognizer) {
            guard parent.reduceMotion, !transitioning, !zoomSuspended else { return }
            let next = parent.spread + (gesture.direction == .left ? 1 : -1)
            guard (0..<parent.spreadCount).contains(next) else { return }
            parent.spread = next
        }

        func updateMotionPolicy(in controller: UIPageViewController) {
            // UIKit owns curl gesture state, including disabled boundary recognizers.
            // A nil data source disables native navigation without disabling page taps.
            // Never change the data source during an interactive transition.
            guard !transitioning else { return }
            reducedMotionSwipes.forEach { $0.isEnabled = parent.reduceMotion && !zoomSuspended }
            if parent.reduceMotion || zoomSuspended {
                if controller.dataSource != nil { controller.dataSource = nil }
            } else if controller.dataSource !== self {
                controller.dataSource = self
                // 单指卷页，双指捏合留给外层缩放手势。
                for case let pan as UIPanGestureRecognizer in controller.gestureRecognizers {
                    pan.maximumNumberOfTouches = 1
                }
                controller.gestureRecognizers.compactMap { $0 as? UITapGestureRecognizer }.forEach { $0.isEnabled = false }
            }
        }

        func setZoomSuspended(_ suspended: Bool, in controller: UIPageViewController) {
            zoomSuspended = suspended
            updateMotionPolicy(in: controller)
        }
        private let rings = UIHostingController(rootView: DiaryBindingRings())

        func installRings(in controller: UIPageViewController) {
            controller.addChild(rings)
            rings.safeAreaRegions = []
            rings.view.backgroundColor = .clear
            rings.view.isUserInteractionEnabled = false
            rings.view.accessibilityElementsHidden = true
            rings.view.frame = controller.view.bounds
            rings.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            controller.view.addSubview(rings.view)
            rings.didMove(toParent: controller)
        }

        private func setRingsVisible(_ visible: Bool, animated: Bool) {
            // 直接修改独立装订层，不触发 SwiftUI 更新或重建卷页控制器。
            UIView.animate(withDuration: animated ? (visible ? 0.18 : 0.08) : 0,
                           delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                self.rings.view.alpha = visible ? 1 : 0
            }
        }
        init(_ parent: DiaryPageCurlReader) {
            self.parent = parent
            self.pageSource = parent
        }

        func page(_ index: Int) -> UIViewController? {
            // A mid-spine controller must always start with two leaves, even for an empty book.
            guard (0..<(max(1, pageSource.spreadCount) * 2)).contains(index) else { return nil }
            if let paper = papers[index] { return paper }
            let paper = pageSource.makePaper(index) { [weak self] in self?.transitioning == false && self?.parent.allowsPageActions == true }
            papers[index] = paper
            return paper
        }
        func show(_ requested: Int, in controller: UIPageViewController, animated: Bool) {
            guard !transitioning else { return }
            let countChanged = pageSource.spreadCount != parent.spreadCount || pageSource.allowsPageActions != parent.allowsPageActions
            pageSource = parent
            if countChanged { papers.removeAll() }
            let target = min(max(requested, 0), max(1, pageSource.spreadCount) - 1)
            guard target != displayed || countChanged else {
                updateMotionPolicy(in: controller)
                return
            }
            guard let left = page(target * 2), let right = page(target * 2 + 1) else { return }
            let direction: UIPageViewController.NavigationDirection = target >= displayed ? .forward : .reverse
            transitioning = true
            // Prevent a pan from starting while a button-driven curl is running.
            controller.dataSource = nil
            // Refreshing read-only paper views during rotation is not a page turn.
            let animateTurn = animated && target != displayed
            if animateTurn { setRingsVisible(false, animated: false) }
            controller.setViewControllers([left, right], direction: direction, animated: animateTurn) { [weak self, weak controller] finished in
                // UIKit is still unwinding its transition inside this callback.
                // Keep the lock until the next main-queue turn before starting another curl.
                DispatchQueue.main.async {
                    guard let self, let controller else { return }
                    if finished { self.displayed = target }
                    self.transitioning = false
                    self.show(self.parent.spread, in: controller, animated: !self.parent.reduceMotion)
                    self.restoreAfterTransition(in: controller)
                }
            }
        }

        private func restoreAfterTransition(in controller: UIPageViewController) {
            guard !transitioning else { return }
            if let indices = controller.viewControllers?.compactMap({ ($0 as? any DiaryIndexedPaper)?.index }),
               let first = indices.min(), let last = indices.max() {
                papers = papers.filter { (first - 2...last + 2).contains($0.key) }
            }
            updateMotionPolicy(in: controller)
            controller.view.bringSubviewToFront(rings.view)
            setRingsVisible(true, animated: !parent.reduceMotion)
        }
        func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
            guard let paper = viewController as? any DiaryIndexedPaper else { return nil }
            return page(paper.index - 1)
        }
        func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
            guard let paper = viewController as? any DiaryIndexedPaper else { return nil }
            return page(paper.index + 1)
        }
        func pageViewController(_ pageViewController: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) {
            transitioning = true
            setRingsVisible(false, animated: !parent.reduceMotion)
        }
        func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
            DispatchQueue.main.async { [weak self, weak pageViewController] in
                guard let self, let pageViewController else { return }
                let requested = self.parent.spread
                let old = self.displayed
                if let first = pageViewController.viewControllers?.compactMap({ ($0 as? any DiaryIndexedPaper)?.index }).min() {
                    self.displayed = first / 2
                }
                self.transitioning = false
                if requested != old {
                    self.show(requested, in: pageViewController, animated: !self.parent.reduceMotion)
                } else {
                    // Rotation may remove the add spread while a native curl is finishing.
                    self.parent.spread = min(max(self.displayed, 0), max(self.parent.spreadCount - 1, 0))
                    self.show(self.parent.spread, in: pageViewController, animated: false)
                }
                self.restoreAfterTransition(in: pageViewController)
            }
        }
        func pageViewController(_ pageViewController: UIPageViewController, spineLocationFor orientation: UIInterfaceOrientation) -> UIPageViewController.SpineLocation {
            .mid
        }
    }
}

/// 每次只加载 UIKit 请求的相邻页；复用现有带版本号的预览缓存，不解码整本原图。
@MainActor private final class DiaryPaperController: UIHostingController<DiaryBookPaper>, UIPopoverPresentationControllerDelegate, DiaryIndexedPaper {
    let index: Int
    private let canSelect: () -> Bool
    private let selectedPage: DiaryPageEntry?
    private let onSelect: (DiaryPageEntry) -> Void
    private let onAdd: (DiaryReaderAddAction) -> Void
    init(index: Int, page: DiaryPageEntry?, store: DiaryDocumentStore, showsAddPlaceholder: Bool, canSelect: @escaping () -> Bool, onAdd: @escaping (DiaryReaderAddAction) -> Void, onSelect: @escaping (DiaryPageEntry) -> Void) {
        self.index = index
        self.canSelect = canSelect
        self.selectedPage = page
        self.onSelect = onSelect
        self.onAdd = onAdd
        super.init(rootView: DiaryBookPaper(page: page, store: store, left: index.isMultiple(of: 2), insideCover: index == 0, showsAddPlaceholder: showsAddPlaceholder))
        view.backgroundColor = .clear
        safeAreaRegions = []
        if showsAddPlaceholder && (page != nil || index > 0) {
            let tap = UITapGestureRecognizer(target: self, action: #selector(selectPage(_:)))
            view.addGestureRecognizer(tap)
            view.accessibilityHint = page == nil ? "轻点添加页面" : "轻点编辑这一页"
        }
    }
    @objc private func selectPage(_ gesture: UITapGestureRecognizer) {
        guard canSelect() else { return }
        if let selectedPage { onSelect(selectedPage) }
        else if index > 0 { showAddMenu(at: gesture.location(in: view)) }
    }
    private func showAddMenu(at point: CGPoint) {
        guard presentedViewController == nil, view.window != nil else { return }
        let menu = UIAlertController(title: "添加页面", message: nil, preferredStyle: .actionSheet)
        for (title, action) in [("空白页", DiaryReaderAddAction.blank), ("从照片新建", .photo), ("从预设选择", .preset)] {
            menu.addAction(UIAlertAction(title: title, style: .default) { [weak self, weak menu] _ in
                // Finish dismissing the native menu before presenting a photo picker or sheet.
                guard let self else { return }
                if let menu, menu.presentingViewController != nil {
                    menu.dismiss(animated: true) { self.onAdd(action) }
                } else { self.onAdd(action) }
            })
        }
        menu.addAction(UIAlertAction(title: "取消", style: .cancel))
        menu.modalPresentationStyle = .popover
        if let popover = menu.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: point.x, y: point.y, width: 1, height: 1)
            popover.permittedArrowDirections = .any
            popover.delegate = self
        }
        present(menu, animated: true)
    }
    func adaptivePresentationStyle(for controller: UIPresentationController, traitCollection: UITraitCollection) -> UIModalPresentationStyle {
        .none
    }
    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("不支持 Storyboard") }
}

private struct DiaryBookPaper: View {
    let page: DiaryPageEntry?
    let store: DiaryDocumentStore
    let left: Bool
    let insideCover: Bool
    let showsAddPlaceholder: Bool
    var body: some View {
        GeometryReader { geometry in
        ZStack {
            Color(red: 0.96, green: 0.92, blue: 0.82)
            if insideCover {
                DiaryBookLining()
                    .accessibilityLabel("内封皮")
            } else if let page {
                DiaryPagePreview(page: page, store: store, large: true, undecorated: true)
            } else if showsAddPlaceholder {
                Label("添加页面", systemImage: "plus.circle").font(.caption).foregroundStyle(.brown.opacity(0.5))
            }
            HStack(spacing: 0) {
                if left { Spacer(minLength: 0) }
                LinearGradient(colors: [.black.opacity(0.16), .clear], startPoint: left ? .trailing : .leading, endPoint: left ? .leading : .trailing)
                    .frame(width: 18)
                if !left { Spacer(minLength: 0) }
            }.allowsHitTesting(false)
        }
        .frame(width: geometry.size.width * (1 - DiaryBookSpine.halfGapFraction), height: geometry.size.height)
        .clipped()
        .shadow(color: .black.opacity(0.35), radius: 1.5, x: left ? 1.5 : -1.5)
        .frame(width: geometry.size.width, height: geometry.size.height, alignment: left ? .leading : .trailing)
        }
    }
}
