import SwiftUI

extension DefaultCustomCapturedMediaScreen {

    @ViewBuilder
    func createEditToolbarButtons() -> some View {
        if previewStore.selectedItem?.isImage == true {
            createToolButton(systemName: "pencil.tip", action: openSecondCameraEditor)
            createToolButton(systemName: "crop.rotate", action: openSecondCameraCropEditor)
            createToolButton(
                systemName: (previewStore.selectedItem?.imageOutputOptions.quality == .high
                             || previewStore.selectedItem?.imageOutputOptions.quality == .original)
                    ? "photo.badge.checkmark"
                    : "arrow.down.left.and.arrow.up.right",
                action: { isShowingQualityPicker = true }
            )
            .confirmationDialog(SecondCameraEditorL10n.Quality.title, isPresented: $isShowingQualityPicker) {
                ForEach(SecondCameraEditorImageQualityPreset.allCases, id: \.self) { preset in
                    Button(preset.localizedTitle) {
                        previewStore.updateSelected { item in
                            item.imageOutputOptions.applySecondCameraQualityPreset(preset)
                            item.bumpPreviewRevision()
                        }
                        refreshSelectedSecondCameraRenderedPreviewImage()
                    }
                }
            }
            createToolButton(systemName: "square.and.arrow.down", action: saveCurrentSecondCameraEditedImage)
        }
    }

    func createToolButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color(.mijickBackgroundInverted))
                .frame(width: 48, height: 48)
                .background(Color(.mijickBackgroundSecondary))
                .clipShape(Circle())
        }
        .transition(.scale)
    }
}
