//
//  CameraCaptureCropper.swift
//
//  通用相机取景框裁剪工具。
//

import AVFoundation
import CoreImage
import UIKit

/// 通用相机取景框裁剪工具。
///
/// 将相机拍摄到的完整照片裁剪为「屏幕上取景框范围内」所见的内容，
/// 取景框外部的内容不会出现在最终照片中。
///
/// 裁剪坐标系必须与实时预览一致：预览通过 `CIImage.oriented(frameOrientation)` 显示画面，
/// 因此裁剪也应在同一「预览空间」的 `CIImage` 上执行（而非依赖 `UIImage` 方向元数据）。
enum CameraCaptureCropper {
    /// 在预览坐标系（已 `oriented(frameOrientation)` 的 `CIImage`）上裁剪到取景框范围。
    static func crop(
        _ ciImage: CIImage,
        viewfinderRect: CGRect,
        containerBounds: CGRect,
        videoGravity: AVLayerVideoGravity = .resizeAspectFill
    ) -> CIImage {
        let extent = ciImage.extent.integral
        guard extent.width > 0, extent.height > 0,
              containerBounds.width > 0, containerBounds.height > 0,
              viewfinderRect.width > 0, viewfinderRect.height > 0
        else { return ciImage }

        guard let cropRect = cropRectInImageSpace(
            viewfinderRect: viewfinderRect,
            containerBounds: containerBounds,
            imageExtent: extent,
            videoGravity: videoGravity
        ) else { return ciImage }

        return ciImage.cropped(to: cropRect)
    }

    /// 将 `UIImage` 裁剪到取景框范围内（兼容旧路径；照片管线优先使用 `CIImage` 版本）。
    static func crop(
        _ image: UIImage,
        viewfinderRect: CGRect,
        containerBounds: CGRect,
        videoGravity: AVLayerVideoGravity = .resizeAspectFill
    ) -> UIImage {
        guard containerBounds.width > 0, containerBounds.height > 0,
              viewfinderRect.width > 0, viewfinderRect.height > 0
        else { return image }

        let normalized = normalizedUpImage(image)
        guard let cgImage = normalized.cgImage else { return image }

        let imageSize = normalized.size
        guard imageSize.width > 0, imageSize.height > 0 else { return image }

        guard let cropInPoints = cropRectInImageSpace(
            viewfinderRect: viewfinderRect,
            containerBounds: containerBounds,
            imageExtent: CGRect(origin: .zero, size: imageSize),
            videoGravity: videoGravity
        ) else { return image }

        let pixelScale = normalized.scale
        let cropInPixels = CGRect(
            x: cropInPoints.minX * pixelScale,
            y: cropInPoints.minY * pixelScale,
            width: cropInPoints.width * pixelScale,
            height: cropInPoints.height * pixelScale
        ).integral

        guard let cropped = cgImage.cropping(to: cropInPixels) else { return image }
        return UIImage(cgImage: cropped, scale: pixelScale, orientation: .up)
    }

    /// 根据取景框在容器中的位置，计算对应到图片 extent 内的裁剪矩形。
    static func cropRectInImageSpace(
        viewfinderRect: CGRect,
        containerBounds: CGRect,
        imageExtent: CGRect,
        videoGravity: AVLayerVideoGravity = .resizeAspectFill
    ) -> CGRect? {
        guard imageExtent.width > 0, imageExtent.height > 0,
              containerBounds.width > 0, containerBounds.height > 0,
              viewfinderRect.width > 0, viewfinderRect.height > 0
        else { return nil }

        let imageSize = imageExtent.size

        // 预览以 videoGravity 的方式把图片显示在容器中，计算其显示比例与显示区域原点。
        let displayScale: CGFloat = switch videoGravity {
            case .resizeAspect: min(containerBounds.width / imageSize.width, containerBounds.height / imageSize.height)
            default: max(containerBounds.width / imageSize.width, containerBounds.height / imageSize.height)
        }

        let displayedSize = CGSize(width: imageSize.width * displayScale, height: imageSize.height * displayScale)
        let displayOriginX = containerBounds.minX + (containerBounds.width - displayedSize.width) / 2
        let displayOriginY = containerBounds.minY + (containerBounds.height - displayedSize.height) / 2

        let cropInPoints = CGRect(
            x: imageExtent.minX + (viewfinderRect.minX - displayOriginX) / displayScale,
            y: imageExtent.minY + (viewfinderRect.minY - displayOriginY) / displayScale,
            width: viewfinderRect.width / displayScale,
            height: viewfinderRect.height / displayScale
        ).intersection(imageExtent)

        guard !cropInPoints.isNull, cropInPoints.width > 0, cropInPoints.height > 0 else { return nil }
        return cropInPoints.integral
    }
}

private extension CameraCaptureCropper {
    /// 将图片重绘为 `.up` 方向，使其像素布局与展示方向一致。
    static func normalizedUpImage(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        format.opaque = false

        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }
}
