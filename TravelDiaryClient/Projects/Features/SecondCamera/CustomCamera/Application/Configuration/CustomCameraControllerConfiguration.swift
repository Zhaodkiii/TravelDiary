//
//  Public+CameraSettings+CustomCameraViewController.swift of MijickCamera
//
//  Created by Tomasz Kurylik. Sending ❤️ from Kraków!
//    - Mail: tomasz.kurylik@mijick.com
//    - GitHub: https://github.com/FulcrumOne
//    - Medium: https://medium.com/@mijick
//
//  Copyright ©2024 Mijick. All rights reserved.



// MARK: Available Actions

import Foundation

internal extension CustomCameraView.Controller {
    /**
     Closes the CustomCameraView.

     See ``CustomCameraView/setCloseCustomCameraAction(_:)`` for more details.
     */
    func closeCustomCamera() { customCameraView.config.closeCustomCameraAction() }

    /**
     Opens the Camera Screen.
     */
    func reopenCameraScreen() { customCameraView.manager.setCapturedMedia(nil) }
}
