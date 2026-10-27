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
        Label(complete ? "已下载" : (downloadedCount == 0 ? "云端" : "已下载 \(downloadedCount) / \(totalCount) 页"),
              systemImage: complete ? "checkmark.circle.fill" : "cloud")
            .font(.caption2).foregroundStyle(complete ? Color.secondary : Color.blue)
            .fixedSize()
    }
}

private struct RemotePresetSelection: Identifiable, Hashable {
    let id = UUID()
    let pageIDs: [String]
    let wholeBook: Bool
}

struct RemotePresetReaderDestination: View {
    let ownerID: String
    let book: RemotePresetBook
    let seriesTitle: String
    let targetBook: DiaryBook?
    let afterPageID: UUID?
    var fixedTarget = false
    let onImported: (DiaryBook) -> Void
    @State private var browse: RemotePresetBrowse?
    @State private var pages: [RemotePresetPage] = []
    @State private var error: String?
    @State private var retry = 0
    @State private var selection: RemotePresetSelection?

    @State private var reading = false
    var body: some View {
        VStack(spacing: 0) {
            PresetMaterialLibraryLinks(templateID: book.id, templateVersion: book.version)
            Picker("展示方式", selection: $reading) { Text("翻阅").tag(true); Text("总览").tag(false) }
                .pickerStyle(.segmented).padding()
            if reading { readerContent }
            else {
                RemotePresetDetailScreen(ownerID: ownerID, book: book, targetBook: targetBook,
                    afterPageID: afterPageID, fixedTarget: fixedTarget, onImported: onImported)
            }
        }.background(DiaryLibraryStyle.background).tint(DiaryLibraryStyle.accent).navigationTitle(book.title)
    }
    private var readerContent: some View {
        Group {
            if let browse {
                DiaryPresetBookReader<RemotePresetDetailScreen>(title: browse.title,
                    pages: pages.compactMap { page in
                        guard let url = URL(string: page.preview_url) else { return nil }
                        return DiaryPresetBookReader<RemotePresetDetailScreen>.Page(id: page.id, url: url, size: browse.page_size.cg,
                            thumbnailURL: URL(string: page.thumbnail_url))
                    }, shellID: browse.shell_page_id, seriesTitle: seriesTitle,
                    allowsWholeBook: !fixedTarget, remoteBook: book, ownerID: ownerID, onAdd: { ids, whole in
                        selection = RemotePresetSelection(pageIDs: ids, wholeBook: whole)
                    }) {
                        RemotePresetDetailScreen(ownerID: ownerID, book: book, targetBook: targetBook,
                            afterPageID: afterPageID, fixedTarget: fixedTarget, onImported: onImported)
                    }
            } else if let error {
                VStack { Text(error); Button("重试") { retry += 1 } }.padding()
            } else { ProgressView("正在打开预设…") }
        }.sheet(item: $selection) { value in
            RemotePresetImportDestination(ownerID: ownerID, book: book, pageIDs: value.pageIDs,
                wholeBook: value.wholeBook, targetBook: value.wholeBook ? nil : targetBook,
                afterPageID: afterPageID, fixedTarget: fixedTarget,
                previewPages: pages.filter { value.pageIDs.contains($0.id) },
                previewSize: browse?.page_size.cg ?? CGSize(width: 1, height: 1.4)) { result in
                    selection = nil; onImported(result)
                }
        }.safeAreaInset(edge: .bottom) {
            if browse != nil, let error {
                VStack { Text(error).font(.caption); Button("重试") { retry += 1 } }.padding()
            }
        }.task(id: retry) {
            do {
                error = nil
                if let cached = await PresetPreviewRepository.shared.cached(book, ownerID: ownerID) {
                    browse = cached; pages = cached.pages
                }
                repeat {
                    let value = try await PresetDownloadManager.shared.browse(book, ownerID: ownerID)
                    try Task.checkCancellation()
                    pages = value.pages; browse = value
                    try await Task.sleep(for: .seconds(max(5, value.expires_at - Date().timeIntervalSince1970)))
                } while !Task.isCancelled
            } catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }
}

struct RemotePresetDetailScreen: View {
    let ownerID: String
    let book: RemotePresetBook
    let targetBook: DiaryBook?
    let afterPageID: UUID?
    var fixedTarget = false
    let onImported: (DiaryBook) -> Void
    private let downloads = PresetDownloadManager.shared
    @ObservedObject private var availability = PresetDownloadManager.shared.availability
    @State private var pages: [RemotePresetPage] = []
    @State private var browse: RemotePresetBrowse?
    @State private var error: String?
    @State private var retry = 0
    @State private var preview: DiaryTemplatePreviewSelection?
    @State private var pendingPreviewImport: String?
    @State private var selection: RemotePresetSelection?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let browse {
                    DiaryPresetOverviewBook(pages: pages.filter { $0.id != browse.shell_page_id }.compactMap { page in
                        guard let url = URL(string: page.preview_url) else { return nil }
                        return .init(id: page.id, url: url, size: browse.page_size.cg,
                                     thumbnailURL: URL(string: page.thumbnail_url))
                    }, pageSize: browse.page_size.cg)
                    Text(book.title).font(.title2.weight(.semibold))
                    HStack {
                        Text("\(pages.filter { $0.id != browse.shell_page_id }.count) 页")
                        PresetBookAvailabilityBadge(downloadedCount: min(book.page_count, availability.downloadedPageIDs(bookID: book.id, version: book.version).count), totalCount: book.page_count)
                    }
                    Text("页面总览").font(.headline)
                    DiaryPresetOverviewGrid(spreads: overviewSpreads) { spread in
                        VStack(alignment: .leading, spacing: 8) {
                            Button { if let id = spread.pages.first?.id { preview = DiaryTemplatePreviewSelection(id: id) } } label: {
                                overviewThumbnail(spread, size: browse.page_size.cg)
                            }
                            Text(spread.pages.map(\.title).joined(separator: " · ")).font(.caption)
                            PresetAvailabilityBadge(downloaded: spread.pages.allSatisfy {
                                availability.hasDownloadedPage(bookID: book.id, version: book.version, pageID: $0.id)
                            })
                            Button(spread.pages.count == 2 ? "使用这两页" : "使用这一页") {
                                selection = RemotePresetSelection(pageIDs: spread.pages.map(\.id), wholeBook: false)
                            }
                        }
                    }
                } else if error == nil { ProgressView("正在读取预设…") }
                if let error { Text(error).foregroundStyle(.red); Button("重试") { retry += 1 } }
            }.padding()
        }.navigationTitle(book.title)
        .background(DiaryLibraryStyle.background)
        .safeAreaInset(edge: .bottom) {
            if !fixedTarget {
                Button("用这本模板") { selection = RemotePresetSelection(pageIDs: pages.map(\.id), wholeBook: true) }
                    .buttonStyle(.borderedProminent).controlSize(.large).disabled(pages.isEmpty)
                    .padding()
//                    .frame(maxWidth: .infinity).background(.regularMaterial)
            }
        }
        .toolbar {
            NavigationLink { PresetDownloadCenter(ownerID: ownerID) } label: {
                Image(systemName: "arrow.down.circle").accessibilityLabel("下载管理")
            }
        }
        .task(id: retry) { await load() }
        .fullScreenCover(item: $preview, onDismiss: {
            if let id = pendingPreviewImport {
                pendingPreviewImport = nil
                selection = RemotePresetSelection(pageIDs: [id], wholeBook: false)
            }
        }) { value in
            DiaryTemplatePagePreview(initialPageID: value.id, pages: pages.map { page in
                DiaryTemplatePreviewPage(id: page.id, title: page.title,
                    size: browse?.page_size.cg ?? CGSize(width: 1, height: 1.4),
                    request: PreviewImagePipeline.shared.request(url: URL(string: page.preview_url), maxPixelSize: 1800))
            }) { id in
                pendingPreviewImport = id
                preview = nil
            }
        }
        .sheet(item: $selection) { value in
            importPage(value)
        }
    }
    private var overviewSpreads: [DiaryPresetOverviewSpread<RemotePresetPage>] {
        DiaryPresetOverviewSpread.group(pages: pages, shellID: browse?.shell_page_id, coverID: browse?.cover_page_id)
    }
    private func overviewThumbnail(_ spread: DiaryPresetOverviewSpread<RemotePresetPage>, size: CGSize) -> some View {
        DiaryPresetOverviewThumbnail(spread: spread, pageSize: size) { page in
            DiaryRemoteCover(url: URL(string: page.thumbnail_url))
        }
    }
    private func importPage(_ value: RemotePresetSelection) -> some View {
        RemotePresetImportDestination(ownerID: ownerID, book: book, pageIDs: value.pageIDs,
            wholeBook: value.wholeBook, targetBook: value.wholeBook ? nil : targetBook,
            afterPageID: afterPageID, fixedTarget: fixedTarget,
            previewPages: pages.filter { value.pageIDs.contains($0.id) },
            previewSize: browse?.page_size.cg ?? CGSize(width: 1, height: 1.4)) { result in
                selection = nil; onImported(result)
            }
    }
    private func remoteImage(_ raw: String, size: CGSize) -> some View {
        CachedPreviewImage(request: PreviewImagePipeline.shared.request(url: URL(string: raw), maxPixelSize: 1800)).aspectRatio(size.width / size.height, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
    private func load() async {
        error = nil
        do {
            if let cached = await PresetPreviewRepository.shared.cached(book, ownerID: ownerID) {
                browse = cached; pages = cached.pages
            }
            repeat {
                let value = try await downloads.browse(book, ownerID: ownerID)
                try Task.checkCancellation()
                browse = value; pages = value.pages
                try await Task.sleep(for: .seconds(max(5, value.expires_at - Date().timeIntervalSince1970)))
            } while !Task.isCancelled
        } catch is CancellationError { }
        catch { self.error = error.localizedDescription }
    }
}

/// Reuses the browsing thumbnail while editable resources are being prepared.
struct RemotePresetLoadingPreview: View {
    let page: RemotePresetPage
    let size: CGSize
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CachedPreviewImage(request: PreviewImagePipeline.shared.request(url: URL(string: page.thumbnail_url))).aspectRatio(size.width / max(1, size.height), contentMode: .fit)
            Text(page.title).font(.headline)
        }
    }
}

/// Prefer local resources; otherwise prepare only the selected download plan.
struct RemotePresetImportDestination: View {
    let ownerID: String
    let book: RemotePresetBook
    let pageIDs: [String]
    let wholeBook: Bool
    let targetBook: DiaryBook?
    let afterPageID: UUID?
    let fixedTarget: Bool
    let previewPages: [RemotePresetPage]
    let previewSize: CGSize
    let onImported: (DiaryBook) -> Void
    var unitID: String? = nil
    @State private var preparation: PresetImportPreparation?
    @State private var error: String?
    @State private var retry = 0

    var body: some View {
        Group {
            if let preparation {
                DiaryPresetImportSheet(ownerID: ownerID, package: preparation.package, pageIDs: pageIDs,
                    defaultTarget: targetBook, wholeBook: wholeBook, defaultAfterPageID: afterPageID,
                    remoteBook: preparation.downloadID == nil ? nil : book,
                    initialDownloadID: preparation.downloadID, loadingPages: previewPages,
                    loadingPreviewSize: previewSize, fixedTarget: fixedTarget, completed: onImported)
            } else {
                NavigationStack {
                    ScrollView {
                        VStack(spacing: 16) {
                            if let page = previewPages.first {
                                RemotePresetLoadingPreview(page: page, size: previewSize)
                            }
                            if let error {
                                Text(error).foregroundStyle(.red)
                                Button("重试") { retry += 1 }
                            } else {
                                ProgressView("正在获取所选页面资源清单…")
                            }
                        }.padding()
                    }.navigationTitle(wholeBook ? "添加整本" : pageIDs.count == 1 ? "添加单页" : "添加双页")
        .navigationBarTitleDisplayMode(.inline)
                }
            }
        }.task(id: retry) {
            error = nil
            do {
                let value = try await PresetDownloadManager.shared.prepareImport(book: book,
                    pageIDs: pageIDs, wholeBook: wholeBook, ownerID: ownerID, unitID: unitID)
                try Task.checkCancellation()
                preparation = value
            } catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
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
                        }
                    }.buttonStyle(.borderless)
                }.padding(.vertical, 10)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
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
        }.navigationTitle("下载管理")
        .task { manager.activate(owner: ownerID) }
        .navigationDestination(isPresented: Binding(get: { opened != nil }, set: { if !$0 { opened = nil } })) {
            if let opened { DiaryBookDestination(ownerID: ownerID, bookID: opened.id) }
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
