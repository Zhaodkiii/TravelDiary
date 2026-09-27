import SwiftUI
import UIKit

/// Wraps Signal's `SecondCameraImageEditorViewController` for SwiftUI `fullScreenCover` presentation.
struct SecondCameraImageEditorRepresentable: UIViewControllerRepresentable {
    let context: SecondCameraImageEditorPresentationContext
    let onDismiss: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onDismiss: onDismiss)
    }

    func makeUIViewController(context swiftUIContext: Context) -> SecondCameraImageEditorViewController {
        let editor = SecondCameraImageEditorViewController(
            model: context.model,
            secondCameraStickerSheetDelegate: context.secondCameraStickerSheetDelegate
        )
        let coordinator = swiftUIContext.coordinator
        editor.secondCameraFullScreenCoverDismissHandler = { [weak coordinator] in
            coordinator?.onDismiss()
        }
        return editor
    }

    func updateUIViewController(
        _ uiViewController: SecondCameraImageEditorViewController,
        context swiftUIContext: Context
    ) {
        swiftUIContext.coordinator.onDismiss = onDismiss
        let coordinator = swiftUIContext.coordinator
        uiViewController.secondCameraFullScreenCoverDismissHandler = { [weak coordinator] in
            coordinator?.onDismiss()
        }
    }

    final class Coordinator {
        var onDismiss: () -> Void

        init(onDismiss: @escaping () -> Void) {
            self.onDismiss = onDismiss
        }
    }
}
