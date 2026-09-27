import SwiftUI
import UIKit

/// SwiftUI ↔ UIKit 大图预览桥接。使用 UIViewControllerRepresentable，便于布局与缩放生命周期管理。
struct SecondCameraUIKitImagePreviewRepresentable: UIViewControllerRepresentable {
    let imageID: AnyHashable
    let image: UIImage
    let contentInsets: UIEdgeInsets
    var cornerRadius: CGFloat = SecondCameraImagePreviewLayout.signalPreviewCornerRadius
    var maximumZoomScaleMultiplier: CGFloat = SecondCameraImagePreviewLayout.maximumZoomScaleMultiplier

    func makeUIViewController(context: Context) -> SecondCameraUIKitImagePreviewViewController {
        SecondCameraUIKitImagePreviewViewController(
            imageID: imageID,
            image: image,
            contentInsets: contentInsets,
            cornerRadius: cornerRadius,
            maximumZoomScaleMultiplier: maximumZoomScaleMultiplier
        )
    }

    func updateUIViewController(
        _ viewController: SecondCameraUIKitImagePreviewViewController,
        context: Context
    ) {
        viewController.update(
            imageID: imageID,
            image: image,
            contentInsets: contentInsets,
            cornerRadius: cornerRadius,
            maximumZoomScaleMultiplier: maximumZoomScaleMultiplier
        )
    }
}
