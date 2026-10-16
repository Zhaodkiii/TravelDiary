import SwiftUI
import Combine

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
    let onAdd: ([String], Bool) -> Void
    @ViewBuilder let detail: () -> Detail
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var previews = PresetPreviewWindow()
    @State private var showingList = false
    @State private var spread = 0
    @State private var opened = false
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
        VStack(spacing: 16) {
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
                .overlay(alignment: .top) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(seriesTitle).font(.subheadline).lineLimit(2)
                            Text("共 \(content.count) 页").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        if allowsWholeBook {
                            Button("整本添加") { onAdd(pages.map(\.id), true) }
                                .buttonStyle(.bordered).controlSize(.small)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, max(12, geometry.size.height * 0.08))
                }
                .overlay {
                    let heightPerWidth = (0.955 * (1 - DiaryBookSpine.halfGapFraction) / ratio + 0.09) / 2
                    let bookHeight = min(max(1, geometry.size.width - 24) * heightPerWidth, max(1, geometry.size.height - 24))
                    addCurrentPageMenu
                        .position(x: geometry.size.width / 2,
                                  y: min(geometry.size.height - 24, geometry.size.height / 2 + bookHeight / 2 + 32))
                }
            }.clipped()
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
            }.padding(.horizontal, 28)
            DiaryBookThumbnailRail(hasCover: shell != nil, spreadCount: spreadCount,
                spread: spread, opened: opened, title: spreadTitle,
                onClose: { spread = 0; opened = false },
                onSelect: { spread = $0; opened = true }) {
                    if let shell { preview(shell) }
                } leaf: { index in leaf(index) }

        }
        .background(Color(uiColor: .systemGroupedBackground))
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
        .onDisappear { previews.update([]) }
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
    private var tasks: [URL: Task<Void, Never>] = [:]
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
            if let image = previews.images[url] {
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
