import SwiftUI

/// 只读缩略图轨道：仅选择，不含删除/追加。
struct SecondCameraReadOnlyPreviewRail: View {
    let items: [SecondCameraReadOnlyPreviewItem]
    let selectedID: UUID?
    let onSelect: (UUID) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        SecondCameraPreviewRailCellView(
                            thumbnail: item.thumbnail ?? item.image,
                            isSelected: item.id == selectedID,
                            canDelete: false,
                            accessibilityLabelText: SecondCameraEditorL10n.PublicPreview.thumbnailAccessibility(
                                index: index + 1,
                                total: items.count
                            ),
                            onSelect: { onSelect(item.id) }
                        )
                        .id(item.id)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 8)
            }
            .onChange(of: selectedID) { newID in
                guard let newID else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(newID, anchor: .center)
                }
            }
            .onAppear {
                if let selectedID {
                    proxy.scrollTo(selectedID, anchor: .center)
                }
            }
        }
        .frame(height: 60)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
}
