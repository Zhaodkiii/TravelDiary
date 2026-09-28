import PhotosUI
import SwiftUI
import UIKit

struct PhotoEditorHomeView: View {
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var editingSession: SecondCameraImageEditingSession?
    @State private var previewImage: UIImage?
    @State private var isLoadingPhoto = false
    @State private var isPresentingEditor = false
    @State private var alertMessage: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 20) {
                preview

                VStack(spacing: 12) {
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Label(previewImage == nil ? "选择照片" : "重新选择照片", systemImage: "photo.on.rectangle")
                            .font(.headline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .foregroundStyle(.black)
                    .disabled(isLoadingPhoto)

                    if editingSession != nil {
                        Button {
                            isPresentingEditor = true
                        } label: {
                            Label("继续编辑", systemImage: "slider.horizontal.3")
                                .font(.headline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                        }
                        .buttonStyle(.bordered)
                        .tint(.white)

                        Button(action: saveEditedPhoto) {
                            Label("保存到相册", systemImage: "square.and.arrow.down")
                                .font(.headline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                        }
                        .buttonStyle(.bordered)
                        .tint(.white)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .onChange(of: selectedPhotoItem) { _, item in
            guard let item else { return }
            Task { await loadPhotoAndOpenEditor(item) }
        }
        .fullScreenCover(isPresented: $isPresentingEditor) {
            if let editingSession {
                DefaultCustomCapturedMediaScreen.SecondCameraStandaloneImageEditorRepresentable(
                    model: editingSession.model,
                    onDismiss: finishEditing
                )
                .ignoresSafeArea()
            }
        }
        .alert("照片编辑", isPresented: alertBinding) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
    }

    @ViewBuilder
    private var preview: some View {
        if isLoadingPhoto {
            ProgressView("正在读取照片…")
                .tint(.white)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let previewImage {
            Image(uiImage: previewImage)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
        } else {
            VStack(spacing: 14) {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 54, weight: .semibold))
                Text("选择一张照片开始编辑")
                    .font(.title2.weight(.bold))
                Text("选择后会直接进入照片编辑模式，不会启动相机。")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
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
    private func loadPhotoAndOpenEditor(_ item: PhotosPickerItem) async {
        isLoadingPhoto = true
        defer {
            isLoadingPhoto = false
            selectedPhotoItem = nil
        }

        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data)
            else {
                throw PhotoEditorHomeError.invalidImage
            }

            let session = try SecondCameraEditorAttachmentFactory.makeSecondCameraImageEditingSession(from: image)
            editingSession = session
            previewImage = image
            isPresentingEditor = true
        } catch {
            alertMessage = (error as? LocalizedError)?.errorDescription ?? "照片读取失败，请重新选择。"
        }
    }

    private func finishEditing() {
        if let renderedImage = editingSession?.model.renderOutput() {
            previewImage = renderedImage
        }
        isPresentingEditor = false
    }

    private func saveEditedPhoto() {
        guard let image = editingSession?.model.renderOutput() ?? previewImage else { return }
        CameraMediaSaver.saveImage(image) { result in
            switch result {
            case .success:
                alertMessage = "照片已保存到系统相册。"
            case .failure(let error):
                alertMessage = error.localizedDescription
            }
        }
    }
}

private enum PhotoEditorHomeError: LocalizedError {
    case invalidImage

    var errorDescription: String? {
        "无法读取所选照片，请重新选择。"
    }
}
