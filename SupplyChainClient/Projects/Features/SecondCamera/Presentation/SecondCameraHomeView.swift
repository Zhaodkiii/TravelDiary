import AVFoundation
import AVKit
import SwiftUI
import UIKit

struct SecondCameraHomeView: View {
    @State private var isPresentingCamera = false
    @State private var selectedPreview: SecondCameraPreview?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 18) {
                previewPane

                VStack(spacing: 10) {
                    Button {
                        isPresentingCamera = true
                    } label: {
                        Label(SecondCameraEditorL10n.Home.open, systemImage: "camera.circle")
                            .font(.headline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .foregroundStyle(.black)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $isPresentingCamera) {
            CustomCameraFullScreenView(
                onMediaBatchCaptured: { mediaItems in
                    SparkLogger.log(
                        level: .info,
                        module: .camera,
                        message: "SecondCameraHomeView onMediaBatchCaptured closing camera count=\(mediaItems.count)"
                    )
                    if let firstImage = mediaItems.compactMap({ $0.getImage() }).first {
                        selectedPreview = .photo(firstImage)
                    } else if let firstVideo = mediaItems.compactMap({ $0.getVideo() }).first {
                        selectedPreview = .video(
                            url: firstVideo,
                            thumbnail: CustomCameraHostViewController.makeVideoThumbnail(from: firstVideo)
                        )
                    }
                    isPresentingCamera = false
                },
                onImageCaptured: { image in
                    SparkLogger.log(
                        level: .info,
                        module: .camera,
                        message: "SecondCameraHomeView onImageCaptured closing camera"
                    )
                    selectedPreview = .photo(image)
                    isPresentingCamera = false
                },
                onVideoCaptured: { url, thumbnail in
                    SparkLogger.log(
                        level: .info,
                        module: .camera,
                        message: "SecondCameraHomeView onVideoCaptured closing camera"
                    )
                    selectedPreview = .video(url: url, thumbnail: thumbnail)
                    isPresentingCamera = false
                },
                onDismiss: {
                    SparkLogger.log(
                        level: .info,
                        module: .camera,
                        message: "SecondCameraHomeView onDismiss closing camera"
                    )
                    isPresentingCamera = false
                }
            )
            .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private var previewPane: some View {
        if let selectedPreview {
            switch selectedPreview {
            case .photo(let image):
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
            case .video(let url, let thumbnail):
                VideoPlayer(player: AVPlayer(url: url))
                    .overlay(alignment: .bottomLeading) {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 74, height: 74)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(.white.opacity(0.35)))
                            .padding(16)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            VStack(spacing: 14) {
                Image(systemName: "camera.circle")
                    .font(.system(size: 52, weight: .semibold))
                Text(SecondCameraEditorL10n.Home.title)
                    .font(.title2.weight(.bold))
                Text(SecondCameraEditorL10n.Home.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 28)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private enum SecondCameraPreview {
    case photo(UIImage)
    case video(url: URL, thumbnail: UIImage)
}

private struct CustomCameraFullScreenView: UIViewControllerRepresentable {
    var onMediaBatchCaptured: ([CustomCameraMedia]) -> Void
    var onImageCaptured: (UIImage) -> Void
    var onVideoCaptured: (URL, UIImage) -> Void
    var onDismiss: () -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        CustomCameraHostViewController(
            onMediaBatchCaptured: onMediaBatchCaptured,
            onImageCaptured: onImageCaptured,
            onVideoCaptured: onVideoCaptured,
            onClose: onDismiss
        )
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

private final class CustomCameraHostViewController: UIHostingController<AnyView> {
    init(
        onMediaBatchCaptured: @escaping ([CustomCameraMedia]) -> Void,
        onImageCaptured: @escaping (UIImage) -> Void,
        onVideoCaptured: @escaping (URL, UIImage) -> Void,
        onClose: @escaping () -> Void
    ) {
        CustomCameraFileStore.removeExpiredTemporaryFiles()

        let cameraView = CustomCameraView()
            .setCameraOutputType(.photo)
            .setCameraPosition(.back)
            .setAudioAvailability(true)
            .setResolution(.hd1920x1080)
            .setFrameRate(30)
            .setGridVisibility(true)
            .setCloseCustomCameraAction(onClose)
            .setCameraScreen {
                DefaultCustomCameraScreen(cameraManager: $0, namespace: $1, closeCustomCameraAction: $2)
                    .cameraOutputSwitchAllowed(false)
            }
            .setCapturedMediaScreen(DefaultCustomCapturedMediaScreen.init)
            .onMediaBatchCaptured { mediaItems, _ in
                for media in mediaItems {
                    if let image = media.getImage() {
                        CameraMediaSaver.saveImage(image) { result in
                            if case .failure = result {
                                print("SecondCamera: failed to save image")
                            }
                        }
                    } else if let video = media.getVideo() {
                        CameraMediaSaver.saveVideo(video) { result in
                            if case .failure = result {
                                print("SecondCamera: failed to save video")
                            }
                        }
                    }
                }
                onMediaBatchCaptured(mediaItems)
            }
            .onImageCaptured { image, _ in
                CameraMediaSaver.saveImage(image) { result in
                    if case .failure = result {
                        print("SecondCamera: failed to save image")
                    }
                    onImageCaptured(image)
                }
            }
            .onVideoCaptured { video, _ in
                CameraMediaSaver.saveVideo(video) { result in
                    if case .failure = result {
                        print("SecondCamera: failed to save video")
                    }
                    onVideoCaptured(video, Self.makeVideoThumbnail(from: video))
                }
            }
            .startSession()
        super.init(rootView: AnyView(cameraView))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    static func makeVideoThumbnail(from url: URL) -> UIImage {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        if let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil) {
            return UIImage(cgImage: cgImage)
        }
        return UIImage(systemName: "video.fill") ?? UIImage()
    }
}
