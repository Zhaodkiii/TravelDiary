import UIKit

/// Carries the state needed to present `SecondCameraImageEditorViewController` via SwiftUI `fullScreenCover`.
@MainActor
final class SecondCameraImageEditorPresentationContext {
    let model: SecondCameraImageEditorModel
    weak var secondCameraStickerSheetDelegate: SecondCameraStickerPickerSheetDelegate?
    weak var previewController: SecondCameraAttachmentPreviewViewController?
    weak var prepController: SecondCameraImageAttachmentPrepViewController?

    init(
        model: SecondCameraImageEditorModel,
        secondCameraStickerSheetDelegate: SecondCameraStickerPickerSheetDelegate?,
        previewController: SecondCameraAttachmentPreviewViewController?,
        prepController: SecondCameraImageAttachmentPrepViewController?
    ) {
        self.model = model
        self.secondCameraStickerSheetDelegate = secondCameraStickerSheetDelegate
        self.previewController = previewController
        self.prepController = prepController
    }
}
