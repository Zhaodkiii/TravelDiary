import Photos
import UIKit

enum CameraMediaSaver {
    static func saveImage(_ image: UIImage, completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        saveMedia(completion: completion) {
            _ = PHAssetChangeRequest.creationRequestForAsset(from: image)
        }
    }

    static func saveVideo(_ url: URL, completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            DispatchQueue.main.async {
                completion(.failure(CameraMediaSaverError.missingVideoFile))
            }
            return
        }

        saveMedia(completion: completion) {
            _ = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }
    }

    private static func saveMedia(
        completion: @escaping @Sendable (Result<Void, Error>) -> Void,
        performChange: @escaping @Sendable () -> Void
    ) {
        requestAddOnlyAuthorization { authorizationResult in
            switch authorizationResult {
            case .failure(let error):
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            case .success:
                PHPhotoLibrary.shared().performChanges(performChange) { success, error in
                    DispatchQueue.main.async {
                        if let error {
                            print("SecondCamera save failed: \(error.localizedDescription)")
                            completion(.failure(error))
                        } else if success {
                            completion(.success(()))
                        } else {
                            completion(.failure(CameraMediaSaverError.saveFailed))
                        }
                    }
                }
            }
        }
    }

    private static func requestAddOnlyAuthorization(
        completion: @escaping @Sendable (Result<Void, Error>) -> Void
    ) {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch status {
        case .authorized, .limited:
            completion(.success(()))
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { newStatus in
                switch newStatus {
                case .authorized, .limited:
                    completion(.success(()))
                default:
                    completion(.failure(CameraMediaSaverError.photoLibraryDenied))
                }
            }
        default:
            completion(.failure(CameraMediaSaverError.photoLibraryDenied))
        }
    }
}

enum CameraMediaSaverError: LocalizedError, Sendable {
    case photoLibraryDenied
    case missingVideoFile
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .photoLibraryDenied:
            return "Photo library add permission was denied."
        case .missingVideoFile:
            return "Captured video file is missing."
        case .saveFailed:
            return "Saving media to the photo library failed."
        }
    }
}
