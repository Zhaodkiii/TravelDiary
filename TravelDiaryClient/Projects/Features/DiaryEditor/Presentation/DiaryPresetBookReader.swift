import SwiftUI
import Combine
import ImageIO

/// Read-only projection of preset previews; never imports pages into the user's library.
struct DiaryPresetBookReader<Detail: View>: View {
    struct Page: Identifiable {
        let id: String
        let url: URL
        let size: CGSize
        let thumbnailURL: URL?
        init(id: String, url: URL, size: CGSize, thumbnailURL: URL? = nil) {
            self.id = id; self.url = url; self.size = size; self.thumbnailURL = thumbnailURL
        }
    }
    let title: String
    let pages: [Page]
    let shellID: String?
    let seriesTitle: String
    var allowsWholeBook = true
    var localPackage: DiaryPresetPackage? = nil
    var remoteBook: RemotePresetBook? = nil
    var ownerID: String? = nil
    let onAdd: ([String], Bool) -> Void
    @ViewBuilder let detail: () -> Detail
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var previews = PresetPreviewWindow()
    @State private var showingList = false
    @State private var spread = 0
    @State private var opened = false
    @State private var hiddenCategories: Set<DiaryLayerSemanticKind> = []
    @State private var filterRetry = 0
    @StateObject private var categoryRenderer = PresetCategoryRenderer()
    @State private var categoryDownload = PresetCategoryDownloadState()
    @State private var categoryError: String?
    @State private var updatingCategories = false
    private var supportsCategoryControls: Bool { localPackage != nil || remoteBook != nil }
    private var content: [Page] { pages.filter { $0.id != shellID } }
    private var shell: Page? { pages.first { $0.id == shellID } }
    private var spreadCount: Int { content.isEmpty ? 0 : (content.count + 2) / 2 }
    private var ratio: CGFloat {
        let size = content.first?.size ?? CGSize(width: 1, height: 1.4)
        return size.width / max(1, size.height)
    }

    private var largePreviewURLs: [URL] {
        if !opened, let shell { return [shell.url] }
        return PresetPreviewWindow.urls(content: content.map(\.url), spread: spread)
    }

    var body: some View {
        GeometryReader { available in
//            ScrollView(.vertical) {
//            }.scrollIndicators(.hidden)

            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(seriesTitle).font(.subheadline.weight(.medium)).lineLimit(2)
                        Text("共 \(content.count) 页").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    if allowsWholeBook {
                        Button("整本添加") { onAdd(pages.map(\.id), true) }
                            .font(.subheadline).buttonStyle(.bordered)
                            .buttonBorderShape(.capsule).fixedSize()
                            .frame(minHeight: 44)
                    }
                }.padding(.horizontal, 24)
                GeometryReader { geometry in
                    DiaryBookZoomViewport(contentSize: geometry.size, resetToken: opened ? spread + 1 : 0) {
                        if let shell, !opened {
                            PresetLargePreview(url: shell.url, thumbnailURL: shell.thumbnailURL, previews: previews).frame(width: geometry.size.width * 0.8, height: geometry.size.height * 0.88)
                                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                                .onTapGesture { opened = true }
                        } else {
                            GeometryReader { viewport in
                                let heightPerWidth = (0.955 * (1 - DiaryBookSpine.halfGapFraction) / ratio + 0.09) / 2
                                let width = min(max(1, viewport.size.width - 24), max(1, viewport.size.height - 24) / heightPerWidth)
                                let rim = width * 0.0225
                                ZStack {
                                    Image("DiaryBookLeather").resizable()
                                    DiaryPageCurlReader(spreadCount: spreadCount, spread: $spread, reduceMotion: reduceMotion) { index, _ in
                                        DiaryPresetPaperController(index: index,
                                            url: content.indices.contains(index - 1) ? content[index - 1].url : nil,
                                            thumbnailURL: content.indices.contains(index - 1) ? content[index - 1].thumbnailURL : nil,
                                            previews: previews)
                                    }.id(content.map(\.url)).padding(rim)
                                }
                                .frame(width: width, height: width * heightPerWidth)
                                .position(x: viewport.size.width / 2, y: viewport.size.height / 2)
                            }
                        }
                    }
                }
                .frame(height: max(200, min(available.size.width * 0.78, available.size.height - 380)))
                .clipped()
                addCurrentPageMenu
                    .frame(minHeight: 44)
                if supportsCategoryControls && opened { categoryControls }
                HStack {
                    Button {
                        if spread > 0 { spread -= 1 } else { opened = false }
                    } label: { Image(systemName: "chevron.left") }
                        .disabled(!opened || (spread == 0 && shell == nil))
                    Spacer()
                    Text(!opened && shell != nil ? "外壳" : spread == 0 ? "第 1 页 / \(content.count)" : "第 \(spread * 2)–\(min(spread * 2 + 1, content.count)) 页 / \(content.count)")
                        .font(.subheadline.monospacedDigit())
                    Spacer()
                    Button {
                        if !opened { opened = true } else { spread += 1 }
                    } label: { Image(systemName: "chevron.right") }
                        .disabled(content.isEmpty || (opened && spread >= spreadCount - 1))
                }.frame(minHeight: 44).padding(.horizontal, 28)
                DiaryBookThumbnailRail(hasCover: shell != nil, spreadCount: spreadCount,
                    spread: spread, opened: opened, title: spreadTitle,
                    onClose: { spread = 0; opened = false },
                    onSelect: { spread = $0; opened = true }) {
                        if let shell { preview(shell) }
                    } leaf: { index in leaf(index) }

            }.padding(.top, 12).padding(.bottom, 8)

        }
        .tint(DiaryLibraryStyle.accent)
        .background(DiaryLibraryStyle.background)
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingList = true } label: { Image(systemName: "list.bullet") }
                    .accessibilityLabel("预设页面列表")
            }
        }
        .navigationDestination(isPresented: $showingList) { detail() }
        .onAppear {
            if shell == nil { opened = true }
            previews.update(largePreviewURLs)
        }
        .onChange(of: largePreviewURLs) { _, urls in previews.update(urls) }
        .onChange(of: spread) { _, _ in hiddenCategories = []; previews.clearCategoryFilter() }
        .onChange(of: opened) { _, _ in hiddenCategories = []; previews.clearCategoryFilter() }
        .task(id: categoryRequestID) { await updateCategoryPreview() }
        .onDisappear { previews.update([]); previews.clearCategoryFilter(); categoryRenderer.reset(); categoryDownload.reset() }
    }

    private var categoryRequestID: String {
        "\(spread)-\(opened)-\(filterRetry)-" + hiddenCategories.map(\.rawValue).sorted().joined(separator: ",") + [leftPage, rightPage].compactMap { $0?.url.absoluteString }.joined(separator: "|")
    }

    private var categoryControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            DiaryPreviewContentPanel(hiddenCategories: $hiddenCategories)
            if remoteBook != nil { PresetCategoryDownloadFeedback(state: categoryDownload) }
            if let categoryError {
                VStack(alignment: .leading, spacing: 4) {
                    Label("预览未更新", systemImage: "exclamationmark.circle")
                    Text(categoryError).foregroundStyle(DiaryLibraryStyle.secondary)
                    Button("重试预览") { filterRetry += 1 }.frame(minHeight: 44)
                }.font(.caption)
            } else if updatingCategories && (remoteBook == nil || categoryDownload.ready) {
                ProgressView("正在更新预览…").font(.caption)
            }
        }
        .tint(DiaryLibraryStyle.accent)
        .padding(.horizontal, 24)
    }

    private func updateCategoryPreview() async {
        let requestID = categoryRequestID
        categoryError = nil
        updatingCategories = false
        guard supportsCategoryControls, opened, !hiddenCategories.isEmpty else {
            previews.clearCategoryFilter(); categoryRenderer.reset(); categoryDownload.reset(); return
        }
        updatingCategories = true
        defer { if requestID == categoryRequestID { updatingCategories = false } }
        let visiblePages = [leftPage, rightPage].compactMap { $0 }
        let urls = visiblePages.map(\.url)
        do {
            try await Task.sleep(for: .milliseconds(100))
            let package: DiaryPresetPackage
            if let localPackage { package = localPackage }
            else if let remoteBook, let ownerID {
                // 素材准备期间保留完整预览，下载状态单独展示。
                previews.clearCategoryFilter()
                package = try await categoryDownload.load(book: remoteBook,
                    pageIDs: visiblePages.map(\.id), ownerID: ownerID)
            } else { return }
            try Task.checkCancellation()
            previews.beginCategoryFilter(urls)
            let images = try await categoryRenderer.render(package: package,
                pageIDs: visiblePages.map(\.id), hidden: hiddenCategories)
            try Task.checkCancellation()
            previews.finishCategoryFilter(Dictionary(uniqueKeysWithValues: visiblePages.compactMap { page in
                images[page.id].map { (page.url, $0) }
            }))
        } catch is CancellationError { }
        catch {
            guard !Task.isCancelled else { return }
            categoryError = error.localizedDescription
            previews.failCategoryFilter()
        }
    }

    private var leftPage: Page? {
        let index = spread * 2 - 1
        return opened && content.indices.contains(index) ? content[index] : nil
    }
    private var rightPage: Page? {
        let index = spread * 2
        return opened && content.indices.contains(index) ? content[index] : nil
    }
    private var addCurrentPageMenu: some View {
        Menu {
            Button("左页") { if let leftPage { onAdd([leftPage.id], false) } }
                .disabled(leftPage == nil)
            Button("右页") { if let rightPage { onAdd([rightPage.id], false) } }
                .disabled(rightPage == nil)
            Button("双页") {
                if let leftPage, let rightPage { onAdd([leftPage.id, rightPage.id], false) }
            }.disabled(leftPage == nil || rightPage == nil)
        } label: {
            Label("添加当前页", systemImage: "plus")
                .font(.subheadline.weight(.medium)).padding(.horizontal, 12)
        }
        .buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
        .disabled(leftPage == nil && rightPage == nil)
    }

    private func spreadTitle(_ index: Int) -> String {
        if index == 0 { return "第 1 页" }
        let first = index * 2
        let last = min(first + 1, content.count)
        return first == last ? "第 \(first) 页" : "第 \(first)–\(last) 页"
    }
    @ViewBuilder private func leaf(_ index: Int) -> some View {
        ZStack {
            Color(red: 0.96, green: 0.92, blue: 0.82)
            if index == -1 { DiaryBookLining() }
            else if content.indices.contains(index) { preview(content[index]) }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
    }
    private func preview(_ page: Page) -> some View {
        DiaryPresetReaderImage(url: page.thumbnailURL ?? page.url)
    }
}

struct DiaryPresetReaderImage: View {
    let url: URL
    @State private var image: UIImage?
    @State private var failed = false
    @State private var retry = 0
    var body: some View {
        ZStack {
            if let image { Image(uiImage: image).resizable().scaledToFit() }
            else if failed { Button("重试预览") { retry += 1 }.font(.caption) }
            else { ProgressView() }
        }.task(id: "\(url)-\(retry)") {
            failed = false
            do {
                let data: Data
                if url.isFileURL { data = try await Task.detached { try Data(contentsOf: url) }.value }
                else {
                    let response = try await URLSession.shared.data(from: url)
                    guard (response.1 as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                    data = response.0
                }
                try Task.checkCancellation()
                image = UIImage(data: data); failed = image == nil
            } catch is CancellationError { }
            catch { failed = true }
        }
    }
}

@MainActor
private final class DiaryPresetPaperController: UIHostingController<DiaryPresetPaper>, DiaryIndexedPaper {
    let index: Int
    init(index: Int, url: URL?, thumbnailURL: URL?, previews: PresetPreviewWindow) {
        self.index = index
        super.init(rootView: DiaryPresetPaper(index: index, url: url, thumbnailURL: thumbnailURL, previews: previews))
        view.backgroundColor = .clear
        safeAreaRegions = []
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("不支持 Storyboard") }
}

private struct DiaryPresetPaper: View {
    let index: Int
    let url: URL?
    let thumbnailURL: URL?
    let previews: PresetPreviewWindow
    var body: some View {
        GeometryReader { geometry in
            let left = index.isMultiple(of: 2)
            ZStack {
                Color(red: 0.96, green: 0.92, blue: 0.82)
                if index == 0 { DiaryBookLining().accessibilityLabel("内封皮") }
                else if let url { PresetLargePreview(url: url, thumbnailURL: thumbnailURL, previews: previews) }
                HStack(spacing: 0) {
                    if left { Spacer(minLength: 0) }
                    LinearGradient(colors: [.black.opacity(0.16), .clear],
                        startPoint: left ? .trailing : .leading, endPoint: left ? .leading : .trailing)
                        .frame(width: 18)
                    if !left { Spacer(minLength: 0) }
                }.allowsHitTesting(false)
            }
            .frame(width: geometry.size.width * (1 - DiaryBookSpine.halfGapFraction), height: geometry.size.height)
            .clipped()
            .shadow(color: .black.opacity(0.35), radius: 1.5, x: left ? 1.5 : -1.5)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: left ? .leading : .trailing)
        }
    }
}


/// Owns large-image requests for only the visible spread and its two neighbors.
@MainActor
final class PresetPreviewWindow: ObservableObject {
    @Published private(set) var images: [URL: UIImage] = [:]
    @Published private(set) var failed: Set<URL> = []
    @Published private(set) var categoryImages: [URL: UIImage] = [:]
    @Published private(set) var categoryURLs: Set<URL> = []
    @Published private(set) var categoryFailed = false
    private var tasks: [URL: Task<Void, Never>] = [:]

    func beginCategoryFilter(_ urls: [URL]) {
        categoryImages = [:]; categoryFailed = false; categoryURLs = Set(urls)
    }
    func finishCategoryFilter(_ images: [URL: UIImage]) { categoryImages = images }
    func failCategoryFilter() { categoryFailed = true }
    func clearCategoryFilter() {
        categoryURLs = []; categoryImages = [:]; categoryFailed = false
    }
    private var active: Set<URL> = []

    nonisolated static func urls(content: [URL], spread: Int) -> [URL] {
        guard !content.isEmpty else { return [] }
        // Paper 0 is the lining; paper n displays content[n - 1].
        let lower = max(0, max(0, spread - 1) * 2 - 1)
        let upper = min(content.count - 1, (spread + 1) * 2)
        guard lower <= upper else { return [] }
        return Array(content[lower...upper])
    }

    func update(_ urls: [URL]) {
        let wanted = Set(urls)
        for url in Array(tasks.keys) where !wanted.contains(url) {
            tasks.removeValue(forKey: url)?.cancel()
        }
        active = wanted
        images = images.filter { wanted.contains($0.key) }
        failed.formIntersection(wanted)
        for url in urls where images[url] == nil && tasks[url] == nil && !failed.contains(url) {
            tasks[url] = Task { [weak self] in
                do {
                    let data: Data
                    if url.isFileURL { data = try await Task.detached { try Data(contentsOf: url) }.value }
                    else {
                        let response = try await URLSession.shared.data(from: url)
                        guard (response.1 as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                        data = response.0
                    }
                    try Task.checkCancellation()
                    guard let self, self.active.contains(url) else { return }
                    if let image = UIImage(data: data) { self.images[url] = image }
                    else { self.failed.insert(url) }
                    self.tasks[url] = nil
                } catch {
                    guard !Task.isCancelled, let self, self.active.contains(url) else { return }
                    self.failed.insert(url)
                    self.tasks[url] = nil
                }
            }
        }
    }

    func retry(_ url: URL) {
        failed.remove(url)
        update(Array(active))
    }
}

private struct PresetLargePreview: View {
    let url: URL
    let thumbnailURL: URL?
    @ObservedObject var previews: PresetPreviewWindow
    var body: some View {
        ZStack {
            if previews.categoryURLs.contains(url) {
                if let image = previews.categoryImages[url] {
                    Image(uiImage: image).resizable().scaledToFit()
                } else if previews.categoryFailed {
                    Text("预览生成失败").font(.caption).foregroundStyle(.secondary)
                } else { ProgressView("正在更新预览…").font(.caption) }
            } else if let image = previews.images[url] {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                if let thumbnailURL { DiaryPresetReaderImage(url: thumbnailURL) }
                else { ProgressView() }
                if previews.failed.contains(url) {
                    Button("重试大图") { previews.retry(url) }.font(.caption)
                        .padding(6).background(.regularMaterial, in: Capsule())
                }
            }
        }
    }
}

/// 当前跨页的临时预览缓存。磁盘读取和图片解码在后台，绘制复用正式页面绘制器。
@MainActor
final class PresetCategoryRenderer: ObservableObject {
    private struct Prepared: Sendable {
        let document: DiaryDocument
        let images: [UUID: UIImage]
    }
    private var identity = ""
    private var prepared: [String: Prepared] = [:]
    private var preparedOrder: [String] = []

    func reset() { identity = ""; prepared = [:]; preparedOrder = [] }

    func render(package: DiaryPresetPackage, pageIDs: [String], hidden: Set<DiaryLayerSemanticKind>,
                maximumDimension: Int = 1400) async throws -> [String: UIImage] {
        // 页组合改变不应使已解码素材失效；图层开关也可复用原始页面。
        let key = package.root.path + "-\(maximumDimension)"
        if identity != key { reset(); identity = key }
        var result: [String: UIImage] = [:]
        for id in pageIDs {
            try Task.checkCancellation()
            let page: Prepared
            if let cached = prepared[id] { page = cached }
            else {
                let work = Task.detached(priority: .userInitiated) { try Self.prepare(package: package, pageID: id, maximumDimension: maximumDimension) }
                page = try await withTaskCancellationHandler(operation: { try await work.value }, onCancel: { work.cancel() })
                try Task.checkCancellation()
                guard identity == key else { throw CancellationError() }
                prepared[id] = page
            }
            preparedOrder.removeAll { $0 == id }
            preparedOrder.append(id)
            while preparedOrder.count > 6 {
                prepared.removeValue(forKey: preparedOrder.removeFirst())
            }
            let document = page.document.excludingPresetCategories(hidden)
            let size = document.root.referenceSize
            let scale = min(1, CGFloat(maximumDimension) / max(size.width, size.height))
            let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = false
            let output = CGSize(width: size.width * scale, height: size.height * scale)
            result[id] = UIGraphicsImageRenderer(size: output, format: format).image { renderer in
                renderer.cgContext.scaleBy(x: scale, y: scale)
                DiaryPageRenderer.draw(document, images: page.images, in: renderer.cgContext, cacheObjects: false)
            }
            await Task.yield()
        }
        return result
    }

    nonisolated private static func prepare(package: DiaryPresetPackage, pageID: String, maximumDimension: Int) throws -> Prepared {
        guard let reference = package.manifest.pages.first(where: { $0.id == pageID }) else { throw DiaryEditorError.invalidDocument }
        let page = try package.read(PresetPage.self, reference.path)
        let ids = Dictionary(uniqueKeysWithValues: package.manifest.assetTable.keys.map { ($0, UUID()) })
        let document = try package.instantiate(page, bookID: UUID(), targetSize: page.size.cg, assetIDs: ids)
        var images: [UUID: UIImage] = [:]
        for (key, asset) in package.manifest.assetTable {
            try Task.checkCancellation()
            guard let id = ids[key], document.assets[id] != nil else { continue }
            guard let source = CGImageSourceCreateWithURL(try package.url(asset.path) as CFURL, nil),
                  let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: maximumDimension
                  ] as CFDictionary) else { throw DiaryEditorError.missingResource }
            images[id] = UIImage(cgImage: cg)
        }
        return Prepared(document: document, images: images)
    }
}

/// 下载属于全局下载中心；退出或翻页仅结束当前等待，不丢弃已完成的资源。
@MainActor
private final class PresetCategoryDownloadState: ObservableObject {
    @Published private(set) var job: PresetDownloadJob?
    @Published private(set) var preparing = false
    @Published private(set) var ready = false
    private var subscription: AnyCancellable?
    private let manager = PresetDownloadManager.shared

    func reset() { subscription = nil; job = nil; preparing = false; ready = false }
    func pause() { if let job { manager.pause(job.id) } }
    func resume() { if let job { manager.resume(job.id) } }
    func cancel() { if let job { manager.cancel(job.id) } }

    func load(book: RemotePresetBook, pageIDs: [String], ownerID: String) async throws -> DiaryPresetPackage {
        reset(); preparing = true
        defer { preparing = false }
        let value = try await manager.prepareCategoryPreview(book: book, pageIDs: pageIDs, ownerID: ownerID)
        try Task.checkCancellation()
        guard let id = value.downloadID else { ready = true; return value.package }
        subscription = manager.$jobs.map { $0.first { $0.id == id } }.removeDuplicates()
            .sink { [weak self] in self?.job = $0 }
        while true {
            try Task.checkCancellation()
            guard let current = manager.jobs.first(where: { $0.id == id }) else { throw DiaryEditorError.missingResource }
            if let package = manager.preparedPackage(id) { ready = true; return package }
            if current.status == "cancelled" {
                throw NSError(domain: "PresetCategoryPreview", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "素材下载已取消。"])
            }
            // 暂停或失败时保持等待，用户继续/重试后自动完成预览。
            try await Task.sleep(for: .milliseconds(200))
        }
    }
}

private struct PresetCategoryDownloadFeedback: View {
    @ObservedObject var state: PresetCategoryDownloadState
    var body: some View {
        VStack(spacing: 4) {
            if state.ready {
                EmptyView()
            } else if let job = state.job {
                let fraction = min(1, Double(job.bytes) / Double(max(1, job.total)))
                ProgressView(value: fraction)
                HStack {
                    Text(job.status == "verifying" ? "正在校验素材…" : job.status == "queued" ? "等待下载…" : job.status == "paused" ? "下载已暂停" : job.status == "failed" ? "下载失败" : "下载素材 \(Int(fraction * 100))%")
                    Spacer()
                    Text("\(ByteCountFormatter.string(fromByteCount: job.bytes, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: job.total, countStyle: .file))")
                }.font(.caption2).foregroundStyle(.secondary)
                HStack {
                    if ["queued", "downloading"].contains(job.status) {
                        Button("暂停", action: state.pause)
                    } else if ["paused", "failed"].contains(job.status) {
                        Button(job.status == "failed" ? "重试下载" : "继续", action: state.resume)
                    }
                    if !["ready", "completed", "cancelled"].contains(job.status) { Button("取消下载", action: state.cancel) }
                }.font(.caption)
                if job.status == "failed", let error = job.error { Text(error).font(.caption2).foregroundStyle(.secondary) }
            } else if state.preparing {
                ProgressView("正在获取当前跨页资源清单…").font(.caption)
            }
        }
    }
}
