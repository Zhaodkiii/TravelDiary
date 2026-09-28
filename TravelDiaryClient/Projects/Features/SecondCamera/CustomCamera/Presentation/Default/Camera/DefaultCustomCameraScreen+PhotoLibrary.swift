import PhotosUI
import SwiftUI

extension DefaultCustomCameraScreen {
    func handlePickedMedia(_ mediaItems: [SecondCameraPickedMedia]) {
        guard !mediaItems.isEmpty else {
            handlePhotoPickerFailure(SecondCameraPhotoLibraryError.mediaBuildFailed)
            return
        }

        SparkLogger.log(
            level: .info,
            module: .camera,
            message: "SecondCamera photo library entering preview count=\(mediaItems.count) remainingCapacity=\(cameraManager.attributes.multiCaptureStore.remainingCapacity)"
        )

        cameraManager.presentPickedMedia(mediaItems)
    }

    func handlePhotoPickerCancel() {
        SparkLogger.log(
            level: .info,
            module: .camera,
            message: "SecondCamera photo library picker cancelled"
        )
    }

    func handlePhotoPickerFailure(_ error: Error) {
        SparkLogger.log(
            level: .error,
            module: .camera,
            message: "SecondCamera photo library picker failed error=\(error.localizedDescription)"
        )
    }
}
