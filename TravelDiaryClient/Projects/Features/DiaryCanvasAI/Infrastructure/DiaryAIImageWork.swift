import UIKit
import ImageIO

/// Serial CPU work keeps large image conversions off the UI executor and bounds peak memory.
nonisolated enum DiaryAIImageWork {
    private static let queue = DispatchQueue(label: "diary.ai.image-work", qos: .userInitiated)

    static func run<T: Sendable>(_ operation: @escaping @Sendable () throws -> T) async throws -> T {
        try Task.checkCancellation()
        let result: T = try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result { try autoreleasepool(invoking: operation) })
            }
        }
        try Task.checkCancellation()
        return result
    }

    static func jpeg(_ image: UIImage, quality: CGFloat = 0.82) async throws -> Data {
        try await run {
            guard let data = image.jpegData(compressionQuality: quality) else { throw DiaryAIError.invalid("预览编码失败") }
            return data
        }
    }

    static func thumbnail(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 480,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: image).jpegData(compressionQuality: 0.65)
    }
}
