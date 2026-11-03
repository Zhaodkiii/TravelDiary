import SwiftUI
import PhotosUI
import UIKit

/// 随记只负责采集与交接，编辑始终使用已有的 DiaryEditorScreen。
struct TravelCaptureHomeView: View {
    let ownerID: String
    @State private var books: [DiaryBook] = []
    @State private var book: DiaryBook?
    @State private var pageID: UUID?
    @State private var pendingEditor: DiaryEditorSession?
    @State private var editor: DiaryEditorSession?
    @State private var camera = false
    private struct ReviewPhoto: Identifiable { let id = UUID(); let image: UIImage }
    @State private var reviewPhoto: ReviewPhoto?
    @State private var loadingPhoto = false
    @State private var image: UIImage?
    @State private var photo: PhotosPickerItem?
    @State private var busy = false
    @State private var error: String?
    @State private var creationDrafts: [CreationDraft] = []
    private struct CreationRoute: Identifiable {
        let id = UUID()
        var draft: CreationDraft?
        var source: String?
    }
    @State private var creationRoute: CreationRoute?
    @State private var showDrafts = false
    @State private var selectedStyle: DiaryAIPageStyle = .scenic
    @State private var styleEditor: DiaryEditorSession?
    @State private var styleCoordinator: CreationCoordinator?
    @State private var styleRequest: DiaryAIRequest?
    @State private var preview: UIImage?
    @State private var subjects: [StickerSubject] = []
    private let size = CGSize(width: 4370, height: 3130)
    private var store: DiaryDocumentStore { DiaryDocumentStore(ownerID: ownerID, bookID: book?.id) }

    private var pendingURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("TravelCapture-" + Data(ownerID.utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_") + ".png")
    }
    private var captureKey: String { "TravelCaptureTarget." + ownerID }
    private func retainCapture(_ value: UIImage) {
        do {
            try FileManager.default.createDirectory(at: pendingURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard let data = value.pngData() else { throw DiaryEditorError.invalidImage }
            try data.write(to: pendingURL, options: .atomic)
            UserDefaults.standard.set([book?.id.uuidString ?? "", pageID?.uuidString ?? ""], forKey: captureKey)
            image = value; error = nil; reviewPhoto = ReviewPhoto(image: value)
        } catch { self.error = error.localizedDescription }
    }

    var body: some View {
        homeContent
        .toolbar(.hidden, for: .navigationBar)
        .background {
            Color(uiColor: .systemGroupedBackground)
            Canvas { context, size in
                for x in stride(from: 8.0, to: size.width, by: 22) {
                    for y in stride(from: 8.0, to: size.height, by: 22) {
                        context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.5, height: 1.5)), with: .color(.secondary.opacity(0.12)))
                    }
                }
            }.allowsHitTesting(false)
        }
        .disabled(busy)
        .overlay { if busy { ProgressView("正在准备…").padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) } }
        .task { await reload(); if let data = try? Data(contentsOf: pendingURL), let value = UIImage(data: data) {
            if let target = UserDefaults.standard.stringArray(forKey: captureKey), target.count == 2, let restored = books.first(where: { $0.id.uuidString == target[0] }) { book = restored; pageID = restored.contentPages.first(where: { $0.id.uuidString == target[1] })?.id }
            image = value; error = nil; reviewPhoto = ReviewPhoto(image: value)
        } }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task {
                loadingPhoto = true
                defer { loadingPhoto = false; photo = nil }
                do {
                    guard let data = try await item.loadTransferable(type: Data.self),
                          let value = UIImage(data: data) else { throw DiaryEditorError.invalidImage }
                    retainCapture(value)
                } catch { self.error = "照片读取失败，请重新选择。\n" + error.localizedDescription }
            }
        }
        .sheet(isPresented: $camera, onDismiss: {
            if let image { retainCapture(image) }
        }) { TravelCaptureCamera { image = $0; camera = false } }
        .sheet(item: $reviewPhoto, onDismiss: {
            if let pendingEditor { editor = pendingEditor; self.pendingEditor = nil }
        }) { capture in
            TravelCaptureReview(original: capture.image, submitting: busy, submissionError: error,
                onNext: { material, kind, frame in Task { await submit(kind, material: material, frame: frame) } },
                onClose: { reviewPhoto = nil })
        }
        .overlay {
            if loadingPhoto { ProgressView("正在读取照片…").padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) }
        }

        .fullScreenCover(item: $creationRoute, onDismiss: { Task { await reload(); await loadCreationDrafts() } }) { route in
            CreationFlowView(owner: ownerID, draft: route.draft, bookID: book?.id, initialSource: route.source)
        }
        .sheet(isPresented: $showDrafts, onDismiss: { Task { await loadCreationDrafts() } }) {
            NavigationStack { CreationDraftListView(owner: ownerID).toolbar { Button("完成") { showDrafts = false } } }
        }
        .task { await loadCreationDrafts() }
        .fullScreenCover(item: $styleEditor, onDismiss: { Task { await reload() } }) { value in
            DiaryEditorScreen(session: value, creationRequest: styleRequest)
        }
        .fullScreenCover(item: $editor, onDismiss: { Task { await reload(); await refreshPreview() } }) { DiaryEditorScreen(session: $0) }
        .alert("旅行随记", isPresented: Binding(get: { error != nil && reviewPhoto == nil }, set: { if !$0 { error = nil } })) { Button("好") { error = nil } } message: { Text(error ?? "") }
    }

    private var homeContent: some View {
        VStack {
            Spacer(minLength: 0)
            TravelStyleDeck(selection: $selectedStyle) { Task { await openStyleCanvas() } }
            Spacer(minLength: 0)
        }.padding(.horizontal, 20).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func openStyleCanvas() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let drafts = try await CreationDraftStore(owner: ownerID).list()
            let existing = drafts.first { $0.styleEntry == true && !$0.published && $0.targetBookID == book?.id }
            var draft = existing ?? CreationDraft(owner: ownerID, targetBookID: book?.id)
            draft.styleEntry = true
            draft.design.style = selectedStyle
            let coordinator = CreationCoordinator(owner: ownerID, draft: draft, bookID: book?.id)
            guard let session = await coordinator.prepare(allowEmpty: true) else {
                throw DiaryAIError.invalid(coordinator.error ?? "无法打开制作草稿")
            }
            styleCoordinator = coordinator
            styleRequest = coordinator.draft.request()
            styleEditor = session
        } catch { self.error = error.localizedDescription }
    }

    private func loadCreationDrafts() async {
        creationDrafts = ((try? await CreationDraftStore(owner: ownerID).list()) ?? []).filter { !$0.published }
    }
    private func reload() async {
        do {
            books = try await DiaryDocumentStore(ownerID: ownerID).listBooks().filter { $0.defaultPageSize == size }
            book = books.first { $0.id == book?.id } ?? books.first
            if !(book?.contentPages.contains { $0.id == pageID } ?? false) { pageID = book?.contentPages.last?.id }
            await refreshPreview()
        } catch { self.error = error.localizedDescription }
    }
    private func createBook() async {
        do { book = try await DiaryDocumentStore(ownerID: ownerID).createBook(title: "旅行随记", preset: .spread); pageID = nil; await newPage(); await reload() }
        catch { self.error = error.localizedDescription }
    }
    private func newPage() async {
        if book == nil { await createBook(); return }
        busy = true; defer { busy = false }
        do {
            var document = DiaryDocument(); document.bookID = book?.id
            document.objects[document.rootContentID]?.referenceSize = size
            try await store.save(document); pageID = document.id
            await reload()
        } catch { self.error = error.localizedDescription }
    }
    private func session() async throws -> DiaryEditorSession {
        guard let pageID else { throw DiaryEditorError.invalidDocument }
        return try await TravelCaptureSessionLoader.open(pageID: pageID, store: store)
    }
    private func open() async {
        if book == nil { await createBook() }
        busy = true; defer { busy = false }
        do { editor = try await session() } catch { self.error = error.localizedDescription }
    }
    private func submit(_ kind: String, material: UIImage, frame: DiaryPhotoFrameCatalog.Item?) async {
        guard !busy else { return }
        if book == nil { await createBook() }
        busy = true; error = nil; defer { busy = false }
        do {
            let session = try await session()
            guard let data = material.pngData() else { throw DiaryEditorError.invalidDocument }
            let success: Bool
            if kind == "背景" { success = await session.importMaterialBackground(data) }
            else if kind == "照片" { success = await session.importPhotos([data], frames: [frame]) }
            else { success = await session.importPhoto(data, asSticker: true) }
            guard success else { throw DiaryEditorError.invalidDocument }
            try await session.save()
            pendingEditor = session
            reviewPhoto = nil
            self.image = nil
            try? FileManager.default.removeItem(at: pendingURL)
            UserDefaults.standard.removeObject(forKey: captureKey)
            // 等预览关闭后再呈现已有编辑页，避免两层模态同时争用。

        } catch { self.error = kind == "贴纸" ? "暂时没能分离主体，请重试或作为照片加入。" : error.localizedDescription }
    }
    private func refreshPreview() async {
        preview = nil
        guard let page = book?.contentPages.first(where: { $0.id == pageID }) else { return }
        preview = try? await DiaryPreviewService.image(page: page, store: store, large: true)
    }
}

private struct TravelCaptureCamera: UIViewControllerRepresentable {
    var complete: (UIImage?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(complete: complete) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController(); picker.sourceType = .camera; picker.delegate = context.coordinator; return picker
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let complete: (UIImage?) -> Void
        init(complete: @escaping (UIImage?) -> Void) { self.complete = complete }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { complete(nil) }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) { complete(info[.originalImage] as? UIImage) }
    }
}

/// 加载和保存必须共享同一实例，保留 load 记录的乐观并发版本基线。
@MainActor
enum TravelCaptureSessionLoader {
    static func open(pageID: UUID, store: DiaryDocumentStore) async throws -> DiaryEditorSession {
        let loaded = try await store.load(pageID)
        return DiaryEditorSession(document: loaded.document, images: loaded.images, store: store)
    }
}

/// Three-card deck. Selection is local; only the center action opens a new canvas.
struct TravelStyleDeck: View {
    @Binding var selection: DiaryAIPageStyle
    var open: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TravelStylePager(selection: $selection, reduceMotion: reduceMotion, open: open)
            .frame(height: 330)
    }
}

/// Native paging owns velocity, cancellation and horizontal/vertical arbitration.
private struct TravelStylePager: UIViewRepresentable {
    @Binding var selection: DiaryAIPageStyle
    var reduceMotion: Bool
    var open: () -> Void
    func makeUIView(context: Context) -> TravelStylePagerView { TravelStylePagerView() }
    func updateUIView(_ view: TravelStylePagerView, context: Context) {
        view.onSelect = { selection = $0 }
        view.onOpen = open
        view.reducedMotion = reduceMotion
        view.select(selection)
    }
}

private final class TravelStylePagerView: UIScrollView, UIScrollViewDelegate {
    private let styles = DiaryAIPageStyle.allCases
    private var cards: [UIImageView] = []
    private var titles: [UILabel] = []
    private var settled = 0
    private var previousWidth: CGFloat = 0
    var onSelect: ((DiaryAIPageStyle) -> Void)?
    var onOpen: (() -> Void)?
    var reducedMotion = false
    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self; isPagingEnabled = true; showsHorizontalScrollIndicator = false
        alwaysBounceVertical = false; alwaysBounceHorizontal = true; isDirectionalLockEnabled = true
        clipsToBounds = false; decelerationRate = .fast
        for style in styles {
            let image = UIImageView(image: UIImage(named: "TravelStyle-" + style.rawValue))
            image.contentMode = .scaleAspectFill; image.clipsToBounds = true
            image.layer.cornerRadius = 22; image.layer.borderColor = UIColor.white.cgColor; image.layer.borderWidth = 2
            image.isUserInteractionEnabled = true
            image.tag = cards.count
            image.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
            image.isAccessibilityElement = true; image.accessibilityTraits = .button
            let title = UILabel()
            title.text = style.name + "  ›"
            title.font = .preferredFont(forTextStyle: .headline)
            title.textColor = .white; title.backgroundColor = UIColor.black.withAlphaComponent(0.45)
            title.textAlignment = .center; title.layer.cornerRadius = 12; title.clipsToBounds = true
            image.addSubview(title); titles.append(title)
            addSubview(image); cards.append(image)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func select(_ style: DiaryAIPageStyle) {
        guard !isDragging, !isDecelerating, let index = styles.firstIndex(of: style), index != settled else { return }
        settled = index
        setContentOffset(CGPoint(x: CGFloat(index) * bounds.width, y: 0), animated: !reducedMotion && window != nil)
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0 else { return }
        contentSize = CGSize(width: bounds.width * CGFloat(styles.count), height: bounds.height)
        if previousWidth != bounds.width {
            previousWidth = bounds.width
            contentOffset = CGPoint(x: CGFloat(settled) * bounds.width, y: 0)
        }
        arrange()
    }
    private func arrange() {
        guard bounds.width > 0 else { return }
        let progress = contentOffset.x / bounds.width
        let width = min(bounds.width * 0.67, 280)
        for (index, card) in cards.enumerated() {
            let distance = CGFloat(index) - progress
            let amount = min(abs(distance), 1)
            card.bounds = CGRect(x: 0, y: 0, width: width, height: 300)
            card.center = CGPoint(x: contentOffset.x + bounds.width / 2 + distance * width * 0.44, y: bounds.height / 2 + amount * 8)
            card.transform = CGAffineTransform(rotationAngle: reducedMotion ? 0 : max(-1, min(1, distance)) * 0.06).scaledBy(x: 1 - amount * 0.1, y: 1 - amount * 0.1)
            card.layer.zPosition = 10 - abs(distance)
            card.isHidden = abs(distance) > 1.7
            titles[index].frame = CGRect(x: 12, y: 246, width: width - 24, height: 42)
            titles[index].alpha = max(0, 1 - abs(distance) * 2)
            card.accessibilityLabel = styles[index].name + (index == settled ? "，使用此风格" : "，选择风格")
        }
    }
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard bounds.contains(point) else { return nil }
        for card in cards.sorted(by: { $0.layer.zPosition > $1.layer.zPosition }) where !card.isHidden {
            if let hit = card.hitTest(card.convert(point, from: self), with: event) { return hit }
        }
        return super.hitTest(point, with: event)
    }
    func scrollViewDidScroll(_ scrollView: UIScrollView) { arrange() }
    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        guard bounds.width > 0 else { return }
        let proposed = Int((targetContentOffset.pointee.x / bounds.width).rounded())
        let next = max(0, min(styles.count - 1, max(settled - 1, min(settled + 1, proposed))))
        targetContentOffset.pointee.x = CGFloat(next) * bounds.width
    }
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { finish() }
    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) { finish() }
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) { if !decelerate { finish() } }
    private func finish() {
        guard bounds.width > 0 else { return }
        let next = max(0, min(styles.count - 1, Int((contentOffset.x / bounds.width).rounded())))
        if next != settled { UISelectionFeedbackGenerator().selectionChanged() }
        settled = next; onSelect?(styles[next]); arrange()
    }
    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        guard !isDragging, !isDecelerating, let index = gesture.view?.tag else { return }
        if index == settled { onOpen?() }
        else { setContentOffset(CGPoint(x: CGFloat(index) * bounds.width, y: 0), animated: !reducedMotion); if reducedMotion { finish() } }
    }
}

struct TravelStyleArtwork: View {
    let style: DiaryAIPageStyle
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            GeometryReader { geo in
                if let image = UIImage(named: "TravelStyle-" + style.rawValue) {
                    Image(uiImage: image).resizable().scaledToFill().frame(width: geo.size.width, height: geo.size.height).clipped()
                } else { DiaryAIDesignPreview(design: .init(style: style)) }
            }
            LinearGradient(colors: [.clear, .black.opacity(0.68)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 6) {
                Text(style.name).font(.title3.bold())
                Text("风格示例 · 点击制作").font(.caption)
            }.foregroundStyle(.white).padding(18)
        }
    }
}
