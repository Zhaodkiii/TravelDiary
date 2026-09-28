import AVFoundation
import UIKit

enum SecondCameraPreviewThumbnailBuilder {
    static let maxPixelSize: CGFloat = 120

    static func makeThumbnail(from media: CustomCameraMedia) -> UIImage? {
        if let image = media.getImage() {
            return makeThumbnail(from: image)
        }
        if let video = media.getVideo() {
            return makeVideoThumbnail(from: video)
        }
        return nil
    }

    static func makeThumbnail(from image: UIImage) -> UIImage {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return image }

        let longEdge = max(size.width, size.height)
        guard longEdge > maxPixelSize else { return image }

        let scale = maxPixelSize / longEdge
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    static func makeVideoThumbnail(from url: URL) -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixelSize, height: maxPixelSize)
        guard let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil) else {
            return UIImage(systemName: "video.fill")
        }
        return UIImage(cgImage: cgImage)
    }
}
