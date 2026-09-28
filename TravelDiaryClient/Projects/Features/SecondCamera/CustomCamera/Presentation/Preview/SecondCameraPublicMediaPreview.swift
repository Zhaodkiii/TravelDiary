import SwiftUI

/// 相机外可复用的公共全屏图片预览（第一阶段仅只读）。
struct SecondCameraPublicMediaPreview: View {
    @StateObject private var store: SecondCameraReadOnlyPreviewStore
    let onClose: () -> Void

    init(
        inputs: [SecondCameraMediaPreviewInput],
        selectedID: UUID?,
        onClose: @escaping () -> Void,
        loader: any SecondCameraPreviewImageLoading = SecondCameraPreviewImageLoader.shared
    ) {
        _store = StateObject(
            wrappedValue: SecondCameraReadOnlyPreviewStore(
                inputs: inputs,
                selectedID: selectedID,
                loader: loader
            )
        )
        self.onClose = onClose
    }

    var body: some View {
        ZStack {
            Color(.mijickBackgroundPrimary).ignoresSafeArea()
            SecondCameraMediaPreviewViewport(
                item: store.selectedDisplayItem,
                contentInsets: .zero
            )
        }
        .overlay(alignment: .topLeading) {
            closeButton
                .padding(.horizontal, 12)
                .padding(.top, 8)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if store.items.count > 1 {
                SecondCameraReadOnlyPreviewRail(
                    items: store.items,
                    selectedID: store.selectedID,
                    onSelect: { store.select(id: $0) }
                )
            }
        }
        .onAppear {
            store.loadSelectedIfNeeded()
            store.prefetchNeighbors()
        }
        .onDisappear {
            store.cancelOutstandingLoads()
            SparkLogger.log(
                level: .info,
                module: .camera,
                message: "Public media preview closed"
            )
        }
    }

    private var closeButton: some View {
        BottomButton(
            icon: .mijickIconCancel,
            iconColor: .init(.mijickBackgroundInverted),
            backgroundColor: .init(.mijickBackgroundSecondary),
            rotationAngle: .zero,
            action: onClose
        )
        .accessibilityLabel(SecondCameraEditorL10n.PublicPreview.close)
    }
}
