import SwiftUI

struct SecondCameraPreviewRailCellView: View {
    let thumbnail: UIImage?
    let isSelected: Bool
    var canDelete: Bool = false
    var accessibilityLabelText: String? = nil
    let onSelect: () -> Void
    var onDelete: (() -> Void)? = nil

    private let size: CGFloat = 44
    private let cornerRadius: CGFloat = 10

    var body: some View {
        ZStack {
            Button(action: onSelect) {
                ZStack {
                    thumbnailImage
                        .frame(width: size, height: size)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

                    if isSelected {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(Color.black.opacity(0.45))
                            .frame(width: size, height: size)
                    }

                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(isSelected ? Color.blue : Color.white, lineWidth: isSelected ? 2 : 1.5)
                        .frame(width: size, height: size)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabelText ?? SecondCameraEditorL10n.PublicPreview.thumbnailFallback)
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])

            if isSelected, canDelete, let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: size, height: size)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(SecondCameraEditorL10n.Multi.delete)
            }
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private var thumbnailImage: some View {
        if let thumbnail {
            Image(uiImage: thumbnail)
                .resizable()
                .scaledToFill()
        } else {
            Color.gray.opacity(0.35)
                .overlay {
                    Image(systemName: "photo")
                        .foregroundStyle(.white.opacity(0.8))
                }
        }
    }
}
