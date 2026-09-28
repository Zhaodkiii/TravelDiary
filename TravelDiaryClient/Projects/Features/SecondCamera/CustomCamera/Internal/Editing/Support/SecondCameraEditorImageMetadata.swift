//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only

import UIKit
//

import Foundation

public enum SecondCameraEditorImageFormat: CustomStringConvertible {
    case png
    case gif
    case tiff
    case jpeg
    case bmp
    case webp
    case heic
    case heif

    public var description: String {
        switch self {
        case .png:
            "SecondCameraEditorImageFormat_Png"
        case .gif:
            "SecondCameraEditorImageFormat_Gif"
        case .tiff:
            "SecondCameraEditorImageFormat_Tiff"
        case .jpeg:
            "SecondCameraEditorImageFormat_Jpeg"
        case .bmp:
            "SecondCameraEditorImageFormat_Bmp"
        case .webp:
            "SecondCameraEditorImageFormat_Webp"
        case .heic:
            "SecondCameraEditorImageFormat_Heic"
        case .heif:
            "SecondCameraEditorImageFormat_Heif"
        }
    }

    public var mimeType: SecondCameraEditorMimeType {
        return self.mimeTypes.preferredSecondCameraEditorMimeType
    }

    private var mimeTypes: (preferredSecondCameraEditorMimeType: SecondCameraEditorMimeType, alternativeSecondCameraEditorMimeTypes: [SecondCameraEditorMimeType]) {
        switch self {
        case .png: (.imagePng, [.imageApng, .imageVndMozillaApng])
        case .gif: (.imageGif, [])
        case .tiff: (.imageTiff, [.imageXTiff])
        case .jpeg: (.imageJpeg, [])
        case .bmp: (.imageBmp, [.imageXWindowsBmp])
        case .webp: (.imageWebp, [])
        case .heic: (.imageHeic, [])
        case .heif: (.imageHeif, [])
        }
    }

    public var fileExtension: String {
        // All known SecondCameraEditorImageFormats must have a corresponding extension.
        return SecondCameraEditorMimeTypeUtil.fileExtensionForSecondCameraEditorMimeType(mimeType.rawValue)!
    }

    func isValid(mimeType: String) -> Bool {
        secondCameraEditorAssertDebug(!mimeType.isEmpty)
        let mimeTypes = self.mimeTypes
        return ([mimeTypes.preferredSecondCameraEditorMimeType] + mimeTypes.alternativeSecondCameraEditorMimeTypes).contains(where: {
            return mimeType.caseInsensitiveCompare($0.rawValue) == .orderedSame
        })
    }
}

public struct SecondCameraEditorImageMetadata {
    public let imageFormat: SecondCameraEditorImageFormat
    public let pixelSize: CGSize
    public let hasAlpha: Bool
    public let isAnimated: Bool

    public var hasStickerLikeProperties: Bool {
        let maxStickerHeight = CGFloat(512)
        return
            pixelSize.width <= maxStickerHeight
                && pixelSize.height <= maxStickerHeight
                && pixelSize != CGSize(width: 1, height: 1)
                && hasAlpha

    }
}
