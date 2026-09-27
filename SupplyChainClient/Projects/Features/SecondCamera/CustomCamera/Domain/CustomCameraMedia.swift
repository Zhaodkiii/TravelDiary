//
//  Public+Model+CustomCameraMedia.swift of MijickCamera
//
//  Created by Tomasz Kurylik. Sending ❤️ from Kraków!
//    - Mail: tomasz.kurylik@mijick.com
//    - GitHub: https://github.com/FulcrumOne
//    - Medium: https://medium.com/@mijick
//
//  Copyright ©2024 Mijick. All rights reserved.



// MARK: Getters

import SwiftUI

internal extension CustomCameraMedia {
    /**
     Gets the image from the media object.
     */
    func getImage() -> UIImage? { image }

    /**
     Gets the video URL from the media object.
     */
    func getVideo() -> URL? { video }
}
