import SwiftUI

struct DiaryExportSpreadPage: View {
    let book: DiaryBook
    let store: DiaryDocumentStore
    @Binding var spreadCount: Int
    @State private var previews: [Int: UIImage] = [:]
    @State private var previewError: String?
    @State private var retry = 0
    private let ink = Color(red: 0.23, green: 0.36, blue: 0.31)

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("每张图片放几个跨页？").font(.title3.bold())
            Text("按帐本顺序预览，保留装订与画面留白。跨页不足时，只放入实际已有的内容。")
                .font(.subheadline).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                ForEach(DiaryCollageLayout.supportedCounts, id: \.self) { count in
                    Button { spreadCount = count } label: {
                        VStack(spacing: 12) {
                            ZStack {
                                Color(red: 0.98, green: 0.975, blue: 0.96)
                                if let preview = previews[count] {
                                    Image(uiImage: preview).resizable().scaledToFit()
                                } else if previewError != nil {
                                    Text("预览加载失败").font(.caption).foregroundStyle(.secondary)
                                } else { ProgressView().controlSize(.small) }
                            }
                            .aspectRatio(DiaryCollageLayout.aspectRatio, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            Text("\(count) 个跨页 / 张").font(.subheadline.bold())
                        }.frame(maxWidth: .infinity).padding(12)
                            .background(.background, in: RoundedRectangle(cornerRadius: 18))
                            .overlay(RoundedRectangle(cornerRadius: 18).stroke(spreadCount == count ? ink : .clear, lineWidth: 2))
                    }.buttonStyle(.plain).accessibilityAddTraits(spreadCount == count ? .isSelected : [])
                }
            }
            if let previewError {
                VStack(alignment: .leading, spacing: 8) {
                    Text(previewError).font(.caption).foregroundStyle(.secondary)
                    Button("重新加载预览") { retry += 1 }
                }
            }
            Text("将生成 \((DiaryBookImageExporter.spreadPages(book).count + spreadCount - 1) / spreadCount) 张 JPG · 保留帐本装订样式")
                .font(.caption).foregroundStyle(.secondary)
        }
        .task(id: "\(book.catalogRevision)-\(retry)") { await loadPreviews() }
    }

    @MainActor private func loadPreviews() async {
        previews = [:]; previewError = nil
        do {
            var spreads: [UIImage] = []
            for (index, pair) in DiaryBookImageExporter.spreadPages(book).prefix(6).enumerated() {
                try Task.checkCancellation()
                var leaves: [UIImage?] = []
                for page in pair {
                    if let page {
                        let loaded = try await store.loadPDFSource(page)
                        await DiaryFontCatalog.shared.prewarm(loaded.document.objects.values.flatMap { $0.layers.compactMap(\.font) }, documentID: loaded.document.id)
                        try Task.checkCancellation()
                        leaves.append(DiaryBookImageExporter.renderPage(loaded.document, images: loaded.images, longestEdge: 400))
                    } else { leaves.append(nil) }
                }
                spreads.append(try DiaryBookImageExporter.renderSpread(left: leaves[0], right: leaves[1],
                    lining: index == 0, book: book, width: 800, scale: 0.5))
                await Task.yield()
            }
            try Task.checkCancellation()
            for count in DiaryCollageLayout.supportedCounts {
                previews[count] = DiaryBookImageExporter.collage(Array(spreads.prefix(count)), canvasWidth: 300, scale: 1)
            }
        } catch is CancellationError { }
        catch { previewError = error.localizedDescription }
    }
}
