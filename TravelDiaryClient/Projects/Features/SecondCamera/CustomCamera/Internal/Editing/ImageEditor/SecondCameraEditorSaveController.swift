import Photos
import UIKit

enum SecondCameraEditorSaveController {

    @MainActor
    static func saveSecondCameraEditedMedia(
        approvalItem: SecondCameraAttachmentApprovalItem,
        options: SecondCameraImageOutputOptions,
        presentingViewController: UIViewController,
    ) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw SaveError.permissionDenied
        }

        switch approvalItem.type {
        case .image:
            guard let image = SecondCameraImageRenderer.renderSecondCameraEditedPhoto(from: approvalItem, options: options) else {
                throw SaveError.renderFailed
            }
            try await saveSecondCameraImageToPhotoLibrary(image)

        case .video:
            let url = approvalItem.attachment.dataSource.fileUrl
            if let model = approvalItem.videoEditorModel, model.isTrimmed {
                let trimmedURL = try await model.render()
                try await saveSecondCameraVideoToPhotoLibrary(at: trimmedURL)
            } else {
                try await saveSecondCameraVideoToPhotoLibrary(at: url)
            }

        case .generic:
            throw SaveError.unsupportedMedia
        }
    }

    // MARK: - Photo Library (nonisolated)

    /// `performChanges` runs on `com.apple.PHPhotoLibrary.changes` — must not use @MainActor closures.
    private static func saveSecondCameraImageToPhotoLibrary(_ image: UIImage) async throws {
        nonisolated(unsafe) let imageToSave = image
        try await performPhotoLibraryChanges {
            PHAssetCreationRequest.creationRequestForAsset(from: imageToSave)
        }
    }

    private static func saveSecondCameraVideoToPhotoLibrary(at url: URL) async throws {
        let fileURL = url
        try await performPhotoLibraryChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
        }
    }

    private static func performPhotoLibraryChanges(
        _ changeBlock: @escaping @Sendable () -> Void,
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges(changeBlock) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: SaveError.saveFailed)
                }
            }
        }
    }

    enum SaveError: LocalizedError {
        case permissionDenied
        case renderFailed
        case unsupportedMedia
        case saveFailed

        var errorDescription: String? {
            switch self {
            case .permissionDenied: return SecondCameraEditorL10n.Preview.saveFailed
            case .renderFailed: return SecondCameraEditorL10n.Error.loadFailed
            case .unsupportedMedia: return SecondCameraEditorL10n.Error.loadFailed
            case .saveFailed: return SecondCameraEditorL10n.Preview.saveFailed
            }
        }
    }
}
