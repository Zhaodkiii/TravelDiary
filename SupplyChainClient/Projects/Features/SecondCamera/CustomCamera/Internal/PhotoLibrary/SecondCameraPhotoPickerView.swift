import PhotosUI
import SwiftUI

struct SecondCameraPhotoPickerView: UIViewControllerRepresentable {
    let selectionLimit: Int
    let filter: PHPickerFilter
    let onComplete: ([SecondCameraPickedMedia]) -> Void
    let onCancel: () -> Void
    let onFailure: (Error) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.selectionLimit = selectionLimit
        config.filter = filter
        config.selection = .ordered

        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: SecondCameraPhotoPickerView
        private let loader = SecondCameraPhotoLibraryLoader()

        init(parent: SecondCameraPhotoPickerView) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            // 由 SwiftUI `.sheet(isPresented:)` 统一关闭，避免与 UIKit dismiss 双重竞争。
            guard !results.isEmpty else {
                parent.onCancel()
                return
            }

            SparkLogger.log(
                level: .info,
                module: .camera,
                message: "SecondCamera photo library selected count=\(results.count)"
            )

            Task {
                do {
                    let media = try await loader.load(results: results)
                    await MainActor.run {
                        parent.onComplete(media)
                    }
                } catch {
                    await MainActor.run {
                        parent.onFailure(error)
                    }
                }
            }
        }
    }
}
