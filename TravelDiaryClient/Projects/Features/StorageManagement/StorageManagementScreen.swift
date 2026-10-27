import SwiftUI
import Combine
import QuickLook

@MainActor
final class StorageManagementViewModel: ObservableObject {
    let owner: String
    let service: StorageService
    @Published var snapshot: StorageSnapshot?
    @Published var loading = false
    @Published var cleaning = false
    @Published var message: String?
    @Published var result: StorageCleanupResult?
    private var cleanupTask: Task<Void, Never>?

    init(owner: String, service: StorageService) { self.owner = owner; self.service = service }
    func refresh() async {
        guard !loading, !cleaning else { return }
        loading = true
        defer { loading = false }
        do {
            var value = try await service.scan(owner: owner)
            if let maintenance = try await service.maintain(snapshot: value) {
                result = maintenance
                value = try await service.scan(owner: owner)
            }
            try Task.checkCancellation()
            snapshot = value
        } catch is CancellationError { }
        catch { snapshot = nil; message = error.localizedDescription }
    }
    func clean(_ ids: Set<String>) {
        guard !cleaning, let snapshot, !ids.isEmpty else { return }
        cleaning = true; result = nil
        cleanupTask = Task {
            do { result = try await service.clean(snapshot: snapshot, ids: ids) }
            catch { message = error.localizedDescription }
            cleaning = false
            await refresh()
        }
    }
    func stop() { cleanupTask?.cancel() }
}

struct StorageManagementScreen: View {
    @StateObject private var model: StorageManagementViewModel
    init(owner: String, service: StorageService) {
        _model = StateObject(wrappedValue: StorageManagementViewModel(owner: owner, service: service))
    }
    var body: some View {
        List {
            Section {
                if let snapshot = model.snapshot {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("本机数据占用").foregroundStyle(.secondary)
                        Text(storageBytes(snapshot.total)).font(.largeTitle.bold()).monospacedDigit()
                        GeometryReader { geometry in
                            HStack(spacing: 1) {
                                ForEach(StorageCategory.allCases) { category in
                                    let bytes = snapshot.totals[category, default: 0]
                                    if bytes > 0 {
                                        categoryColor(category).frame(width: max(0, (geometry.size.width - 9) * Double(bytes) / Double(max(1, snapshot.total))))
                                    }
                                }
                            }.clipShape(Capsule())
                        }.frame(height: 10).accessibilityHidden(true)
                        if let available = snapshot.available { Text("设备可用约 \(storageBytes(available))").font(.subheadline) }
                        Text("更新于 \(snapshot.generatedAt.formatted(date: .omitted, time: .shortened)) · 文件大小估算，不含应用安装包")
                            .font(.caption).foregroundStyle(.secondary)
                        if snapshot.unreadableCount > 0 {
                            Label("部分数据暂不可统计，相关文件已保留", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                        }
                    }.padding(.vertical, 8)
                } else { ProgressView("正在计算本机占用…") }
            }
            Section {
                if model.cleaning {
                    ProgressView("正在清理所选文件…")
                    Button("停止清理") { model.stop() }
                } else {
                    NavigationLink {
                        StorageCleanupScreen(model: model)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("可以安全清理 \(storageBytes(model.snapshot?.safeBytes ?? 0))").font(.headline)
                            Text("查看并清理预览和过期临时副本，保留手帐与草稿")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }.disabled(model.snapshot == nil)
                }
                if let result = model.result {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(result.stopped ? "清理已停止" : "清理结果").font(.headline)
                        Text("已移除 \(result.removed) 项，按文件大小估算 \(storageBytes(result.bytes))")
                        if result.skipped + result.failed > 0 { Text("跳过 \(result.skipped) 项，失败 \(result.failed) 项；可刷新后重新选择。") }
                    }.font(.subheadline)
                }
            } footer: { Text("作品、离线下载、未保存媒体、印制任务和其他账号私有资料不会参加安全清理。") }
            Section("内容管理") {
                NavigationLink { StorageBooksScreen(owner: model.owner, service: model.service) } label: {
                    row(.diaries)
                }
                NavigationLink { StorageDownloadsScreen(owner: model.owner) } label: { row(.downloads) }
                ForEach([StorageCategory.previews, .exports, .camera, .printOrders, .business, .otherAccounts, .unknown]) { category in
                    NavigationLink { StorageCategoryScreen(model: model, category: category) } label: { row(category) }
                }
                NavigationLink {
                    StorageTrashScreen(owner: model.owner, service: model.service)
                } label: { Label("最近删除", systemImage: "trash") }
            }
            Section {
                NavigationLink("缓存容量与自动清理") { StoragePolicyScreen(owner: model.owner, service: model.service) }
            }
        }
        .navigationTitle("存储空间")
        .toolbar { Button { Task { await model.refresh() } } label: { Image(systemName: "arrow.clockwise") }.disabled(model.loading || model.cleaning).accessibilityLabel("刷新占用") }
        .task { await model.refresh() }
        .onAppear { if model.snapshot != nil { Task { await model.refresh() } } }
        .refreshable { await model.refresh() }
        .alert("存储空间", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("好") { model.message = nil }
        } message: { Text(model.message ?? "") }
    }
    private func row(_ category: StorageCategory) -> some View {
        HStack {
            Label(category.title, systemImage: category.symbol)
            Spacer()
            Text(model.snapshot.map { storageBytes($0.totals[category, default: 0]) } ?? "正在计算")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }
    private func categoryColor(_ category: StorageCategory) -> Color {
        switch category {
        case .diaries: .teal
        case .downloads: .blue
        case .previews: .orange
        case .exports: .purple
        case .camera: .pink
        case .printOrders: .brown
        default: .gray
        }
    }
}

private struct StorageCleanupScreen: View {
    @ObservedObject var model: StorageManagementViewModel
    @State private var selected = Set<String>()
    private var items: [StorageItem] { model.snapshot?.items.filter { $0.automatic } ?? [] }
    private var bytes: Int64 { items.filter { selected.contains($0.id) }.reduce(0) { $0 + $1.bytes } }
    var body: some View {
        List {
            Section {
                Text("仅清理可重新生成或获取的缓存，以及超过 7 天的已完成导出副本。不删除原图、草稿和下载包。")
            }
            if items.isEmpty { ContentUnavailableView("暂时没有可安全清理的内容", systemImage: "checkmark.shield", description: Text("可返回管理已下载模板或导出文件。")) }
            ForEach(StorageCategory.allCases) { category in
                let group = items.filter { $0.category == category }
                if !group.isEmpty {
                    Section(category.title) {
                        Toggle(isOn: Binding(get: { group.allSatisfy { selected.contains($0.id) } }, set: { value in
                            if value { selected.formUnion(group.map(\.id)) } else { selected.subtract(group.map(\.id)) }
                        })) {
                            VStack(alignment: .leading) {
                                Text("\(group.count) 项 · \(storageBytes(group.reduce(0) { $0 + $1.bytes }))")
                                Text(category.explanation).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            if model.cleaning { ProgressView("正在处理…"); Button("停止清理") { model.stop() } }
            else {
                Button("清理所选，预计释放 \(storageBytes(bytes))") { model.clean(selected) }
                    .disabled(selected.isEmpty || model.loading)
            }
            if let result = model.result { Text("已移除 \(result.removed) 项，跳过 \(result.skipped) 项，失败 \(result.failed) 项。") }
        }.navigationTitle("安全清理预览")
            .onAppear { selected = Set(items.map(\.id)) }
            .onChange(of: model.snapshot?.id) { selected = Set(items.map(\.id)) }
    }
}

private struct StorageCategoryScreen: View {
    @ObservedObject var model: StorageManagementViewModel
    let category: StorageCategory
    @State private var selected = Set<String>()
    @State private var confirming = false
    @State private var exportAccess: StorageService.ExportAccess?
    private var items: [StorageItem] { model.snapshot?.items.filter { $0.category == category } ?? [] }
    var body: some View {
        List {
            Section {
                Text(category.explanation)
                Text("本机占用 \(storageBytes(model.snapshot?.totals[category, default: 0] ?? 0))").font(.headline)
                if category == .printOrders {
                    NavigationLink("管理我的印制订单") { PrintOrdersScreen(owner: model.owner) }
                }
            }
            if !items.isEmpty {
                Section("可管理的本地文件") {
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: 6) {
                        Toggle(isOn: Binding(get: { selected.contains(item.id) }, set: { if $0 { selected.insert(item.id) } else { selected.remove(item.id) } })) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title).lineLimit(2)
                                Text("\(storageBytes(item.bytes)) · \(item.modified.formatted(date: .abbreviated, time: .omitted))").font(.caption)
                                Text(item.reason).font(.caption).foregroundStyle(.secondary)
                            }
                        }.disabled(!item.canRemove || model.cleaning)
                        if category == .exports {
                            Button("预览与分享") {
                                Task {
                                    guard let snapshot = model.snapshot else { return }
                                    do { exportAccess = try await model.service.exportAccess(snapshot: snapshot, id: item.id) }
                                    catch { model.message = error.localizedDescription }
                                }
                            }
                        }
                        }
                    }
                }
                Button(category == .exports ? "删除所选本地副本" : "清理所选缓存", role: .destructive) { confirming = true }
                    .disabled(selected.isEmpty || model.cleaning)
            } else { Text("此分类暂无可直接清理的已登记文件。原件和未识别资料保持保留。 ").foregroundStyle(.secondary) }
        }.navigationTitle(category.title)
            .confirmationDialog("确认处理所选 \(selected.count) 项？", isPresented: $confirming, titleVisibility: .visible) {
                Button(category == .exports ? "删除本地副本" : "清理缓存", role: .destructive) { model.clean(selected); selected = [] }
            } message: { Text(category == .exports ? "只删除 App 内副本，不影响原手帐和系统相册、文件中的副本。" : "再次打开时将重新生成预览或联网获取目录。") }
            .onChange(of: model.snapshot?.id) { selected = [] }
            .sheet(item: $exportAccess) { access in
                NavigationStack {
                    StorageExportPreview(url: access.url)
                        .navigationTitle("导出副本")
                        .toolbar { ShareLink(item: access.url) { Label("分享", systemImage: "square.and.arrow.up") } }
                }
            }
    }
}

private struct StorageBooksScreen: View {
    let owner: String
    let service: StorageService
    @State private var books: [DiaryBook] = []
    @State private var sizes: [UUID: Int64] = [:]
    @State private var search = ""
    @State private var message: String?
    @State private var loading = true
    var body: some View {
        List {
            Section { Text("作品原件、草稿和历史均受保护。移到最近删除不会立即释放空间。") }
            ForEach(books.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }.sorted { sizes[$0.id, default: 0] > sizes[$1.id, default: 0] }) { book in
                NavigationLink {
                    StorageBookDetail(owner: owner, book: book, service: service)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(book.title).font(.headline)
                        Text("\(book.contentPages.count) 页 · \(storageBytes(sizes[book.id, default: 0])) · \(book.updatedAt.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if loading { ProgressView() }
            if let message { Text(message).foregroundStyle(.orange) }
            NavigationLink("查看最近删除") { StorageTrashScreen(owner: owner, service: service) }
        }.navigationTitle("手帐作品").searchable(text: $search, prompt: "搜索手帐名称")
            .task { await refresh() }.onAppear { Task { await refresh() } }
    }
    private func refresh() async {
        do {
            try await service.checkOwner(owner)
            let shelf = try await DiaryDocumentStore(ownerID: owner).loadShelf()
            sizes = try await service.bookSizes(owner: owner)
            books = shelf.books
            message = shelf.unreadableIDs.isEmpty ? nil : "部分手帐无法读取，原文件已保留。"
        } catch { message = error.localizedDescription }
        loading = false
    }
}

private struct StorageBookDetail: View {
    let owner: String
    let book: DiaryBook
    let service: StorageService
    @Environment(\.dismiss) private var dismiss
    @State private var confirming = false
    @State private var message: String?
    @State private var busy = false
    var body: some View {
        List {
            Section {
                Text(book.title).font(.title2.bold())
                Text("有效页 \(book.pages.count) · 最近删除页 \(book.trashedPages.count)")
                Text("原图、已导入素材、草稿及必要历史作为作品整体保留，不单独清除原图。")
                NavigationLink("打开手帐与页面管理") { DiaryBookScreen(ownerID: owner, book: book) }
            }
            Section("页面恢复") {
                ForEach(book.trashedPages) { record in
                    VStack(alignment: .leading) {
                        Text(record.entry.title.isEmpty ? "已删除页面" : record.entry.title)
                        Text(record.deletedAt.formatted()).font(.caption).foregroundStyle(.secondary)
                        Button("恢复页面") {
                            Task {
                                do {
                                    try await service.checkOwner(owner)
                                    try await DiaryDocumentStore(ownerID: owner, bookID: book.id).restorePage(record.id)
                                    dismiss()
                                } catch { message = error.localizedDescription }
                            }
                        }
                    }
                }
                if book.trashedPages.isEmpty { Text("没有待恢复的页面") }
            }
            Section {
                Text("草稿与恢复资料仍保留在作品中，可打开对应页面继续编辑。历史与无引用素材尚未开启自动回收。")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("移到最近删除", role: .destructive) { confirming = true }.disabled(busy)
            }
        }.navigationTitle("作品存储详情")
            .confirmationDialog("将「\(book.title)」移到最近删除？", isPresented: $confirming, titleVisibility: .visible) {
                Button("移到最近删除", role: .destructive) {
                    busy = true
                    Task {
                        do {
                            try await service.checkOwner(owner)
                            try await DiaryDocumentStore(ownerID: owner).trashBook(book.id)
                            dismiss()
                        } catch { message = error.localizedDescription }
                        busy = false
                    }
                }
            } message: { Text("页面、照片和草稿仍会保留。可在最近删除中恢复，永久删除后才能释放空间。") }
            .alert("操作未完成", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("好") { message = nil } } message: { Text(message ?? "") }
    }
}

private struct StorageTrashScreen: View {
    let owner: String
    let service: StorageService
    @State private var records: [DiaryDocumentStore.TrashedBook] = []
    @State private var deleting: DiaryDocumentStore.TrashedBook?
    @State private var message: String?
    @State private var busy = false
    var body: some View {
        List {
            Section { Text("这里保留整本手帐。恢复会保留原 ID 和内容；永久删除无法恢复。默认保留到你手动永久删除。已删除页面可在手帐作品详情中恢复。") }
            ForEach(records) { record in
                VStack(alignment: .leading, spacing: 8) {
                    Text(record.book.title).font(.headline)
                    Text("\(record.book.pages.count) 页 · 删除于 \(record.deletedAt.formatted(date: .abbreviated, time: .omitted))").font(.caption)
                    HStack {
                        Button("恢复") { perform { try await DiaryDocumentStore(ownerID: owner).restoreBook(record.id) } }.buttonStyle(.bordered)
                        Button("永久删除", role: .destructive) { deleting = record }.buttonStyle(.bordered)
                    }
                }
            }
            if records.isEmpty { ContentUnavailableView("最近删除为空", systemImage: "trash") }
        }.navigationTitle("最近删除").disabled(busy)
            .task { await refresh() }
            .confirmationDialog("永久删除这本手帐？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                if let record = deleting { Button("永久删除「\(record.book.title)」", role: .destructive) { perform { try await DiaryDocumentStore(ownerID: owner).permanentlyDeleteBook(record.id) }; deleting = nil } }
            } message: { Text("将删除这本手帐的全部页面、原图、草稿和历史，无法恢复。") }
            .alert("存储空间", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("好") { message = nil } } message: { Text(message ?? "") }
    }
    private func refresh() async {
        do { try await service.checkOwner(owner); records = try await DiaryDocumentStore(ownerID: owner).listTrashedBooks() }
        catch { message = error.localizedDescription }
    }
    private func perform(_ action: @escaping @MainActor () async throws -> Void) {
        busy = true
        Task {
            defer { busy = false }
            do { try await service.checkOwner(owner); try await action(); await refresh() }
            catch { message = error.localizedDescription }
        }
    }
}

private struct StorageDownloadsScreen: View {
    let owner: String
    @ObservedObject private var manager = PresetDownloadManager.shared
    @State private var selected = Set<UUID>()
    @State private var confirming = false
    @State private var message: String?
    private var jobs: [PresetDownloadJob] { manager.jobs.filter { $0.owner == owner } }
    var body: some View {
        List {
            Section { Text(StorageCategory.downloads.explanation) }
            ForEach(jobs) { job in
                VStack(alignment: .leading, spacing: 6) {
                    Toggle(isOn: Binding(get: { selected.contains(job.id) }, set: { if $0 { selected.insert(job.id) } else { selected.remove(job.id) } })) {
                        VStack(alignment: .leading) {
                            Text(job.title)
                            Text("\(job.wholeBook ? "整本" : "部分页面") · \(status(job)) · 已下载 \(storageBytes(job.bytes))").font(.caption).foregroundStyle(.secondary)
                        }
                    }.disabled(job.pinned || manager.isRunning(job.id) || !["ready", "completed", "cancelled", "paused", "failed"].contains(job.status))
                    Toggle("离线保留", isOn: Binding(get: { job.pinned }, set: { value in
                        do { try manager.setPinned(value, id: job.id, ownerID: owner); if value { selected.remove(job.id) } }
                        catch { message = error.localizedDescription }
                    })).font(.subheadline)
                    if manager.isRunning(job.id) { Button("暂停并保留进度") { manager.pause(job.id) } }
                    else if ["paused", "failed"].contains(job.status) { Button("继续下载") { manager.resume(job.id) } }
                }
            }
            if jobs.isEmpty { ContentUnavailableView("暂无本账号下载记录", systemImage: "arrow.down.circle") }
            Button("移除所选本地下载", role: .destructive) { confirming = true }.disabled(selected.isEmpty)
        }.navigationTitle("模板与素材下载")
            .task { await manager.waitUntilRestored() }
            .confirmationDialog("移除所选 \(selected.count) 项下载？", isPresented: $confirming, titleVisibility: .visible) {
                Button("移除本地下载", role: .destructive) {
                    do { try manager.removeDownloads(selected, ownerID: owner); selected = [] }
                    catch { message = error.localizedDescription }
                }
            } message: { Text("已完整导入手帐的内容会保留。移除会丢失离线资源及所选未完成下载的断点；再次下载需要联网，资源下架后可能无法获取。") }
            .alert("未能移除下载", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("好") { message = nil } } message: { Text(message ?? "") }
    }
    private func status(_ job: PresetDownloadJob) -> String {
        switch job.status {
        case "ready", "completed": "已下载"
        case "paused": "已暂停"
        case "failed": "下载失败"
        case "cancelled": "已取消"
        default: "任务进行中"
        }
    }
}

private struct StoragePolicyScreen: View {
    let owner: String
    let service: StorageService
    @State private var policy = StoragePolicy()
    @State private var loaded = false
    @State private var message: String?
    var body: some View {
        List {
            Section("自动缓存") {
                Picker("缓存容量上限", selection: $policy.previewLimit) {
                    ForEach(StoragePolicy.cacheCapacities, id: \.self) { bytes in
                        Text(storageBytes(bytes)).tag(bytes)
                    }
                }
                Text("达到容量后自动移除最久未使用的缓存。再次查看时会重新获取。已下载资源、手帐和草稿会保留；使用中的缓存将在释放后整理。")
                    .font(.caption).foregroundStyle(.secondary)
                if let message { Text(message).foregroundStyle(.orange) }
            }
            Section("导出副本整理") {
                Toggle("打开存储空间时自动整理", isOn: $policy.automaticallyManageSafeFiles)
                Text("开启后，在存储页刷新时移除超过 7 天且源作品仍在的已完成导出副本。缓存容量限制始终生效。")
                    .font(.caption).foregroundStyle(.secondary)
                if let message { Text(message).foregroundStyle(.orange) }
            }
            Section("清理规则") {
                Text("作品、草稿、下载包、相机唯一产物和最近删除不参加自动清理。")
                Text("安全清理预览会推荐当前账号可重建缓存，以及超过 7 天、源手帐仍存在的已完成导出副本。系统也可能自行回收缓存和临时文件。")
            }
            Section("目录与账号") {
                Text("所有模块直接使用统一目录规范。账号资料、共享下载、缓存和临时任务分别存放；未识别或正在使用的资料保持保留。")
                Text("其他账号仅展示汇总大小；切换对应账号后才能管理。退出登录不会删除作品。")
            }
            Section("统计说明") {
                Text("容量按文件字节数估算，1 GB = 1,000,000,000 字节。不含安装包、系统相册及已导出到其他位置的文件。压缩、克隆及系统回收会使设备实际可用空间变化与估算不同。")
                Text("登录和 OSS 上传成功不代表手帐已具备云端备份。请保留原件，当前不提供仅留云端或云空间扩容。")
            }
        }.navigationTitle("缓存与空间设置")
            .task { policy = await service.policy(); loaded = true }
            .onChange(of: policy) { _, value in
                guard loaded else { return }
                Task { do { try await service.savePolicy(value, owner: owner) } catch { message = error.localizedDescription } }
            }
    }
}

private func storageBytes(_ value: Int64) -> String {
    if value > 0 && value < 1_000_000 { return "小于 1 MB" }
    if value == 0 { return "0 MB" }
    return ByteCountFormatter.string(fromByteCount: value, countStyle: .decimal)
}

private struct StorageExportPreview: UIViewControllerRepresentable {
    let url: URL
    func makeCoordinator() -> Coordinator { Coordinator(url: url) }
    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: QLPreviewController, context: Context) {}
    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> any QLPreviewItem { url as NSURL }
    }
}
