//
//  Public+UI+CustomCapturedMediaScreen.swift of MijickCamera
//
//  Created by Tomasz Kurylik. Sending ❤️ from Kraków!
//    - Mail: tomasz.kurylik@mijick.com
//    - GitHub: https://github.com/FulcrumOne
//    - Medium: https://medium.com/@mijick
//
//  Copyright ©2024 Mijick. All rights reserved.
//

import SwiftUI
import AVFoundation

/**
 Screen that displays the captured media.

 - important: A view conforming to **CustomCapturedMediaScreen** has to be passed directly to ``CustomCameraView``. See ``CustomCameraView/setCapturedMediaScreen(_:)`` for more details.
 */
internal protocol CustomCapturedMediaScreen: View {
    var previewStore: SecondCameraMultiCaptureStore { get }
    var namespace: Namespace.ID { get }
    var discardAction: () -> () { get }
    var continueCaptureAction: () -> () { get }
    var acceptMediaAction: () -> () { get }
}
