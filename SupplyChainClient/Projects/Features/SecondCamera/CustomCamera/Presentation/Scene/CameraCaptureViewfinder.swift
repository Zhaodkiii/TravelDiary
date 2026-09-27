//
//  CameraCaptureViewfinder.swift
//
//  通用「相机取景框」声明工具：让任意场景都能指定拍摄裁剪区域。
//

import SwiftUI

/// 预览视图与取景框在同一个 SwiftUI 坐标系（`.global`）中的位置。
///
/// 之所以同时采集「预览」与「取景框」两个矩形并换算成归一化比例，是为了让裁剪逻辑
/// 完全工作在 SwiftUI 坐标系内 —— SwiftUI 在界面旋转（Landscape）时会一致地旋转
/// 坐标系，从而避免与 UIKit window 坐标系混用导致的横屏裁剪错位问题。
struct CameraCropRegions: Equatable {
    var previewFrame: CGRect?
    var viewfinderFrame: CGRect?
}

struct CameraCropRegionKey: PreferenceKey {
    static let defaultValue = CameraCropRegions()
    static func reduce(value: inout CameraCropRegions, nextValue: () -> CameraCropRegions) {
        let next = nextValue()
        if let preview = next.previewFrame { value.previewFrame = preview }
        if let viewfinder = next.viewfinderFrame { value.viewfinderFrame = viewfinder }
    }
}

extension View {
    /// 上报相机预览视图在全局坐标系中的位置（内部使用，由 `createCameraOutputView` 调用）。
    func reportCameraPreviewFrame() -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: CameraCropRegionKey.self,
                    value: CameraCropRegions(previewFrame: proxy.frame(in: .global))
                )
            }
        )
    }

    /// 将当前视图标记为「相机取景框」。
    ///
    /// 最终拍摄到的照片会被裁剪到此视图的范围内（取景框外的内容不会出现在照片里）。
    /// 适用于任意大小 / 形状的取景框，可在不同相机场景中复用，并自动兼容各拍摄方向。
    ///
    /// - important: 需要在外层容器调用 ``SwiftUI/View/bindCameraCaptureViewfinder(to:)``
    ///   把取景框范围同步给相机管理器。
    /// - note: 请在 `.frame(...)` 之后、`.position(...)` 之前调用，以确保读取到的是取景框自身的尺寸。
    func cameraCaptureViewfinder() -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: CameraCropRegionKey.self,
                    value: CameraCropRegions(viewfinderFrame: proxy.frame(in: .global))
                )
            }
        )
    }

    /// 监听取景框 / 预览范围变化，换算成「相对预览的归一化矩形」后同步给相机管理器，拍摄时据此裁剪。
    func bindCameraCaptureViewfinder(to manager: CustomCameraManager) -> some View {
        onPreferenceChange(CameraCropRegionKey.self) { regions in
            let normalized = Self.normalizedViewfinderRect(from: regions)
            Task { @MainActor in manager.setCaptureViewfinderNormalizedRect(normalized) }
        }
    }

    private static func normalizedViewfinderRect(from regions: CameraCropRegions) -> CGRect? {
        guard let preview = regions.previewFrame,
              let viewfinder = regions.viewfinderFrame,
              preview.width > 0, preview.height > 0
        else { return nil }

        return CGRect(
            x: (viewfinder.minX - preview.minX) / preview.width,
            y: (viewfinder.minY - preview.minY) / preview.height,
            width: viewfinder.width / preview.width,
            height: viewfinder.height / preview.height
        )
    }
}
