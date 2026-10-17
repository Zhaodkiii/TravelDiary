import SwiftUI
import ImageIO

/// 与现有阅读器一致：去掉外壳后，第一页单独在右，随后按原页序两两展示。
/// 这是阅读顺序投影，不为旧包创造新的艺术跨页配对。
nonisolated enum DiaryMagazineSpreadSelection {
    static func select(pageIDs: [String], shellID: String?, coverID: String?) -> [[String]] {
        let content = pageIDs.filter { $0 != shellID }
        var spreads: [[String]] = []
        var index = 1
        while index < content.count && spreads.count < 2 {
            let pair = Array(content[index..<min(index + 2, content.count)])
            if !pair.contains(where: { $0 == coverID }) { spreads.append(pair) }
            index += 2
        }
        if spreads.isEmpty, let first = content.first, first != coverID { spreads = [[first]] }
        return spreads
    }
}

/// 左侧封面，右侧两张真实内页跨页缩略图。仅请求浏览目录和缩略图。
struct DiaryPresetMagazinePreview: View {
    let item: PresetLibraryItem
    let ownerID: String
    @State private var spreads: [[Leaf]] = []
    @State private var loading = true
    @State private var failed = false
    @State private var retry = 0

    private struct Leaf: Identifiable, Sendable {
        let id: String
        let url: URL?
        let size: CGSize
    }
    private var taskID: String { "\(ownerID):\(item.id):\(item.version):\(item.local?.root.path ?? "remote"):\(retry)" }

    var body: some View {
        GeometryReader { geometry in
            let gap: CGFloat = 12
            let width = max(1, geometry.size.width - 24 - gap)
            let height = max(1, geometry.size.height - 24)
            HStack(spacing: gap) {
                Group {
                    if let local = item.local { DiaryPresetCover(package: local) }
                    else if let remote = item.remote { DiaryRemoteCover(url: URL(string: remote.cover_url)) }
                }
                .frame(width: width * 0.46, height: height)
                .shadow(color: .black.opacity(0.10), radius: 4, y: 3)
                .accessibilityLabel("模板封面")

                VStack(spacing: gap) {
                    ForEach(0..<2, id: \.self) { index in
                        Group {
                            if spreads.indices.contains(index) {
                                spread(spreads[index])
                                    .accessibilityLabel("第 \(index + 1) 个内页预览，按页序展示")
                            } else { placeholder(index: index) }
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }.frame(width: width * 0.54, height: height)
            }.padding(12)
        }
        .aspectRatio(4.0 / 3, contentMode: .fit)
        .background(DiaryLibraryStyle.surface, in: RoundedRectangle(cornerRadius: 16))
        .task(id: taskID) { await load() }
    }

    private func spread(_ leaves: [Leaf]) -> some View {
        let ratio = leaves.first.map { max($0.size.width, 1) / max($0.size.height, 1) } ?? 0.7
        return GeometryReader { geometry in
            // 外沿和装订缝占据真实空间，与阅读器的纸张宽高比计算保持一致。
            let heightPerWidth = (0.955 * (1 - DiaryBookSpine.halfGapFraction) / ratio + 0.09) / 2
            let width = min(geometry.size.width, geometry.size.height / heightPerWidth)
            let height = width * heightPerWidth
            DiaryBoundSpread {
                previewLeaf(leaves.first)
            } right: {
                previewLeaf(leaves.count > 1 ? leaves[1] : nil)
            }
            .frame(width: width, height: height)
            .shadow(color: .black.opacity(0.10), radius: 3, y: 2)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
    private func previewLeaf(_ leaf: Leaf?) -> some View {
        ZStack {
            Color(red: 0.96, green: 0.92, blue: 0.82)
            if let leaf { DiaryMagazineThumbnail(url: leaf.url) }
        }
    }
    @ViewBuilder private func placeholder(index: Int) -> some View {
        if loading { ProgressView().accessibilityLabel("正在读取内页预览") }
        else if failed {
            VStack(spacing: 4) {
                Image(systemName: "photo")
                if index == 0 { Button("重试内页") { retry += 1 }.font(.caption).frame(minHeight: 44) }
            }.foregroundStyle(DiaryLibraryStyle.secondary)
        } else {
            VStack(spacing: 4) {
                Image(systemName: "book.pages")
                Text("暂无更多内页").font(.caption2)
            }.foregroundStyle(DiaryLibraryStyle.secondary)
        }
    }
    private func load() async {
        loading = true; failed = false; spreads = []
        do {
            let loaded: [[Leaf]]
            if let package = item.local ?? item.remote.flatMap({ PresetDownloadManager.shared.completeCachedPackage(for: $0) }) {
                loaded = try await Task.detached {
                    let groups = DiaryMagazineSpreadSelection.select(pageIDs: package.manifest.pages.map(\.id),
                        shellID: package.manifest.shellPageID, coverID: package.manifest.coverPageID)
                    return try groups.map { ids in
                        try ids.map { id in
                            guard let ref = package.manifest.pages.first(where: { $0.id == id }) else { throw DiaryEditorError.missingResource }
                            let page = try package.read(PresetPage.self, ref.path)
                            return Leaf(id: id, url: try package.url(page.preview.thumbnailPath), size: page.size.cg)
                        }
                    }
                }.value
            } else if let remote = item.remote {
                let browse = try await PresetDownloadManager.shared.browse(remote, ownerID: ownerID)
                loaded = DiaryMagazineSpreadSelection.select(pageIDs: browse.pages.map(\.id),
                    shellID: browse.shell_page_id, coverID: browse.cover_page_id).map { ids in
                    ids.map { id in
                        // 保留无效 URL 的页位，不 compactMap 导致左右页错位。
                        let page = browse.pages.first { $0.id == id }
                        return Leaf(id: id, url: page.flatMap { URL(string: $0.thumbnail_url) }, size: browse.page_size.cg)
                    }
                }
            } else { loaded = [] }
            try Task.checkCancellation()
            spreads = loaded; loading = false
        } catch is CancellationError { }
        catch { if !Task.isCancelled { loading = false; failed = true } }
    }
}

private struct DiaryMagazineThumbnail: View {
    let url: URL?
    @State private var image: UIImage?
    @State private var failed = false
    @State private var retry = 0
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFit() }
            else if failed {
                Button { retry += 1 } label: { Image(systemName: "arrow.clockwise").frame(minWidth: 44, minHeight: 44) }
                    .accessibilityLabel("重试内页图片")
            } else { ProgressView().controlSize(.small) }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .task(id: "\(url?.absoluteString ?? "missing"):\(retry)") {
                image = nil; failed = false
                do {
                    guard let url else { throw DiaryEditorError.missingResource }
                    let data: Data
                    if url.isFileURL { data = try await Task.detached { try Data(contentsOf: url) }.value }
                    else {
                        var request = URLRequest(url: url)
                        request.cachePolicy = .returnCacheDataElseLoad
                        let (bytes, response) = try await URLSession.shared.data(for: request)
                        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                            throw URLError(.badServerResponse)
                        }
                        data = bytes
                    }
                    let decoded = try await Task.detached {
                        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                                kCGImageSourceCreateThumbnailFromImageAlways: true,
                                kCGImageSourceCreateThumbnailWithTransform: true,
                                kCGImageSourceThumbnailMaxPixelSize: 640
                              ] as CFDictionary) else { throw DiaryEditorError.invalidImage }
                        return UIImage(cgImage: cg)
                    }.value
                    try Task.checkCancellation()
                    image = decoded
                } catch is CancellationError { }
                catch { if !Task.isCancelled { failed = true } }
            }
    }
}
