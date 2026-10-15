import SwiftUI

/// 手帐入口改为书架。这里只读取本目录和封面，不提前加载整本编辑数据。
struct DiaryEditorHomeView: View {
    let ownerID: String
    @Binding var path: NavigationPath
    @Binding var creating: Bool
    @State private var books: [DiaryBook] = []
    @State private var createdBookID: UUID?
    @State private var title = "未命名手帐"
    @State private var pagePreset: DiaryPagePreset = .a5
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        ScrollView {
                if books.isEmpty {
                    ContentUnavailableView("创建第一本手帐", systemImage: "books.vertical", description: Text("一本手帐可以有很多页，记录每一次旅行和日常。"))
                        .padding(.top, 60)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 20) {
                    ForEach(books) { book in
                        NavigationLink(value: DiaryBookRoute(bookID: book.id)) {
                            VStack(alignment: .leading, spacing: 8) {
                                if let cover = book.effectiveCover {
                                    DiaryPagePreview(page: cover, store: DiaryDocumentStore(ownerID: ownerID, bookID: book.id))
                                } else {
                                    RoundedRectangle(cornerRadius: 12).fill(.orange.opacity(0.12))
                                        .overlay { Image(systemName: "book.closed").font(.largeTitle).foregroundStyle(.orange) }
                                        .aspectRatio(book.defaultPageSize.width / book.defaultPageSize.height, contentMode: .fit)
                                }
                                Text(book.title).font(.headline).lineLimit(2)
                                Text("\(book.pages.count) 页 · \(book.updatedAt.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }.buttonStyle(.plain)
                    }
                }.padding()
        }
        .onChange(of: creating) { _, presented in if presented { pagePreset = .a5 } }
        .task { await reload(); _ = try? await Task.detached { try BundleDiaryPresetProvider().catalog() }.value }
        .onAppear { Task { await reload() } }
        .refreshable { await reload() }
        .sheet(isPresented: $creating, onDismiss: {
            // 等表单关闭后，才向应用唯一的导航栈推入详情。
            if let id = createdBookID {
                createdBookID = nil
                path.append(DiaryBookRoute(bookID: id))
            }
        }) {
                NavigationStack {
                    Form {
                        TextField("手帐名称", text: $title)
                        Picker("画布尺寸", selection: $pagePreset) {
                            ForEach(DiaryPagePreset.allCases) { preset in
                                Text(preset.title).tag(preset)
                            }
                        }
                        if pagePreset == .a5 {
                            Text("1748 × 2480 px · 148 × 210 mm · 300 DPI")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Text("默认透明背景；一本内页面保持相同尺寸。名称最多 60 个字符。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .navigationTitle("新建手帐本")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("取消") { creating = false }.disabled(busy) }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("创建") { Task { await create() } }
                                .disabled(busy || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || title.count > 60)
                        }
                    }
                    .interactiveDismissDisabled(busy)
                }
        }
        .alert("手帐", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("确定") { message = nil }
        } message: { Text(message ?? "") }
    }
    private func reload() async {
        do { books = try await DiaryDocumentStore(ownerID: ownerID).listBooks() }
        catch { message = error.localizedDescription }
    }
    private func create() async {
        guard !busy else { return }; busy = true
        defer { busy = false }
        do {
            let book = try await DiaryDocumentStore(ownerID: ownerID).createBook(title: title, preset: pagePreset)
            books.insert(book, at: 0); createdBookID = book.id; creating = false
            title = "未命名手帐"; pagePreset = .a5
        } catch { message = error.localizedDescription }
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
