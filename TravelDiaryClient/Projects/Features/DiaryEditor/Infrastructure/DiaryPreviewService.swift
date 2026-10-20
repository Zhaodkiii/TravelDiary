import UIKit

/// 按页版本合并请求；绘制结果立即返回，持久化不阻塞阅读。
@MainActor
enum DiaryPreviewService {
    private static var pending: [String: Task<UIImage, Error>] = [:]
    private nonisolated static let encodingQueue = DispatchQueue(label: "TravelDiary.PreviewEncoding", qos: .utility)
    private static let cache: NSCache<NSString, UIImage> = {
        let value = NSCache<NSString, UIImage>(); value.totalCostLimit = 64 * 1024 * 1024
        return value
    }()
    static func image(page: DiaryPageEntry, store: DiaryDocumentStore, large: Bool) async throws -> UIImage {
        // 不把任意账号的页面图缓存在同一个 pageID 键下；磁盘缓存由 Store 额外隔离账号和本。
        try Task.checkCancellation()
        let identity = "\(store.previewScope)-\(page.id)-\(page.revisionID)-\(large)"
        if let image = cache.object(forKey: identity as NSString) { return image }
        let work: Task<UIImage, Error>
        if let existing = pending[identity] { work = existing }
        else {
            // 取消某个界面的等待不取消其他界面正在复用的生成任务。
            work = Task { @MainActor in
                defer { pending[identity] = nil }
                return try await generate(page: page, store: store, large: large, key: identity as NSString)
            }
            pending[identity] = work
        }
        let image = try await work.value
        try Task.checkCancellation()
        return image
    }

    private static func generate(page: DiaryPageEntry, store: DiaryDocumentStore, large: Bool, key: NSString) async throws -> UIImage {
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
        cache.setObject(image, forKey: key, cost: (image.cgImage?.bytesPerRow ?? 0) * (image.cgImage?.height ?? 0))
        // 串行后台编码控制峰值内存；磁盘缓存失败不影响已交付的图片。
        Task.detached(priority: .utility) {
            let data: Data? = await withCheckedContinuation { continuation in
                encodingQueue.async {
                    let data = autoreleasepool { image.pngData() }
                    continuation.resume(returning: data)
                }
            }
            if let data { try? await store.cachePreview(data, page: page, large: large) }
        }
        return image
    }
}
