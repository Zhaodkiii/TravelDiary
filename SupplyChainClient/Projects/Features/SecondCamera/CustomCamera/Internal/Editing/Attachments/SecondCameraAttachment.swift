//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//
import AVFoundation
import UIKit
import Foundation
import MobileCoreServices
//import SDWebImage

public struct SecondCameraAttachmentReference {
    public enum RenderingFlag {
        case `default`
        case voiceMessage
        case borderless
        case shouldLoop
    }
}

public enum SecondCameraAttachmentError: Error {
    case missingData
    case fileSizeTooLarge
    case invalidData
    case couldNotParseImage
    case couldNotConvertImage
    case couldNotConvertToMpeg4
    case couldNotRemoveMetadata
    case invalidFileFormat
    case couldNotResizeImage
}

// MARK: -

extension SecondCameraAttachmentError: LocalizedError, SecondCameraEditorUserErrorDescriptionProvider {
    public var errorDescription: String? {
        localizedDescription
    }

    nonisolated public var localizedDescription: String {
        switch self {
        case .missingData:
            return SecondCameraEditorLocalizedString("ATTACHMENT_ERROR_MISSING_DATA", comment: "Attachment error message for attachments without any data")
        case .fileSizeTooLarge:
            return SecondCameraEditorLocalizedString("ATTACHMENT_ERROR_FILE_SIZE_TOO_LARGE", comment: "Attachment error message for attachments whose data exceed file size limits")
        case .invalidData:
            return SecondCameraEditorLocalizedString("ATTACHMENT_ERROR_INVALID_DATA", comment: "Attachment error message for attachments with invalid data")
        case .couldNotParseImage:
            return SecondCameraEditorLocalizedString("ATTACHMENT_ERROR_COULD_NOT_PARSE_IMAGE", comment: "Attachment error message for image attachments which cannot be parsed")
        case .couldNotConvertImage:
            return SecondCameraEditorLocalizedString("ATTACHMENT_ERROR_COULD_NOT_CONVERT_TO_JPEG", comment: "Attachment error message for image attachments which could not be converted to JPEG")
        case .invalidFileFormat:
            return SecondCameraEditorLocalizedString("ATTACHMENT_ERROR_INVALID_FILE_FORMAT", comment: "Attachment error message for attachments with an invalid file format")
        case .couldNotConvertToMpeg4:
            return SecondCameraEditorLocalizedString("ATTACHMENT_ERROR_COULD_NOT_CONVERT_TO_MP4", comment: "Attachment error message for video attachments which could not be converted to MP4")
        case .couldNotRemoveMetadata:
            return SecondCameraEditorLocalizedString("ATTACHMENT_ERROR_COULD_NOT_REMOVE_METADATA", comment: "Attachment error message for image attachments in which metadata could not be removed")
        case .couldNotResizeImage:
            return SecondCameraEditorLocalizedString("ATTACHMENT_ERROR_COULD_NOT_RESIZE_IMAGE", comment: "Attachment error message for image attachments which could not be resized")
        }
    }
}

// MARK: -

// Represents a possible attachment to upload.
//
// Signal attachments are subject to validation and, in some cases, file
// format conversion.
//
// This class gathers that logic. It offers factory methods for attachments
// that do the necessary work.
//
// TODO: Perhaps do conversion off the main thread?

public class SecondCameraAttachment: CustomDebugStringConvertible {

    // MARK: Properties

    public let dataSource: SecondCameraEditorDataSourcePath

    // Attachment types are identified using UTIs.
    //
    // See: https://developer.apple.com/library/content/documentation/Miscellaneous/Reference/UTIRef/Articles/System-DeclaredUniformTypeIdentifiers.html
    public let dataUTI: String

    // To avoid redundant work of repeatedly compressing/uncompressing
    // images, we cache the UIImage associated with this attachment if
    // possible.
    private var cachedImage: UIImage?
    private var cachedThumbnail: UIImage?
    private var cachedVideoPreview: UIImage?

    public var isVoiceMessage = false

    public static let maxAttachmentsAllowed: Int = 32

    // MARK: Constructor

    // This method should not be called directly; use the factory
    // methods instead.
    init(dataSource: SecondCameraEditorDataSourcePath, dataUTI: String) {
        self.dataSource = dataSource
        self.dataUTI = dataUTI

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didReceiveMemoryWarningNotification),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
        )
    }

    @objc
    private func didReceiveMemoryWarningNotification() {
        cachedImage = nil
        cachedThumbnail = nil
        cachedVideoPreview = nil
    }

    // MARK: Methods

    public var debugDescription: String {
        return "[SecondCameraAttachment mimeType: \(mimeType)]"
    }

    public func staticThumbnail() -> UIImage? {
        if let cachedThumbnail {
            return cachedThumbnail
        }

        return autoreleasepool {
            guard
                let image: UIImage = {
                    if isImage {
                        return image()
                    } else if isVideo {
                        return videoPreview()
                    } else if isAudio {
                        return nil
                    } else {
                        return nil
                    }
                }() else { return nil }

            // We want to limit the *smaller* dimension to 60 points,
            // so figure out what the larger dimension would need to
            // be limited to if we preserved our aspect ratio. This
            // ensures crisp thumbnails when we center crop in a
            // 60x60 or smaller container.
            let pixelSize = image.pixelSize
            let maxDimensionPixels = ((60 * UIScreen.main.scale) / pixelSize.secondCameraEditor_smallerAxis).secondCameraEditor_clamp01() * pixelSize.secondCameraEditor_largerAxis

            let thumbnail = image.resized(maxDimensionPixels: maxDimensionPixels)
            cachedThumbnail = thumbnail
            return thumbnail
        }
    }

    public var renderingFlag: SecondCameraAttachmentReference.RenderingFlag {
        if isVoiceMessage {
            return .voiceMessage
        } else if isBorderless {
            return .borderless
        } else if isLoopingVideo || SecondCameraEditorMimeTypeUtil.isSupportedDefinitelyAnimatedSecondCameraEditorMimeType(mimeType) {
            return .shouldLoop
        } else {
            return .default
        }
    }

    public func image() -> UIImage? {
        if let cachedImage {
            return cachedImage
        }
        guard let imageData = try? dataSource.readData(), let image = UIImage(data: imageData) else {
            return nil
        }
        cachedImage = image
        return image
    }

    public func videoPreview() -> UIImage? {
        if let cachedVideoPreview {
            return cachedVideoPreview
        }

        let mediaUrl = dataSource.fileUrl

        do {
            let filePath = mediaUrl.path
            guard FileManager.default.fileExists(atPath: filePath) else {
                secondCameraEditorFailDebug("asset at \(filePath) doesn't exist")
                return nil
            }

            let asset = AVURLAsset(url: mediaUrl)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            let cgImage = try generator.copyCGImage(at: CMTimeMake(value: 0, timescale: 1), actualTime: nil)
            let image = UIImage(cgImage: cgImage)

            cachedVideoPreview = image
            return image

        } catch {
            return nil
        }
    }

    public var isBorderless = false
    public var isLoopingVideo = false

    // Returns the MIME type for this attachment or nil if no MIME type
    // can be identified.
    public var mimeType: String {
        if isVoiceMessage {
            // Legacy iOS clients don't handle "audio/mp4" files correctly;
            // they are written to disk as .mp4 instead of .m4a which breaks
            // playback.  So we send voice messages as "audio/aac" to work
            // around this.
            //
            // TODO: Remove this Nov. 2016 or after.
            return "audio/aac"
        }
        return SecondCameraEditorMimeTypeUtil.mimeTypeForSecondCameraEditorDataSource(dataSource, dataUTI: dataUTI)
    }

    // Returns the file extension for this attachment or nil if no file extension
    // can be identified.
    public var fileExtension: String? {
        if let filename = dataSource.sourceFilename?.secondCameraEditor_filterFilename() {
            let fileExtension = (filename as NSString).pathExtension
            if !fileExtension.isEmpty {
                return fileExtension.secondCameraEditor_filterFilename()
            }
        }
        guard let fileExtension = SecondCameraEditorMimeTypeUtil.fileExtensionForUtiType(dataUTI) else {
            return nil
        }
        return fileExtension
    }

    // Returns the set of UTIs that correspond to valid _input_ image formats
    // for Signal attachments.
    //
    // Image attachments may be converted to another image format before
    // being uploaded.
    public static let inputImageUTISet: Set<String> = {
        // We support additional types for input images because we can transcode
        // these to a format that's always supported by the receiver.
        var additionalTypes = [UTType]()
        if #available(iOS 18.2, *) {
            additionalTypes.append(.jpegxl)
        }
        if #available(iOS 18.0, *) {
            additionalTypes.append(.dng)
        } else {
            additionalTypes.append(UTType("com.adobe.raw-image")!)
        }
        if #available(iOS 16.0, *) {
            additionalTypes.append(UTType("public.avif")!)
        }
        additionalTypes.append(.heif)
        additionalTypes.append(.heic)
        additionalTypes.append(.webP)

        return outputImageUTISet.union(additionalTypes.map(\.identifier))
    }()

    // Returns the set of UTIs that correspond to valid _output_ image formats
    // for Signal attachments.
    class var outputImageUTISet: Set<String> {
        SecondCameraEditorMimeTypeUtil.supportedImageUtiTypes.union(animatedImageUTISet)
    }

    private class var outputVideoUTISet: Set<String> {
        [UTType.mpeg4Movie.identifier]
    }

    // Returns the set of UTIs that correspond to valid animated image formats
    // for Signal attachments.
    private class var animatedImageUTISet: Set<String> {
        SecondCameraEditorMimeTypeUtil.supportedAnimatedImageUtiTypes
    }

    // Returns the set of UTIs that correspond to valid video formats
    // for Signal attachments.
    public class var videoUTISet: Set<String> {
        SecondCameraEditorMimeTypeUtil.supportedVideoUtiTypes
    }

    // Returns the set of UTIs that correspond to valid audio formats
    // for Signal attachments.
    public class var audioUTISet: Set<String> {
        SecondCameraEditorMimeTypeUtil.supportedAudioUtiTypes
    }

    // Returns the set of UTIs that correspond to valid image, video and audio formats
    // for Signal attachments.
    public class var mediaUTISet: Set<String> {
        return audioUTISet.union(videoUTISet).union(animatedImageUTISet).union(inputImageUTISet)
    }

    public var isImage: Bool {
        return SecondCameraAttachment.outputImageUTISet.contains(dataUTI)
    }

    /// Only valid when `isImage` is true.
    ///
    /// If `isAnimatedImage` is true, then `isImage` must be true. In other
    /// words, all animated images are images (but not all images are animated).
    public var isAnimatedImage = false

    public var isVideo: Bool {
        return SecondCameraAttachment.videoUTISet.contains(dataUTI)
    }

    public var isVisualMedia: Bool {
        return self.isImage || self.isVideo
    }

    public var isAudio: Bool {
        return SecondCameraAttachment.audioUTISet.contains(dataUTI)
    }

    public var isUrl: Bool {
        UTType(dataUTI)?.conforms(to: .url) ?? false
    }
}
