import UIKit

enum SecondCameraImageRenderer {

    @MainActor
    static func renderSecondCameraEditedPhoto(
        from approvalItem: SecondCameraAttachmentApprovalItem,
        options: SecondCameraImageOutputOptions,
    ) -> UIImage? {
        if let model = approvalItem.secondCameraImageEditorModel {
            if let rendered = model.renderOutput() {
                return applySecondCameraOutputOptions(to: rendered, options: options)
            }
        }
        if let image = approvalItem.attachment.rawValue.image() {
            return applySecondCameraOutputOptions(to: image, options: options)
        }
        return nil
    }

    @MainActor
    static func applySecondCameraOutputOptions(to image: UIImage, options: SecondCameraImageOutputOptions) -> UIImage {
        let scaled = scale(image: image, options: options)
        guard options.quality != .original, options.outputFormat == .jpeg else {
            return scaled
        }
        guard let quality = options.quality.jpegQuality,
              let data = scaled.jpegData(compressionQuality: quality),
              let compressed = UIImage(data: data) else {
            return scaled
        }
        return compressed
    }

    private static func scale(image: UIImage, options: SecondCameraImageOutputOptions) -> UIImage {
        let maxLongEdge: CGFloat?
        if let custom = options.customPixelSize {
            maxLongEdge = max(custom.width, custom.height)
        } else {
            maxLongEdge = options.sizePreset.maxLongEdge
        }
        guard let maxLongEdge, maxLongEdge > 0 else { return image }

        let size = image.size
        let longEdge = max(size.width, size.height)
        guard longEdge > maxLongEdge else { return image }

        let scale = maxLongEdge / longEdge
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}
