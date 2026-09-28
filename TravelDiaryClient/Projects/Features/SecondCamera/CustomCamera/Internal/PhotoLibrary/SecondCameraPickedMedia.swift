import Foundation
import UIKit

enum SecondCameraPickedMedia {
    case image(UIImage, assetIdentifier: String?)
    case video(URL, assetIdentifier: String?)

    var customCameraMedia: CustomCameraMedia? {
        switch self {
        case .image(let image, _):
            return CustomCameraMedia(data: image)
        case .video(let url, _):
            return CustomCameraMedia(data: url)
        }
    }
}
