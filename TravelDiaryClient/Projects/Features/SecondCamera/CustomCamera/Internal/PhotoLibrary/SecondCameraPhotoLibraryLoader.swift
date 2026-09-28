import PhotosUI
import UniformTypeIdentifiers
import UIKit

final class SecondCameraPhotoLibraryLoader {
    func load(results: [PHPickerResult]) async throws -> [SecondCameraPickedMedia] {
        guard !results.isEmpty else {
            throw SecondCameraPhotoLibraryError.emptySelection
        }

        var loaded: [SecondCameraPickedMedia] = []
        loaded.reserveCapacity(results.count)

        for result in results {
            let media = try await loadSingle(result)
            loaded.append(media)
        }

        guard !loaded.isEmpty else {
            throw SecondCameraPhotoLibraryError.mediaBuildFailed
        }

        return loaded
    }

    private func loadSingle(_ result: PHPickerResult) async throws -> SecondCameraPickedMedia {
        let provider = result.itemProvider
        let assetIdentifier = result.assetIdentifier

        if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
            return try await loadVideo(provider: provider, assetIdentifier: assetIdentifier)
        }

        if provider.canLoadObject(ofClass: UIImage.self) {
            return try await loadImage(provider: provider, assetIdentifier: assetIdentifier)
        }

        throw SecondCameraPhotoLibraryError.unsupportedType
    }

    private func loadImage(
        provider: NSItemProvider,
        assetIdentifier: String?
    ) async throws -> SecondCameraPickedMedia {
        let image: UIImage = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UIImage, Error>) in
            provider.loadObject(ofClass: UIImage.self) { object, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let image = object as? UIImage else {
                    continuation.resume(throwing: SecondCameraPhotoLibraryError.imageLoadFailed)
                    return
                }

                continuation.resume(returning: image)
            }
        }

        return .image(Self.normalizedImage(image), assetIdentifier: assetIdentifier)
    }

    private func loadVideo(
        provider: NSItemProvider,
        assetIdentifier: String?
    ) async throws -> SecondCameraPickedMedia {
        let sourceURL: URL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let url else {
                    continuation.resume(throwing: SecondCameraPhotoLibraryError.videoLoadFailed)
                    return
                }

                continuation.resume(returning: url)
            }
        }

        let copiedURL = try copyVideoToTemporaryDirectory(sourceURL)
        return .video(copiedURL, assetIdentifier: assetIdentifier)
    }

    private func copyVideoToTemporaryDirectory(_ sourceURL: URL) throws -> URL {
        try CustomCameraFileStore.ensureTemporaryDirectory()

        let destinationURL = CustomCameraFileStore.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }

        do {
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        } catch {
            throw SecondCameraPhotoLibraryError.videoCopyFailed
        }

        return destinationURL
    }

    private static func normalizedImage(_ image: UIImage) -> UIImage {
        if image.imageOrientation == .up { return image }

        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = false

        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }
}
