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
    @State private var readingID: UUID?
    @State private var busy = false
    @State private var message: String?
    @State private var deleting: DiaryPageEntry?
    @State private var showingTrash = false
    @State private var renaming = false
    @State private var name = ""

    init(ownerID: String, book: DiaryBook) {
        self.ownerID = ownerID
        _book = State(initialValue: book)
        _store = State(initialValue: DiaryDocumentStore(ownerID: ownerID, bookID: book.id))
    }
    var body: some View {
        ScrollView {
            if book.pages.isEmpty {
                ContentUnavailableView("新建第一页", systemImage: "doc.badge.plus", description: Text("从空白画布或一张照片开始。"))
                    .padding(.top, 50)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 20) {
                ForEach(Array(book.pages.enumerated()), id: \.element.id) { index, page in
                    VStack(alignment: .leading, spacing: 8) {
                        Button { Task { await open(page) } } label: { DiaryPagePreview(page: page, store: store) }
                            .buttonStyle(.plain)
                        HStack {
                            Text(page.title.isEmpty ? "第 \(index + 1) 页" : page.title).font(.subheadline)
                            Spacer()
                            if book.effectiveCover?.id == page.id { Image(systemName: "book.closed.fill").foregroundStyle(.orange) }
                            pageMenu(page, index: index)
                        }
                    }.accessibilityElement(children: .contain)
                }
            }.padding()
            Menu {
                Button("空白页", systemImage: "doc") { Task { await createPage(data: nil) } }
                Button("从照片新建", systemImage: "photo") { pickingPhoto = true }
                NavigationLink("从预设选择") { DiaryPresetLibraryScreen(ownerID: ownerID, targetBook: book) }
            } label: { Label("新建一页", systemImage: "plus") }
                .buttonStyle(.borderedProminent).padding(.bottom)
        }
        .navigationTitle(book.title)
        .toolbar {
            Button { readingID = book.pages.first?.id; reading = true } label: { Image(systemName: "book") }
                .disabled(book.pages.isEmpty).accessibilityLabel("阅读整本")
            Menu {
                Button("重命名手帐") { name = book.title; renaming = true }
                Button("自动使用第一页作封面") { perform { try await store.setCover(nil) } }
                Button("最近删除（\(book.trashedPages.count)）") { showingTrash = true }
            } label: { Image(systemName: "ellipsis.circle") }
        }
        .disabled(busy)
        .overlay { if busy { ProgressView("正在准备页面…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
        .task { await refresh() }
        .photosPicker(isPresented: $pickingPhoto, selection: $photo, matching: .images)
        .onChange(of: photo) { _, value in
            guard let value else { return }
            Task {
                guard !busy else { return }
                busy = true
                do {
                    guard let data = try await value.loadTransferable(type: Data.self) else { throw DiaryEditorError.invalidImage }
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
    private func pageMenu(_ page: DiaryPageEntry, index: Int) -> some View {
        Menu {
            Button("编辑") { Task { await open(page) } }
            NavigationLink("在此页后添加预设") { DiaryPresetLibraryScreen(ownerID: ownerID, targetBook: book, targetAfterPageID: page.id) }
            Button("从这页开始阅读") { readingID = page.id; reading = true }
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
    private var pages: [DiaryPageEntry] { (currentBook ?? book).pages }

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
