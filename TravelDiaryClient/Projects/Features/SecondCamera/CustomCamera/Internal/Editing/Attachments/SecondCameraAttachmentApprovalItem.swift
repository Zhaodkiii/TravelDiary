//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import UIKit

public class SecondCameraAttachmentApprovalItem {

    enum SecondCameraAttachmentApprovalItemError: Error {
        case noThumbnail
    }

    public let attachment: SecondCameraPreviewableAttachment

    enum `Type` {
        case generic
        case image
        case video
    }

    var type: `Type` {
        if secondCameraImageEditorModel != nil {
            return .image
        }
        if videoEditorModel != nil {
            return .video
        }
        return .generic
    }

    // This might be nil if the attachment is not a valid image.
    let secondCameraImageEditorModel: SecondCameraImageEditorModel?
    // This might be nil if the attachment is not a valid video.
    let videoEditorModel: SecondCameraVideoEditorModel?
    let canSave: Bool

    public init(attachment: SecondCameraPreviewableAttachment, canSave: Bool) {
        self.attachment = attachment
        self.canSave = canSave

        self.secondCameraImageEditorModel = SecondCameraAttachmentApprovalItem.secondCameraImageEditorModel(for: attachment)
        if self.secondCameraImageEditorModel == nil {
            self.videoEditorModel = SecondCameraAttachmentApprovalItem.videoEditorModel(for: attachment)
        } else {
            // Make sure we only have one of a video editor and an image editor, not both.
            self.videoEditorModel = nil
        }
    }

    private static func secondCameraImageEditorModel(for attachment: SecondCameraPreviewableAttachment) -> SecondCameraImageEditorModel? {
        guard case .image(let normalizedImage) = attachment.attachmentType else {
            return nil
        }
        do {
            return try SecondCameraImageEditorModel(normalizedImage: normalizedImage)
        } catch {
            secondCameraEditorFailDebug("Could not create image editor: \(error)")
            return nil
        }
    }

    private static func videoEditorModel(for attachment: SecondCameraPreviewableAttachment) -> SecondCameraVideoEditorModel? {
        do {
            return try SecondCameraVideoEditorModel(attachment)
        } catch {
            secondCameraEditorFailDebug("couldn't create video editor: \(error)")
            return nil
        }
    }

    func getThumbnailImage() -> UIImage? {
        return self.attachment.rawValue.staticThumbnail()
    }

    public func isIdenticalTo(_ other: SecondCameraAttachmentApprovalItem?) -> Bool {
        return self === other
    }
}

// MARK: -

class SecondCameraAttachmentApprovalItemCollection {
    private(set) var attachmentApprovalItems: [SecondCameraAttachmentApprovalItem]
    let isAddMoreVisible: () -> Bool

    init(attachmentApprovalItems: [SecondCameraAttachmentApprovalItem], isAddMoreVisible: @escaping () -> Bool) {
        self.attachmentApprovalItems = attachmentApprovalItems
        self.isAddMoreVisible = isAddMoreVisible
    }

    func itemAfter(item: SecondCameraAttachmentApprovalItem) -> SecondCameraAttachmentApprovalItem? {
        guard let currentIndex = attachmentApprovalItems.firstIndex(where: { $0.isIdenticalTo(item) }) else {
            secondCameraEditorFailDebug("currentIndex was unexpectedly nil")
            return nil
        }

        let nextIndex = attachmentApprovalItems.index(after: currentIndex)

        return attachmentApprovalItems.indices.contains(nextIndex) ? attachmentApprovalItems[nextIndex] : nil
    }

    func itemBefore(item: SecondCameraAttachmentApprovalItem) -> SecondCameraAttachmentApprovalItem? {
        guard let currentIndex = attachmentApprovalItems.firstIndex(where: { $0.isIdenticalTo(item) }) else {
            secondCameraEditorFailDebug("currentIndex was unexpectedly nil")
            return nil
        }

        let prevIndex = attachmentApprovalItems.index(before: currentIndex)

        return attachmentApprovalItems.indices.contains(prevIndex) ? attachmentApprovalItems[prevIndex] : nil
    }

    func remove(item: SecondCameraAttachmentApprovalItem) {
        attachmentApprovalItems.removeAll(where: { $0.isIdenticalTo(item) })
    }

    var count: Int {
        return attachmentApprovalItems.count
    }
}
