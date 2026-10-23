import SwiftUI
import ImageIO

struct DiaryAlbumPhotoThumbnail: View {
    let photo: DiaryAlbumPhoto
    let directory: URL
    @State private var image: UIImage?
    @State private var loaded = false
    var body: some View {
        GeometryReader { proxy in
            Group {
                if let image { Image(uiImage: image).resizable().scaledToFill() }
                else if loaded { Image(systemName: "exclamationmark.triangle").frame(maxWidth: .infinity, maxHeight: .infinity) }
                else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            }.frame(width: proxy.size.width, height: proxy.size.height).clipped()
        }
        .background(DiaryLibraryStyle.surface)
        .task(id: photo.id) { image = await DiaryAlbumThumbnailLoader.load(directory.appendingPathComponent(photo.filename), maximumDimension: 128); loaded = true }
    }
}

/// 使用正式导出渲染器预览，照片裁切、文字及背景与保存后的页面一致。
struct DiaryAlbumPagePreview: View {
    let page: DiaryAlbumPage
    let draft: DiaryAlbumDraft
    let directory: URL
    @State private var image: UIImage?
    @State private var failed = false
    private var request: DiaryAlbumPreviewRequest { DiaryAlbumPreviewRequest(page: page, draft: draft, directory: directory) }
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFit() }
            else {
                Rectangle().fill(Color(uiColor: DiaryPageRenderer.color(page.theme.palette(page.paletteID).paper))).overlay {
                    if failed { Image(systemName: "exclamationmark.triangle").foregroundStyle(.secondary) }
                    else { ProgressView() }
                }
            }
        }
        .aspectRatio(draft.pageSize.width / draft.pageSize.height, contentMode: .fit)
        .task(id: request) {
            failed = false
            do { image = try await DiaryAlbumPreviewService.shared.image(request) }
            catch is CancellationError { }
            catch { image = nil; failed = true }
        }
    }
}
