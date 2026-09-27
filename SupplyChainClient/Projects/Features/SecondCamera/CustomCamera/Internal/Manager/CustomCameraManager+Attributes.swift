//
//  CustomCameraManager+Attributes.swift of MijickCamera
//
//  Created by Tomasz Kurylik. Sending ❤️ from Kraków!
//    - Mail: tomasz.kurylik@mijick.com
//    - GitHub: https://github.com/FulcrumOne
//    - Medium: https://medium.com/@mijick
//
//  Copyright ©2024 Mijick. All rights reserved.




import AVFoundation
import AVKit
import Combine

enum CustomCameraSessionState: Equatable {
    case idle
    case starting
    case running
    case interrupted
    case backgrounded
    case resuming
    case failed
}

struct CustomCameraManagerAttributes {
    var capturedMedia: CustomCameraMedia? = nil
    /// 多图预览队列；继续拍摄时不清空，仅 `clearCapturedMediaSession` 会清空。
    let multiCaptureStore = SecondCameraMultiCaptureStore()
    var error: CustomCameraError? = nil

    var outputType: CameraOutputType = .photo
    var cameraPosition: CameraPosition = .back
    var isAudioSourceAvailable: Bool = true
    var zoomFactor: CGFloat = 1.0
    var flashMode: CameraFlashMode = .off
    var lightMode: CameraLightMode = .off
    var resolution: AVCaptureSession.Preset = .hd1920x1080
    var frameRate: Int32 = 30
    var cameraExposure: CameraExposure = .init()
    var hdrMode: CameraHDRMode = .auto
    var cameraFilters: [CIFilter] = []
    var mirrorOutput: Bool = false
    var isGridVisible: Bool = true
    var isSessionReady: Bool = false
    var sessionState: CustomCameraSessionState = .idle

    var deviceOrientation: AVCaptureVideoOrientation = .portrait
    var frameOrientation: CGImagePropertyOrientation = .right
    var orientationLocked: Bool = false
    var userBlockedScreenRotation: Bool = false
}
