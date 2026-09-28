import UIKit

struct SecondCameraImageEditingSession {
    let approvalItem: SecondCameraAttachmentApprovalItem
    let model: SecondCameraImageEditorModel
    var outputOptions: SecondCameraImageOutputOptions
}

enum SecondCameraEditorAttachmentFactory {

    static func makeSecondCameraImageEditingSession(
        from image: UIImage,
        outputOptions: SecondCameraImageOutputOptions = SecondCameraImageOutputOptions()
    ) throws -> SecondCameraImageEditingSession {
        SecondCameraEditorAppContextImplBootstrap.bootstrapIfNeeded()

        let normalized = try SecondCameraNormalizedImage.forImage(image)
        let attachment = SecondCameraPreviewableAttachment.imageAttachmentForSecondCameraNormalizedImage(normalized)
        let approvalItem = SecondCameraAttachmentApprovalItem(attachment: attachment, canSave: true)
        guard let model = approvalItem.secondCameraImageEditorModel else {
            throw SecondCameraImageEditorError.invalidInput
        }
        return SecondCameraImageEditingSession(
            approvalItem: approvalItem,
            model: model,
            outputOptions: outputOptions
        )
    }
}
