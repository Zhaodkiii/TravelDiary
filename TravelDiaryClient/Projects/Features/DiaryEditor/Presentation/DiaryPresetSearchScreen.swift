import SwiftUI

/// 搜索 Tab 的独立页面；结果始终逐本纵向排列，不参与模板库的系列分组。
struct DiaryPresetSearchScreen: View {
    let ownerID: String
    @Binding var searchText: String
    var initialCatalog: RemotePresetCatalog? = nil
    var catalogLoader: @MainActor () async throws -> RemotePresetCatalog = { try await PresetDownloadManager.shared.catalog() }

    private let downloads = PresetDownloadManager.shared
    @ObservedObject private var availability = PresetDownloadManager.shared.availability
    @State private var catalog: RemotePresetCatalog?
    @State private var finishedLoading = false
    @State private var loadError: String?
    @State private var reload = 0
    @State private var importedBook: DiaryBook?
    @State private var onlyDownloaded = false
    @State private var styles: Set<String> = []
    @State private var usages: Set<String> = []
    @State private var draftOnlyDownloaded = false
    @State private var draftStyles: Set<String> = []
    @State private var draftUsages: Set<String> = []
    @State private var showingFilters = false

    private var items: [PresetLibraryItem] {
        PresetLibraryItem.merge(local: [], remote: (catalog ?? initialCatalog)?.books ?? [])
    }
    private var results: [PresetLibraryItem] {
        items.filter {
            $0.matches(search: searchText, series: "", styles: styles, usages: usages)
                && (!onlyDownloaded || isAvailable($0))
        }
    }
    private var hasConditions: Bool {
        !searchText.isEmpty || onlyDownloaded || !styles.isEmpty || !usages.isEmpty
    }
    private var allStyles: [String] { Array(Set(items.flatMap(\.styles))).sorted() }
    private var allUsages: [String] { Array(Set(items.flatMap(\.usages))).sorted() }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                if let loadError {
                    DiaryLibraryNotice(message: loadError) { reload += 1 }
                }
                HStack {
                    Text("\(results.count) 本模板")
                        .font(.subheadline).foregroundStyle(DiaryLibraryStyle.secondary)
                    Spacer()
                    if hasConditions {
                        Button("清空条件") {
                            searchText = ""; onlyDownloaded = false; styles = []; usages = []
                        }.font(.subheadline).frame(minHeight: 44)
                    }
                }
                if items.isEmpty && !finishedLoading {
                    ProgressView("正在加载模板…").frame(maxWidth: .infinity).padding(48)
                } else if results.isEmpty {
                    ContentUnavailableView("暂无匹配的模板", systemImage: "magnifyingglass",
                        description: Text(hasConditions ? "试试其他关键词，或清空筛选条件。" : "暂时没有可用模板，请稍后重试。"))
                } else {
                    ForEach(results) { item in
                        templateLink(item).padding(.bottom, 8)
                    }
                }
            }
            .frame(maxWidth: 1200).padding(20).frame(maxWidth: .infinity)
        }
        .background(DiaryLibraryStyle.background)
        .foregroundStyle(DiaryLibraryStyle.ink).tint(DiaryLibraryStyle.accent)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("搜索模板")
        .searchable(text: $searchText, prompt: "搜索模板名称")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    draftStyles = styles; draftUsages = usages
                    draftOnlyDownloaded = onlyDownloaded; showingFilters = true
                } label: {
                    Image(systemName: hasConditions ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease")
                }.accessibilityLabel("筛选模板")
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { PresetDownloadCenter(ownerID: ownerID) } label: {
                    Image(systemName: "arrow.down.circle").accessibilityLabel("下载管理")
                }
            }
        }
        .sheet(isPresented: $showingFilters) { filterSheet }
        .navigationDestination(isPresented: Binding(get: { importedBook != nil }, set: { if !$0 { importedBook = nil } })) {
            if let importedBook {
                DiaryBookScreen(ownerID: ownerID, book: importedBook).toolbar(.hidden, for: .tabBar)
            }
        }
        .refreshable { await loadCatalog() }
        .task(id: reload) {
            downloads.activate(owner: ownerID)
            if catalog == nil {
                if let initialCatalog { catalog = initialCatalog }
                else { catalog = await Task.detached { PresetLibraryCatalogCache.read(ownerID: ownerID) }.value }
            }
            await loadCatalog()
        }
    }

    private func templateLink(_ item: PresetLibraryItem) -> some View {
        let seriesTitle = (catalog ?? initialCatalog)?.series.first { $0.slug == item.series }?.title
        return NavigationLink {
            DiaryStablePresetDestination(item: item, ownerID: ownerID, seriesTitle: seriesTitle ?? "旅行模板",
                targetBook: nil, targetAfterPageID: nil, fixedTarget: false,
                onImported: { importedBook = $0 })
                .toolbar(.hidden, for: .tabBar)
        } label: {
            DiaryPresetTemplateCard(item: item, ownerID: ownerID,
                downloadedCount: item.remote.map { availability.downloadedPageIDs(bookID: $0.id, version: $0.version).count } ?? 0,
                expanded: true, seriesTitle: seriesTitle)
        }.buttonStyle(.plain).accessibilityIdentifier("template-search-result-\(item.id)")
    }

    private var filterSheet: some View {
        NavigationStack {
            List {
                Toggle("仅看可离线使用的模板", isOn: $draftOnlyDownloaded)
                if !allStyles.isEmpty {
                    Section("风格") { ForEach(allStyles, id: \.self) { filterRow($0, selection: $draftStyles) } }
                }
                if !allUsages.isEmpty {
                    Section("用途") { ForEach(allUsages, id: \.self) { filterRow($0, selection: $draftUsages) } }
                }
                Button("重置") { draftStyles = []; draftUsages = []; draftOnlyDownloaded = false }
            }
            .navigationTitle("筛选模板")
            .toolbar { Button("取消") { showingFilters = false } }
            .safeAreaInset(edge: .bottom) {
                Button("查看结果") {
                    styles = draftStyles; usages = draftUsages
                    onlyDownloaded = draftOnlyDownloaded; showingFilters = false
                }.buttonStyle(.borderedProminent).controlSize(.large).padding()
                    .frame(maxWidth: .infinity).background(.regularMaterial)
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
        guard let remote = item.remote else { return item.local != nil }
        return remote.page_count > 0
            && availability.downloadedPageIDs(bookID: remote.id, version: remote.version).count >= remote.page_count
            && downloads.completeCachedPackage(for: remote) != nil
    }

    private func loadCatalog() async {
        do {
            let value = try await catalogLoader()
            try Task.checkCancellation()
            catalog = value; loadError = nil
            await Task.detached { PresetLibraryCatalogCache.save(value, ownerID: ownerID) }.value
        } catch is CancellationError { return }
        catch { loadError = "在线模板暂时无法更新，请重试；已下载的资源可在下载管理中使用。" }
        finishedLoading = true
    }
}
