import CoreImage
import UIKit

public extension UIImage {

    nonisolated func normalized() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    @concurrent
    nonisolated func cgImageWithGaussianBlurAsync(radius: CGFloat, resizeToMaxPixelDimension: CGFloat) async throws -> CGImage {
        guard let resized = self.resized(maxDimensionPixels: resizeToMaxPixelDimension) else {
            throw SecondCameraEditorAssertionError("Failed to downsize image for blur")
        }
        return try resized._scGaussianBlurCGImage(radius: radius)
    }

    nonisolated private func _scGaussianBlurCGImage(radius: CGFloat) throws -> CGImage {
        guard let cgImage else {
            throw SecondCameraEditorAssertionError("Missing cgImage for blur")
        }
        let inputImage = CIImage(cgImage: cgImage)

        guard
            let clampFilter = CIFilter(name: "CIAffineClamp", parameters: [kCIInputImageKey: inputImage])
        else { throw SecondCameraEditorAssertionError("Failed to create CIAffineClamp filter") }
        clampFilter.setDefaults()
        guard let clampOutput = clampFilter.outputImage else {
            throw SecondCameraEditorAssertionError("Failed to clamp image")
        }

        guard
            let blurFilter = CIFilter(
                name: "CIGaussianBlur",
                parameters: [kCIInputRadiusKey: radius, kCIInputImageKey: clampOutput]
            )
        else { throw SecondCameraEditorAssertionError("Failed to create CIGaussianBlur filter") }
        guard let blurOutput = blurFilter.outputImage else {
            throw SecondCameraEditorAssertionError("Failed to create blurred image")
        }

        let context = CIContext(options: nil)
        guard let result = context.createCGImage(blurOutput, from: inputImage.extent) else {
            throw SecondCameraEditorAssertionError("Failed to create CGImage from blurred output")
        }
        return result
    }
}

public extension UIImage {
    nonisolated var withNativeScale: UIImage {
        let nativeScale = UIScreen.main.scale
        guard scale != nativeScale, let cgImage else {
            return self
        }
        return UIImage(cgImage: cgImage, scale: nativeScale, orientation: imageOrientation)
    }

    nonisolated var pixelWidth: Int {
        switch imageOrientation {
        case .up, .down, .upMirrored, .downMirrored:
            return cgImage?.width ?? 0
        case .left, .right, .leftMirrored, .rightMirrored:
            return cgImage?.height ?? 0
        @unknown default:
            return cgImage?.width ?? 0
        }
    }

    nonisolated var pixelHeight: Int {
        switch imageOrientation {
        case .up, .down, .upMirrored, .downMirrored:
            return cgImage?.height ?? 0
        case .left, .right, .leftMirrored, .rightMirrored:
            return cgImage?.width ?? 0
        @unknown default:
            return cgImage?.height ?? 0
        }
    }

    nonisolated var pixelSize: CGSize {
        CGSize(width: pixelWidth, height: pixelHeight)
    }

    nonisolated func resized(maxDimensionPixels: CGFloat) -> UIImage? {
        resized(originalSize: pixelSize, maxDimension: maxDimensionPixels, isPixels: true)
    }

    nonisolated private func resized(originalSize: CGSize, maxDimension: CGFloat, isPixels: Bool) -> UIImage? {
        guard originalSize.width >= 1, originalSize.height >= 1 else {
            SecondCameraEditorLogger.error("Invalid original image size: \(originalSize)")
            return nil
        }

        let maxOriginalDimension = max(originalSize.width, originalSize.height)
        guard maxOriginalDimension >= maxDimension else {
            return self
        }

        let thumbnailSize: CGSize
        if originalSize.width > originalSize.height {
            thumbnailSize = CGSize(
                width: round(maxDimension),
                height: round(maxDimension * originalSize.height / originalSize.width)
            )
        } else {
            thumbnailSize = CGSize(
                width: round(maxDimension * originalSize.width / originalSize.height),
                height: round(maxDimension)
            )
        }

        let format = UIGraphicsImageRendererFormat()
        if isPixels {
            format.scale = 1
        }
        format.opaque = false

        let renderRect = CGRect(origin: .zero, size: thumbnailSize)
        let renderer = UIGraphicsImageRenderer(size: thumbnailSize, format: format)
        return renderer.image { context in
            context.cgContext.interpolationQuality = .high
            draw(in: renderRect)
        }
    }

    nonisolated static func secondCameraEditor(named name: String, systemName: String? = nil) -> UIImage? {
        if let image = UIImage(named: name) {
            return image
        }
        if let systemName, let image = UIImage(systemName: systemName) {
            return image
        }
        secondCameraEditorFailDebug("Missing SecondCamera image asset: \(name)")
        return nil
    }
}
