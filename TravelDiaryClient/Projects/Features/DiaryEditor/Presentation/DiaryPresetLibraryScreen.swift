import SwiftUI
import ImageIO

/// 预设浏览全程只读；只有“添加”成功后才进入用户自己的本子。
struct DiaryPresetLibraryScreen: View {
    let ownerID: String
    var targetBook: DiaryBook? = nil
    var targetAfterPageID: UUID? = nil
    @ObservedObject private var downloads = PresetDownloadManager.shared
    @State private var remote: RemotePresetCatalog?
    @State private var pending: DiaryPresetImportIntent?
    @State private var resuming: DiaryPresetImportIntent?
    @State private var recovered: DiaryBook?
    @State private var catalog: DiaryPresetCatalog?
    @State private var selectedSeries = ""
    @State private var search = ""
    @State private var reload = 0
    @State private var error: String?
    var body: some View {
        VStack {
            if let catalog {
                if let pending {
                    HStack {
                        Text("有未完成的预设导入").font(.caption)
                        Button("继续") { resuming = pending }
                        Button("暂不处理") { self.pending = nil }
                    }.padding()
                }
                Picker("系列", selection: $selectedSeries) {
                    Text("全部").tag("")
                    ForEach(combinedSeries(catalog)) { Text($0.title).tag($0.id) }
                }.pickerStyle(.segmented).padding(.horizontal)
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 20) {
                        ForEach(catalog.books.filter { book in
                            (selectedSeries.isEmpty || book.manifest.seriesID == selectedSeries) &&
                            (search.isEmpty || (book.manifest.title + (book.manifest.tags ?? []).joined()).localizedCaseInsensitiveContains(search))
                        }) { package in
                            // 书库既可位于根 Tab，也可从手帐详情进入。
                            // 直接提供目的地，避免 Tab 子树中的值路由注册对外层导航栈不可见。
                            NavigationLink {
                                DiaryPresetDetailScreen(ownerID: ownerID, package: package, targetBook: targetBook,
                                                        targetAfterPageID: targetAfterPageID) { book in recovered = book }
                            } label: {
                                VStack(alignment: .leading) {
                                    DiaryPresetCover(package: package)
                                    Text(package.manifest.title).font(.headline)
                                    Text("\(package.manifest.pages.count) 页").font(.caption).foregroundStyle(.secondary)
                                }
                            }.buttonStyle(.plain)
                        }
                        ForEach((remote?.books ?? []).filter { book in
                            !catalog.books.contains(where: { $0.id == book.id }) &&
                            (selectedSeries.isEmpty || book.series == selectedSeries) &&
                            (search.isEmpty || book.title.localizedCaseInsensitiveContains(search))
                        }) { book in
                            NavigationLink {
                                RemotePresetDetailScreen(ownerID: ownerID, book: book, targetBook: targetBook,
                                    afterPageID: targetAfterPageID) { recovered = $0 }
                            } label: {
                                VStack(alignment: .leading) {
                                    AsyncImage(url: URL(string: book.cover_url)) { image in image.resizable().scaledToFit() }
                                        placeholder: { Color.gray.opacity(0.1).aspectRatio(0.7, contentMode: .fit).overlay { ProgressView() } }
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                    HStack {
                                        Text(book.title).font(.headline)
                                        PresetBookAvailabilityBadge(downloadedCount: min(book.page_count, downloads.downloadedPageIDs(bookID: book.id, version: book.version).count), totalCount: book.page_count)
                                    }
                                    Text("\(book.page_count) 页").font(.caption).foregroundStyle(.secondary)
                                }
                            }.buttonStyle(.plain)
                        }
                    }.padding()
                    if !catalog.issues.isEmpty {
                        Text("部分预设暂不可用：\n" + catalog.issues.joined(separator: "\n"))
                            .font(.caption).foregroundStyle(.secondary).padding()
                    }
                    if !(remote?.books.contains(where: { (selectedSeries.isEmpty || $0.series == selectedSeries) && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)) }) ?? false) && !catalog.books.contains(where: { (selectedSeries.isEmpty || $0.manifest.seriesID == selectedSeries) && (search.isEmpty || ($0.manifest.title + ($0.manifest.tags ?? []).joined()).localizedCaseInsensitiveContains(search)) }) {
                        ContentUnavailableView("暂无匹配的预设", systemImage: "books.vertical")
                        Button("查看全部") { selectedSeries = ""; search = "" }
                    }
                }
            } else if let error { VStack { Text(error); Button("重试") { reload += 1 } } }
            else { ProgressView("正在读取预设…") }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { PresetDownloadCenter(ownerID: ownerID) } label: { Image(systemName: "arrow.down.circle").accessibilityLabel("下载管理") }
            }
        }
        .refreshable { remote = try? await downloads.catalog() }
        .searchable(text: $search, prompt: "搜索预设本")
        .sheet(item: $resuming) { intent in
            if let package = catalog?.books.first(where: { $0.id == intent.templateID && $0.manifest.packageVersion == intent.version }) {
                DiaryPresetImportSheet(ownerID: ownerID, package: package, pageIDs: intent.pageIDs, defaultTarget: nil,
                                       wholeBook: intent.wholeBook, resume: intent) { book in
                    resuming = nil; pending = nil; recovered = book
                }
            } else { Text("该版本预设暂不可用，导入记录已保留。").padding() }
        }
        .navigationDestination(isPresented: Binding(get: { recovered != nil }, set: { if !$0 { recovered = nil } })) {
            if let recovered { DiaryBookScreen(ownerID: ownerID, book: recovered) }
        }
        .task(id: reload) {
            downloads.activate(owner: ownerID)
            pending = DiaryPresetImportIntent.read(owner: ownerID)
            do { catalog = try await Task.detached { try BundleDiaryPresetProvider().catalog() }.value }
            catch { self.error = error.localizedDescription }
            do { remote = try await downloads.catalog() }
            catch { /* Local templates remain available when the network is unavailable. */ }
        }
    }
    private func combinedSeries(_ catalog: DiaryPresetCatalog) -> [DiaryPresetSeries] {
        var result = catalog.series
        for entry in remote?.series ?? [] where !result.contains(where: { $0.id == entry.slug }) {
            result.append(DiaryPresetSeries(id: entry.slug, title: entry.title, directory: entry.slug, sortOrder: result.count))
        }
        return result
    }
}
struct DiaryPresetCover: View {
    let package: DiaryPresetPackage
    @State private var page: PresetPage?
    var body: some View {
        Group {
            if let page { DiaryPresetImage(package: package, path: page.preview.thumbnailPath, size: page.size.cg) }
            else { Rectangle().fill(.gray.opacity(0.1)).aspectRatio(0.7, contentMode: .fit).overlay { ProgressView() } }
        }.task {
            page = try? await Task.detached { try package.pages.first { $0.id == package.manifest.coverPageID } }.value
        }
    }
}
private struct DiaryPresetImage: View {
    let package: DiaryPresetPackage
    let path: String
    let size: CGSize
    @State private var image: UIImage?
    @State private var failed = false
    @State private var retry = 0
    var body: some View {
        ZStack {
            Color(uiColor: .secondarySystemGroupedBackground)
            if let image { Image(uiImage: image).resizable().scaledToFit() }
            else if failed { Button("重试预览") { retry += 1 } }
            else { ProgressView() }
        }.aspectRatio(size.width / size.height, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 10))
            .task(id: "\(path)-\(retry)") {
                do {
                    let data = try await Task.detached { try Data(contentsOf: package.url(path)) }.value
                    image = UIImage(data: data); failed = image == nil
                } catch { failed = true }
            }
    }
}
private struct PresetSelection: Identifiable { let id = UUID(); let pageIDs: [String]; var wholeBook = false }
private struct DiaryPresetDetailScreen: View {
    let ownerID: String
    let package: DiaryPresetPackage
    let targetBook: DiaryBook?
    let targetAfterPageID: UUID?
    @State private var pages: [PresetPage] = []
    @State private var previewPage: String?
    @State private var showingPreview = false
    @State private var selection: PresetSelection?
    let onImported: (DiaryBook) -> Void
    @State private var error: String?
    @State private var validated = false
    @State private var photoSlots = 0
    @State private var textSlots = 0
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("\(pages.count) 页 · \(Int(package.manifest.pageSize.width)) × \(Int(package.manifest.pageSize.height))")
                Text("可替换照片 \(photoSlots) 处 · 可编辑文字 \(textSlots) 处。图片文字保持为装饰。").font(.caption).foregroundStyle(.secondary)
                if (package.manifest.requiredFonts ?? []).contains(where: { !DiaryFontCatalog.shared.available($0) }) {
                    Text("此预设的部分字体暂不可用，导入后将临时使用系统字体，排版可能与预览不同。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button("整本添加到我的") { selection = PresetSelection(pageIDs: pages.map(\.id), wholeBook: true) }
                    .buttonStyle(.borderedProminent).disabled(pages.isEmpty || !validated)
                DiaryPageListGrid(pages: pages, shellID: package.manifest.shellPageID,
                                  coverID: package.manifest.coverPageID) { page in
                        VStack {
                            Button { previewPage = page.id; showingPreview = true } label: {
                                DiaryPresetImage(package: package, path: page.preview.thumbnailPath, size: page.size.cg)
                            }
                            Text(page.title).font(.caption)
                            Button("使用这一页") { selection = PresetSelection(pageIDs: [page.id]) }.disabled(!validated)
                        }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }.padding()
        }.navigationTitle(package.manifest.title)
            .task {
                do {
                    pages = try await Task.detached { try package.pages }.value
                    let counts = try await Task.detached {
                        try package.validate()
                        let ids = Dictionary(uniqueKeysWithValues: package.manifest.assetTable.keys.map { ($0, UUID()) })
                        var photoCount = 0; var textCount = 0
                        for page in try package.pages {
                            let document = try package.instantiate(page, bookID: UUID(), targetSize: page.size.cg, assetIDs: ids)
                            photoCount += document.objects.values.flatMap(\.layers).filter { $0.kind == .photo }.count
                            textCount += document.objects.values.flatMap(\.layers).filter { $0.kind == .text }.count
                        }
                        return (photoCount, textCount)
                    }.value
                    photoSlots = counts.0; textSlots = counts.1; validated = true
                }
                catch { self.error = error.localizedDescription }
            }
            .fullScreenCover(isPresented: $showingPreview) {
                NavigationStack {
                    TabView(selection: $previewPage) {
                        ForEach(pages) { page in
                            VStack {
                                if abs((pages.firstIndex { $0.id == page.id } ?? 0) - (pages.firstIndex { $0.id == previewPage } ?? 0)) <= 1 {
                                    DiaryPresetImage(package: package, path: page.preview.largePath, size: page.size.cg)
                                } else { Color.clear }
                                Text(page.title)
                            }.padding().tag(Optional(page.id))
                        }
                    }.tabViewStyle(.page).navigationTitle("\((pages.firstIndex { $0.id == previewPage } ?? 0) + 1) / \(pages.count)")
                        .toolbar { Button("完成") { showingPreview = false } }
                        .safeAreaInset(edge: .bottom) {
                            Button("使用这一页") {
                                if let previewPage { showingPreview = false; selection = PresetSelection(pageIDs: [previewPage]) }
                            }.buttonStyle(.borderedProminent).padding()
                        }
                }
            }
            .sheet(item: $selection) { value in
                DiaryPresetImportSheet(ownerID: ownerID, package: package, pageIDs: value.pageIDs,
                                       defaultTarget: value.wholeBook ? nil : targetBook, wholeBook: value.wholeBook, defaultAfterPageID: targetAfterPageID) { book in
                    selection = nil; onImported(book)
                }
            }
    }
}
private nonisolated struct PresetPhotoSlotPreview: Identifiable, Sendable {
    let id: UUID
    let name: String
    let image: UIImage?
}

struct DiaryPresetImportSheet: View {
    let ownerID: String
    let package: DiaryPresetPackage
    let pageIDs: [String]
    let defaultTarget: DiaryBook?
    let wholeBook: Bool
    var defaultAfterPageID: UUID? = nil
    var resume: DiaryPresetImportIntent? = nil
    var remoteBook: RemotePresetBook? = nil
    let completed: (DiaryBook) -> Void
    @ObservedObject private var downloads = PresetDownloadManager.shared
    @State private var downloadID: UUID?
    @State private var readyPackage: DiaryPresetPackage?
    @State private var planning = false
    @State private var step = 1
    @State private var showingPhotos = false
    @State private var replacementPhotos: [URL] = []
    @State private var photoSlots: [PresetPhotoSlotPreview] = []
    @State private var previewReady = false
    @State private var preparationDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("preset-photos-" + UUID().uuidString)
    private var singlePage: Bool { !wholeBook && pageIDs.count == 1 }
    private var availablePackage: DiaryPresetPackage? { remoteBook == nil ? package : readyPackage }
    private var previewIdentity: String { availablePackage?.root.path ?? "waiting" }
    @Environment(\.dismiss) private var dismiss
    @State private var books: [DiaryBook] = []
    @State private var targetID: UUID?
    @State private var afterPageID: UUID?
    @State private var title = ""
    @State private var operationID = UUID()
    @State private var busy = false
    @State private var error: String?
    @State private var preview: PresetPage?
    @State private var progress = ""
    @State private var cancellation = DiaryPresetCancellation()
    private var target: DiaryBook? { books.first { $0.id == targetID } }
    var body: some View {
        NavigationStack {
            Form {
                Text(singlePage ? "第 \(step) 步 / 3 · \(step == 1 ? "预览单页" : step == 2 ? "选择照片" : "选择帐本")" : "添加 \(pageIDs.count) 页")
                if singlePage && step == 1, let availablePackage {
                    if let preview {
                        Section {
                            DiaryPresetImage(package: availablePackage, path: preview.preview.largePath, size: preview.size.cg)
                                .listRowInsets(EdgeInsets())
                            Text(preview.title).font(.headline)
                        }
                        Section("一键替换照片 · \(photoSlots.count) 张") {
                            if photoSlots.isEmpty {
                                Text("这一页没有可一键替换的照片，下一步可保留原图继续。")
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(photoSlots) { slot in
                                HStack {
                                    if let image = slot.image { Image(uiImage: image).resizable().scaledToFit().frame(width: 60, height: 80) }
                                    else { Image(systemName: "photo").frame(width: 60, height: 80) }
                                    Text(slot.name)
                                }
                            }
                        }
                    } else if !previewReady { ProgressView("正在读取页面…") }
                }
                if remoteBook != nil && (!singlePage || step == 1) {
                    Section {
                        if let job = downloads.jobs.first(where: { $0.id == downloadID }) {
                            ProgressView(value: Double(job.bytes), total: Double(max(1, job.total)))
                            Text(readyPackage == nil ? "正在准备资源 · \(Int(min(1, Double(job.bytes) / Double(max(1, job.total))) * 100))%" : "资源已下载，可以添加")
                            if let error = job.error { Text(error).foregroundStyle(.red) }
                            HStack {
                                if ["queued", "downloading", "verifying"].contains(job.status) { Button("暂停下载") { downloads.pause(job.id) } }
                                if ["paused", "failed"].contains(job.status) { Button("继续下载") { downloads.resume(job.id) } }
                            }
                        } else if planning { ProgressView("正在获取资源清单…") }
                        else if readyPackage != nil { Label("资源已下载，可以添加", systemImage: "checkmark.circle.fill") }
                        else { Button("下载资源") { Task { await prepareRemote() } } }
                    }
                }
                if !singlePage || step == 3 {
                if singlePage { Text(replacementPhotos.isEmpty ? "保留原照片" : "已选择 \(replacementPhotos.count) 张替换照片").foregroundStyle(.secondary) }
                if !wholeBook {
                    Picker("添加到", selection: $targetID) {
                        Text("新建手帐本").tag(Optional<UUID>.none)
                        ForEach(books) { Text($0.title).tag(Optional($0.id)) }
                    }.onChange(of: targetID) { _, _ in afterPageID = nil; operationID = UUID() }
                }
                if let target {
                    Picker("插入位置", selection: $afterPageID) {
                        Text("末尾").tag(Optional<UUID>.none)
                        ForEach(Array(target.pages.enumerated()), id: \.element.id) { index, page in
                            Text("第 \(index + 1) 页之后").tag(Optional(page.id))
                        }
                    }
                    if target.defaultPageSize != package.manifest.pageSize.cg {
                        Text("纸张比例不同，将等比居中完整放入，四周可能留透明空白。")
                        if let preview {
                            GeometryReader { proxy in
                                let s = min(proxy.size.width / preview.size.width, proxy.size.height / preview.size.height)
                                ZStack {
                                    Color.gray.opacity(0.12)
                                    DiaryPresetImage(package: readyPackage ?? package, path: preview.preview.thumbnailPath, size: preview.size.cg)
                                        .frame(width: preview.size.width * s, height: preview.size.height * s)
                                }.frame(width: proxy.size.width, height: proxy.size.height)
                            }.aspectRatio(target.defaultPageSize.width / target.defaultPageSize.height, contentMode: .fit)
                        }
                    }
                } else { TextField("手帐名称", text: $title) }
                }
                if let error { Text(error).foregroundStyle(.red) }
                if busy { ProgressView(progress.isEmpty ? "正在校验资源…" : progress) }
            }.disabled(busy).navigationTitle(singlePage ? "添加单页" : "添加预设")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(busy ? "取消导入" : "取消") { if busy { cancellation.cancel() } else { cleanupPhotos(); dismiss() } } }
                    ToolbarItem(placement: .confirmationAction) {
                        if singlePage && step < 3 {
                            Button("下一步") { step = 2; showingPhotos = true }
                                .disabled(busy || !previewReady || availablePackage == nil)
                        } else {
                            Button("添加") { Task { await runImport() } }.disabled(busy || (remoteBook != nil && readyPackage == nil) || (targetID == nil && title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                        }
                    }
                    ToolbarItem(placement: .bottomBar) {
                        if singlePage && step == 3 {
                            Button("上一步：选择照片") { step = 2; showingPhotos = true }.disabled(busy)
                        }
                    }
                }.onChange(of: downloads.jobs) { _, _ in
                    if let downloadID { readyPackage = downloads.preparedPackage(downloadID) }
                }.interactiveDismissDisabled(busy)
                .task(id: previewIdentity) { await preparePreview() }
                .sheet(isPresented: $showingPhotos, onDismiss: { if step == 2 { step = 1 } }) {
                    if let availablePackage {
                        DiaryBatchPhotoSheet(store: DiaryDocumentStore(ownerID: ownerID), preset: availablePackage,
                            presetPageIDs: pageIDs, preparationDirectory: preparationDirectory, onPrepared: { files in
                                for old in replacementPhotos { try? FileManager.default.removeItem(at: old) }
                                replacementPhotos = files; operationID = UUID(); step = 3; showingPhotos = false
                            })
                    }
                }
                .onDisappear { if !showingPhotos && !busy { cleanupPhotos() } }
                .task {
                    title = package.manifest.title
                    await prepareRemote()

                    do {
                        books = try await DiaryDocumentStore(ownerID: ownerID).listBooks()
                        if let resume {
                            targetID = resume.targetID; afterPageID = resume.afterPageID; title = resume.title
                        } else { targetID = defaultTarget?.id; afterPageID = defaultAfterPageID }
                    }
                    catch { self.error = error.localizedDescription }
                }
        }
    }
    private func cleanupPhotos() {
        try? FileManager.default.removeItem(at: preparationDirectory)
    }
    private func preparePreview() async {
        previewReady = false
        guard let availablePackage else { return }
        do {
            let ids = pageIDs
            let value = try await Task.detached {
                let page = try availablePackage.pages.first { $0.id == ids.first }
                guard let page else { throw DiaryEditorError.invalidDocument }
                let assetIDs = Dictionary(uniqueKeysWithValues: availablePackage.manifest.assetTable.keys.map { ($0, UUID()) })
                let document = try availablePackage.instantiate(page, bookID: UUID(), targetSize: page.size.cg, assetIDs: assetIDs)
                let paths = Dictionary(uniqueKeysWithValues: availablePackage.manifest.assetTable.compactMap { key, asset in
                    assetIDs[key].map { ($0, asset.path) }
                })
                let slots = try document.replaceablePhotos().map { layer -> PresetPhotoSlotPreview in
                    var image: UIImage?
                    if let id = layer.assetID, let path = paths[id],
                       let source = CGImageSourceCreateWithURL(try availablePackage.url(path) as CFURL, nil),
                       let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: 180
                       ] as CFDictionary) { image = UIImage(cgImage: cg) }
                    return PresetPhotoSlotPreview(id: layer.id, name: layer.name, image: image)
                }
                return (page, slots)
            }.value
            try Task.checkCancellation()
            preview = value.0; photoSlots = value.1; previewReady = true
        } catch is CancellationError { }
        catch { self.error = error.localizedDescription }
    }
    private func prepareRemote() async {
        guard let remoteBook else { return }
        downloads.activate(owner: ownerID)
        if let cached = downloads.cachedPackage(bookID: remoteBook.id, version: remoteBook.version, pageIDs: pageIDs) {
            readyPackage = cached; return
        }
        guard downloadID == nil, !planning else { return }
        planning = true
        defer { planning = false }
        do {
            downloadID = try await downloads.enqueue(book: remoteBook, pageIDs: wholeBook ? nil : pageIDs,
                owner: ownerID, target: nil, after: nil, downloadOnly: true)
            if let downloadID { readyPackage = downloads.preparedPackage(downloadID) }
        } catch { self.error = error.localizedDescription }
    }
    private func runImport() async {
        guard !busy else { return }; busy = true
        defer { busy = false }
        do {
            if let resume { operationID = resume.id }
            if let old = DiaryPresetImportIntent.read(owner: ownerID), old.templateID == package.id,
               old.pageIDs == pageIDs, old.targetID == targetID, old.afterPageID == afterPageID, old.title == title,
               old.version == package.manifest.packageVersion { operationID = old.id }
            cancellation = DiaryPresetCancellation()
            let intent = DiaryPresetImportIntent(id: operationID, templateID: package.id, version: package.manifest.packageVersion,
                  pageIDs: pageIDs, wholeBook: wholeBook, targetID: targetID, afterPageID: afterPageID, title: title)
            try intent.save(owner: ownerID)
            let result = try await DiaryDocumentStore(ownerID: ownerID, bookID: targetID).importPreset(readyPackage ?? package, pageIDs: pageIDs, title: title,
                    operationID: operationID, replacementPhotos: replacementPhotos, afterPageID: afterPageID, expectedRevision: target?.catalogRevision, progress: { value in
                        Task { @MainActor in progress = value }
                    }, cancellation: cancellation)
            DiaryPresetImportIntent.clear(owner: ownerID)
            cleanupPhotos()
            completed(result)
        } catch is CancellationError {
            DiaryPresetImportIntent.clear(owner: ownerID)
            self.error = "已取消，未添加页面。"
        } catch {
            self.error = error.localizedDescription
            books = (try? await DiaryDocumentStore(ownerID: ownerID).listBooks()) ?? books
        }
    }
}
