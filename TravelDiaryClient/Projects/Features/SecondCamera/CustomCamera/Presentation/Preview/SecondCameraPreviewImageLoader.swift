import Foundation
import ImageIO
import UIKit

/// 公共预览图片加载协议，便于测试注入 fake loader。
protocol SecondCameraPreviewImageLoading {
    func loadPreviewImage(from url: URL, maxPixelSize: CGFloat) async throws -> UIImage
    func loadThumbnail(from url: URL, maxPixelSize: CGFloat) async throws -> UIImage
}

/// ImageIO 降采样加载器：后台解码、保留 EXIF 方向，并带内存缓存。
final class SecondCameraPreviewImageLoader: SecondCameraPreviewImageLoading, @unchecked Sendable {
    static let shared = SecondCameraPreviewImageLoader()

    private nonisolated(unsafe) let previewCache = NSCache<NSString, UIImage>()
    private nonisolated(unsafe) let thumbnailCache = NSCache<NSString, UIImage>()
    private nonisolated(unsafe) var memoryWarningObserver: NSObjectProtocol?

    init() {
        previewCache.totalCostLimit = 64 * 1024 * 1024
        thumbnailCache.totalCostLimit = 16 * 1024 * 1024
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.previewCache.removeAllObjects()
        }
    }

    deinit {
        if let memoryWarningObserver {
            NotificationCenter.default.removeObserver(memoryWarningObserver)
        }
    }

    nonisolated func loadPreviewImage(from url: URL, maxPixelSize: CGFloat) async throws -> UIImage {
        try await loadImage(from: url, maxPixelSize: maxPixelSize, cache: previewCache)
    }

    nonisolated func loadThumbnail(from url: URL, maxPixelSize: CGFloat) async throws -> UIImage {
        try await loadImage(from: url, maxPixelSize: maxPixelSize, cache: thumbnailCache)
    }

    nonisolated private func loadImage(
        from url: URL,
        maxPixelSize: CGFloat,
        cache: NSCache<NSString, UIImage>
    ) async throws -> UIImage {
        guard url.isFileURL else {
            throw SecondCameraMediaPreviewLoadError.unsupportedType
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw SecondCameraMediaPreviewLoadError.fileMissing
        }

        let cacheKey = makeCacheKey(url: url, maxPixelSize: maxPixelSize)
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        let image: UIImage = try await Task.detached(priority: .userInitiated) {
            try Self.decodeImage(from: url, maxPixelSize: maxPixelSize)
        }.value

        if Task.isCancelled {
            throw SecondCameraMediaPreviewLoadError.cancelled
        }

        let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        cache.setObject(image, forKey: cacheKey, cost: max(cost, 1))
        return image
    }

    nonisolated private func makeCacheKey(url: URL, maxPixelSize: CGFloat) -> NSString {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let modified = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        let size = values?.fileSize ?? 0
        return "\(url.standardizedFileURL.path)|\(modified)|\(size)|\(Int(maxPixelSize))" as NSString
    }

    nonisolated private static func decodeImage(from url: URL, maxPixelSize: CGFloat) throws -> UIImage {
        guard url.isFileURL else {
            throw SecondCameraMediaPreviewLoadError.unsupportedType
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw SecondCameraMediaPreviewLoadError.fileMissing
        }
        if Task.isCancelled {
            throw SecondCameraMediaPreviewLoadError.cancelled
        }

        let sourceOptions: CFDictionary = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
            throw SecondCameraMediaPreviewLoadError.cannotCreateImageSource
        }

        let thumbnailOptions: CFDictionary = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ] as CFDictionary

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
            throw SecondCameraMediaPreviewLoadError.cannotDecodeImage
        }
        if Task.isCancelled {
            throw SecondCameraMediaPreviewLoadError.cancelled
        }
        return UIImage(cgImage: cgImage, scale: 1, orientation: .up)
    }
}

enum SecondCameraPreviewImageSizePolicy {
    nonisolated static var thumbnailMaxPixelSize: CGFloat {
        160 * UIScreen.main.scale
    }

    nonisolated static var previewMaxPixelSize: CGFloat {
        let bounds = UIScreen.main.bounds
        let scale = UIScreen.main.scale
        let longest = max(bounds.width, bounds.height) * scale
        return min(longest * 3, 8192)
    }
}
