//
//  Public+Model+CameraUtilities.swift of MijickCamera
//
//  Created by Tomasz Kurylik. Sending ❤️ from Kraków!
//    - Mail: tomasz.kurylik@mijick.com
//    - GitHub: https://github.com/FulcrumOne
//    - Medium: https://medium.com/@mijick
//
//  Copyright ©2024 Mijick. All rights reserved.



// MARK: Camera Output Type

import SwiftUI

internal enum CameraOutputType: CaseIterable {
    case photo
    case video
}

// MARK: Camera Position
internal enum CameraPosition: CaseIterable {
    case back
    case front
}

// MARK: Camera Flash Mode
internal enum CameraFlashMode: CaseIterable {
    case off
    case on
    case auto
}

// MARK: Camera Light Mode
internal enum CameraLightMode: CaseIterable {
    case off
    case on
}

// MARK: Camera HDR Mode
internal enum CameraHDRMode: CaseIterable {
    case off
    case on
    case auto
}
