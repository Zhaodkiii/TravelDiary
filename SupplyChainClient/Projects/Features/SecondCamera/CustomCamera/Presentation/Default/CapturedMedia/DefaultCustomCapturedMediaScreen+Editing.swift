import SwiftUI
import UIKit

extension DefaultCustomCapturedMediaScreen {

    struct SecondCameraCropEditorRepresentable: UIViewControllerRepresentable {
        let model: SecondCameraImageEditorModel
        let onDismiss: () -> Void

        func makeCoordinator() -> Coordinator {
            Coordinator(onDismiss: onDismiss)
        }

        func makeUIViewController(context: Context) -> SecondCameraImageEditorCropViewController {
            guard let srcImage = SecondCameraImageEditorCanvasView.loadSrcImage(model: model) else {
                DispatchQueue.main.async { context.coordinator.onDismiss() }
                return SecondCameraImageEditorCropViewController(
                    model: model,
                    srcImage: UIImage(),
                    previewImage: UIImage()
                )
            }
            let previewTransform = SecondCameraImageEditorTransform.defaultTransform(
                srcImageSizePixels: model.srcImageSizePixels
            )
            let previewImage = SecondCameraImageEditorCanvasView.renderForOutput(
                model: model,
                transform: previewTransform
            ) ?? srcImage

            let crop = SecondCameraImageEditorCropViewController(
                model: model,
                srcImage: srcImage,
                previewImage: previewImage
            )
            let coordinator = context.coordinator
            crop.secondCameraFullScreenCoverDismissHandler = { [weak coordinator] in
                coordinator?.onDismiss()
            }
            return crop
        }

        func updateUIViewController(
            _ uiViewController: SecondCameraImageEditorCropViewController,
            context: Context
        ) {
            context.coordinator.onDismiss = onDismiss
            let coordinator = context.coordinator
            uiViewController.secondCameraFullScreenCoverDismissHandler = { [weak coordinator] in
                coordinator?.onDismiss()
            }
        }

        final class Coordinator {
            var onDismiss: () -> Void
            init(onDismiss: @escaping () -> Void) { self.onDismiss = onDismiss }
        }
    }

    /// Lightweight representable that presents the image editor from a model (no Signal preview VC).
    struct SecondCameraStandaloneImageEditorRepresentable: UIViewControllerRepresentable {
        let model: SecondCameraImageEditorModel
        let onDismiss: () -> Void

        func makeCoordinator() -> Coordinator {
            Coordinator(onDismiss: onDismiss)
        }

        func makeUIViewController(context: Context) -> SecondCameraImageEditorViewController {
            let editor = SecondCameraImageEditorViewController(
                model: model,
                secondCameraStickerSheetDelegate: nil
            )
            let coordinator = context.coordinator
            editor.secondCameraFullScreenCoverDismissHandler = { [weak coordinator] in
                coordinator?.onDismiss()
            }
            return editor
        }

        func updateUIViewController(
            _ uiViewController: SecondCameraImageEditorViewController,
            context: Context
        ) {
            context.coordinator.onDismiss = onDismiss
            let coordinator = context.coordinator
            uiViewController.secondCameraFullScreenCoverDismissHandler = { [weak coordinator] in
                coordinator?.onDismiss()
            }
        }

        final class Coordinator {
            var onDismiss: () -> Void
            init(onDismiss: @escaping () -> Void) { self.onDismiss = onDismiss }
        }
    }
}
