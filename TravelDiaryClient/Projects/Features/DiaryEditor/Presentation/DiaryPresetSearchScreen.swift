import SwiftUI
import ImageIO

/// Native search owns mode, filters and cursor; each result pins a published version.
struct DiaryPresetSearchScreen: View {
    let ownerID: String
    @Binding var searchText: String
    var initialCatalog: RemotePresetCatalog? = nil
    var fixedSeriesID: String? = nil
    var catalogLoader: @MainActor () async throws -> RemotePresetCatalog = { try await PresetDownloadManager.shared.catalog() }
    var showsSearchField = true
    var onBookOpened: ((DiaryBook) -> Void)? = nil
    @AppStorage("preset.search.kind") private var kind = "book"
    @State private var entries: [PresetSearchEntry] = []
    @State private var total = 0
    @State private var cursor: String?
    @State private var loading = false
    @State private var paging = false
    @State private var error: String?
    @State private var offline = false
    @State private var onlyDownloaded = false
    @State private var filters: [String: Set<String>] = [:]
    @State private var taxonomy: PresetTaxonomy?
    @State private var showingFilters = false
    @State private var importedBook: DiaryBook?
    @State private var selectedSpread: PresetSearchEntry?
    @State private var reload = 0
    @State private var clearsSeriesScope = false
    @State private var positions: [String: String] = [:]
    private var activeSeries: String? { clearsSeriesScope ? nil : fixedSeriesID }
    private let downloads = PresetDownloadManager.shared
    private var queryKey: String {
        "\(ownerID)|\(kind)|\(searchText)|\(onlyDownloaded)|\(activeSeries ?? "")|\(filters.keys.sorted().map { $0 + (filters[$0] ?? []).sorted().joined(separator: ",") }.joined())|\(reload)"
    }
    private var taxonomyURL: URL {
        StoragePaths.system.cacheAccount(ownerID).appendingPathComponent("Catalog/taxonomy.json")
    }
    var body: some View {
        if onBookOpened == nil {
            searchBody.navigationDestination(item: Binding<UUID?>(get: { importedBook?.id }, set: { if $0 == nil { importedBook = nil } })) { bookID in
                DiaryBookDestination(ownerID: ownerID, bookID: bookID).toolbar(.hidden, for: .tabBar)
            }
        } else { searchBody }
    }
    @ViewBuilder private var searchBody: some View {
        if showsSearchField {
            content.searchable(text: $searchText, prompt: kind == "spread" ? "搜索地点、景点或主题" : "搜索模板名称")
        } else {
            content
        }
    }

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                if let activeSeries {
                    HStack { Text("当前系列：\(activeSeries)").font(.footnote); Spacer(); Button("搜索全部系列") { clearsSeriesScope = true } }
                }
                if offline {
                    Text("离线结果，仅包含本机已有内容；目录可能不是最新版本。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let error { DiaryLibraryNotice(message: error) { reload += 1 } }
                HStack {
                    Text("\(total) \(kind == "spread" ? "个跨页" : "本模板")").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    if !searchText.isEmpty || onlyDownloaded || filters.values.contains(where: { !$0.isEmpty }) {
                        Button("清空条件") { searchText = ""; filters = [:]; onlyDownloaded = false }
                    }
                }
                if loading { ProgressView("正在搜索…").frame(maxWidth: .infinity).padding(40) }
                else if entries.isEmpty && error == nil {
                    ContentUnavailableView(kind == "spread" ? "暂无匹配跨页" : "暂无匹配模板", systemImage: "magnifyingglass",
                        description: Text(offline ? "本机没有符合条件的完整离线内容。" : "试试其他关键词或清空筛选条件。"))
                }
                if kind == "spread" {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 18) {
                        ForEach(entries) { entry in resultLink(entry).id(entry.id) }
                    }.scrollTargetLayout()
                } else {
                    ForEach(entries) { entry in resultLink(entry).id(entry.id) }
                }
                if cursor != nil {
                    Button { Task { await loadMore() } } label: {
                        if paging { ProgressView() } else { Text("加载更多") }
                    }.disabled(paging).frame(maxWidth: .infinity, minHeight: 44)
                }
            }.padding(20).frame(maxWidth: 1200).frame(maxWidth: .infinity)
        }
        .background(DiaryLibraryStyle.background).tint(DiaryLibraryStyle.accent)
        .navigationTitle("搜索模板")
        .scrollDismissesKeyboard(.interactively)
        .scrollPosition(id: Binding(get: { positions[kind] }, set: { positions[kind] = $0 }))
        .safeAreaInset(edge: .top, spacing: 0) {
            Picker("搜索范围", selection: $kind) {
                Text("整本").tag("book"); Text("跨页").tag("spread")
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("preset-search-mode")
            .padding(.horizontal, 20).padding(.top, 20)
            .frame(maxWidth: 1200).frame(maxWidth: .infinity)
            .background(DiaryLibraryStyle.background)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button { showingFilters = true } label: { Image(systemName: "line.3.horizontal.decrease.circle") }.accessibilityLabel("筛选模板") }
            ToolbarItem(placement: .topBarTrailing) { NavigationLink { PresetDownloadCenter(ownerID: ownerID) } label: { Image(systemName: "arrow.down.circle") }.accessibilityLabel("下载管理") }
        }
        .sheet(isPresented: $showingFilters) { filterSheet }
        .sheet(item: $selectedSpread) { entry in
            RemotePresetImportDestination(ownerID: ownerID, book: entry.book, pageIDs: entry.page_ids,
                wholeBook: false, targetBook: nil, afterPageID: nil, fixedTarget: false,
                previewPages: entry.previewPages, previewSize: CGSize(width: 1, height: 1.4),
                onImported: { openBook($0) }, unitID: entry.unit_id)
        }
        .task(id: queryKey) { await loadFirst() }
        .task(id: ownerID) {
            let owner = ownerID
            let taxonomyKey = ResourceCacheKey.account(ownerID, category: "catalog", identity: "taxonomy")
            taxonomy = (ResourceCache.shared.data(for: taxonomyKey) ?? (try? Data(contentsOf: taxonomyURL))).flatMap { try? JSONDecoder().decode(PresetTaxonomy.self, from: $0) }
            if ResourceCache.shared.data(for: taxonomyKey) == nil, FileManager.default.fileExists(atPath: taxonomyURL.path) { ResourceCache.shared.register(taxonomyURL, for: taxonomyKey) }
            do {
                let value = try await downloads.searchTaxonomy()
                try Task.checkCancellation()
                guard owner == ownerID else { return }
                taxonomy = value
                if let data = try? JSONEncoder().encode(value), ResourceCache.shared.store(data, for: taxonomyKey) != nil { try? FileManager.default.removeItem(at: taxonomyURL) }
            } catch { }
        }
        .refreshable { reload += 1 }
    }
    private func openBook(_ book: DiaryBook) {
        if let onBookOpened { onBookOpened(book) } else { importedBook = book }
    }
    private func resultLink(_ entry: PresetSearchEntry) -> some View {
        Group {
            if entry.entity_type == "spread" {
                Button { selectedSpread = entry } label: {
                    resultCard(entry)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("template-search-result-\(entry.id)")
            } else {
                NavigationLink {
                DiaryStablePresetDestination(item: PresetLibraryItem(id: entry.template_id,
                    local: downloads.completeCachedPackage(for: entry.book), remote: entry.book),
                    ownerID: ownerID, seriesTitle: entry.series, targetBook: nil, targetAfterPageID: nil, fixedTarget: false,
                    onImported: { openBook($0) }).toolbar(.hidden, for: .tabBar)
                } label: { resultCard(entry) }
                .buttonStyle(.plain)
                .accessibilityIdentifier("template-search-result-\(entry.id)")
            }
        }
    }

    private func resultCard(_ entry: PresetSearchEntry) -> some View {
            VStack(alignment: .leading, spacing: 8) {
                Group {
                    if entry.entity_type == "spread" {
                        PresetSearchSpreadShell(previews: entry.previews, refresh: {
                            if let value = try? await downloads.refreshedSearchEntry(entry), let index = entries.firstIndex(where: { $0.id == entry.id }) { entries[index] = value }
                        })
                    } else {
                        // 整本搜索使用现有杂志式卡片：左侧封面，右侧上下两组跨页预览。
                        DiaryPresetMagazinePreview(
                            item: PresetLibraryItem(id: entry.template_id,
                                local: downloads.completeCachedPackage(for: entry.book), remote: entry.book),
                            ownerID: ownerID)
                    }
                }
                .frame(maxHeight: entry.entity_type == "spread" ? 360 : 420)
                Text(entry.title).font(.headline).foregroundStyle(DiaryLibraryStyle.ink)
                Text(entry.entity_type == "spread" ? "\(entry.book_title) · 2 页" : "\(entry.page_count) 页")
                    .font(.caption).foregroundStyle(.secondary)
                if !entry.tags.isEmpty { Text(entry.tags.prefix(2).joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) }
            }
    }
    private var filterSheet: some View {
        NavigationStack {
            List {
                Toggle("仅看可离线使用", isOn: $onlyDownloaded)
                Text("开启后搜索本机完整离线内容，并按本机范围计数。位置、主题、风格和用途可组合筛选。")
                    .font(.footnote).foregroundStyle(.secondary)
                ForEach([("location", "地点"), ("theme", "主题"), ("style", "风格"), ("usage", "用途")], id: \.0) { dimension, title in
                    Section(title) {
                        ForEach(taxonomy?.terms.filter { $0.dimension == dimension } ?? []) { term in
                            Button {
                                var selected = filters[dimension] ?? []
                                if selected.contains(term.id) { selected.remove(term.id) } else { selected.insert(term.id) }
                                filters[dimension] = selected
                            } label: {
                                HStack { Text(term.name); Spacer(); if filters[dimension]?.contains(term.id) == true { Image(systemName: "checkmark") } }
                            }
                        }
                    }
                }
                Button("重置") { filters = [:]; onlyDownloaded = false }
            }.navigationTitle("筛选模板").toolbar { Button("完成") { showingFilters = false } }
        }
    }
    private func localResults() -> [PresetSearchEntry] {
        let local = downloads.offlineSearchEntries(ownerID: ownerID, taxonomy: taxonomy).filter {
            $0.entity_type == kind && (activeSeries == nil || $0.series == activeSeries) && PresetSearchMatcher.matches($0, query: searchText, taxonomy: taxonomy, filters: filters)
        }
        return local.sorted { a, b in
            let left = PresetSearchMatcher.score(a, query: searchText, taxonomy: taxonomy, filters: filters) ?? (9, 0)
            let right = PresetSearchMatcher.score(b, query: searchText, taxonomy: taxonomy, filters: filters) ?? (9, 0)
            return (left.0, left.1, a.book_position ?? 0, a.template_id, a.position ?? 0, a.id)
                < (right.0, right.1, b.book_position ?? 0, b.template_id, b.position ?? 0, b.id)
        }
    }
    private func loadFirst() async {
        let key = queryKey
        entries = []; cursor = nil; total = 0; error = nil; loading = true; offline = onlyDownloaded
        downloads.activate(owner: ownerID)
        do {
            try await Task.sleep(for: .milliseconds(300))
            // Do not send uncommitted Chinese IME composition to the server.
            while hasMarkedSearchText {
                try await Task.sleep(for: .milliseconds(100))
            }
            await downloads.waitUntilRestored()
            try Task.checkCancellation()
            guard key == queryKey else { return }
            if onlyDownloaded { entries = localResults(); total = entries.count }
            else {
                let value = try await downloads.search(kind: kind, query: searchText, filters: filters, seriesID: activeSeries)
                try Task.checkCancellation()
                guard key == queryKey else { return }
                entries = value.entries; total = value.total; cursor = value.next_cursor
            }
            loading = false
        } catch is CancellationError { }
        catch {
            guard key == queryKey else { return }
            entries = localResults(); total = entries.count; offline = true; loading = false
            self.error = "在线搜索暂时不可用，可重试；下方仅展示本机离线结果。"
        }
    }
    private var hasMarkedSearchText: Bool {
        func marked(_ view: UIView) -> Bool {
            if let input = view as? UISearchTextField, input.isFirstResponder, input.markedTextRange != nil { return true }
            return view.subviews.contains(where: marked)
        }
        return UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).contains(where: marked)
    }
    private func loadMore() async {
        guard let cursor, !paging else { return }
        let key = queryKey; paging = true
        defer { paging = false }
        do {
            let value = try await downloads.search(kind: kind, query: searchText, filters: filters, cursor: cursor, seriesID: activeSeries)
            try Task.checkCancellation()
            guard key == queryKey else { return }
            let known = Set(entries.map(\.id))
            entries += value.entries.filter { !known.contains($0.id) }; self.cursor = value.next_cursor; total = value.total; error = nil
        } catch {
            guard key == queryKey else { return }
            if case let SupportNetworkError.http(statusCode: code, backend: _, data: _) = error, code == 409 {
                reload += 1
            } else { self.error = "加载更多失败，请重试；如目录已更新，可刷新搜索。" }
        }
    }
}

struct PresetSearchPairImage: View {
    let previews: [[String: PresetSearchAsset]]
    let large: Bool
    var refresh: (() async -> Void)? = nil
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(previews.enumerated()), id: \.offset) { _, image in
                PresetSearchImage(url: image[large ? "largePath" : "thumbnailPath"]?.url ?? "", refresh: refresh)
            }
        }.background(Color.gray.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

/// Search cards reuse the same leather edge, spine and binding rings as preset-page previews.
private struct PresetSearchSpreadShell: View {
    let previews: [[String: PresetSearchAsset]]
    var refresh: (() async -> Void)? = nil
    @State private var paperRatio: CGFloat = 0.7

    private var spreadRatio: CGFloat {
        // 与杂志卡片、阅读器一致：纸张之外还需计入皮革外沿和装订缝。
        2 / (0.955 * (1 - DiaryBookSpine.halfGapFraction) / paperRatio + 0.09)
    }

    var body: some View {
        GeometryReader { geometry in
            DiaryBoundSpread {
                page(at: 0)
            } right: {
                page(at: 1)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .aspectRatio(spreadRatio, contentMode: .fit)
        .shadow(color: .black.opacity(0.12), radius: 4, y: 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("完整跨页预览，包含手帐外壳和装订结构")
    }

    private func page(at index: Int) -> some View {
        ZStack {
            Color(red: 0.96, green: 0.92, blue: 0.82)
            if previews.indices.contains(index) {
                PresetSearchImage(url: previews[index]["thumbnailPath"]?.url ?? "", refresh: refresh,
                                  onImageSize: { size in
                    if index == 0, size.width > 0, size.height > 0 {
                        paperRatio = size.width / size.height
                    }
                })
            }
        }
    }
}

private struct PresetSearchImage: View {
    let url: String
    var refresh: (() async -> Void)? = nil
    var onImageSize: ((CGSize) -> Void)? = nil
    var body: some View {
        CachedPreviewImage(request: PreviewImagePipeline.shared.request(url: URL(string: url), maxPixelSize: 2048),
                           onImageSize: onImageSize, onRetry: refresh)
    }
}

private struct PresetSearchSpreadDestination: View {
    let ownerID: String
    let entry: PresetSearchEntry
    let onImported: (DiaryBook) -> Void
    @State private var selection: [String]?
    @State private var showingImport = false
    @State private var refreshed: PresetSearchEntry?
    @State private var side = 0
    private var visiblePreviews: [[String: PresetSearchAsset]] {
        let all = (refreshed ?? entry).previews
        if side == 0 { return all }
        return all.indices.contains(side - 1) ? [all[side - 1]] : []
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Picker("预览范围", selection: $side) { Text("完整跨页").tag(0); Text("看左页").tag(1); Text("看右页").tag(2) }.pickerStyle(.segmented)
                GeometryReader { geometry in
                    DiaryBookZoomViewport(contentSize: geometry.size, resetToken: side) {
                        PresetSearchPairImage(previews: visiblePreviews, large: true, refresh: {
                            refreshed = try? await PresetDownloadManager.shared.refreshedSearchEntry(entry)
                        }).frame(width: geometry.size.width, height: geometry.size.height)
                    }
                }.frame(height: 380)
                Text(entry.title).font(.title2)
                Text(entry.book_title).foregroundStyle(.secondary)
                Button("添加这两页") { selection = entry.page_ids; showingImport = true }.buttonStyle(.borderedProminent)
                HStack {
                    ForEach(Array(entry.page_ids.enumerated()), id: \.offset) { index, id in
                        Button(index == 0 ? "仅添加左页" : "仅添加右页") { selection = [id]; showingImport = true }
                    }
                }
                NavigationLink("查看所属整本") {
                    DiaryStablePresetDestination(item: PresetLibraryItem(id: entry.template_id, local: nil, remote: entry.book), ownerID: ownerID,
                        seriesTitle: entry.series, targetBook: nil, targetAfterPageID: nil, fixedTarget: false, onImported: onImported)
                }
            }.padding()
        }.navigationTitle("跨页预览")
        .sheet(isPresented: $showingImport) {
            RemotePresetImportDestination(ownerID: ownerID, book: entry.book, pageIDs: selection ?? entry.page_ids,
                wholeBook: false, targetBook: nil, afterPageID: nil, fixedTarget: false, previewPages: entry.previewPages,
                previewSize: CGSize(width: 1, height: 1.4), onImported: onImported,
                unitID: selection?.count == 2 ? entry.unit_id : nil)
        }
    }
}
