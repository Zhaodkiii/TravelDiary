import SwiftUI

/// 每页独立滚动吸附，显示任意相邻两页；取消勾选不重排页面。
struct DiaryPresetImportPreview: View {
    let package: DiaryPresetPackage?
    let pageIDs: [String]
    @Binding var excludedPageIDs: Set<String>
    let hiddenCategories: Set<DiaryLayerSemanticKind>
    @Binding var scrollPage: Int?
    var loadingPages: [RemotePresetPage] = []
    var loadingSize: CGSize = CGSize(width: 1, height: 1.4)
    private struct Page: Identifiable {
        let id: String
        let title: String
        let size: CGSize
        let previewPath: String?
        let thumbnailURL: URL?
    }
    @State private var pages: [Page] = []
    @State private var images: [String: UIImage] = [:]
    @State private var loadError: String?
    @State private var renderError: String?
    @State private var retry = 0
    @StateObject private var renderer = PresetCategoryRenderer()

    private var firstVisiblePage: Int { min(max(0, scrollPage ?? 0), max(0, positionCount - 1)) }
    private var positionCount: Int { max(1, pages.count - 1) }
    private var visiblePages: [Page] {
        Array(pages.dropFirst(firstVisiblePage).prefix(2))
    }
    // 当前两页及两侧露出的邻页都使用当前图层开关。
    private var previewPages: [Page] {
        let lower = max(0, firstVisiblePage - 1)
        let upper = min(pages.count, firstVisiblePage + 3)
        return Array(pages[lower..<upper])
    }
    private var renderID: String {
        (package?.root.path ?? "remote") + previewPages.map(\.id).joined(separator: ",")
        + hiddenCategories.map(\.rawValue).sorted().joined(separator: ",") + "-\(retry)"
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("已选 \(pageIDs.count - excludedPageIDs.count) / \(pageIDs.count) 页")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Menu("批量选择") {
                    Button("全选") { excludedPageIDs.removeAll() }
                    Button("取消全选") { excludedPageIDs = Set(pageIDs) }
                    if pages.count > 1 {
                        Button("选中当前两页") { excludedPageIDs.subtract(visiblePages.map(\.id)) }
                        Button("取消当前两页") { excludedPageIDs.formUnion(visiblePages.map(\.id)) }
                    }
                }.frame(minHeight: 44)
            }
            if pages.isEmpty {
                if let loadError { failure(loadError) }
                else { ProgressView("正在读取页面…").frame(maxHeight: .infinity) }
            } else {
                DiaryPresetSpreadCarousel(count: pages.count, position: $scrollPage) { index in
                    pageCard(pages[index], active: index >= firstVisiblePage - 1 && index <= firstVisiblePage + 2)
                }
                if !hiddenCategories.isEmpty, let renderError { failure(renderError) }
            }
        }
        .task(id: (package?.root.path ?? "remote") + "-\(retry)") {
            loadError = nil
            do {
                if let package {
                    let values = try await Task.detached {
                        try pageIDs.map { id in
                            guard let ref = package.manifest.pages.first(where: { $0.id == id }) else { throw DiaryEditorError.invalidDocument }
                            return try package.read(PresetPage.self, ref.path)
                        }
                    }.value
                    try Task.checkCancellation()
                    pages = values.map { Page(id: $0.id, title: $0.title, size: $0.size.cg,
                        previewPath: $0.preview.largePath, thumbnailURL: nil) }
                } else {
                    pages = pageIDs.compactMap { id in
                        loadingPages.first { $0.id == id }.map {
                            Page(id: $0.id, title: $0.title, size: loadingSize,
                                previewPath: nil, thumbnailURL: URL(string: $0.thumbnail_url))
                        }
                    }
                }
            } catch is CancellationError { }
            catch { loadError = error.localizedDescription }
        }
        .task(id: renderID) {
            images = [:]; renderError = nil
            guard let package, !hiddenCategories.isEmpty, !previewPages.isEmpty else { return }
            do {
                try await Task.sleep(for: .milliseconds(100))
                let result = try await renderer.render(package: package, pageIDs: previewPages.map(\.id), hidden: hiddenCategories,
                    maximumDimension: pages.count == 1 ? 1400 : 900)
                try Task.checkCancellation()
                images = result
            } catch is CancellationError { }
            catch { if !Task.isCancelled { renderError = error.localizedDescription } }
        }
    }

    private func pageCard(_ page: Page, active: Bool) -> some View {
        let selected = !excludedPageIDs.contains(page.id)
        return Button {
            if selected { excludedPageIDs.insert(page.id) }
            else { excludedPageIDs.remove(page.id) }
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    Rectangle().fill(DiaryLibraryStyle.surface)
                    if !active { Color.clear }
                    else if hiddenCategories.isEmpty, let package, let path = page.previewPath {
                        DiaryPresetImage(package: package, path: path, size: page.size)
                    } else if package == nil {
                        AsyncImage(url: page.thumbnailURL) { phase in
                            if let image = phase.image { image.resizable().scaledToFit() }
                            else if phase.error != nil { Image(systemName: "photo.badge.exclamationmark") }
                            else { ProgressView() }
                        }
                    } else if let image = images[page.id] {
                        Image(uiImage: image).resizable().scaledToFit()
                    } else if renderError != nil {
                        Image(systemName: "exclamationmark.circle")
                    } else { ProgressView("更新预览…").font(.caption) }
                }
                .aspectRatio(page.size.width / max(1, page.size.height), contentMode: .fit)
                .opacity(selected ? 1 : 0.4)
                .overlay(alignment: .topTrailing) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.title2).symbolRenderingMode(.palette)
                        .foregroundStyle(selected ? DiaryLibraryStyle.accent : DiaryLibraryStyle.secondary, DiaryLibraryStyle.surface)
                        .padding(8)
                }
                .overlay { Rectangle().strokeBorder(selected ? DiaryLibraryStyle.accent : DiaryLibraryStyle.line, lineWidth: selected ? 2 : 1) }
                Text(page.title).font(.caption).lineLimit(2)
                    .foregroundStyle(DiaryLibraryStyle.ink)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(page.title)
        .accessibilityValue(selected ? "已选中" : "未选中")
        .accessibilityHint("轻点切换是否添加这一页")
    }

    private func failure(_ message: String) -> some View {
        VStack {
            Text(message).font(.caption).foregroundStyle(.red)
            Button("重试预览") { retry += 1 }
        }
    }
}

/// 页码栏与预览共用滚动位置，由导入页放在固定的底部区域。
struct DiaryPresetImportPageControls: View {
    let count: Int
    @Binding var position: Int?
    private var first: Int { min(max(0, position ?? 0), max(0, count - 2)) }

    var body: some View {
        HStack {
            Button { withAnimation(.snappy) { position = first - 1 } } label: {
                Image(systemName: "chevron.left").frame(minWidth: 44, minHeight: 44)
            }
            .disabled(first == 0).accessibilityLabel("上一页")
            Spacer()
            Text(count <= 1 ? "第 \(count) 页" : "第 \(first + 1)–\(min(first + 2, count)) 页 / \(count)")
                .font(.caption.monospacedDigit())
            Spacer()
            Button { withAnimation(.snappy) { position = first + 1 } } label: {
                Image(systemName: "chevron.right").frame(minWidth: 44, minHeight: 44)
            }
            .disabled(first >= max(0, count - 2)).accessibilityLabel("下一页")
        }
        .buttonStyle(.plain)
    }
}
