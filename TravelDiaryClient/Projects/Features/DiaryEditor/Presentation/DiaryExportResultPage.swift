import SwiftUI
import ImageIO

struct DiaryExportResultPage: View {
    let result: DiaryBookImageExporter.Result
    let saved: Bool
    let saving: Bool
    let busy: Bool
    let onRetry: () -> Void
    @State private var previewID: URL?
    private let ink = Color(red: 0.23, green: 0.36, blue: 0.31)

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: saved ? "checkmark.seal.fill" : "photo.stack").font(.system(size: 64)).foregroundStyle(ink)
            Text(saved ? "旅途记忆，已收藏" : "图片已生成").font(.title2.bold())
            Text(saved ? "已自动保存 \(result.urls.count) 张照片到相册" : "\(result.urls.count) 张图片等待保存到相册")
                .foregroundStyle(.secondary)
            if result.usedFallbackFonts { Text("部分字体暂不可用，已使用替代字体，文字排版可能变化。").font(.caption).foregroundStyle(.orange) }
            if !saved { Button("重试保存到相册") { onRetry() }.disabled(busy) }
            if saving { ProgressView("正在保存到相册…") }
            ShareLink(items: result.urls) { Label("分享图片", systemImage: "square.and.arrow.up") }.buttonStyle(.borderedProminent).disabled(busy)
            previewGallery
        }.frame(maxWidth: .infinity).padding(.vertical, 24)
        .onAppear { if previewID == nil { previewID = result.urls.first } }
    }

    private var previewGallery: some View {
        VStack(spacing: 12) {
            HStack {
                Text("导出预览").font(.headline)
                Spacer()
                Text("\((previewID.flatMap { result.urls.firstIndex(of: $0) } ?? 0) + 1) / \(result.urls.count)")
                    .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(Array(result.urls.enumerated()), id: \.element) { index, url in
                        DiaryExportedImagePreview(url: url)
                            .containerRelativeFrame(.horizontal)
                            .frame(height: 360)
                            .background(Color(red: 0.98, green: 0.975, blue: 0.96), in: RoundedRectangle(cornerRadius: 14))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .id(url)
                            .accessibilityLabel("第 \(index + 1) 张导出图片，共 \(result.urls.count) 张")
                    }
                }.scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $previewID)
            if result.urls.count > 1 {
                Text("左右滑动查看全部图片").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct DiaryExportedImagePreview: View {
    let url: URL
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let image { Image(uiImage: image).resizable().scaledToFit() }
            else if failed {
                ContentUnavailableView("无法读取预览", systemImage: "photo", description: Text("请返回后重新导出。"))
            } else { ProgressView("正在加载预览…") }
        }
        .task(id: url) {
            image = nil; failed = false
            guard !Task.isCancelled else { return }
            // Decode a bounded thumbnail from the actual exported file instead
            // of retaining every full-resolution JPEG in the gallery.
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 1200
                  ] as CFDictionary) else { failed = true; return }
            image = UIImage(cgImage: thumbnail)
        }
    }
}
