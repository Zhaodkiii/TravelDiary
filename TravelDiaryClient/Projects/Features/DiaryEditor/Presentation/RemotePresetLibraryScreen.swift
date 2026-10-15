import SwiftUI

struct RemotePresetLibraryScreen: View {
    let ownerID: String
    var targetBook: DiaryBook?
    var afterPageID: UUID?
    @ObservedObject private var downloads = PresetDownloadManager.shared
    @State private var catalog: RemotePresetCatalog?
    @State private var error: String?
    @State private var series = ""
    var body: some View {
        ScrollView {
            if let catalog {
                Picker("系列", selection: $series) {
                    Text("全部").tag("")
                    ForEach(catalog.series, id: \.slug) { Text($0.title).tag($0.slug) }
                }.pickerStyle(.menu)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))]) {
                    ForEach(catalog.books.filter { series.isEmpty || $0.series == series }) { book in
                        NavigationLink {
                            RemotePresetDetailScreen(ownerID: ownerID, book: book, targetBook: targetBook, afterPageID: afterPageID)
                        } label: {
                            VStack {
                                AsyncImage(url: URL(string: book.cover_url)) { image in image.resizable().scaledToFit() }
                                    placeholder: { ProgressView() }.frame(height: 180)
                                Text(book.title)
                                Text("\(book.page_count) 页").font(.caption)
                            }.padding()
                        }.buttonStyle(.plain)
                    }
                }
            } else if error == nil { ProgressView("正在加载云端预设…") }
            if let error { Text(error).foregroundStyle(.secondary); Button("重试") { Task { await load() } } }
        }
        .navigationTitle("云端预设")
        .toolbar { NavigationLink("下载管理") { PresetDownloadCenter(ownerID: ownerID) } }
        .task { downloads.activate(owner: ownerID); await load() }
        .refreshable { await load() }
    }
    private func load() async {
        error = nil
        do { catalog = try await downloads.catalog() } catch { self.error = error.localizedDescription }
    }
}

private struct RemotePresetDetailScreen: View {
    let ownerID: String
    let book: RemotePresetBook
    let targetBook: DiaryBook?
    let afterPageID: UUID?
    @ObservedObject private var downloads = PresetDownloadManager.shared
    @State private var pages: [RemotePresetPage] = []
    @State private var error: String?
    @State private var preview: RemotePresetPage?
    @State private var busy = false
    @State private var showDownloads = false
    var body: some View {
        ScrollView {
            Button("整本添加到我的（新建一本）") { add(nil) }.disabled(busy || pages.isEmpty)
            if let error { Text(error).foregroundStyle(.red) }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))]) {
                ForEach(pages) { page in
                    VStack {
                        Button { preview = page } label: {
                            AsyncImage(url: URL(string: page.thumbnail_url)) { image in image.resizable().scaledToFit() }
                                placeholder: { ProgressView() }.frame(height: 200)
                        }
                        Text(page.title)
                        Button(targetBook == nil ? "使用这一页（新建本）" : "加入当前本") { add([page.id]) }.disabled(busy)
                    }.padding()
                }
            }
        }
        .navigationTitle(book.title)
        .toolbar { Button("下载管理") { showDownloads = true } }
        .navigationDestination(isPresented: $showDownloads) { PresetDownloadCenter(ownerID: ownerID) }
        .sheet(item: $preview) { page in
            NavigationStack {
                AsyncImage(url: URL(string: page.preview_url)) { image in image.resizable().scaledToFit() }
                    placeholder: { ProgressView() }.navigationTitle(page.title)
                    .toolbar { Button("关闭") { preview = nil } }
            }
        }
        .task { do { pages = try await downloads.pages(book) } catch { self.error = error.localizedDescription } }
    }
    private func add(_ ids: [String]?) {
        busy = true
        Task {
            defer { busy = false }
            do {
                try await downloads.enqueue(book: book, pageIDs: ids, owner: ownerID, target: targetBook, after: afterPageID)
                showDownloads = true
            } catch { self.error = error.localizedDescription }
        }
    }
}

struct PresetDownloadCenter: View {
    let ownerID: String
    @ObservedObject private var manager = PresetDownloadManager.shared
    @State private var opened: DiaryBook?
    @State private var error: String?
    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(.red) }
            ForEach(manager.jobs.filter { $0.owner == ownerID }) { job in
                VStack(alignment: .leading, spacing: 8) {
                    Text(job.title).font(.headline)
                    Text(label(job.status)).font(.caption)
                    ProgressView(value: Double(job.bytes), total: Double(max(1, job.total)))
                    Text("\(ByteCountFormatter.string(fromByteCount: job.bytes, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: job.total, countStyle: .file))")
                        .font(.caption)
                    if let error = job.error { Text(error).font(.caption).foregroundStyle(.red) }
                    HStack {
                        if ["queued", "downloading", "verifying"].contains(job.status) { Button("暂停") { manager.pause(job.id) } }
                        if ["paused", "failed"].contains(job.status) { Button("继续") { manager.resume(job.id) } }
                        if !["completed", "cancelled", "importing"].contains(job.status) { Button("取消", role: .destructive) { manager.cancel(job.id) } }
                        if job.status == "completed", let id = job.resultID {
                            Button("打开手帐") {
                                Task {
                                    do { opened = try await DiaryDocumentStore(ownerID: ownerID, bookID: id).loadBook() }
                                    catch { self.error = error.localizedDescription }
                                }
                            }
                        }
                    }.buttonStyle(.borderless)
                }.padding(.vertical, 6)
            }
        }.navigationTitle("下载管理")
        .task { manager.activate(owner: ownerID) }
        .navigationDestination(isPresented: Binding(get: { opened != nil }, set: { if !$0 { opened = nil } })) {
            if let opened { DiaryBookScreen(ownerID: ownerID, book: opened) }
        }
    }
    private func label(_ state: String) -> String {
        ["queued":"等待下载", "downloading":"正在下载", "verifying":"正在校验", "importing":"正在添加", "completed":"已完成", "paused":"已暂停", "failed":"失败，可继续重试", "cancelled":"已取消"][state] ?? state
    }
}
