import UIKit

/// 预览以页版本为身份；仅可见卡片请求生成，取消后的结果不再交给界面。
@MainActor
enum DiaryPreviewService {
    private static let cache: NSCache<NSString, UIImage> = {
        let value = NSCache<NSString, UIImage>(); value.totalCostLimit = 64 * 1024 * 1024
        return value
    }()
    static func image(page: DiaryPageEntry, store: DiaryDocumentStore, large: Bool) async throws -> UIImage {
        // 不把任意账号的页面图缓存在同一个 pageID 键下；磁盘缓存由 Store 额外隔离账号和本。
        let key = "\(store.previewScope)-\(page.id)-\(page.revisionID)-\(large)" as NSString
        if let image = cache.object(forKey: key) { return image }
        if let data = try await store.cachedPreview(page, large: large), let image = UIImage(data: data) {
            try Task.checkCancellation()
            cache.setObject(image, forKey: key, cost: (image.cgImage?.bytesPerRow ?? 0) * (image.cgImage?.height ?? 0))
            return image
        }
        let source = try await store.loadPreviewSource(page, large: large)
        try Task.checkCancellation()
        let size = source.document.root.referenceSize
        let format = UIGraphicsImageRendererFormat(); format.opaque = false
        format.scale = (large ? 1800 : 480) / max(size.width, size.height)
        let image = UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            DiaryPageRenderer.draw(source.document, images: source.images, in: renderer.cgContext, cacheObjects: false)
        }
        guard let data = image.pngData() else { throw DiaryEditorError.exportFailed }
        try? await store.cachePreview(data, page: page, large: large)
        try Task.checkCancellation()
        cache.setObject(image, forKey: key, cost: (image.cgImage?.bytesPerRow ?? 0) * (image.cgImage?.height ?? 0))
        return image
    }
}
