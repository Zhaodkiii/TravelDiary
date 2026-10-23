import UIKit
import ImageIO

/// 不在视图 body 内编码整本草稿；任务只比较当前页及其实际用到的素材。
nonisolated struct DiaryAlbumPreviewRequest: Equatable, Sendable {
    let page: DiaryAlbumPage
    let size: CGSize
    let pageNumber: Int
    let photos: [DiaryAlbumPhoto]
    let directory: URL

    init(page: DiaryAlbumPage, draft: DiaryAlbumDraft, directory: URL) {
        self.page = page; size = draft.pageSize; self.directory = directory
        pageNumber = (draft.pages.firstIndex(where: { $0.id == page.id }) ?? 0) + 1
        let ids = Set(page.placements.map(\.photoID))
        photos = draft.photos.filter { ids.contains($0.id) }
    }
}

/// 原图读取和解码共用串行后台队列；相同规格请求合并，避免多页同时解码峰值。
@MainActor enum DiaryAlbumThumbnailLoader {
    private static let queue = DispatchQueue(label: "TravelDiary.AlbumThumbnails", qos: .userInitiated)
    private static var pending: [String: Task<UIImage?, Never>] = [:]
    private static let cache: NSCache<NSString, UIImage> = {
        let value = NSCache<NSString, UIImage>(); value.totalCostLimit = 32 * 1024 * 1024; return value
    }()
    private(set) static var decodeCount = 0
    static func load(_ url: URL, maximumDimension: Int = 128) async -> UIImage? {
        let dimension = min(1024, max(64, maximumDimension))
        let key = "\(url.path):\(dimension)"
        if let image = cache.object(forKey: key as NSString) { return image }
        let work: Task<UIImage?, Never>
        if let existing = pending[key] { work = existing }
        else {
            decodeCount += 1
            work = Task {
                let result: UIImage? = await withCheckedContinuation { continuation in
                    queue.async {
                        let value: UIImage? = autoreleasepool {
                            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                                  let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                                    kCGImageSourceCreateThumbnailWithTransform: true,
                                    kCGImageSourceShouldCacheImmediately: true,
                                    kCGImageSourceThumbnailMaxPixelSize: dimension
                                  ] as CFDictionary) else { return nil }
                            return UIImage(cgImage: cg)
                        }
                        continuation.resume(returning: value)
                    }
                }
                if let result { cache.setObject(result, forKey: key as NSString, cost: cost(result)) }
                pending[key] = nil
                return result
            }
            pending[key] = work
        }
        return await work.value
    }
    private static func cost(_ image: UIImage) -> Int {
        (image.cgImage?.bytesPerRow ?? 0) * (image.cgImage?.height ?? 0)
    }
}

/// 已生成的页图跨列表回收复用；滚动时仅显示缓存，停止后再执行新页合成。
@MainActor @Observable final class DiaryAlbumPreviewService {
    static let shared = DiaryAlbumPreviewService()
    var scrolling = false
    private struct Work {
        let id: UUID
        let task: Task<UIImage, Error>
        var consumers: Set<UUID>
    }
    private var pending: [String: Work] = [:]
    private let cache: NSCache<NSString, UIImage> = {
        let value = NSCache<NSString, UIImage>(); value.totalCostLimit = 48 * 1024 * 1024; return value
    }()
    private(set) var renderCount = 0
    private(set) var totalRenderMilliseconds = 0.0
    private var rendering = false

    func image(_ request: DiaryAlbumPreviewRequest) async throws -> UIImage {
        try Task.checkCancellation()
        let key = try identity(request)
        if let image = cache.object(forKey: key as NSString) { return image }
        let consumer = UUID()
        let work: Work
        if var existing = pending[key] {
            existing.consumers.insert(consumer); pending[key] = existing; work = existing
        } else {
            let workID = UUID()
            let task = Task { @MainActor in
                defer { if pending[key]?.id == workID { pending[key] = nil } }
                let image = try await generate(request)
                try Task.checkCancellation()
                cache.setObject(image, forKey: key as NSString,
                    cost: (image.cgImage?.bytesPerRow ?? 0) * (image.cgImage?.height ?? 0))
                return image
            }
            work = Work(id: workID, task: task, consumers: [consumer])
            pending[key] = work
        }
        defer { release(key, consumer: consumer) }
        return try await withTaskCancellationHandler {
            let result = try await work.task.value
            try Task.checkCancellation()
            return result
        } onCancel: {
            Task { @MainActor in self.release(key, consumer: consumer) }
        }
    }
    private func release(_ key: String, consumer: UUID) {
        guard var work = pending[key], work.consumers.remove(consumer) != nil else { return }
        if work.consumers.isEmpty { work.task.cancel(); pending[key] = nil }
        else { pending[key] = work }
    }
    private func identity(_ request: DiaryAlbumPreviewRequest) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let page = try encoder.encode(request.page).base64EncodedString()
        let assets = request.photos.map { "\($0.id):\($0.filename):\($0.pixelSize.width)x\($0.pixelSize.height)" }.joined(separator: ",")
        return "\(request.directory.path)|\(request.size.width)x\(request.size.height)|\(request.pageNumber)|\(page)|\(assets)"
    }
    private func generate(_ request: DiaryAlbumPreviewRequest) async throws -> UIImage {
        var images: [UUID: UIImage] = [:], assets: [UUID: DiaryAsset] = [:]
        for photo in request.photos {
            try Task.checkCancellation()
            guard let image = await DiaryAlbumThumbnailLoader.load(request.directory.appendingPathComponent(photo.filename), maximumDimension: 640) else {
                throw DiaryEditorError.invalidImage
            }
            images[photo.id] = image
            assets[photo.id] = DiaryAsset(id: photo.id, path: photo.filename, pixelSize: photo.pixelSize)
        }
        // UI 绘制器依赖主线程字体与对象缓存。保留统一绘制规则，但将合成排到滚动结束后。
        try Task.checkCancellation()
        while scrolling || rendering { try await Task.sleep(for: .milliseconds(50)) }
        rendering = true
        defer { rendering = false }
        // 每页间让出至少一帧，避免停止滑动后一次合成所有预取页。
        try await Task.sleep(for: .milliseconds(16))
        while scrolling { try await Task.sleep(for: .milliseconds(50)) }
        var draft = DiaryAlbumDraft(); draft.size = DiaryPagePreset.b5.rawValue
        draft.photos = request.photos
        // 构建器的页码只依赖目录位置，不需要复制整本草稿。
        let document = DiaryAlbumDocumentBuilder.document(page: request.page, draft: draft, assets: assets,
            pageSize: request.size, pageNumber: request.pageNumber)
        let format = UIGraphicsImageRendererFormat(); format.scale = 384 / request.size.width; format.opaque = true
        let started = CACurrentMediaTime()
        let result = autoreleasepool {
            UIGraphicsImageRenderer(size: request.size, format: format).image { renderer in
                DiaryPageRenderer.draw(document, images: images, in: renderer.cgContext, cacheObjects: false)
            }
        }
        totalRenderMilliseconds += (CACurrentMediaTime() - started) * 1000
        renderCount += 1
        return result
    }
}
