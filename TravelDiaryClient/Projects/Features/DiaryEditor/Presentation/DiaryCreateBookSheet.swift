import SwiftUI
import UIKit

/// 同一新建面板切换手帐、照片、空白；手帐保留原有预设导入流程。
struct DiaryCreateBookSheet: View {
    let ownerID: String
    let completed: (DiaryBook) -> Void
    private let initialCatalog: RemotePresetCatalog?
    @State private var category = "手帐"
    @State private var album: DiaryAlbumComposer
    @State private var blankPalette = "0"
    init(ownerID: String, initialCatalog: RemotePresetCatalog? = nil, completed: @escaping (DiaryBook) -> Void) {
        self.ownerID = ownerID; self.completed = completed
        self.initialCatalog = initialCatalog
        _album = State(initialValue: DiaryAlbumComposer(ownerID: ownerID))
    }
    @Environment(\.dismiss) private var dismiss
    @State private var path = NavigationPath()
    @State private var detent: PresentationDetent = .height(450)
    @State private var fittedHeight: CGFloat = 450
    @State private var rootContentHeight: CGFloat = 340
    @State private var actionHeight: CGFloat = 90
    @State private var templateCardHeight: CGFloat = 0
    @State private var photoContentHeight: CGFloat = 400
    @State private var blankContentHeight: CGFloat = 260
    @State private var fullHeight = false
    @State private var items: [PresetLibraryItem] = []
    @State private var selectedID: String?
    @State private var compactPosition: Int? = 0
    @State private var expandedCatalog = false
    @State private var search = ""
    @State private var searchPresented = false
    @State private var searchExpansionID: UUID?
    @State private var series: [RemotePresetCatalog.Series] = []
    @State private var loaded = false
    @State private var error: String?
    private let downloads = PresetDownloadManager.shared
    @ObservedObject private var availability = PresetDownloadManager.shared.availability

    private enum Route: Hashable { case preview(String), photos, blank }

    var body: some View {
        NavigationStack(path: $path) {
            GeometryReader { geometry in
                VStack(alignment: .leading, spacing: 8) {
                    // isPresented 由系统搜索组件同步更新，原生取消搜索后自动恢复这一行。
                    if !searchPresented {
                        HStack(spacing: 12) {
                            Button {
                                if category == "手帐" {
                                    beginSearch()
                                } else { dismiss() }
                            } label: {
                                Image(systemName: category == "手帐" ? "magnifyingglass" : "xmark").font(.system(size: 18, weight: .medium))
                                    .frame(width: 44, height: 44)
                                    .background(DiaryLibraryStyle.ink.opacity(0.04), in: Circle())
                            }
                            .accessibilityLabel(category == "手帐" ? "搜索模板" : "关闭新建面板")
                            .disabled(album.busy)
                            Picker("制作方式", selection: $category) {
                                Text("手帐").tag("手帐"); Text("照片").tag("照片"); Text("空白").tag("空白")
                            }.pickerStyle(.segmented)
                        }.padding(.top, 16).padding(.bottom, 8)
                    }
                    if category == "照片" {
                        DiaryAlbumDesignPicker(model: album, contentHeightChanged: { height in
                            if abs(photoContentHeight - height) > 1 { photoContentHeight = height }
                        })
                        .frame(height: photoContentHeight)
                    } else if category == "空白" {
                        blankDesigns.frame(height: blankContentHeight)
                    } else if !loaded && items.isEmpty {
                        ProgressView("正在读取预设…").frame(maxWidth: .infinity, minHeight: 220)
                    } else if items.isEmpty {
                        Text(error ?? "暂无可用预设").font(.footnote).foregroundStyle(.secondary)
                        Button("重新加载") { Task { await loadCatalog() } }
                    } else if expandedCatalog {
                        expandedPresets
                    } else {
                        ScrollView(.vertical) {
                        DiaryPresetTemplateCarousel(count: items.count, position: $compactPosition,
                            maximumCardWidth: 380, cardWidthFraction: 0.76) { index in
                            let item = items[index]
                            Button { selectedID = item.id } label: {
                                DiaryPresetTemplateCard(item: item, ownerID: ownerID,
                                    downloadedCount: item.remote.map { availability.downloadedPageIDs(bookID: $0.id, version: $0.version).count } ?? 0)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 18)
                                            .strokeBorder(selectedID == item.id ? DiaryLibraryStyle.accent : .clear, lineWidth: 2)
                                    }
                            }
                            .buttonStyle(.plain)
                            .fixedSize(horizontal: false, vertical: true)
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                                if height > 0, abs(templateCardHeight - height) > 1 { templateCardHeight = height }
                            }
                            .accessibilityAddTraits(selectedID == item.id ? .isSelected : [])
                        }
                        .frame(height: templateCardHeight > 0 ? templateCardHeight : DiaryPresetTemplateCarousel<EmptyView>.cardWidth(in: geometry.size.width - 40,
                            maximum: 380, fraction: 0.76) * 0.75 + 64)
                        }
                        .frame(height: templateCardHeight > 0 ? templateCardHeight : DiaryPresetTemplateCarousel<EmptyView>.cardWidth(in: geometry.size.width - 40,
                            maximum: 380, fraction: 0.76) * 0.75 + 64)
                        .scrollIndicators(.hidden)
                    }
                }
                .padding(.horizontal, 20)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    guard !expandedCatalog, height > 0 else { return }
                    rootContentHeight = height
                    fitSheet(content: height, actions: actionHeight)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .background(DiaryLibraryStyle.background)
            .background {
                DiaryNavigationAppearanceObserver {
                    // 原生 pop（包含右滑）完成后，才恢复选择页高度。
                    withAnimation {
                        expandedCatalog = false
                        searchPresented = false
                        searchExpansionID = nil
                        fullHeight = false
                        detent = .height(fittedHeight)
                    }
                }
            }
            .toolbar(expandedCatalog && category == "手帐" ? .visible : .hidden, for: .navigationBar)
            .navigationTitle("选择手帐")
            .navigationBarTitleDisplayMode(.inline)
            // 搜索控制器始终归属于稳定的导航根节点，不能挂在条件创建的卡片列表内。
            .searchable(text: $search, isPresented: $searchPresented,
                placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索模板名称")
            .toolbar {
                if expandedCatalog && category == "手帐" {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("关闭", systemImage: "xmark") { dismiss() }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if category != "手帐" || detent != .large {
                    DiaryImportFloatingActions {
                        if category == "照片" {
                            NavigationLink(value: Route.photos) { Text(album.draft.pages.isEmpty ? "下一步 · 添加照片" : "继续制作相册").frame(maxWidth: .infinity) }
                        } else if category == "空白" {
                            NavigationLink(value: Route.blank) { Text("下一步").frame(maxWidth: .infinity) }
                        } else {
                        NavigationLink(value: selectedID.map { Route.preview($0) }) {
                            Text("下一步").frame(maxWidth: .infinity)
                        }.disabled(selectedID == nil)
                        }
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                        guard height > 0 else { return }
                        actionHeight = height
                        fitSheet(content: rootContentHeight, actions: height)
                    }
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .photos:
                    DiaryAlbumComposerScreen(model: album, completed: completed)
                        .toolbar(.visible, for: .navigationBar)
                        .onAppear { detent = .large; fullHeight = true }
                case .blank:
                    DiaryBlankBookSheet(ownerID: ownerID, completed: completed, paletteID: blankPalette)
                        .toolbar(.visible, for: .navigationBar)
                        .onAppear { detent = .large; fullHeight = true }
                case .preview(let id):
                    if let item = items.first(where: { $0.id == id }) {
                        DiaryCreatePresetDestination(ownerID: ownerID, item: item, path: $path, completed: completed)
                            .toolbar(.visible, for: .navigationBar)
                            .background {
                                DiaryNavigationAppearanceObserver {
                                    // push 完成后再展开，避免两种系统动画互相打断。
                                    withAnimation { detent = .large; fullHeight = true }
                                }
                            }
                    }
                }
            }
        }
        .tint(DiaryLibraryStyle.accent)
        .onChange(of: category) { _, _ in cancelSearchActivation() }
        .onChange(of: path.count) { _, count in
            if count > 0 { cancelSearchActivation() }
        }
        .onDisappear { cancelSearchActivation() }
        .presentationDetents(fullHeight ? [.large] : [.height(fittedHeight), .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .task(id: detent == .large && path.isEmpty) {
            guard detent == .large, path.isEmpty else {
                if detent != .large {
                    expandedCatalog = false
                    cancelSearchActivation()
                }
                return
            }
            do {
                try await Task.sleep(for: .seconds(1))
                try Task.checkCancellation()
                guard !expandedCatalog else { return }
                withAnimation(.easeInOut(duration: 0.2)) { expandedCatalog = true }
            } catch is CancellationError { }
            catch { }
        }
        .task {
            if let initialCatalog {
                update(initialCatalog)
                loaded = true
            } else { await loadCatalog() }
        }
    }

    private func beginSearch() {
        guard searchExpansionID == nil else { return }
        if expandedCatalog && detent == .large {
            searchPresented = true
            return
        }
        let requestID = UUID()
        searchExpansionID = requestID
        // 先提交导航栏、列表和 detent 的变更；动画结束后才激活已有的搜索控制器。
        withAnimation(.easeInOut(duration: 0.3), completionCriteria: .removed) {
            detent = .large
            expandedCatalog = true
        } completion: {
            guard searchExpansionID == requestID, category == "手帐", path.isEmpty,
                  expandedCatalog, detent == .large else { return }
            searchExpansionID = nil
            searchPresented = true
        }
    }

    private func cancelSearchActivation() {
        searchExpansionID = nil
        searchPresented = false
    }

    /// 测量自然内容，而不是 sheet 容器高度，避免 detent 与布局互相放大。
    private func fitSheet(content: CGFloat, actions: CGFloat) {
        let height = max(280, ceil(content + actions + 8))
        guard abs(fittedHeight - height) > 1 else { return }
        let followsContent = detent != .large && !fullHeight
        fittedHeight = height
        if followsContent { detent = .height(height) }
    }

    private var blankDesigns: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(["0", "1", "2"], id: \.self) { id in
                    Button { blankPalette = id } label: {
                        VStack(spacing: 10) {
                            Rectangle().fill(Color(uiColor: DiaryPageRenderer.color(id == "2" ? DiaryAlbumTheme.film.palette("1").paper : DiaryAlbumTheme.minimal.palette(id).paper)))
                                .aspectRatio(176.0 / 250, contentMode: .fit)
                                .overlay(Rectangle().stroke(blankPalette == id ? DiaryLibraryStyle.accent : DiaryLibraryStyle.line, lineWidth: blankPalette == id ? 2 : 1))
                            Text(id == "0" ? "白纸" : id == "1" ? "暖纸" : "深色纸").font(.subheadline)
                        }
                    }.buttonStyle(.plain).accessibilityAddTraits(blankPalette == id ? .isSelected : [])
                }
            }.padding(.vertical)
            Text("B5 竖版 · 从一张白纸开始，创建后自由添加照片与文字。")
                .font(.footnote).foregroundStyle(.secondary)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                if height > 0, abs(blankContentHeight - height) > 1 { blankContentHeight = height }
            }
        }
    }

    private var expandedPresets: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                if !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let matches = items.filter {
                        $0.matches(search: search, series: "", styles: [], usages: [])
                    }
                    if matches.isEmpty {
                        ContentUnavailableView("暂无匹配的模板", systemImage: "books.vertical",
                            description: Text("试试其他关键词。"))
                    }
                    ForEach(matches) { item in
                        expandedTemplateLink(item, expanded: true)
                    }
                } else {
                    ForEach(PresetLibrarySection.group(items, series: series)) { section in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text(section.title).font(.title3.weight(.semibold))
                                Spacer()
                                Text("\(section.items.count) 本").font(.caption)
                                    .foregroundStyle(DiaryLibraryStyle.secondary)
                            }.frame(minHeight: 44)
                            DiaryPresetTemplateCarousel(count: section.items.count) { index in
                                expandedTemplateLink(section.items[index])
                            }.id(section.items.map(\.id))
                        }
                    }
                }
            }
            .frame(maxWidth: 1200)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func expandedTemplateLink(_ item: PresetLibraryItem, expanded: Bool = false) -> some View {
        NavigationLink(value: Route.preview(item.id)) {
            DiaryPresetTemplateCard(item: item, ownerID: ownerID,
                downloadedCount: item.remote.map {
                    availability.downloadedPageIDs(bookID: $0.id, version: $0.version).count
                } ?? 0, expanded: expanded)
        }.buttonStyle(.plain)
    }

    private func loadCatalog() async {
        error = nil
        downloads.activate(owner: ownerID)
        await downloads.waitUntilRestored()
        if let cached = PresetLibraryCatalogCache.read(ownerID: ownerID) { update(cached) }
        do {
            let catalog = try await downloads.catalog()
            PresetLibraryCatalogCache.save(catalog, ownerID: ownerID)
            update(catalog)
        } catch { self.error = error.localizedDescription }
        loaded = true
    }

    private func update(_ catalog: RemotePresetCatalog) {
        series = catalog.series
        items = PresetLibraryItem.merge(local: catalog.books.compactMap { downloads.completeCachedPackage(for: $0) }, remote: catalog.books)
        if !items.contains(where: { $0.id == selectedID }) { selectedID = nil }
    }
}

/// 先展示预览步骤；完整素材的下载进度由共享导入页负责。
private struct DiaryCreatePresetDestination: View {
    let ownerID: String
    let item: PresetLibraryItem
    @Binding var path: NavigationPath
    let completed: (DiaryBook) -> Void
    @State private var preparation: PresetImportPreparation?
    @State private var browse: RemotePresetBrowse?
    @State private var error: String?
    @State private var retry = 0

    var body: some View {
        Group {
            if let preparation {
                DiaryPresetImportSheet(ownerID: ownerID, package: preparation.package,
                    pageIDs: preparation.package.manifest.pages.map(\.id), defaultTarget: nil, wholeBook: true,
                    remoteBook: preparation.downloadID == nil ? nil : item.remote,
                    initialDownloadID: preparation.downloadID, loadingPages: browse?.pages ?? [],
                    loadingPreviewSize: browse?.page_size.cg ?? preparation.package.manifest.pageSize.cg,
                    creationFlow: true, externalPath: $path, completed: completed)
            } else {
                VStack(spacing: 16) {
                    if let error {
                        Text(error).foregroundStyle(.red)
                        Button("重试") { retry += 1 }
                    } else { ProgressView("正在读取预览…") }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(DiaryLibraryStyle.background)
                    .navigationTitle("预览手帐")
        .navigationBarTitleDisplayMode(.inline)
            }
        }
        .task(id: retry) {
            error = nil
            do {
                if let local = item.local {
                    preparation = PresetImportPreparation(package: local, downloadID: nil)
                } else if let remote = item.remote {
                    let manager = PresetDownloadManager.shared
                    let value = try await manager.browse(remote, ownerID: ownerID)
                    try Task.checkCancellation()
                    browse = value
                    let prepared = try await manager.prepareImport(book: remote,
                        pageIDs: value.pages.map(\.id), wholeBook: true, ownerID: ownerID)
                    try Task.checkCancellation()
                    preparation = prepared
                }
            } catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }
}

/// SwiftUI onAppear 会在交互式返回开始时触发；UIKit didAppear 只在返回完成后触发。
/// 只观察原生容器的生命周期，不替换导航代理或右滑手势代理。
private struct DiaryNavigationAppearanceObserver: UIViewControllerRepresentable {
    let appeared: () -> Void

    func makeUIViewController(context: Context) -> Controller {
        let controller = Controller()
        controller.appeared = appeared
        return controller
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.appeared = appeared
    }

    final class Controller: UIViewController {
        var appeared: (() -> Void)?

        override func loadView() {
            view = UIView()
            view.backgroundColor = .clear
            view.isUserInteractionEnabled = false
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard let coordinator = transitionCoordinator else {
                appeared?()
                return
            }
            // 如果子控制器先收到显示回调，仍等待导航容器的转场完成。
            let observing = coordinator.animate(alongsideTransition: nil) { [weak self] context in
                guard !context.isCancelled else { return }
                self?.appeared?()
            }
            if !observing { appeared?() }
        }
    }
}
