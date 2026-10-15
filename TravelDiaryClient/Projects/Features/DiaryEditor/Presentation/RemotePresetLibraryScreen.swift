import SwiftUI

struct PresetAvailabilityBadge: View {
    let downloaded: Bool
    var body: some View {
        Label(downloaded ? "已下载" : "云端", systemImage: downloaded ? "checkmark.circle.fill" : "cloud")
            .font(.caption2).foregroundStyle(downloaded ? Color.secondary : Color.blue)
            .fixedSize().accessibilityLabel(downloaded ? "已下载" : "云端，尚未下载")
    }
}

struct PresetBookAvailabilityBadge: View {
    let downloadedCount: Int
    let totalCount: Int
    private var complete: Bool { totalCount > 0 && downloadedCount >= totalCount }
    var body: some View {
        Label(complete ? "已下载" : "已下载 \(downloadedCount) / \(totalCount) 页",
              systemImage: complete ? "checkmark.circle.fill" : "cloud")
            .font(.caption2).foregroundStyle(complete ? Color.secondary : Color.blue)
            .fixedSize()
    }
}

private struct RemotePresetSelection: Identifiable {
    let id = UUID()
    let pageIDs: [String]
    let wholeBook: Bool
}

struct RemotePresetDetailScreen: View {
    let ownerID: String
    let book: RemotePresetBook
    let targetBook: DiaryBook?
    let afterPageID: UUID?
    let onImported: (DiaryBook) -> Void
    @ObservedObject private var downloads = PresetDownloadManager.shared
    @State private var pages: [RemotePresetPage] = []
    @State private var manifest: PresetManifest?
    @State private var pageData: [PresetPage] = []
    @State private var error: String?
    @State private var previewID: String?
    @State private var showingPreview = false
    @State private var selection: RemotePresetSelection?
    private var placeholderPackage: DiaryPresetPackage? {
        manifest.map { DiaryPresetPackage(root: FileManager.default.temporaryDirectory.appendingPathComponent("remote-metadata"), manifest: $0) }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let manifest {
                    HStack {
                        Text("\(pages.count) 页 · \(Int(manifest.pageSize.width)) × \(Int(manifest.pageSize.height))")
                        PresetBookAvailabilityBadge(downloadedCount: min(book.page_count, downloads.downloadedPageIDs(bookID: book.id, version: book.version).count), totalCount: book.page_count)
                    }
                    Button("整本添加到我的") {
                        selection = RemotePresetSelection(pageIDs: pages.map(\.id), wholeBook: true)
                    }.buttonStyle(.borderedProminent)
                    DiaryPageListGrid(pages: pageData, shellID: manifest.shellPageID, coverID: manifest.coverPageID) { page in
                        if let remote = pages.first(where: { $0.id == page.id }) {
                            VStack {
                                Button { previewID = page.id; showingPreview = true } label: {
                                    remoteImage(remote.thumbnail_url, size: page.size.cg)
                                }
                                HStack {
                                    Text(page.title).font(.caption)
                                    PresetAvailabilityBadge(downloaded: downloads.hasDownloadedPage(bookID: book.id, version: book.version, pageID: page.id))
                                }
                                Button("使用这一页") { selection = RemotePresetSelection(pageIDs: [page.id], wholeBook: false) }
                            }
                        }
                    }
                } else if error == nil { ProgressView("正在读取预设…") }
                if let error { Text(error).foregroundStyle(.red); Button("重试") { Task { await load() } } }
            }.padding()
        }.navigationTitle(book.title)
        .toolbar {
            NavigationLink { PresetDownloadCenter(ownerID: ownerID) } label: {
                Image(systemName: "arrow.down.circle").accessibilityLabel("下载管理")
            }
        }
        .task { await load() }
        .fullScreenCover(isPresented: $showingPreview) {
            NavigationStack {
                TabView(selection: $previewID) {
                    ForEach(pages) { page in
                        VStack {
                            if abs((pages.firstIndex { $0.id == page.id } ?? 0) - (pages.firstIndex { $0.id == previewID } ?? 0)) <= 1 {
                                remoteImage(page.preview_url, size: manifest?.pageSize.cg ?? CGSize(width: 1, height: 1.4))
                            } else { Color.clear }
                            Text(page.title)
                        }.padding().tag(Optional(page.id))
                    }
                }.tabViewStyle(.page)
                    .navigationTitle("\((pages.firstIndex { $0.id == previewID } ?? 0) + 1) / \(pages.count)")
                    .toolbar { Button("完成") { showingPreview = false } }
                    .safeAreaInset(edge: .bottom) {
                        Button("使用这一页") {
                            if let previewID { showingPreview = false; selection = RemotePresetSelection(pageIDs: [previewID], wholeBook: false) }
                        }.buttonStyle(.borderedProminent).padding()
                    }
            }
        }
        .sheet(item: $selection) { value in
            if let package = placeholderPackage {
                DiaryPresetImportSheet(ownerID: ownerID, package: package, pageIDs: value.pageIDs,
                    defaultTarget: value.wholeBook ? nil : targetBook, wholeBook: value.wholeBook,
                    defaultAfterPageID: afterPageID, remoteBook: book) { result in
                        selection = nil; onImported(result)
                    }
            }
        }
    }
    private func remoteImage(_ raw: String, size: CGSize) -> some View {
        AsyncImage(url: URL(string: raw)) { phase in
            switch phase {
            case .success(let image): image.resizable().scaledToFit()
            case .failure: Image(systemName: "photo.badge.exclamationmark").frame(maxWidth: .infinity)
            default: Color.gray.opacity(0.1).overlay { ProgressView() }
            }
        }.aspectRatio(size.width / size.height, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
    private func load() async {
        error = nil
        do {
            struct Detail: Decodable { let manifest: PresetManifest; let page_data: [PresetPage]; let pages: [RemotePresetPage] }
            let value = try JSONDecoder().decode(Detail.self, from: await downloads.request("templates/\(book.id)/\(book.version)/"))
            manifest = value.manifest; pageData = value.page_data; pages = value.pages
        } catch { self.error = error.localizedDescription }
    }
}

struct PresetDownloadCenter: View {
    let ownerID: String
    @ObservedObject private var manager = PresetDownloadManager.shared
    @State private var opened: DiaryBook?
    @State private var error: String?
    @State private var removing = Set<UUID>()
    @State private var confirmingRemovalID: UUID?
    @State private var confirmingBulkRemoval = false
    private var downloadedJobs: [PresetDownloadJob] {
        manager.jobs.filter { $0.owner == ownerID && ["ready", "completed"].contains($0.status) }
    }
    var body: some View {
        List {
            Section {
                Text("已下载 \(downloadedJobs.count) 份资源，可清理单页或整本下载。清理后可以重新下载，已添加到我的手帐的内容不受影响。")
                    .font(.footnote).foregroundStyle(.secondary)
                if !downloadedJobs.isEmpty {
                    Button("清理全部已下载资源", role: .destructive) {
                        confirmingBulkRemoval = true
                    }
                    .confirmationDialog("清理预设资源？", isPresented: $confirmingBulkRemoval, titleVisibility: .visible) {
                        Button("清理所选资源", role: .destructive) { clearDownloads(Set(downloadedJobs.map(\.id))) }
                        Button("取消", role: .cancel) { }
                    } message: {
                        Text("将删除已下载记录及本机缓存。其他任务共用的资源会保留；已添加到手帐的页面不受影响。内置预设无需清理。")
                    }
                }
            }
            if let error { Text(error).foregroundStyle(.red) }
            ForEach(manager.jobs.filter { $0.owner == ownerID }) { job in
                VStack(alignment: .leading, spacing: 8) {
                    Text(job.title).font(.headline)
                    if let manifest = try? JSONDecoder().decode(PresetManifest.self, from: job.manifestData) {
                        Text("\(job.wholeBook ? "整本" : "单页/选页") · \(manifest.pages.count) 页 · 版本 \(manifest.packageVersion)").font(.caption).foregroundStyle(.secondary)
                    }
                    Text(label(job.status)).font(.caption)
                    ProgressView(value: Double(job.bytes), total: Double(max(1, job.total)))
                    Text("\(ByteCountFormatter.string(fromByteCount: job.bytes, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: job.total, countStyle: .file))")
                        .font(.caption)
                    if let error = job.error { Text(error).font(.caption).foregroundStyle(.red) }
                    HStack {
                        if ["queued", "downloading", "verifying"].contains(job.status) { Button("暂停") { manager.pause(job.id) } }
                        if ["paused", "failed"].contains(job.status) { Button("继续") { manager.resume(job.id) } }
                        if !["completed", "ready", "cancelled", "importing"].contains(job.status) { Button("取消", role: .destructive) { manager.cancel(job.id) } }
                        if job.status == "completed", let id = job.resultID {
                            Button("打开手帐") {
                                Task {
                                    do { opened = try await DiaryDocumentStore(ownerID: ownerID, bookID: id).loadBook() }
                                    catch { self.error = error.localizedDescription }
                                }
                            }
                        }
                        if ["ready", "completed", "cancelled", "paused", "failed"].contains(job.status) {
                            Button("清理资源", role: .destructive) { confirmingRemovalID = job.id }
                                .confirmationDialog("清理这份预设资源？", isPresented: Binding(
                                    get: { confirmingRemovalID == job.id },
                                    set: { if !$0 && confirmingRemovalID == job.id { confirmingRemovalID = nil } }
                                ), titleVisibility: .visible) {
                                    Button("清理「\(job.title)」", role: .destructive) { clearDownloads([job.id]) }
                                    Button("取消", role: .cancel) { confirmingRemovalID = nil }
                                } message: {
                                    Text("将删除这条下载记录及本机缓存。其他任务共用的资源会保留；已添加到手帐的页面不受影响。")
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
    private func clearDownloads(_ ids: Set<UUID>) {
        do { try manager.removeDownloads(ids, ownerID: ownerID); error = nil }
        catch { self.error = error.localizedDescription }
        confirmingRemovalID = nil
    }
    private func label(_ state: String) -> String {
        ["queued":"等待下载", "downloading":"正在下载", "verifying":"正在校验", "importing":"正在添加", "completed":"已完成", "ready":"已下载，可返回预设继续添加", "paused":"已暂停", "failed":"失败，可继续重试", "cancelled":"已取消"][state] ?? state
    }
}
