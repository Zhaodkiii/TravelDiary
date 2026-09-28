import SwiftUI

struct SecondCameraPreviewRailView: View {
    @ObservedObject var store: SecondCameraMultiCaptureStore
    let onContinueCapture: () -> Void
    let onPickFromLibrary: () -> Void
    let onDeleteLastItem: () -> Void

    @State private var isShowingAddMoreDialog = false
    @State private var pendingDeleteItemID: UUID?
    @State private var isShowingDeleteConfirm = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(store.items.enumerated()), id: \.element.id) { index, item in
                        SecondCameraPreviewRailCellView(
                            thumbnail: item.thumbnail ?? item.displayImage,
                            isSelected: item.id == store.selectedID,
                            canDelete: store.canRemoveSelected,
                            accessibilityLabelText: SecondCameraEditorL10n.PublicPreview.thumbnailAccessibility(
                                index: index + 1,
                                total: store.items.count
                            ),
                            onSelect: {
                                store.select(id: item.id)
                            },
                            onDelete: {
                                pendingDeleteItemID = item.id
                                isShowingDeleteConfirm = true
                            }
                        )
                        .id(item.id)
                    }

                    if store.canAddMore {
                        SecondCameraPreviewAddMoreButton(
                            isEnabled: true,
                            action: { isShowingAddMoreDialog = true }
                        )
                        .id("add-more")
                        .confirmationDialog("", isPresented: $isShowingAddMoreDialog) {
                            Button(SecondCameraEditorL10n.Multi.continueCapture) {
                                onContinueCapture()
                            }
                            Button(SecondCameraEditorL10n.Multi.pickFromLibrary) {
                                onPickFromLibrary()
                            }
                            Button(SecondCameraEditorL10n.Editor.cancel, role: .cancel) {}
                        }
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 8)
            }
            .onChange(of: store.selectedID) { newID in
                guard let newID else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(newID, anchor: .center)
                }
            }
            .onChange(of: store.count) { _ in
                if let selectedID = store.selectedID {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(selectedID, anchor: .center)
                    }
                }
            }
        }
        .frame(height: 60)
        .confirmationDialog(
            SecondCameraEditorL10n.Multi.deleteConfirmTitle,
            isPresented: $isShowingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button(SecondCameraEditorL10n.Multi.deleteConfirmAction, role: .destructive) {
                guard let pendingDeleteItemID else { return }
                handleDelete(itemID: pendingDeleteItemID)
                self.pendingDeleteItemID = nil
            }
            Button(SecondCameraEditorL10n.Editor.cancel, role: .cancel) {
                pendingDeleteItemID = nil
            }
        } message: {
            Text(SecondCameraEditorL10n.Multi.deleteConfirmMessage)
        }
    }

    private func handleDelete(itemID: UUID) {
        let wasLast = store.count <= 1
        store.remove(id: itemID)
        if wasLast || store.isEmpty {
            onDeleteLastItem()
        }
    }
}
