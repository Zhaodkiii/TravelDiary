import Foundation
import SwiftUI

/// 多图预览页上下文：队列在 manager 生命周期上，继续拍摄不会丢图。
struct SecondCameraCapturedMediaContext {
    let store: SecondCameraMultiCaptureStore
    let namespace: Namespace.ID
    /// 放弃全部预览并清空队列，回到相机。
    let discardAction: () -> Void
    /// 继续拍摄：回到相机，保留队列。
    let continueCaptureAction: () -> Void
    /// 完成：输出队列内全部媒体。
    let acceptMediaAction: () -> Void
}

internal typealias CameraScreenBuilder = @MainActor (CustomCameraManager, Namespace.ID, _ closeCustomCameraAction: @escaping () -> ()) -> any CustomCameraScreen
internal typealias CapturedMediaScreenBuilder = @MainActor (SecondCameraCapturedMediaContext) -> any CustomCapturedMediaScreen
internal typealias ErrorScreenBuilder = @MainActor (CustomCameraError, _ closeCustomCameraAction: @escaping () -> ()) -> any CustomCameraErrorScreen
