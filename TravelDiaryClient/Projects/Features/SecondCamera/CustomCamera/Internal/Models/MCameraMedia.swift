//
//  CustomCameraMedia.swift of MijickCamera
//
//  Created by Tomasz Kurylik. Sending ❤️ from Kraków!
//    - Mail: tomasz.kurylik@mijick.com
//    - GitHub: https://github.com/FulcrumOne
//    - Medium: https://medium.com/@mijick
//
//  Copyright ©2024 Mijick. All rights reserved.




import SwiftUI

internal struct CustomCameraMedia: Sendable {
    let image: UIImage?
    let video: URL?

    init?(data: Any?) {
        if let image = data as? UIImage { self.image = image; self.video = nil }
        else if let video = data as? URL { self.video = video; self.image = nil }
        else { return nil }
    }
}

// MARK: Equatable
extension CustomCameraMedia: Equatable {
    internal static func == (lhs: CustomCameraMedia, rhs: CustomCameraMedia) -> Bool { lhs.image == rhs.image && lhs.video == rhs.video }
}
