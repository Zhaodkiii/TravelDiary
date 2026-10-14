import Photos
import PhotosUI
import SwiftUI
import UIKit
import MediaEditorScreen

struct TelegramPhotoEditorHomeView: View {
    @State private var selectedItem: PhotosPickerItem?
    @State private var sourceImage: UIImage?
    @State private var editedImage: UIImage?
    @State private var isLoading = false
    @State private var isPresentingEditor = false
    @State private var alertMessage: String?

    var body: some View {
        let hasEditedImage = editedImage != nil
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 20) {
                preview

                VStack(spacing: 12) {
                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        Label(hasEditedImage ? "重新选择照片" : "选择照片", systemImage: "photo.on.rectangle")
                            .font(.headline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.21, green: 0.65, blue: 0.96))
                    .disabled(isLoading)

                    if editedImage != nil {
                        Button {
                            sourceImage = editedImage
                            isPresentingEditor = true
                        } label: {
                            Label("继续编辑", systemImage: "slider.horizontal.3")
                                .frame(maxWidth: .infinity)
                                .frame(height: 46)
                        }
                        .buttonStyle(.bordered)
                        .tint(.white)

                        Button(action: saveEditedImage) {
                            Label("保存到相册", systemImage: "square.and.arrow.down")
                                .frame(maxWidth: .infinity)
                                .frame(height: 46)
                        }
                        .buttonStyle(.bordered)
                        .tint(.white)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .onChange(of: selectedItem) { _, item in
            guard let item else { return }
            Task { await openSelectedPhoto(item) }
        }
        .fullScreenCover(isPresented: $isPresentingEditor) {
            if let sourceImage {
                TelegramOriginalPhotoEditorView(
                    sourceImage: sourceImage,
                    onCancel: { isPresentingEditor = false },
                    onComplete: { result in
                        editedImage = result
                        isPresentingEditor = false
                    }
                )
            }
        }
        .alert("Telegram 照片编辑", isPresented: alertBinding) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
    }

    @ViewBuilder
    private var preview: some View {
        if isLoading {
            ProgressView("正在读取照片…")
                .tint(.white)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let editedImage {
            Image(uiImage: editedImage)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 14) {
                Image(systemName: "wand.and.stars.inverse")
                    .font(.system(size: 54, weight: .semibold))
                Text("Telegram 照片编辑")
                    .font(.title2.weight(.bold))
                Text("调整、裁剪、绘制和添加文字")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.68))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var alertBinding: Binding<Bool> {
        Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )
    }

    @MainActor
    private func openSelectedPhoto(_ item: PhotosPickerItem) async {
        isLoading = true
        defer {
            isLoading = false
            selectedItem = nil
        }

        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data)
            else {
                throw TelegramPhotoEditorError.invalidImage
            }
            sourceImage = image
            editedImage = nil
            isPresentingEditor = true
        } catch {
            alertMessage = (error as? LocalizedError)?.errorDescription ?? "照片读取失败。"
        }
    }

    private func saveEditedImage() {
        guard let editedImage else { return }
        TelegramPhotoLibrarySaver.save(editedImage) { result in
            switch result {
            case .success:
                alertMessage = "照片已保存到系统相册。"
            case .failure(let error):
                alertMessage = error.localizedDescription
            }
        }
    }
}

private struct TelegramOriginalPhotoEditorView: UIViewControllerRepresentable {
    let sourceImage: UIImage
    let onCancel: () -> Void
    let onComplete: (UIImage) -> Void

    func makeUIViewController(context: Context) -> TelegramPhotoEditorViewController {
        TelegramPhotoEditorViewController(
            sourceImage: sourceImage,
            onCancel: onCancel,
            onComplete: onComplete
        )
    }

    func updateUIViewController(_ uiViewController: TelegramPhotoEditorViewController, context: Context) {}
}

private enum TelegramPhotoLibrarySaver {
    static func save(_ image: UIImage, completion: @escaping @MainActor (Result<Void, Error>) -> Void) {
        Task {
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else {
                completion(.failure(TelegramPhotoEditorError.photoLibraryDenied))
                return
            }

            do {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                }
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        }
    }
}

private enum TelegramPhotoEditorError: LocalizedError {
    case invalidImage
    case photoLibraryDenied

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            "无法读取所选照片，请重新选择。"
        case .photoLibraryDenied:
            "没有保存照片到系统相册的权限。"
        }
    }
}
