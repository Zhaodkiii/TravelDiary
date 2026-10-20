import SwiftUI

/// 书架只读取目录与封面；继续编辑时才加载目标页。
struct DiaryEditorHomeView: View {
    let ownerID: String
    @Binding var path: NavigationPath
    @Binding var creating: Bool
    var onBrowseTemplates: (() -> Void)? = nil
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var books: [DiaryBook] = []
    @State private var createdBookID: UUID?
    @State private var message: String?
    @State private var deletingBook: DiaryBook?
    @State private var renamingBook: DiaryBook?
    @State private var newTitle = ""
    @State private var sort: DiaryShelfSort = .updated
    @State private var recent: DiaryBookAccessStore.Record?
    @State private var editor: DiaryEditorSession?
    @State private var loadingEditor = false
    @State private var loaded = false
    @State private var loadError: String?
    @State private var unreadable: [UUID] = []
    @State private var showingReadIssues = false
    @State private var fallbackBook: DiaryBook?
    @State private var fallbackPage: UUID?
    private var access: DiaryBookAccessStore { DiaryBookAccessStore(ownerID: ownerID) }
    private var sortKey: String { "DiaryShelfSort." + Data(ownerID.utf8).base64EncodedString() }
    private var results: [DiaryBook] { sort.apply(to: books, search: "") }
    private var recentBook: DiaryBook? { books.first { $0.id == recent?.bookID } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if let loadError {
                    DiaryLibraryNotice(message: loadError) { Task { await reload() } }
                }
                if !unreadable.isEmpty {
                    DiaryLibraryNotice(message: "有 \(unreadable.count) 本手帐暂时无法读取", actionTitle: "查看详情") {
                        showingReadIssues = true
                    }
                }
                if !loaded && books.isEmpty { ProgressView("正在整理书架…").frame(maxWidth: .infinity).padding(.vertical, 64) }
                else if books.isEmpty && unreadable.isEmpty && loadError == nil { emptyShelf }
                else {
                    if let book = recentBook { continueCard(book) }
                    shelfHeader
                    LazyVGrid(columns: typeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.adaptive(minimum: 150), spacing: 16)], alignment: .leading, spacing: 28) {
                        ForEach(results) { book in bookCard(book) }
                    }
                }
            }.frame(maxWidth: 1200).padding(20).frame(maxWidth: .infinity)
        }
        .background(DiaryLibraryStyle.background).foregroundStyle(DiaryLibraryStyle.ink)
        .tint(DiaryLibraryStyle.accent)
        .refreshable { await reload() }
        .task {
            sort = DiaryShelfSort(rawValue: UserDefaults.standard.string(forKey: sortKey) ?? "") ?? .updated
        }
        .onAppear { Task { await reload() } }
        .onChange(of: sort) { _, value in UserDefaults.standard.set(value.rawValue, forKey: sortKey) }
        .overlay { if loadingEditor { ProgressView("正在打开页面…").padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) } }
        .disabled(loadingEditor)
        .sheet(isPresented: $creating, onDismiss: {
            if let id = createdBookID {
                createdBookID = nil
                path.append(DiaryBookRoute(bookID: id))
            }
            Task { await reload() }
        }) {
            DiaryCreateBookSheet(ownerID: ownerID) { book in
                books.insert(book, at: 0); createdBookID = book.id; creating = false
            }
        }
        .fullScreenCover(item: $editor, onDismiss: { Task { await reload() } }) { DiaryEditorScreen(session: $0) }
        .confirmationDialog("移到最近删除？", isPresented: Binding(get: { deletingBook != nil }, set: { if !$0 { deletingBook = nil } }), titleVisibility: .visible) {
            if let book = deletingBook {
                Button("移到最近删除", role: .destructive) {
                    Task {
                        do {
                            try await DiaryDocumentStore(ownerID: ownerID).trashBook(book.id)
                            access.remove(book.id); await reload()
                        } catch { message = error.localizedDescription }
                    }
                }
            }
            Button("取消", role: .cancel) { deletingBook = nil }
        } message: { Text("将保留这本手帐的页面与素材。可在设置 → 存储空间 → 最近删除中恢复；移入最近删除不会立即释放空间。") }
        .alert("重命名手帐", isPresented: Binding(get: { renamingBook != nil }, set: { if !$0 { renamingBook = nil } })) {
            TextField("手帐名称", text: $newTitle)
            if let book = renamingBook {
                Button("保存") {
                    let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    Task {
                        do { try await DiaryDocumentStore(ownerID: ownerID, bookID: book.id).renameBook(title); await reload() }
                        catch { message = error.localizedDescription }
                    }
                }.disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Button("取消", role: .cancel) { renamingBook = nil }
        }
        .alert("上次编辑的页面已移除", isPresented: Binding(get: { fallbackBook != nil }, set: { if !$0 { fallbackBook = nil } })) {
            if let book = fallbackBook, let pageID = fallbackPage {
                Button("打开第一页") { Task { await openEditor(book, pageID: pageID) } }
            }
            Button("取消", role: .cancel) { fallbackBook = nil }
        } message: { Text("可以从这本手帐的第一张正文页继续。") }
        .alert("手帐", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("确定") { message = nil }
        } message: { Text(message ?? "") }
        .sheet(isPresented: $showingReadIssues) {
            NavigationStack {
                List {
                    Text("以下手帐的目录暂时无法读取，原文件已保留。请重试，或使用已有备份恢复。")
                    ForEach(unreadable, id: \.self) { Text($0.uuidString).font(.caption.monospaced()) }
                    Button("重新读取") { showingReadIssues = false; Task { await reload() } }
                }.navigationTitle("读取问题").toolbar { Button("完成") { showingReadIssues = false } }
            }
        }
    }
    private var emptyShelf: some View {
        VStack(spacing: 20) {
            Image(systemName: "book.closed").font(.system(size: 52, weight: .light)).foregroundStyle(DiaryLibraryStyle.accent)
            Text("把旅途，收进第一本手帐").font(.title2.weight(.semibold)).multilineTextAlignment(.center)
            Text("选一本模板，放入照片，开始记录。").foregroundStyle(DiaryLibraryStyle.secondary)
            Button("挑选模板") {
                if let onBrowseTemplates { onBrowseTemplates() } else { creating = true }
            }.buttonStyle(.borderedProminent).controlSize(.large)
            Button("新建手帐") { creating = true }.frame(minHeight: 44)
        }.frame(maxWidth: .infinity).padding(.vertical, 64)
    }
    private var shelfHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack { shelfTitle; Spacer(); sortMenu }
            VStack(alignment: .leading) { shelfTitle; sortMenu }
        }
    }
    private var shelfTitle: some View { Text("全部手帐 · \(results.count) 本").font(.headline) }
    private var sortMenu: some View {
        Menu {
            Picker("排序", selection: $sort) { ForEach(DiaryShelfSort.allCases) { Text($0.label).tag($0) } }
        } label: { Label(sort.label, systemImage: "arrow.up.arrow.down").font(.subheadline).frame(minHeight: 44) }
    }
    private func continueCard(_ book: DiaryBook) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("继续创作").font(.headline)
            HStack(alignment: .center, spacing: 16) {
                if !typeSize.isAccessibilitySize { cover(book).frame(width: 76, height: 100) }
                VStack(alignment: .leading, spacing: 8) {
                    Text(book.title).font(.headline).lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                    if let index = book.contentPages.firstIndex(where: { $0.id == recent?.pageID }) {
                        Text("上次编辑第 \(index + 1) 页").font(.caption).foregroundStyle(DiaryLibraryStyle.secondary)
                    }
                    Button("继续编辑", systemImage: "pencil") { Task { await resume(book) } }
                        .buttonStyle(.borderedProminent).frame(minHeight: 44)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.padding(16).background(DiaryLibraryStyle.surface, in: RoundedRectangle(cornerRadius: 16))
        }
    }
    private func bookCard(_ book: DiaryBook) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { path.append(DiaryBookRoute(bookID: book.id)) } label: {
                VStack(alignment: .leading, spacing: 12) {
                    cover(book).aspectRatio(3.0 / 4, contentMode: .fit)
                    Text(book.title).font(.headline).lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("打开手帐，\(book.title)")
            HStack(alignment: .top, spacing: 4) {
                Text("\(book.contentPages.count) 页 · \(updatedLabel(book.updatedAt))")
                    .font(.caption).foregroundStyle(DiaryLibraryStyle.secondary)
                    .accessibilityLabel("\(book.contentPages.count) 页，更新于 \(book.updatedAt.formatted(date: .complete, time: .shortened))")
                Spacer(minLength: 0)
                Menu { bookActions(book) } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                    .accessibilityLabel("\(book.title)的更多操作")
            }
        }.contextMenu { bookActions(book) }
    }
    @ViewBuilder private func bookActions(_ book: DiaryBook) -> some View {
        Button("继续编辑", systemImage: "pencil") { Task { await resume(book) } }
        Button("管理页面", systemImage: "square.grid.2x2") { path.append(DiaryBookRoute(bookID: book.id, managePages: true)) }
        Button("重命名", systemImage: "character.cursor.ibeam") { newTitle = book.title; renamingBook = book }
        Button("删除整本手帐", systemImage: "trash", role: .destructive) { deletingBook = book }
    }
    private func cover(_ book: DiaryBook) -> some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(DiaryLibraryStyle.surface)
                if let page = book.effectiveCover {
                    DiaryPagePreview(page: page, store: DiaryDocumentStore(ownerID: ownerID, bookID: book.id), undecorated: true)
                        .frame(maxWidth: geometry.size.width - 16, maxHeight: geometry.size.height - 16)
                        .shadow(color: .black.opacity(0.1), radius: 4, y: 3)
                } else {
                    Image(systemName: "book.closed").font(.largeTitle).foregroundStyle(DiaryLibraryStyle.accent.opacity(0.6))
                }
            }.frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
    private func updatedLabel(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "今天更新" }
        if Calendar.current.isDateInYesterday(date) { return "昨天更新" }
        let sameYear = Calendar.current.component(.year, from: date) == Calendar.current.component(.year, from: Date())
        return date.formatted(sameYear ? .dateTime.month().day() : .dateTime.year().month().day()) + "更新"
    }
    private func resume(_ book: DiaryBook) async {
        guard !loadingEditor else { return }
        loadingEditor = true
        defer { loadingEditor = false }
        do {
            let current = try await DiaryDocumentStore(ownerID: ownerID, bookID: book.id).loadBook()
            let preferred = access.records.first { $0.bookID == book.id }?.pageID
            guard let page = DiaryBookAccessStore.resumePage(in: current, preferred: preferred) else {
                path.append(DiaryBookRoute(bookID: book.id, managePages: true)); return
            }
            if let preferred, preferred != page.id { fallbackPage = page.id; fallbackBook = current; return }
            await openEditor(current, pageID: page.id)
        } catch { message = error.localizedDescription }
    }
    private func openEditor(_ book: DiaryBook, pageID: UUID?) async {
        guard let pageID else { return }
        loadingEditor = true
        defer { loadingEditor = false }
        do {
            let store = DiaryDocumentStore(ownerID: ownerID, bookID: book.id)
            let loaded = try await store.load(pageID)
            editor = DiaryEditorSession(document: loaded.document, images: loaded.images, store: store)
        } catch { message = error.localizedDescription }
    }
    private func reload() async {
        do {
            let snapshot = try await DiaryDocumentStore(ownerID: ownerID).loadShelf()
            books = snapshot.books; unreadable = snapshot.unreadableIDs; loadError = nil
            recent = access.latest(in: books)
        } catch { loadError = "书架暂时无法刷新：" + error.localizedDescription }
        loaded = true
    }
}

/// 卡片以版本作为任务身份。复用或滚出屏幕后，取消任务不会把旧结果贴到别的页面。
struct DiaryPagePreview: View {
    let page: DiaryPageEntry
    let store: DiaryDocumentStore
    var large = false
    var undecorated = false
    @State private var image: UIImage?
    @State private var failed = false
    @State private var retry = 0

    var body: some View {
        ZStack {
            if !undecorated { RoundedRectangle(cornerRadius: 8).fill(Color(uiColor: .secondarySystemGroupedBackground)) }
            if let image { Image(uiImage: image).resizable().scaledToFit() }
            else if failed {
                Button { retry += 1 } label: { Label("重试预览", systemImage: "arrow.clockwise") }.font(.caption)
            } else { ProgressView() }
        }
        .aspectRatio(page.size.width / page.size.height, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: undecorated ? 0 : 8))
        .task(id: "\(page.id)-\(page.revisionID)-\(large)-\(retry)") {
            image = nil; failed = false
            do {
                let result = try await DiaryPreviewService.image(page: page, store: store, large: large)
                try Task.checkCancellation(); image = result
            } catch is CancellationError { }
            catch { failed = true }
        }
        .accessibilityLabel("页面设计预览")
    }
}
