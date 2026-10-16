import SwiftUI
import PhotosUI

/// 本内总览只持有目录；点击一页才解码该页资源并建立现有通用编辑会话。
struct DiaryBookScreen: View {
    let ownerID: String
    @State private var book: DiaryBook
    @State private var store: DiaryDocumentStore
    @State private var editor: DiaryEditorSession?
    @State private var photo: PhotosPickerItem?
    @State private var pickingPhoto = false
    @State private var reading = false
    @State private var bookReading = false
    @State private var readingID: UUID?
    @State private var busy = false
    @State private var message: String?
    @State private var deleting: DiaryPageEntry?
    @State private var showingTrash = false
    @State private var renaming = false
    @State private var name = ""
    @State private var replacingPhotos = false
    @State private var showingPresetPicker = false
    @State private var presetAfterPageID: UUID?
    @State private var draggingPage: DiaryPageEntry?
    @State private var dragOrigin = CGRect.zero
    @State private var dragTranslation = CGSize.zero
    @State private var pageFrames: [UUID: CGRect] = [:]
    @State private var orderBeforeDrag: DiaryBook?
    @State private var dragStartPoint = CGPoint.zero
    @State private var showingExport = false

    init(ownerID: String, book: DiaryBook) {
        self.ownerID = ownerID
        _book = State(initialValue: book)
        _store = State(initialValue: DiaryDocumentStore(ownerID: ownerID, bookID: book.id))
    }
    var body: some View {
        ScrollViewReader { scrollProxy in
        GeometryReader { viewport in
        ScrollView {
            if book.pages.isEmpty {
                ContentUnavailableView("新建第一页", systemImage: "doc.badge.plus", description: Text("从空白画布或一张照片开始。"))
                    .padding(.top, 50)
            }
            DiaryPageListGrid(pages: book.pages, shellID: book.shellPageID,
                              coverID: book.effectiveCover?.id) { page in
                pageCard(page)
            }.padding()
            Menu {
                Button("空白页", systemImage: "doc") { Task { await createPage(data: nil) } }
                Button("从照片新建", systemImage: "photo") { pickingPhoto = true }
                Button("从预设选择") { presetAfterPageID = nil; showingPresetPicker = true }
            } label: { Label("新建一页", systemImage: "plus") }
                .buttonStyle(.borderedProminent).padding(.bottom)
        }
        .scrollDisabled(draggingPage != nil)
        .onPreferenceChange(DiaryPageSortFrames.self) { pageFrames = $0 }
        .overlay(alignment: .topLeading) {
            if let page = draggingPage {
                VStack(alignment: .leading, spacing: 8) {
                    DiaryPagePreview(page: page, store: store)
                    Text(page.title).font(.subheadline).lineLimit(2)
                }
                .frame(width: dragOrigin.width, height: dragOrigin.height, alignment: .top)
                .scaleEffect(1.04)
                .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
                .position(x: dragOrigin.midX + dragTranslation.width,
                          y: dragOrigin.midY + dragTranslation.height)
                .allowsHitTesting(false)
            }
        }
        .coordinateSpace(name: "diary-page-sort")
        .task(id: draggingPage?.id) {
            // 手指靠近上下边缘时继续滚动，可跨越当前可见页排序。
            while draggingPage != nil && !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(180))
                guard !Task.isCancelled, let dragged = draggingPage else { break }
                let y = dragOrigin.midY + dragTranslation.height
                let direction = y < 80 ? -1 : (y > viewport.size.height - 80 ? 1 : 0)
                guard direction != 0 else { continue }
                let visible = book.pages.indices.filter {
                    guard let frame = pageFrames[book.pages[$0].id] else { return false }
                    return frame.maxY > 0 && frame.minY < viewport.size.height
                }
                guard let edge = direction < 0 ? visible.min() : visible.max() else { continue }
                let next = min(max(edge + direction, 0), book.pages.count - 1)
                guard book.pages[next].id != dragged.id else { continue }
                withAnimation(.easeInOut(duration: 0.16)) {
                    scrollProxy.scrollTo(book.pages[next].id, anchor: direction < 0 ? .top : .bottom)
                }
            }
        }
        }
        }
        .navigationTitle(book.title)
        .toolbar {
            Menu {
                Button("书本翻页预览", systemImage: "book.pages") { bookReading = true }
                Button("原有单页预览", systemImage: "rectangle.portrait") {
                    readingID = book.contentPages.first?.id; reading = true
                }.disabled(book.contentPages.isEmpty)
            } label: { Image(systemName: "book") }
                .disabled(book.pages.isEmpty).accessibilityLabel("阅读整本")
            Menu {
                Button("导出手帐", systemImage: "square.and.arrow.up") { showingExport = true }
                    .disabled(book.pages.isEmpty || draggingPage != nil)
                Button("一键替换照片", systemImage: "photo.on.rectangle.angled") { replacingPhotos = true }
                    .disabled(book.pages.isEmpty)
                Button("重命名手帐") { name = book.title; renaming = true }
                Menu("配置外壳", systemImage: "book.closed") {
                    Button("不使用外壳") { perform { try await store.setShell(nil) } }
                    ForEach(Array(book.pages.enumerated()), id: \.element.id) { index, page in
                        Button(page.title.isEmpty ? "第 \(index + 1) 页" : page.title) {
                            perform { try await store.setShell(page.id) }
                        }
                    }
                }
                Button("自动使用第一页作封面") { perform { try await store.setCover(nil) } }
                Button("最近删除（\(book.trashedPages.count)）") { showingTrash = true }
            } label: { Image(systemName: "ellipsis.circle") }
        }
        .disabled(busy)
        .overlay {
            if busy {
                ProgressView("正在准备页面…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .task { await refresh() }
        .photosPicker(isPresented: $pickingPhoto, selection: $photo, matching: .images)
        .onChange(of: photo) { _, value in
            guard let value else { return }
            Task {
                guard !busy else { return }
                busy = true
                do {
                    guard let data = try await value.loadTransferable(type: Data.self) else { throw DiaryEditorError.invalidImage.logged() }
                    busy = false
                    await createPage(data: data)
                } catch { message = error.localizedDescription }
                busy = false; photo = nil
            }
        }
        .fullScreenCover(item: $editor, onDismiss: { Task { await refresh() } }) { session in
            DiaryEditorScreen(session: session)
        }
        .fullScreenCover(isPresented: $reading, onDismiss: { Task { await refresh() } }) {
            DiaryBookReaderScreen(book: book, store: store, pageID: readingID)
        }
        .fullScreenCover(isPresented: $bookReading) {
            DiaryPhysicalBookScreen(book: book, store: store)
        }
        .sheet(isPresented: $replacingPhotos, onDismiss: { Task { await refresh() } }) { DiaryBatchPhotoSheet(store: store) }
        .sheet(isPresented: $showingPresetPicker, onDismiss: { Task { await refresh() } }) {
            DiaryPresetPagePicker(ownerID: ownerID, targetBook: book, afterPageID: presetAfterPageID) { updated in
                book = updated
            }
        }
        .sheet(isPresented: $showingExport) { DiaryBookExportSheet(book: book, store: store) }
        .sheet(isPresented: $showingTrash) { trashPanel }
        .alert("手帐", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("确定") { message = nil }
        } message: { Text(message ?? "") }
        .alert("重命名手帐", isPresented: $renaming) {
            TextField("名称", text: $name)
            Button("取消", role: .cancel) { }
            Button("保存") { perform { try await store.renameBook(name) } }
        }
        .confirmationDialog("将这一页移到最近删除？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            if let page = deleting {
                Button("移到最近删除", role: .destructive) { perform { try await store.trashPage(page.id) }; deleting = nil }
            }
            Button("取消", role: .cancel) { deleting = nil }
        }
    }
    @ViewBuilder private func pageCard(_ page: DiaryPageEntry) -> some View {
        let index = book.pages.firstIndex { $0.id == page.id } ?? 0
        VStack(alignment: .leading, spacing: 8) {
            DiaryPagePreview(page: page, store: store)
                .overlay {
                    DiaryPageTouchSurface(
                        onTap: { Task { await open(page) } },
                        onBegin: { point in beginSorting(page, at: point) },
                        onMove: { translation in moveSorting(page, translation: translation) },
                        onEnd: { finishSorting() }
                    ).accessibilityHidden(true)
                }
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { Task { await open(page) } }
            HStack {
                Text(page.title.isEmpty ? "第 \(index + 1) 页" : page.title).font(.subheadline)
                Spacer()
                if book.effectiveCover?.id == page.id { Image(systemName: "book.closed.fill").foregroundStyle(.orange) }
                if book.shellPageID == page.id { Text("外壳").font(.caption).foregroundStyle(.secondary) }
                pageMenu(page, index: index)
            }
        }
        .id(page.id)
        .opacity(draggingPage?.id == page.id ? 0.25 : 1)
        .background {
            GeometryReader { geometry in
                Color.clear.preference(key: DiaryPageSortFrames.self,
                    value: [page.id: geometry.frame(in: .named("diary-page-sort"))])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityHint(page.id == book.shellPageID || page.id == book.effectiveCover?.id ? "外壳和封面固定显示在首行" : "长按照片并拖动可调整页面顺序")
    }

    private func beginSorting(_ page: DiaryPageEntry, at point: CGPoint) {
        guard !busy, draggingPage == nil,
              page.id != book.shellPageID, page.id != book.effectiveCover?.id,
              let frame = pageFrames[page.id] else { return }
        orderBeforeDrag = book
        dragOrigin = frame
        dragTranslation = .zero
        dragStartPoint = CGPoint(x: frame.minX + point.x, y: frame.minY + point.y)
        draggingPage = page
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func moveSorting(_ page: DiaryPageEntry, translation: CGSize) {
        guard !busy, draggingPage?.id == page.id else { return }
        dragTranslation = translation
        let point = CGPoint(x: dragStartPoint.x + translation.width, y: dragStartPoint.y + translation.height)
        guard let target = book.pages.first(where: {
            $0.id != page.id && $0.id != book.shellPageID && $0.id != book.effectiveCover?.id && pageFrames[$0.id]?.contains(point) == true
        }), let from = book.pages.firstIndex(where: { $0.id == page.id }),
           let to = book.pages.firstIndex(where: { $0.id == target.id }) else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            let moved = book.pages.remove(at: from)
            book.pages.insert(moved, at: to)
        }
    }

    private func finishSorting() {
        guard draggingPage != nil, let before = orderBeforeDrag else { return }
        let ids = book.pages.map(\.id)
        draggingPage = nil
        orderBeforeDrag = nil
        guard ids != before.pages.map(\.id) else { return }
        busy = true
        Task { @MainActor in
            defer { busy = false }
            do {
                try await store.reorderPages(ids, expectedRevision: before.catalogRevision)
                await refresh()
            } catch {
                book = before
                message = "排序未保存：\(error.localizedDescription)"
                if let latest = try? await store.loadBook() { book = latest }
            }
        }
    }

    private func pageMenu(_ page: DiaryPageEntry, index: Int) -> some View {
        Menu {
            Button("编辑") { Task { await open(page) } }
            Button("在此页后添加预设") { presetAfterPageID = page.id; showingPresetPicker = true }
            Button("从这页开始阅读") { readingID = page.id; reading = true }.disabled(book.shellPageID == page.id)
            if book.shellPageID == page.id {
                Button("取消外壳") { perform { try await store.setShell(nil) } }
            } else {
                Button("设为外壳") { perform { try await store.setShell(page.id) } }
            }
            Button("设为封面") { perform { try await store.setCover(page.id) } }
            Button("前移一页") { perform { try await store.movePage(page.id, forward: false) } }.disabled(index == 0)
            Button("后移一页") { perform { try await store.movePage(page.id, forward: true) } }.disabled(index == book.pages.count - 1)
            Button("移到最近删除", role: .destructive) { deleting = page }
        } label: { Image(systemName: "ellipsis") }
    }
    private var trashPanel: some View {
        NavigationStack {
            List {
                if book.trashedPages.isEmpty { Text("没有已删除页面").foregroundStyle(.secondary) }
                ForEach(book.trashedPages) { record in
                    HStack {
                        Text(record.entry.title.isEmpty ? "已删除页面" : record.entry.title)
                        Spacer()
                        Button("恢复") { perform { try await store.restorePage(record.id) } }
                    }
                }
            }
            .navigationTitle("最近删除")
            .toolbar { Button("完成") { showingTrash = false } }
        }
    }
    private func refresh() async {
        do { book = try await store.loadBook() }
        catch { message = error.localizedDescription }
    }
    private func perform(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            do { try await operation(); await refresh() }
            catch { message = error.localizedDescription }
        }
    }
    private func open(_ page: DiaryPageEntry) async {
        guard !busy else { return }; busy = true
        defer { busy = false }
        do {
            let loaded = try await store.load(page.id)
            editor = DiaryEditorSession(document: loaded.document, images: loaded.images, store: store)
        } catch { message = error.localizedDescription }
    }
    /// 新页发布成功才打开编辑器；取消相册或资源导入失败不会产生空白占位页。
    private func createPage(data: Data?) async {
        guard !busy else { return }; busy = true
        defer { busy = false }
        do {
            var document = DiaryDocument()
            document.bookID = book.id
            document.objects[document.rootContentID]?.referenceSize = book.defaultPageSize
            var images: [UUID: UIImage] = [:]
            if let data {
                let (asset, image) = try await store.importImage(data, documentID: document.id)
                document.assets[asset.id] = asset; images[asset.id] = image
                document.appendObject(containing: DiaryLayer.photo(asset: asset, center: CGPoint(x: book.defaultPageSize.width / 2, y: book.defaultPageSize.height / 2)))
            }
            try await store.save(document)
            await refresh()
            editor = DiaryEditorSession(document: document, images: images, store: store)
        } catch { message = error.localizedDescription }
    }


}

/// 阅读只显示页面预览，不为整本创建编辑会话；当前页可直接打开同一编辑器。
private struct DiaryBookReaderScreen: View {
    let book: DiaryBook
    let store: DiaryDocumentStore
    @State var pageID: UUID?
    @State private var editor: DiaryEditorSession?
    @State private var busy = false
    @State private var currentBook: DiaryBook?
    @State private var message: String?
    @Environment(\.dismiss) private var dismiss
    private var pages: [DiaryPageEntry] { (currentBook ?? book).contentPages }

    private var currentIndex: Int { pages.firstIndex { $0.id == pageID } ?? 0 }
    var body: some View {
        NavigationStack {
            pageTabs
                .navigationTitle("\(currentIndex + 1) / \(pages.count)")
                .toolbar { readerToolbar }
                .fullScreenCover(item: $editor, onDismiss: {
                    Task {
                        do { currentBook = try await store.loadBook() }
                        catch { message = error.localizedDescription }
                    }
                }) { session in DiaryEditorScreen(session: session) }
                .alert("无法打开页面", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                    Button("确定") { message = nil }
                } message: { Text(message ?? "") }
        }
    }
    private var pageTabs: some View {
        TabView(selection: $pageID) {
            ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                readerPage(page, index: index).tag(Optional(page.id))
            }
        }.tabViewStyle(.page(indexDisplayMode: .never))
    }
    @ViewBuilder
    private func readerPage(_ page: DiaryPageEntry, index: Int) -> some View {
        if abs(index - currentIndex) <= 1 {
            DiaryPagePreview(page: page, store: store, large: true).padding(20)
        } else { Color.clear }
    }
    @ToolbarContentBuilder
    private var readerToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) { Button("返回") { dismiss() } }
        ToolbarItem(placement: .topBarTrailing) {
            Button("编辑当前页") { Task { await openCurrent() } }.disabled(busy)
        }
    }
    private func openCurrent() async {
        guard !busy, let page = pages.first(where: { $0.id == pageID }) else { return }
        busy = true
        defer { busy = false }
        do {
            let loaded = try await store.load(page.id)
            editor = DiaryEditorSession(document: loaded.document, images: loaded.images, store: store)
        } catch { message = error.localizedDescription }
    }
}

private struct DiaryPageSortFrames: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}
