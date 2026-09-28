import SwiftUI
import UIKit

/// 无状态媒体预览视口：只渲染 display item，不持有业务 Store。
struct SecondCameraMediaPreviewViewport: View {
    let item: SecondCameraMediaPreviewDisplayItem?
    let contentInsets: UIEdgeInsets

    var body: some View {
        ZStack {
            Color(.mijickBackgroundPrimary)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var content: some View {
        if let item {
            switch item.content {
            case .idle, .loading:
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(Color(.mijickBackgroundInverted))
            case .image(let image):
                SecondCameraUIKitImagePreviewRepresentable(
                    imageID: item.imageIdentity,
                    image: image,
                    contentInsets: contentInsets,
                    cornerRadius: SecondCameraImagePreviewLayout.signalPreviewCornerRadius,
                    maximumZoomScaleMultiplier: SecondCameraImagePreviewLayout.maximumZoomScaleMultiplier
                )
                .ignoresSafeArea()
                .transition(.scale(scale: 1.1))
            case .video:
                // 公共本期不接视频；相机层自行渲染 VideoPlayer。
                emptyState
            case .failure(let error):
                failureState(message: error.localizedUserMessage)
            }
        } else {
            emptyState
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo")
                .font(.system(size: 36))
                .foregroundStyle(Color(.mijickBackgroundInverted).opacity(0.7))
            Text(SecondCameraEditorL10n.PublicPreview.empty)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color(.mijickBackgroundInverted))
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .accessibilityElement(children: .combine)
    }

    private func failureState(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(Color(.mijickBackgroundInverted).opacity(0.7))
            Text(message)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color(.mijickBackgroundInverted))
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .accessibilityElement(children: .combine)
    }
}
