//
//  CustomCameraView+Config.swift of MijickCamera
//
//  Created by Tomasz Kurylik. Sending ❤️ from Kraków!
//    - Mail: tomasz.kurylik@mijick.com
//    - GitHub: https://github.com/FulcrumOne
//    - Medium: https://medium.com/@mijick
//
//  Copyright ©2024 Mijick. All rights reserved.




import Combine
import SwiftUI

extension CustomCameraView { @MainActor class Config {
    // MARK: Screens
    var cameraScreen: CameraScreenBuilder = DefaultCustomCameraScreen.init
    var capturedMediaScreen: CapturedMediaScreenBuilder? = DefaultCustomCapturedMediaScreen.init
    var errorScreen: ErrorScreenBuilder = DefaultCustomCameraErrorScreen.init

    // MARK: Actions
    var imageCapturedAction: (UIImage, CustomCameraView.Controller) -> () = { _,_ in }
    var videoCapturedAction: (URL, CustomCameraView.Controller) -> () = { _,_ in }
    /// 多图完成回调；设置后优先于逐张 image/video 回调。
    var mediaBatchCapturedAction: (([CustomCameraMedia], CustomCameraView.Controller) -> ())? = nil
    var closeCustomCameraAction: () -> () = {}

    // MARK: Others
    var appDelegate: CustomCameraApplicationDelegate.Type? = nil
    var isCameraConfigured: Bool = false
}}
