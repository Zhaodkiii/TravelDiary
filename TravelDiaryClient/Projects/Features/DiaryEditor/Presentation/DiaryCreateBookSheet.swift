import SwiftUI
import UIKit

/// 首页创建入口：轻量挑选预设，再复用模板库的预览、下载和照片流程。
struct DiaryCreateBookSheet: View {
    let ownerID: String
    let completed: (DiaryBook) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var path = NavigationPath()
    @State private var detent: PresentationDetent = .fraction(0.48)
    @State private var fullHeight = false
    @State private var items: [PresetLibraryItem] = []
    @State private var selectedID: String?
    @State private var compactPosition: Int? = 0
    @State private var expandedCatalog = false
    @State private var search = ""
    @State private var series: [RemotePresetCatalog.Series] = []
    @State private var loaded = false
    @State private var error: String?
    private let downloads = PresetDownloadManager.shared
    @ObservedObject private var availability = PresetDownloadManager.shared.availability

    private enum Route: Hashable { case preview(String) }

    var body: some View {
        NavigationStack(path: $path) {
            GeometryReader { geometry in
                VStack(alignment: .leading, spacing: 8) {
                    if !loaded && items.isEmpty {
                        ProgressView("正在读取预设…").frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if items.isEmpty {
                        Text(error ?? "暂无可用预设").font(.footnote).foregroundStyle(.secondary)
                        Button("重新加载") { Task { await loadCatalog() } }
                        Spacer()
                    } else if expandedCatalog {
                        expandedPresets
                    } else {
                        DiaryPresetTemplateCarousel(count: items.count, position: $compactPosition) { index in
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
                            .accessibilityAddTraits(selectedID == item.id ? .isSelected : [])
                        }
                        .frame(height: max(80, geometry.size.height))
                    }
                }.padding(.horizontal, 20)
            }
            .background(DiaryLibraryStyle.background)
            .background {
                DiaryNavigationAppearanceObserver {
                    // 原生 pop（包含右滑）完成后，才恢复选择页高度。
                    withAnimation {
                        expandedCatalog = false
                        fullHeight = false
                        detent = .fraction(0.48)
                    }
                }
            }
            .navigationTitle("新建手帐本")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭", systemImage: "xmark") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if detent != .large {
                    DiaryImportFloatingActions {
                        NavigationLink(value: selectedID.map { Route.preview($0) }) {
                            Text("下一步").frame(maxWidth: .infinity)
                        }.disabled(selectedID == nil)
                    }
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .preview(let id):
                    if let item = items.first(where: { $0.id == id }) {
                        DiaryCreatePresetDestination(ownerID: ownerID, item: item, path: $path, completed: completed)
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
        .presentationDetents(fullHeight ? [.large] : [.fraction(0.48), .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .task(id: detent == .large && path.isEmpty) {
            guard detent == .large, path.isEmpty else {
                if detent != .large { expandedCatalog = false }
                return
            }
            do {
                try await Task.sleep(for: .seconds(1))
                try Task.checkCancellation()
                withAnimation(.easeInOut(duration: 0.2)) { expandedCatalog = true }
            } catch is CancellationError { }
            catch { }
        }
        .task { await loadCatalog() }
    }

    private var expandedPresets: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                DiaryLibrarySearch(text: $search, prompt: "搜索模板名称")
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
