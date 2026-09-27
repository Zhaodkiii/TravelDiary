import UIKit

enum SecondCameraEditorTheme {
    static var darkThemePrimaryColor: UIColor { .white }

    static func iconImage(_ icon: SecondCameraEditorThemeIcon) -> UIImage? {
        switch icon {
        case .checkmark:
            return UIImage(systemName: "checkmark")
        }
    }
}

enum SecondCameraEditorThemeIcon {
    case checkmark
}
