import SwiftUI

struct SecondCameraPreviewAddMoreButton: View {
    let isEnabled: Bool
    let action: () -> Void

    private let size: CGFloat = 44
    private let cornerRadius: CGFloat = 10

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus.square")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .accessibilityLabel(SecondCameraEditorL10n.Multi.addMore)
    }
}
