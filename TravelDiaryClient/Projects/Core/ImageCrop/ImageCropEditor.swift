import SwiftUI
import UIKit

/// 通用裁剪参数使用原图像素坐标；可序列化，重新打开时恢复同一取景。
nonisolated struct ImageCropParameters: Codable, Equatable, Sendable {
    var outputSize: CGSize
    var translation: CGPoint
    var rotation: CGFloat
    var scale: CGFloat
    var flipped: Bool

    var isValid: Bool {
        [outputSize.width, outputSize.height, translation.x, translation.y, rotation, scale].allSatisfy(\.isFinite)
            && outputSize.width >= 1 && outputSize.height >= 1 && scale >= 1
    }
}

extension ImageCropParameters {
    @MainActor init(_ transform: SecondCameraImageEditorTransform) {
        outputSize = transform.outputSizePixels; translation = transform.unitTranslation
        rotation = transform.rotationRadians; scale = transform.scaling; flipped = transform.isFlipped
    }
    @MainActor var transform: SecondCameraImageEditorTransform {
        SecondCameraImageEditorTransform(outputSizePixels: outputSize, unitTranslation: translation,
                                        rotationRadians: rotation, scaling: scale, isFlipped: flipped)
    }
}

/// 通用入口只接收照片与参数，完成返回新位图；不会混入调用方的贴纸、文字或画笔。
@MainActor
struct ImageCropEditor: UIViewControllerRepresentable {
    let model: SecondCameraImageEditorModel
    let image: UIImage
    let onComplete: (UIImage, ImageCropParameters) -> Void
    let onCancel: () -> Void
    let onError: (String) -> Void
    var locksOutputSize = false

    init(image: UIImage, parameters: ImageCropParameters?,
         onComplete: @escaping (UIImage, ImageCropParameters) -> Void,
         onCancel: @escaping () -> Void, onError: @escaping (String) -> Void) throws {
        // 手帐可直接打开裁剪，必须在创建素材与模型之前初始化编辑环境。
        // 模型的贴纸缓存会立即读取 AppContext；初始化方法支持重复调用。
        SecondCameraEditorAppContextImplBootstrap.bootstrapIfNeeded()
        guard let data = image.pngData() else { throw CocoaError(.fileReadCorruptFile) }
        // 直接构造原尺寸资源，避免相机附件发送流程对图片再次缩小。
        let source = try SecondCameraEditorDataSourcePath(writingTempFileData: data, fileExtension: "png")
        let normalized = SecondCameraNormalizedImage(dataSource: source, dataUTI: "public.png",
                                                     mustCompress: false, mayHaveMetadata: false, mayHaveTransparency: true)
        model = try SecondCameraImageEditorModel(normalizedImage: normalized)
        if let parameters, parameters.isValid { model.replace(transform: parameters.transform) }
        self.image = image; self.onComplete = onComplete; self.onCancel = onCancel; self.onError = onError
    }

    func makeUIViewController(context: Context) -> SecondCameraImageEditorCropViewController {
        let controller = SecondCameraImageEditorCropViewController(model: model, srcImage: image, previewImage: image)
        configure(controller)
        return controller
    }
    func updateUIViewController(_ controller: SecondCameraImageEditorCropViewController, context: Context) { configure(controller) }
    private func configure(_ controller: SecondCameraImageEditorCropViewController) {
        controller.locksOutputSize = locksOutputSize
        controller.secondCameraFullScreenCoverDismissHandler = onCancel
        controller.cropCompletionHandler = { transform in
            model.replace(transform: transform)
            guard let output = model.renderOutput() else { onError("裁剪图片生成失败，请重试。"); return }
            onComplete(output, ImageCropParameters(transform))
        }
    }
}
