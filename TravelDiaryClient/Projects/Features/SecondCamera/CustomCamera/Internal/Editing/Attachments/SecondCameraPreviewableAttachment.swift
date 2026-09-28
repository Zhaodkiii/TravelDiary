//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import AVFoundation

/// Represents an attachment the user *might* choose to send.
///
/// See also ``SendableAttachment``.
///
/// These are attachments that are valid enough that we believe we can make
/// them fully valid if the user chooses to send them.
///
/// For example, if the user selects an image we can't decode, we can't make
/// a `SecondCameraPreviewableAttachment`. However, if the user selects an image whose
/// file size is too large, we *can* make a `SecondCameraPreviewableAttachment`. If the
/// user chooses to send it, we can re-encode the image with lower quality
/// and/or dimensions to fit within the limit.
///
/// On the other hand, if the user selects a PDF document that's too large,
/// we can't make it valid (e.g., we don't delete or re-encode pages), so we
/// can't make a `SecondCameraPreviewableAttachment` for it.
public struct SecondCameraPreviewableAttachment: @unchecked Sendable {
    public let rawValue: SecondCameraAttachment
    public let attachmentType: AttachmentType

    public enum AttachmentType {
        case image(SecondCameraNormalizedImage)
        case animatedImage
        case other
    }

    public var dataSource: SecondCameraEditorDataSourcePath { self.rawValue.dataSource }

    public var dataUTI: String { self.rawValue.dataUTI }
    public var mimeType: String { self.rawValue.mimeType }
    public var renderingFlag: SecondCameraAttachmentReference.RenderingFlag { self.rawValue.renderingFlag }

    public var isImage: Bool { self.rawValue.isImage }
    public var isAnimatedImage: Bool { self.rawValue.isAnimatedImage }
    public var isVideo: Bool { self.rawValue.isVideo }
    public var isVisualMedia: Bool { self.rawValue.isVisualMedia }
    public var isAudio: Bool { self.rawValue.isAudio }

    // Factory method for an image attachment.
    public static func imageAttachment(dataSource: SecondCameraEditorDataSourcePath, dataUTI: String, canBeBorderless: Bool = false) throws -> Self {
        assert(!dataUTI.isEmpty)

        guard SecondCameraAttachment.inputImageUTISet.contains(dataUTI) else {
            throw SecondCameraAttachmentError.invalidFileFormat
        }

        // [15M] TODO: Allow sending empty attachments?
        guard let fileSize = try? dataSource.readLength(), fileSize > 0 else {
            secondCameraEditorFailDebug("imageData was empty")
            throw SecondCameraAttachmentError.invalidData
        }

        let imageMetadata = try? dataSource.imageSource().imageMetadata()
        let isBorderless = canBeBorderless && (imageMetadata?.hasStickerLikeProperties ?? false)

        let isAnimated = imageMetadata?.isAnimated ?? false
        // Never re-encode animated images (i.e. GIFs) as JPEGs.
        if isAnimated {
            guard fileSize <= SecondCameraEditorMediaUtils.kMaxFileSizeAnimatedImage else {
                throw SecondCameraAttachmentError.fileSizeTooLarge
            }

            let rawValue = SecondCameraAttachment(dataSource: dataSource, dataUTI: dataUTI)
            rawValue.isBorderless = isBorderless
            rawValue.isAnimatedImage = true
            return Self(
                rawValue: rawValue,
                attachmentType: .animatedImage,
            )
        } else {
            if
                let sourceFilename = dataSource.sourceFilename,
                ["heic", "heif"].contains((sourceFilename as NSString).pathExtension.lowercased()),
                dataUTI == UTType.jpeg.identifier as String
            {

                // If a .heic file actually contains jpeg data, update the extension to
                // match.
                //
                // Here's how that can happen:
                //
                // In iOS11, the Photos.app records photos with HEIC UTIType, with the
                // .HEIC extension. Since HEIC isn't a valid output format for Signal,
                // we'll detect that and convert to JPEG, updating the extension as well.
                // No problem. However the problem comes in when you edit an HEIC image in
                // Photos.app - the image is saved in the Photos.app as a JPEG, but retains
                // the (now incongruous) HEIC extension in the filename.

                let baseFilename = (sourceFilename as NSString).deletingPathExtension
                dataSource.sourceFilename = (baseFilename as NSString).appendingPathExtension("jpg") ?? baseFilename
            }

            let normalizedImage = try SecondCameraNormalizedImage.forSecondCameraEditorDataSource(dataSource, dataUTI: dataUTI)
            return imageAttachmentForSecondCameraNormalizedImage(normalizedImage, isBorderless: isBorderless)
        }
    }

    public static func imageAttachmentForSecondCameraNormalizedImage(_ normalizedImage: SecondCameraNormalizedImage, isBorderless: Bool = false) -> Self {
        let rawValue = SecondCameraAttachment(dataSource: normalizedImage.dataSource, dataUTI: normalizedImage.dataUTI)
        rawValue.isBorderless = isBorderless
        return Self(
            rawValue: rawValue,
            attachmentType: .image(normalizedImage),
        )
    }

    // Factory method for video attachments.
    public static func videoAttachment(
        dataSource: SecondCameraEditorDataSourcePath,
        dataUTI: String,
        attachmentLimits: OutgoingAttachmentLimits,
    ) throws -> Self {
        try SecondCameraEditorMediaUtils.validateVideoExtension(ofPath: dataSource.fileUrl.path)
        try SecondCameraEditorMediaUtils.validateVideoAsset(atPath: dataSource.fileUrl.path)
        return try newAttachment(
            dataSource: dataSource,
            dataUTI: dataUTI,
            validUTISet: SecondCameraAttachment.videoUTISet,
            maxFileSize: attachmentLimits.maxPlaintextVideoBytes,
        )
    }

    @MainActor
    public static func compressVideoAsMp4(
        dataSource: SecondCameraEditorDataSourcePath,
        attachmentLimits: OutgoingAttachmentLimits,
        sessionCallback: (@MainActor (AVAssetExportSession) -> Void)? = nil,
    ) async throws -> Self {
        return try await compressVideoAsMp4(
            asset: AVAsset(url: dataSource.fileUrl),
            baseFilename: dataSource.sourceFilename,
            attachmentLimits: attachmentLimits,
            sessionCallback: sessionCallback,
        )
    }

    @MainActor
    public static func compressVideoAsMp4(
        asset: AVAsset,
        baseFilename: String?,
        attachmentLimits: OutgoingAttachmentLimits,
        sessionCallback: (@MainActor (AVAssetExportSession) -> Void)? = nil,
    ) async throws -> Self {
        let startTime = MonotonicDate()

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset640x480) else {
            throw SecondCameraAttachmentError.couldNotConvertToMpeg4
        }

        exportSession.shouldOptimizeForNetworkUse = true
        exportSession.metadataItemFilter = AVMetadataItemFilter.forSharing()

        if let sessionCallback {
            sessionCallback(exportSession)
        }

        let exportURL = SecondCameraEditorFileSystem.temporaryFileUrl(fileExtension: "mp4", isAvailableWhileDeviceLocked: false)

        try await exportSession.exportAsync(to: exportURL, as: .mp4)

        switch exportSession.status {
        case .unknown:
            throw SecondCameraEditorAssertionError("Unknown export status.")
        case .waiting:
            throw SecondCameraEditorAssertionError("Export status: .waiting.")
        case .exporting:
            throw SecondCameraEditorAssertionError("Export status: .exporting.")
        case .completed:
            break
        case .failed:
            if let error = exportSession.error {
                secondCameraEditorFailDebug("Error: \(error)")
                throw error
            } else {
                throw SecondCameraEditorAssertionError("Export failed without error.")
            }
        case .cancelled:
            throw CancellationError()
        @unknown default:
            throw SecondCameraEditorAssertionError("Unknown export status: \(exportSession.status.rawValue)")
        }

        let mp4Filename: String?
        if let baseFilename {
            let baseFilenameWithoutExtension = (baseFilename as NSString).deletingPathExtension
            mp4Filename = (baseFilenameWithoutExtension as NSString).appendingPathExtension("mp4") ?? baseFilenameWithoutExtension
        } else {
            mp4Filename = nil
        }

        let dataSource = SecondCameraEditorDataSourcePath(fileUrl: exportURL, ownership: .owned)
        dataSource.sourceFilename = mp4Filename

        let endTime = MonotonicDate()
        let formattedDuration = SecondCameraEditorOperation.formattedNs((endTime - startTime).nanoseconds)
        SecondCameraEditorLogger.info("transcoded video in \(formattedDuration)s")

        return try videoAttachment(dataSource: dataSource, dataUTI: UTType.mpeg4Movie.identifier, attachmentLimits: attachmentLimits)
    }

    // MARK: Audio Attachments

    // Factory method for audio attachments.
    public static func audioAttachment(
        dataSource: SecondCameraEditorDataSourcePath,
        dataUTI: String,
        attachmentLimits: OutgoingAttachmentLimits,
    ) throws(SecondCameraAttachmentError) -> Self {
        return try newAttachment(
            dataSource: dataSource,
            dataUTI: dataUTI,
            validUTISet: SecondCameraAttachment.audioUTISet,
            maxFileSize: attachmentLimits.maxPlaintextAudioBytes,
        )
    }

    // MARK: Generic Attachments

    // Factory method for generic attachments.
    public static func genericAttachment(
        dataSource: SecondCameraEditorDataSourcePath,
        dataUTI: String,
        attachmentLimits: OutgoingAttachmentLimits,
    ) throws(SecondCameraAttachmentError) -> Self {
        // [15M] TODO: Enforce this at compile-time rather than runtime.
        secondCameraEditorPrecondition(!SecondCameraAttachment.videoUTISet.contains(dataUTI))
        secondCameraEditorPrecondition(!SecondCameraAttachment.inputImageUTISet.contains(dataUTI))
        return try newAttachment(
            dataSource: dataSource,
            dataUTI: dataUTI,
            validUTISet: nil,
            maxFileSize: attachmentLimits.maxPlaintextBytes,
        )
    }

    // MARK: Voice Messages

    public static func voiceMessageAttachment(
        dataSource: SecondCameraEditorDataSourcePath,
        dataUTI: String,
        attachmentLimits: OutgoingAttachmentLimits,
    ) throws(SecondCameraAttachmentError) -> Self {
        let attachment = try audioAttachment(dataSource: dataSource, dataUTI: dataUTI, attachmentLimits: attachmentLimits)
        attachment.rawValue.isVoiceMessage = true
        return attachment
    }

    // MARK: Attachments

    public struct AttachmentTypes: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        public static let image = Self(rawValue: 1 << 0)
        public static let video = Self(rawValue: 1 << 1)
        public static let audio = Self(rawValue: 1 << 2)
        public static let other = Self(rawValue: 1 << 3)

        public static let all: Self = [.image, .video, .audio, .other]
    }

    public struct BuildOptions: OptionSet {
        public let rawValue: Int
        public init(rawValue: Int) {
            self.rawValue = rawValue
        }
    }

    public static func buildAttachment(
        ofTypes types: AttachmentTypes = .all,
        dataSource: SecondCameraEditorDataSourcePath,
        dataUTI: String,
        attachmentLimits: OutgoingAttachmentLimits,
        options: BuildOptions = [],
    ) throws -> Self {
        if SecondCameraAttachment.inputImageUTISet.contains(dataUTI) {
            guard types.contains(.image) else {
                throw SecondCameraAttachmentError.invalidFileFormat
            }
            return try imageAttachment(dataSource: dataSource, dataUTI: dataUTI)
        }
        if SecondCameraAttachment.videoUTISet.contains(dataUTI) {
            guard types.contains(.video) else {
                throw SecondCameraAttachmentError.invalidFileFormat
            }
            return try videoAttachment(dataSource: dataSource, dataUTI: dataUTI, attachmentLimits: attachmentLimits)
        }
        if SecondCameraAttachment.audioUTISet.contains(dataUTI) {
            guard types.contains(.audio) else {
                throw SecondCameraAttachmentError.invalidFileFormat
            }
            return try audioAttachment(dataSource: dataSource, dataUTI: dataUTI, attachmentLimits: attachmentLimits)
        }
        guard types.contains(.other) else {
            throw SecondCameraAttachmentError.invalidFileFormat
        }
        return try genericAttachment(dataSource: dataSource, dataUTI: dataUTI, attachmentLimits: attachmentLimits)
    }

    // MARK: Helper Methods

    private static func newAttachment(
        dataSource: SecondCameraEditorDataSourcePath,
        dataUTI: String,
        validUTISet: Set<String>?,
        maxFileSize: UInt64,
    ) throws(SecondCameraAttachmentError) -> Self {
        assert(!dataUTI.isEmpty)

        let attachment = SecondCameraAttachment(dataSource: dataSource, dataUTI: dataUTI)

        if let validUTISet {
            guard validUTISet.contains(dataUTI) else {
                throw .invalidFileFormat
            }
        }

        // [15M] TODO: Allow sending empty attachments?
        guard let fileSize = try? dataSource.readLength(), fileSize > 0 else {
            secondCameraEditorFailDebug("Empty attachment")
            throw .invalidData
        }

        guard fileSize <= maxFileSize else {
            throw .fileSizeTooLarge
        }

        // Attachment is valid
        return Self(rawValue: attachment, attachmentType: .other)
    }
}
