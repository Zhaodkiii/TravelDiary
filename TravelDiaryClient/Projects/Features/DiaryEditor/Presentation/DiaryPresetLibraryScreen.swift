import SwiftUI
import ImageIO

/// 浏览只读取预览；使用动作继续复用原有下载与导入事务。
struct DiaryPresetLibraryScreen: View {
    let ownerID: String
    var targetBook: DiaryBook? = nil
    var targetAfterPageID: UUID? = nil
    var singlePageOnly = false
    var onPageAdded: ((DiaryBook) -> Void)? = nil
    private let downloads = PresetDownloadManager.shared
    @ObservedObject private var availability = PresetDownloadManager.shared.availability
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var remote: RemotePresetCatalog?
    @State private var pending: DiaryPresetImportIntent?
    @State private var resuming: DiaryPresetImportIntent?
    @State private var recovered: DiaryBook?
    @State private var selectedSeries = ""
    @State private var search = ""
    @State private var reload = 0
    @State private var remoteError: String?
    @State private var remoteFinished = false
    @State private var onlyDownloaded = false
    @State private var styles: Set<String> = []
    @State private var usages: Set<String> = []
    @State private var draftStyles: Set<String> = []
    @State private var draftUsages: Set<String> = []
    @State private var showingFilters = false
    private var items: [PresetLibraryItem] { PresetLibraryItem.merge(local: [], remote: remote?.books ?? []) }
    private var results: [PresetLibraryItem] {
        items.filter { $0.matches(search: search, series: selectedSeries, styles: styles, usages: usages) && (!onlyDownloaded || isAvailable($0)) }
    }
    private var allStyles: [String] { Array(Set(items.flatMap(\.styles))).sorted() }
    private var allUsages: [String] { Array(Set(items.flatMap(\.usages))).sorted() }
    private var series: [DiaryPresetSeries] {
        var result: [DiaryPresetSeries] = []
        for entry in remote?.series ?? [] where !result.contains(where: { $0.id == entry.slug }) {
            result.append(DiaryPresetSeries(id: entry.slug, title: entry.title, directory: entry.slug, sortOrder: result.count))
        }
        return result
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if singlePageOnly {
                    Text("为「\(targetBook?.title ?? "当前手帐")」挑选一页").font(.headline)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("下一段旅途，从这里开始").font(.title2.weight(.semibold))
                        Text("翻一翻，找到适合你的那一本。").font(.subheadline).foregroundStyle(DiaryLibraryStyle.secondary)
                    }
                }
                DiaryLibrarySearch(text: $search, prompt: "搜索模板名称")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        DiaryLibraryChip(title: "全部", selected: selectedSeries.isEmpty) { selectedSeries = "" }
                        ForEach(series) { entry in
                            DiaryLibraryChip(title: entry.title, selected: selectedSeries == entry.id) { selectedSeries = entry.id }
                        }
                    }
                }
                filterBar
                if let pending, !singlePageOnly {
                    DiaryLibraryNotice(message: "有未完成的模板导入", actionTitle: "继续导入") { resuming = pending }
                }
                if let remoteError { DiaryLibraryNotice(message: remoteError) { reload += 1 } }

                HStack {
                    Text("\(results.count) 本模板").font(.subheadline).foregroundStyle(DiaryLibraryStyle.secondary)
                    Spacer()
                    if !search.isEmpty || !selectedSeries.isEmpty || onlyDownloaded || !styles.isEmpty || !usages.isEmpty {
                        Button("清空条件") { search = ""; selectedSeries = ""; onlyDownloaded = false; styles = []; usages = [] }.frame(minHeight: 44)
                    }
                }
                if items.isEmpty && !remoteFinished {
                    ProgressView("正在寻找旅行灵感…").frame(maxWidth: .infinity).padding(48)
                } else if results.isEmpty {
                    ContentUnavailableView("暂无匹配的模板", systemImage: "books.vertical", description: Text("试试其他分类，或清空筛选条件。"))
                } else {
                    LazyVGrid(columns: typeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.adaptive(minimum: 280), spacing: 24)], alignment: .leading, spacing: 32) {
                        ForEach(results) { item in
                            NavigationLink { destination(item) } label: { magazineCard(item) }.buttonStyle(.plain)
                        }
                    }
                }
            }.frame(maxWidth: 1200).padding(20).frame(maxWidth: .infinity)
        }
        .background(DiaryLibraryStyle.background).foregroundStyle(DiaryLibraryStyle.ink).tint(DiaryLibraryStyle.accent)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(singlePageOnly ? "选择模板" : "旅行模板")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { PresetDownloadCenter(ownerID: ownerID) } label: { Image(systemName: "arrow.down.circle").accessibilityLabel("下载管理") }
            }
        }
        .refreshable { await loadRemote() }
        .sheet(isPresented: $showingFilters) { filterSheet }
        .sheet(item: $resuming) { intent in
            if let package = downloads.cachedPackage(bookID: intent.templateID, version: intent.version, pageIDs: intent.pageIDs) {
                DiaryPresetImportSheet(ownerID: ownerID, package: package, pageIDs: intent.pageIDs, defaultTarget: nil,
                                       wholeBook: intent.wholeBook, resume: intent) { book in
                    resuming = nil; pending = nil; recovered = book
                }
            } else {
                NavigationStack {
                    ContentUnavailableView("模板资源暂不可用", systemImage: "arrow.down.circle", description: Text("导入记录已保留，请在下载管理中恢复资源后再试。"))
                        .toolbar { Button("完成") { resuming = nil } }
                }
            }
        }
        .navigationDestination(isPresented: Binding(get: { recovered != nil }, set: { if !$0 { recovered = nil } })) {
            if let recovered { DiaryBookScreen(ownerID: ownerID, book: recovered) }
        }
        .task(id: reload) {
            downloads.activate(owner: ownerID)
            pending = DiaryPresetImportIntent.read(owner: ownerID)
        }
        .task(id: reload) {
            if remote == nil { remote = await Task.detached { PresetLibraryCatalogCache.read(ownerID: ownerID) }.value }
            await loadRemote()
        }
    }
    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                DiaryLibraryChip(title: "可离线使用", selected: onlyDownloaded) { onlyDownloaded.toggle() }
                if !allStyles.isEmpty || !allUsages.isEmpty {
                    DiaryLibraryChip(title: "风格与用途\(styles.isEmpty && usages.isEmpty ? "" : " · \(styles.count + usages.count)")", selected: !styles.isEmpty || !usages.isEmpty) {
                        draftStyles = styles; draftUsages = usages; showingFilters = true
                    }
                }
            }
        }
    }
    private var filterSheet: some View {
        NavigationStack {
            List {
                if !allStyles.isEmpty { Section("风格") { ForEach(allStyles, id: \.self) { filterRow($0, selection: $draftStyles) } } }
                if !allUsages.isEmpty { Section("用途") { ForEach(allUsages, id: \.self) { filterRow($0, selection: $draftUsages) } } }
                Button("重置") { draftStyles = []; draftUsages = [] }
            }.navigationTitle("挑选适合你的模板")
                .toolbar { Button("取消") { showingFilters = false } }
                .safeAreaInset(edge: .bottom) {
                    Button("查看结果") { styles = draftStyles; usages = draftUsages; showingFilters = false }
                        .buttonStyle(.borderedProminent).controlSize(.large).padding().frame(maxWidth: .infinity).background(.regularMaterial)
                }
        }.tint(DiaryLibraryStyle.accent)
    }
    private func filterRow(_ title: String, selection: Binding<Set<String>>) -> some View {
        Button {
            if selection.wrappedValue.contains(title) { selection.wrappedValue.remove(title) }
            else { selection.wrappedValue.insert(title) }
        } label: {
            HStack { Text(title); Spacer(); if selection.wrappedValue.contains(title) { Image(systemName: "checkmark") } }
        }.accessibilityAddTraits(selection.wrappedValue.contains(title) ? [.isSelected] : [])
    }
    private func isAvailable(_ item: PresetLibraryItem) -> Bool {
        if item.local != nil { return true }
        guard let remote = item.remote else { return false }
        // Read the published index so completed downloads invalidate this filter.
        return remote.page_count > 0
            && availability.downloadedPageIDs(bookID: remote.id, version: remote.version).count >= remote.page_count
            && downloads.completeCachedPackage(for: remote) != nil
    }
    private func magazineCard(_ item: PresetLibraryItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            DiaryPresetMagazinePreview(item: item, ownerID: ownerID)
            Text(item.title).font(.title3.weight(.semibold)).lineLimit(typeSize.isAccessibilitySize ? nil : 2)
            ViewThatFits(in: .horizontal) {
                HStack { metadata(item); Spacer(); availabilityLabel(item) }
                VStack(alignment: .leading, spacing: 6) { metadata(item); availabilityLabel(item) }
            }
            if !item.tags.isEmpty {
                Text(item.tags.joined(separator: " · ")).font(.caption).foregroundStyle(DiaryLibraryStyle.secondary)
            }
            HStack { Text("翻看这本模板"); Image(systemName: "arrow.right") }
                .font(.subheadline.weight(.medium)).foregroundStyle(DiaryLibraryStyle.accent).frame(minHeight: 44)
        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
    }
    private func metadata(_ item: PresetLibraryItem) -> some View {
        Text("\(series.first { $0.id == item.series }?.title ?? "旅行模板") · \(item.pageLabel)")
            .font(.caption).foregroundStyle(DiaryLibraryStyle.secondary)
    }
    @ViewBuilder private func availabilityLabel(_ item: PresetLibraryItem) -> some View {
        if item.local != nil { Label("内置可用", systemImage: "checkmark.circle").font(.caption).foregroundStyle(DiaryLibraryStyle.secondary) }
        else if let remote = item.remote {
            PresetBookAvailabilityBadge(downloadedCount: min(remote.page_count, availability.downloadedPageIDs(bookID: remote.id, version: remote.version).count), totalCount: remote.page_count)
        }
    }
    private func destination(_ item: PresetLibraryItem) -> some View {
        DiaryStablePresetDestination(item: item, ownerID: ownerID,
            seriesTitle: series.first { $0.id == item.series }?.title ?? "旅行模板",
            targetBook: targetBook, targetAfterPageID: targetAfterPageID,
            fixedTarget: singlePageOnly, onImported: imported)
    }
    private func imported(_ book: DiaryBook) {
        if let onPageAdded { onPageAdded(book) } else { recovered = book }
    }
    private func loadRemote() async {
        do {
            let value = try await downloads.catalog()
            try Task.checkCancellation()
            remote = value; remoteError = nil
            await Task.detached { PresetLibraryCatalogCache.save(value, ownerID: ownerID) }.value
        } catch is CancellationError { return }
        catch { remoteError = "在线模板暂时无法更新，请重试；已下载的资源可在下载管理中使用。" }
        remoteFinished = true
    }
}

struct DiaryRemoteCover: View {
    let url: URL?
    @State private var retry = 0
    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image): image.resizable().scaledToFit()
            case .failure:
                VStack(spacing: 8) {
                    Image(systemName: "photo")
                    Text("预览暂不可用").font(.caption)
                    Button("重试预览") { retry += 1 }.frame(minHeight: 44)
                }.foregroundStyle(DiaryLibraryStyle.secondary)
            case .empty: ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            @unknown default: Image(systemName: "photo")
            }
        }.id("\(url?.absoluteString ?? "")-\(retry)")
    }
}

struct DiaryPresetCover: View {
    let package: DiaryPresetPackage
    @State private var page: PresetPage?
    @State private var failed = false
    @State private var retry = 0
    var body: some View {
        Group {
            if let page { DiaryPresetImage(package: package, path: page.preview.thumbnailPath, size: page.size.cg) }
            else if failed {
                VStack(spacing: 8) {
                    Image(systemName: "photo")
                    Text("预览暂不可用").font(.caption)
                    Button("重试预览") { retry += 1 }.frame(minHeight: 44)
                }.foregroundStyle(DiaryLibraryStyle.secondary)
            } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
        }.task(id: "\(package.root.path)-\(package.manifest.packageVersion)-\(retry)") {
            page = nil; failed = false
            do {
                let loaded = try await Task.detached {
                    guard let reference = package.manifest.pages.first(where: { $0.id == package.manifest.coverPageID }) else {
                        throw DiaryEditorError.missingResource
                    }
                    return try package.read(PresetPage.self, reference.path)
                }.value
                try Task.checkCancellation()
                page = loaded
            } catch is CancellationError { }
            catch { failed = true }
        }
    }
}
struct DiaryPresetImage: View {
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
            .task(id: "\(package.root.path)-\(path)-\(retry)") {
                image = nil; failed = false
                do {
                    let loaded = try await Task.detached {
                        let url = try package.url(path)
                        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                                kCGImageSourceCreateThumbnailFromImageAlways: true,
                                kCGImageSourceCreateThumbnailWithTransform: true,
                                kCGImageSourceThumbnailMaxPixelSize: path.contains("thumb") ? 960 : 2048
                              ] as CFDictionary) else { throw DiaryEditorError.invalidImage }
                        return UIImage(cgImage: cg)
                    }.value
                    try Task.checkCancellation()
                    image = loaded
                } catch is CancellationError { }
                catch { failed = true }
            }
    }
}
private struct PresetSelection: Identifiable, Hashable { let id = UUID(); let pageIDs: [String]; var wholeBook = false }
/// Keep both the reader type and its sheet state alive while availability changes.
private struct DiaryStablePresetDestination: View {
    @StateObject private var presentation: PresetReaderPresentation
    let ownerID: String
    let seriesTitle: String
    let targetBook: DiaryBook?
    let targetAfterPageID: UUID?
    let fixedTarget: Bool
    let onImported: (DiaryBook) -> Void

    init(item: PresetLibraryItem, ownerID: String, seriesTitle: String,
         targetBook: DiaryBook?, targetAfterPageID: UUID?, fixedTarget: Bool,
         onImported: @escaping (DiaryBook) -> Void) {
        _presentation = StateObject(wrappedValue: PresetReaderPresentation(item: item,
            cachedPackage: item.remote.flatMap { PresetDownloadManager.shared.completeCachedPackage(for: $0) }))
        self.ownerID = ownerID; self.seriesTitle = seriesTitle
        self.targetBook = targetBook; self.targetAfterPageID = targetAfterPageID
        self.fixedTarget = fixedTarget; self.onImported = onImported
    }

    var body: some View {
        switch presentation.source {
        case .local(let package):
            DiaryPresetReaderDestination(ownerID: ownerID, package: package, seriesTitle: seriesTitle,
                targetBook: targetBook, targetAfterPageID: targetAfterPageID,
                fixedTarget: fixedTarget, onImported: onImported)
        case .remote(let book):
            RemotePresetReaderDestination(ownerID: ownerID, book: book, seriesTitle: seriesTitle,
                targetBook: targetBook, afterPageID: targetAfterPageID,
                fixedTarget: fixedTarget, onImported: onImported)
        case nil:
            ContentUnavailableView("模板暂不可用", systemImage: "book.closed")
        }
    }
}

private struct DiaryPresetReaderDestination: View {
    let ownerID: String
    let package: DiaryPresetPackage
    let seriesTitle: String
    let targetBook: DiaryBook?
    let targetAfterPageID: UUID?
    var fixedTarget = false
    let onImported: (DiaryBook) -> Void
    @State private var error: String?
    @State private var pages: [PresetPage] = []
    @State private var retry = 0
    @State private var selection: PresetSelection?

    @State private var reading = true
    var body: some View {
        VStack(spacing: 0) {
            PresetMaterialLibraryLinks(templateID: package.id, templateVersion: package.manifest.packageVersion)
            Picker("展示方式", selection: $reading) {
                Text("翻阅").tag(true)
                Text("总览").tag(false)
            }.pickerStyle(.segmented).padding()
            if reading { readerContent }
            else {
                DiaryPresetDetailScreen(ownerID: ownerID, package: package, targetBook: targetBook,
                    targetAfterPageID: targetAfterPageID, fixedTarget: fixedTarget, onImported: onImported)
            }
        }.background(DiaryLibraryStyle.background).tint(DiaryLibraryStyle.accent)
            .navigationTitle(package.manifest.title)
    }
    private var readerContent: some View {
        Group {
            if !pages.isEmpty {
                DiaryPresetBookReader<DiaryPresetDetailScreen>(title: package.manifest.title,
                    pages: pages.compactMap { page in
                        guard let url = try? package.url(page.preview.largePath) else { return nil }
                        return DiaryPresetBookReader<DiaryPresetDetailScreen>.Page(id: page.id, url: url, size: page.size.cg,
                            thumbnailURL: try? package.url(page.preview.thumbnailPath))
                    },
                    shellID: package.manifest.shellPageID, seriesTitle: seriesTitle,
                    allowsWholeBook: !fixedTarget,
                    localPackage: package.manifest.layerSchemaVersion >= 2 ? package : nil, onAdd: { ids, whole in
                        selection = PresetSelection(pageIDs: ids, wholeBook: whole)
                    }) {
                        DiaryPresetDetailScreen(ownerID: ownerID, package: package, targetBook: targetBook,
                            targetAfterPageID: targetAfterPageID, fixedTarget: fixedTarget, onImported: onImported)
                    }
            } else if let error {
                VStack { Text(error); Button("重试") { retry += 1 } }.padding()
            } else { ProgressView("正在打开预设…") }
        }.sheet(item: $selection) { value in
            DiaryPresetImportSheet(ownerID: ownerID, package: package, pageIDs: value.pageIDs,
                defaultTarget: value.wholeBook ? nil : targetBook, wholeBook: value.wholeBook,
                defaultAfterPageID: targetAfterPageID, fixedTarget: fixedTarget) { book in
                    selection = nil; onImported(book)
                }
        }.task(id: retry) {
            do { pages = try await Task.detached { try package.pages }.value }
            catch { self.error = error.localizedDescription }
        }
    }
}

private struct DiaryPresetDetailScreen: View {
    let ownerID: String
    let package: DiaryPresetPackage
    let targetBook: DiaryBook?
    let targetAfterPageID: UUID?
    var fixedTarget = false
    @State private var error: String?
    @State private var pages: [PresetPage] = []
    @State private var previewPage: String?
    @State private var showingPreview = false
    @State private var selection: PresetSelection?
    let onImported: (DiaryBook) -> Void
    @State private var validated = false
    @State private var photoSlots = 0
    @State private var textSlots = 0
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                DiaryPresetCover(package: package).frame(maxWidth: .infinity).frame(height: 260)
                    .padding(20).background(DiaryLibraryStyle.surface, in: RoundedRectangle(cornerRadius: 16))
                Text(package.manifest.title).font(.title2.weight(.semibold))
                Text("\(pages.filter { $0.id != package.manifest.shellPageID }.count) 页 · 可独立编辑的旅行手帐")
                    .font(.subheadline).foregroundStyle(DiaryLibraryStyle.secondary)
                if let tags = package.manifest.tags, !tags.isEmpty {
                    Text(tags.joined(separator: " · ")).font(.caption).foregroundStyle(DiaryLibraryStyle.secondary)
                }
                if validated {
                    Text("可替换照片 \(photoSlots) 处 · 可编辑文字 \(textSlots) 处。图片文字保持为装饰。").font(.caption).foregroundStyle(.secondary)
                }
                if (package.manifest.requiredFonts ?? []).contains(where: { !DiaryFontCatalog.shared.available($0) }) {
                    Text("此预设的部分字体暂不可用，导入后将临时使用系统字体，排版可能与预览不同。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("页面总览").font(.headline)
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
            .background(DiaryLibraryStyle.background)
            .safeAreaInset(edge: .bottom) {
                if !fixedTarget {
                    Button("用这本模板") { selection = PresetSelection(pageIDs: pages.map(\.id), wholeBook: true) }
                        .buttonStyle(.borderedProminent).controlSize(.large).disabled(pages.isEmpty || !validated)
                        .padding().frame(maxWidth: .infinity).background(.regularMaterial)
                }
            }
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
                importPage(value)
            }
    }
    private func importPage(_ value: PresetSelection) -> some View {
                DiaryPresetImportSheet(ownerID: ownerID, package: package, pageIDs: value.pageIDs,
                                       defaultTarget: value.wholeBook ? nil : targetBook, wholeBook: value.wholeBook, defaultAfterPageID: targetAfterPageID, fixedTarget: fixedTarget) { book in
                    selection = nil; onImported(book)
                }

    }
}
enum DiaryPresetImportRoute: Hashable { case photos, target }
struct DiaryPresetImportSheet: View {
    let ownerID: String
    let package: DiaryPresetPackage
    let pageIDs: [String]
    let defaultTarget: DiaryBook?
    let wholeBook: Bool
    var defaultAfterPageID: UUID? = nil
    var resume: DiaryPresetImportIntent? = nil
    var remoteBook: RemotePresetBook? = nil
    var initialDownloadID: UUID? = nil
    var loadingPages: [RemotePresetPage] = []
    var loadingPreviewSize: CGSize = CGSize(width: 1, height: 1.4)
    var fixedTarget = false
    let completed: (DiaryBook) -> Void
    private let downloads = PresetDownloadManager.shared
    @StateObject private var downloadObservation = PresetDownloadObservation()
    @State private var downloadID: UUID?
    @State private var readyPackage: DiaryPresetPackage?
    @State private var planning = false
    @State private var path: [DiaryPresetImportRoute] = []
    @State private var initialized = false
    @State private var replacementPhotos: [URL] = []
    @State private var replacementFill: DiaryPhotoSlot.Fill = .cover
    @State private var excludedPageIDs: Set<String> = []
    @State private var hiddenCategories: Set<DiaryLayerSemanticKind> = []
    @State private var preparationDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("preset-photos-" + UUID().uuidString)
    @Environment(\.dismiss) private var dismiss
    @State private var books: [DiaryBook] = []
    @State private var targetID: UUID?
    @State private var afterPageID: UUID?
    @State private var title = ""
    @State private var operationID = UUID()
    @State private var error: String?
    @State private var busy = false
    @State private var progress = ""
    @State private var cancellation = DiaryPresetCancellation()

    private var selectedPageIDs: [String] { pageIDs.filter { !excludedPageIDs.contains($0) } }
    private var availablePackage: DiaryPresetPackage? { remoteBook == nil ? package : readyPackage }
    private var target: DiaryBook? { books.first { $0.id == targetID } }
    private var finishesAtPhotos: Bool { wholeBook || fixedTarget }
    private var selectionIdentity: String {
        selectedPageIDs.joined(separator: ",") + hiddenCategories.map(\.rawValue).sorted().joined(separator: ",")
    }
    private var validName: Bool {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && name.count <= 60
    }
    private var importTitle: String { wholeBook ? "添加整本" : pageIDs.count == 1 ? "添加单页" : "添加双页" }

    var body: some View {
        NavigationStack(path: $path) {
            previewStep
                .navigationDestination(for: DiaryPresetImportRoute.self) { route in
                    switch route {
                    case .photos: photoStep
                    case .target: targetStep
                    }
                }
        }
        .tint(DiaryLibraryStyle.accent)
        .interactiveDismissDisabled(busy)
        .onDisappear { cleanupPhotos() }
        .onChange(of: downloadObservation.job?.status) { _, _ in
            if let downloadID { readyPackage = downloads.preparedPackage(downloadID) }
        }
        .onChange(of: selectionIdentity) { _, _ in invalidatePhotos() }
        .onChange(of: title) { _, _ in operationID = UUID() }
        .onChange(of: afterPageID) { _, _ in operationID = UUID() }
        .task { await initialize() }
    }

    private var previewStep: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("第 1 步 / \(finishesAtPhotos ? 2 : 3) · 预览并选择页面")
                        .font(.subheadline).foregroundStyle(.secondary)
                    DiaryPresetImportPreview(package: availablePackage, pageIDs: pageIDs,
                        excludedPageIDs: $excludedPageIDs, hiddenCategories: hiddenCategories,
                        loadingPages: loadingPages, loadingSize: loadingPreviewSize)
                        .frame(height: max(280, min(560, geometry.size.height - (wholeBook ? 150 : 70))))
                    if wholeBook {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("手帐名称").font(.subheadline.weight(.medium))
                            TextField("手帐名称", text: $title).textFieldStyle(.roundedBorder)
                            Text("将所选页面创建为新的手帐本").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if selectedPageIDs.isEmpty {
                        Text("请至少选择一页后继续。").font(.caption).foregroundStyle(.secondary)
                    }
                    if let error { Text(error).font(.caption).foregroundStyle(.red) }
                }.padding()
            }
            .background(DiaryLibraryStyle.background)
        }
        .safeAreaInset(edge: .bottom) {
            Group {
                if availablePackage != nil {
                    DiaryPreviewContentPanel(hiddenCategories: $hiddenCategories, affectsImport: true)
                } else {
                    downloadFeedback
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial)
        }
        .navigationTitle(importTitle)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("下一步") { error = nil; path.append(.photos) }
                    .disabled(!initialized || availablePackage == nil || selectedPageIDs.isEmpty || (wholeBook && !validName))
            }
        }
    }

    @ViewBuilder private var downloadFeedback: some View {
        if remoteBook != nil {
            VStack(alignment: .leading, spacing: 8) {
                if let job = downloadObservation.job {
                    ProgressView(value: Double(job.bytes), total: Double(max(1, job.total)))
                    Text("正在准备资源 · \(Int(min(1, Double(job.bytes) / Double(max(1, job.total))) * 100))%")
                    if let message = job.error { Text(message).foregroundStyle(.red) }
                    HStack {
                        if ["queued", "downloading", "verifying"].contains(job.status) { Button("暂停下载") { downloads.pause(job.id) } }
                        if ["paused", "failed"].contains(job.status) { Button("继续下载") { downloads.resume(job.id) } }
                    }
                } else if planning { ProgressView("正在获取资源清单…") }
                else { Button("下载资源") { Task { await prepareRemote() } } }
            }.font(.caption)
        }
    }

    private var targetStep: some View {
        Form {
            Text("第 3 步 / 3 · 选择帐本")
            Text("已选 \(selectedPageIDs.count) 页 · \(replacementPhotos.isEmpty ? "保留原照片" : "已选择 \(replacementPhotos.count) 张替换照片")")
                .foregroundStyle(.secondary)
            Picker("添加到", selection: $targetID) {
                Text("新建手帐本").tag(Optional<UUID>.none)
                ForEach(books) { Text($0.title).tag(Optional($0.id)) }
            }.onChange(of: targetID) { _, _ in afterPageID = nil; operationID = UUID() }
            if let target {
                Picker("插入位置", selection: $afterPageID) {
                    Text("末尾").tag(Optional<UUID>.none)
                    ForEach(Array(target.pages.enumerated()), id: \.element.id) { index, page in
                        Text("第 \(index + 1) 页之后").tag(Optional(page.id))
                    }
                }
                if target.defaultPageSize != package.manifest.pageSize.cg {
                    Text("纸张比例不同，将等比居中完整放入，四周可能留透明空白。")
                }
            } else { TextField("手帐名称", text: $title) }
            if let error { Text(error).foregroundStyle(.red) }
            if busy { ProgressView(progress.isEmpty ? "正在添加…" : progress) }
        }
        .disabled(busy)
        .navigationTitle("选择帐本")
        .navigationBarBackButtonHidden(busy)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(busy ? "取消导入" : "取消") { if busy { cancellation.cancel() } else { dismiss() } }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("添加") { Task { await runImport() } }
                    .disabled(busy || selectedPageIDs.isEmpty || (targetID == nil && !validName))
            }
        }
    }

    @ViewBuilder private var photoStep: some View {
        if let availablePackage {
            DiaryBatchPhotoSheet(store: DiaryDocumentStore(ownerID: ownerID), preset: availablePackage,
                presetPageIDs: selectedPageIDs, hiddenPresetCategories: hiddenCategories,
                preparationDirectory: preparationDirectory,
                finishesImport: finishesAtPhotos, embedded: true, onPrepared: { files, fill in
                    for old in replacementPhotos { try? FileManager.default.removeItem(at: old) }
                    replacementPhotos = files; replacementFill = fill; operationID = UUID(); error = nil
                    if finishesAtPhotos { Task { await runImport() } }
                    else { path.append(.target) }
                })
                .id(selectionIdentity)
                .disabled(busy)
                .navigationBarBackButtonHidden(busy)
                .overlay {
                    if busy { ProgressView(progress.isEmpty ? "正在添加…" : progress).padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) }
                }
                .safeAreaInset(edge: .bottom) {
                    if let error {
                        VStack {
                            Text(error).font(.caption).foregroundStyle(.red)
                            Button("重试添加") { Task { await runImport() } }.disabled(busy)
                        }.padding().frame(maxWidth: .infinity).background(.regularMaterial)
                    }
                }
                .toolbar {
                    if busy {
                        ToolbarItem(placement: .bottomBar) { Button("取消导入") { cancellation.cancel() } }
                    }
                }
        }
    }

    private func initialize() async {
        guard !initialized else { return }
        title = resume?.title ?? package.manifest.title
        hiddenCategories = resume?.hiddenCategories ?? []
        do {
            books = try await DiaryDocumentStore(ownerID: ownerID).listBooks()
            if let resume {
                targetID = wholeBook ? nil : resume.targetID
                afterPageID = wholeBook ? nil : resume.afterPageID
            } else {
                targetID = wholeBook ? nil : defaultTarget?.id
                afterPageID = wholeBook ? nil : defaultAfterPageID
            }
        } catch { self.error = error.localizedDescription }
        initialized = true
        await prepareRemote()
    }
    private func invalidatePhotos() {
        cleanupPhotos(); replacementPhotos = []; operationID = UUID(); error = nil
    }
    private func cleanupPhotos() {
        try? FileManager.default.removeItem(at: preparationDirectory)
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
            if let initialDownloadID {
                downloadID = initialDownloadID
            } else {
                downloadID = try await downloads.enqueue(book: remoteBook, pageIDs: wholeBook ? nil : pageIDs,
                    owner: ownerID, target: nil, after: nil, downloadOnly: true)
            }
            if let downloadID {
                downloadObservation.bind(downloadID, manager: downloads)
                readyPackage = downloads.preparedPackage(downloadID)
            }
        } catch { self.error = error.localizedDescription }
    }
    private func runImport() async {
        guard !busy, !selectedPageIDs.isEmpty, availablePackage != nil else { return }
        if fixedTarget && (defaultTarget == nil || targetID != defaultTarget?.id) {
            error = "目标帐本暂不可用，请重新打开添加页面。"; return
        }
        busy = true
        defer { busy = false }
        do {
            if let old = DiaryPresetImportIntent.read(owner: ownerID), old.templateID == package.id,
               old.pageIDs == selectedPageIDs, old.wholeBook == wholeBook,
               (old.hiddenCategories ?? []) == hiddenCategories, replacementPhotos.isEmpty,
               old.targetID == targetID, old.afterPageID == afterPageID, old.title == title,
               old.version == package.manifest.packageVersion { operationID = old.id }
            cancellation = DiaryPresetCancellation()
            let intent = DiaryPresetImportIntent(id: operationID, templateID: package.id, version: package.manifest.packageVersion,
                  pageIDs: selectedPageIDs, wholeBook: wholeBook, targetID: targetID, afterPageID: afterPageID, title: title,
                  hiddenCategories: hiddenCategories)
            try intent.save(owner: ownerID)
            let result = try await DiaryDocumentStore(ownerID: ownerID, bookID: targetID).importPreset(readyPackage ?? package, pageIDs: selectedPageIDs, title: title,
                    operationID: operationID, replacementPhotos: replacementPhotos, replacementFill: replacementFill, hiddenCategories: hiddenCategories, afterPageID: afterPageID, expectedRevision: target?.catalogRevision, progress: { value in
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

struct DiaryPresetPagePicker: View {
    let ownerID: String
    let targetBook: DiaryBook
    var afterPageID: UUID? = nil
    let completed: (DiaryBook) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack() {
            DiaryPresetLibraryScreen(ownerID: ownerID, targetBook: targetBook,
                targetAfterPageID: afterPageID, singlePageOnly: true, onPageAdded: { book in
                    completed(book); dismiss()
                })
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }
    }
}
