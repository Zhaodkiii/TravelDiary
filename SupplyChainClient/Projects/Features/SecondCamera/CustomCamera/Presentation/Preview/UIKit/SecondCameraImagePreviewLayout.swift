import UIKit

/// 预览大图布局常量与 contentInsets 计算，对齐 Signal Attachment Approval 避让逻辑。
enum SecondCameraImagePreviewLayout {
    static let signalPreviewCornerRadius: CGFloat = 18
    static let maximumZoomScaleMultiplier: CGFloat = 5
    static let horizontalInset: CGFloat = 0
    /// 预留顶部关闭/返回按钮区域（与 Signal top bar 接近）。
    static let topPreviewControlsHeight: CGFloat = 0
    /// 底部工具栏高度；若 SwiftUI 已用 safeAreaInset 压缩内容区，则不要再计入。
    static let bottomToolbarHeight: CGFloat = 0
    /// 小图轨区域（含内边距），对齐当前 `SecondCameraPreviewRailView` 视觉高度。
    static let previewRailHeight: CGFloat = 0
    static let previewRailSpacing: CGFloat = 0

    /// - Parameter toolbarReservedBySafeAreaInset: 为 true 时不再把工具栏高度计入 bottom，避免与 `.safeAreaInset` 双重避让。
    static func contentInsets(
        showsPreviewRail: Bool,
        toolbarReservedBySafeAreaInset: Bool
    ) -> UIEdgeInsets {
        var bottom: CGFloat = 0
        if !toolbarReservedBySafeAreaInset {
            bottom += bottomToolbarHeight
        }
        if showsPreviewRail {
            bottom += previewRailHeight + previewRailSpacing
        }

        return UIEdgeInsets(
            top: topPreviewControlsHeight,
            left: horizontalInset,
            bottom: bottom,
            right: horizontalInset
        )
    }
}
