import Foundation
import UIKit

/// Minimal stub so image-only SecondCamera editing does not pull in Signal video editor.
final class SecondCameraVideoEditorModel {
    var isTrimmed: Bool { false }

    init(_ attachment: SecondCameraPreviewableAttachment) throws {
        throw SecondCameraImageEditorError.invalidInput
    }

    func render() async throws -> URL {
        throw SecondCameraImageEditorError.invalidInput
    }
}

/// Placeholder type referenced by prep factory; SecondCamera does not ship video trim UI in this module.
final class SecondCameraVideoAttachmentPrepViewController: SecondCameraAttachmentPrepViewController {
    override init?(attachmentApprovalItem: SecondCameraAttachmentApprovalItem) {
        return nil
    }
}

/// Not used by DefaultCustomCapturedMediaScreen; kept only so copied prep helpers compile.
final class SecondCameraAttachmentPreviewViewController: UIViewController {}
