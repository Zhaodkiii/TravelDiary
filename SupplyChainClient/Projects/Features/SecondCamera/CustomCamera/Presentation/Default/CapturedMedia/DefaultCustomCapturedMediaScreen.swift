//
//  DefaultCustomCapturedMediaScreen.swift of MijickCamera
//
//  Created by Tomasz Kurylik. Sending ❤️ from Kraków!
//    - Mail: tomasz.kurylik@mijick.com
//    - GitHub: https://github.com/FulcrumOne
//    - Medium: https://medium.com/@mijick
//
//  Copyright ©2024 Mijick. All rights reserved.
//

import AVKit
import AVFoundation
import PhotosUI
import SwiftUI

/// 相机拍摄完成后的媒体预览页：支持多图轨、继续拍摄、相册追加、单图编辑。
struct DefaultCustomCapturedMediaScreen: CustomCapturedMediaScreen {
    @ObservedObject var previewStore: SecondCameraMultiCaptureStore
    let namespace: Namespace.ID
    let discardAction: () -> ()
    let continueCaptureAction: () -> ()
    let acceptMediaAction: () -> ()

    @State private var player: AVPlayer = .init()
    @State private var isInitialized: Bool = false
    @State private var playingVideoURL: URL?

    @State var isShowingImageEditor = false
    @State var isShowingCropEditor = false
    @State var isShowingQualityPicker = false
    @State var isShowingPhotoPicker = false
    @State var editorErrorMessage: String?
    @State var isSavingCurrentImage = false

    init(_ context: SecondCameraCapturedMediaContext) {
        self.previewStore = context.store
        self.namespace = context.namespace
        self.discardAction = context.discardAction
        self.continueCaptureAction = context.continueCaptureAction
        self.acceptMediaAction = context.acceptMediaAction
    }

    var body: some View {
        ZStack {
            createContentView()

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topLeading) {
            createRetakeButton()
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 0) {
                if !isShowingImageEditor && !isShowingCropEditor {
                    SecondCameraPreviewRailView(
                        store: previewStore,
                        onContinueCapture: continueCaptureAction,
                        onPickFromLibrary: { isShowingPhotoPicker = true },
                        onDeleteLastItem: discardAction
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .background(Color(.mijickBackgroundPrimary).ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            createButtons()
        }
        .animation(.mSpring, value: isInitialized)
        .onAppear {
            isInitialized = true
            SecondCameraEditorAppContextImplBootstrap.bootstrapIfNeeded()
            prepareSelectedSecondCameraEditorIfNeeded()
        }
        .onChange(of: previewStore.selectedID) { _ in
            guard !isShowingImageEditor, !isShowingCropEditor else { return }
            prepareSelectedSecondCameraEditorIfNeeded()
            syncPlayerForSelectedItem()
        }
        .fullScreenCover(isPresented: $isShowingImageEditor) {
            if let editorModel = selectedEditorModel() {
                SecondCameraStandaloneImageEditorRepresentable(
                    model: editorModel,
                    onDismiss: {
                        refreshSelectedSecondCameraRenderedPreviewImage()
                        isShowingImageEditor = false
                    }
                )
                .ignoresSafeArea()
            } else {
                Color.black
                    .ignoresSafeArea()
                    .onAppear { isShowingImageEditor = false }
            }
        }
        .fullScreenCover(isPresented: $isShowingCropEditor) {
            if let editorModel = selectedEditorModel() {
                SecondCameraCropEditorRepresentable(
                    model: editorModel,
                    onDismiss: {
                        refreshSelectedSecondCameraRenderedPreviewImage()
                        isShowingCropEditor = false
                    }
                )
                .ignoresSafeArea()
            } else {
                Color.black
                    .ignoresSafeArea()
                    .onAppear { isShowingCropEditor = false }
            }
        }
        .sheet(isPresented: $isShowingPhotoPicker) {
            SecondCameraPhotoPickerView(
                selectionLimit: previewStore.remainingCapacity,
                filter: .images,
                onComplete: { picked in
                    isShowingPhotoPicker = false
                    Task { @MainActor in
                        await Task.yield()
                        previewStore.appendLibrary(picked)
                        prepareSelectedSecondCameraEditorIfNeeded()
                    }
                },
                onCancel: {
                    isShowingPhotoPicker = false
                },
                onFailure: { error in
                    isShowingPhotoPicker = false
                    editorErrorMessage = error.localizedDescription
                }
            )
        }
        .alert(
            SecondCameraEditorL10n.Error.editorGeneric,
            isPresented: Binding(
                get: { editorErrorMessage != nil },
                set: { if !$0 { editorErrorMessage = nil } }
            )
        ) {
            Button(SecondCameraEditorL10n.Error.ok, role: .cancel) { editorErrorMessage = nil }
        } message: {
            Text(editorErrorMessage ?? "")
        }
    }
}

// MARK: - 视图构建
private extension DefaultCustomCapturedMediaScreen {
    @ViewBuilder func createContentView() -> some View {
        if isInitialized, let item = previewStore.selectedItem {
            if item.displayImage != nil {
                SecondCameraMediaPreviewViewport(
                    item: item.asMediaPreviewDisplayItem,
                    contentInsets: previewContentInsets
                )
                .id(item.id)
            } else if let video = item.media.getVideo() {
                createVideoView(video)
                    .id(item.id)
            }
        }
    }

    func createButtons() -> some View {
        HStack(spacing: 10) {
            createEditToolbarButtons()
            Spacer(minLength: 0)
            createSaveButton()
        }
        .padding(.horizontal, 12)

    }
}

private extension DefaultCustomCapturedMediaScreen {
    var previewContentInsets: UIEdgeInsets {
        // 小图轨始终可能显示（单图也有继续拍摄入口）；与 overlay 避让对齐。
        let showsRail = !isShowingImageEditor && !isShowingCropEditor
        return SecondCameraImagePreviewLayout.contentInsets(
            showsPreviewRail: showsRail,
            toolbarReservedBySafeAreaInset: true
        )
    }

    func createVideoView(_ video: URL) -> some View {
        VideoPlayer(player: player)
            .onAppear { onVideoAppear(video) }
    }

    @ViewBuilder func createRetakeButton() -> some View {
        if isInitialized {
            BottomButton(
                icon: .mijickIconCancel,
                iconColor: .init(.mijickBackgroundInverted),
                backgroundColor: .init(.mijickBackgroundSecondary),
                rotationAngle: .zero,
                action: discardAction
            )
            .transition(.scale)
        }
    }

    @ViewBuilder func createSaveButton() -> some View {
        if isInitialized {
            BottomButton(
                icon: .mijickIconCheck,
                iconColor: .init(.mijickBackgroundPrimary),
                backgroundColor: .init(.mijickBackgroundInverted),
                rotationAngle: .zero,
                action: acceptEditedOrOriginalMedia
            )
            .transition(.scale)
        }
    }
}

// MARK: - 选中项编辑
extension DefaultCustomCapturedMediaScreen {
    func selectedEditorModel() -> SecondCameraImageEditorModel? {
        previewStore.selectedItem?.editorModel
    }

    func prepareSelectedSecondCameraEditorIfNeeded() {
        guard let item = previewStore.selectedItem,
              item.isImage,
              item.editorModel == nil,
              let image = item.media.getImage()
        else { return }

        do {
            let session = try SecondCameraEditorAttachmentFactory.makeSecondCameraImageEditingSession(
                from: image,
                outputOptions: item.imageOutputOptions
            )
            previewStore.updateSelected { selected in
                selected.editableImage = image
                selected.approvalItem = session.approvalItem
                selected.editorModel = session.model
                selected.imageOutputOptions = session.outputOptions
                if selected.renderedPreviewImage == nil {
                    selected.renderedPreviewImage = image
                }
            }
        } catch {
            editorErrorMessage = SecondCameraEditorL10n.Error.editorInitFailed
        }
    }

    func openSecondCameraEditor() {
        guard !isShowingCropEditor else { return }
        prepareSelectedSecondCameraEditorIfNeeded()
        guard selectedEditorModel() != nil else { return }
        isShowingImageEditor = true
    }

    func openSecondCameraCropEditor() {
        guard !isShowingImageEditor else { return }
        prepareSelectedSecondCameraEditorIfNeeded()
        guard selectedEditorModel() != nil else { return }
        isShowingCropEditor = true
    }

    func refreshSelectedSecondCameraRenderedPreviewImage() {
        guard let item = previewStore.selectedItem,
              let model = item.editorModel
        else { return }

        if let rendered = model.renderOutput() {
            let preview = SecondCameraImageRenderer.applySecondCameraOutputOptions(
                to: rendered,
                options: item.imageOutputOptions
            )
            previewStore.updateSelected { selected in
                selected.renderedPreviewImage = preview
                selected.thumbnail = SecondCameraPreviewThumbnailBuilder.makeThumbnail(from: preview)
                // 质量切换可能已 bump；编辑/裁剪返回时在此 bump。
                selected.bumpPreviewRevision()
            }
        }
    }

    func saveCurrentSecondCameraEditedImage() {
        guard !isSavingCurrentImage else { return }
        prepareSelectedSecondCameraEditorIfNeeded()
        guard let approvalItem = previewStore.selectedItem?.approvalItem,
              let options = previewStore.selectedItem?.imageOutputOptions
        else {
            editorErrorMessage = SecondCameraEditorL10n.Error.noImageToSave
            return
        }
        isSavingCurrentImage = true
        Task { @MainActor in
            defer { isSavingCurrentImage = false }
            do {
                let host = UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .flatMap(\.windows)
                    .first { $0.isKeyWindow }?
                    .rootViewController
                try await SecondCameraEditorSaveController.saveSecondCameraEditedMedia(
                    approvalItem: approvalItem,
                    options: options,
                    presentingViewController: host ?? UIViewController()
                )
            } catch {
                editorErrorMessage = (error as? LocalizedError)?.errorDescription ?? "保存失败"
            }
        }
    }

    func acceptEditedOrOriginalMedia() {
        for item in previewStore.items where item.isImage {
            if let model = item.editorModel, let rendered = model.renderOutput() {
                let preview = SecondCameraImageRenderer.applySecondCameraOutputOptions(
                    to: rendered,
                    options: item.imageOutputOptions
                )
                previewStore.updateItem(id: item.id) { target in
                    target.renderedPreviewImage = preview
                    target.bumpPreviewRevision()
                }
            }
        }
        acceptMediaAction()
    }
}

private extension DefaultCustomCapturedMediaScreen {
    func onVideoAppear(_ url: URL) {
        guard playingVideoURL != url else {
            player.play()
            return
        }
        playingVideoURL = url
        player = .init(url: url)
        player.play()
    }

    func syncPlayerForSelectedItem() {
        guard let video = previewStore.selectedItem?.media.getVideo() else {
            player.pause()
            playingVideoURL = nil
            return
        }
        onVideoAppear(video)
    }
}
