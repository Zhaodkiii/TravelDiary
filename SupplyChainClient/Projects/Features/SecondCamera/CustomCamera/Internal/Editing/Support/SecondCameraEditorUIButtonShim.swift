//
// Signal Camera - UIButton edge insets shim (from UIButton+DeprecationWorkaround)
//

import UIKit

public extension UIButton {
    var ows_contentEdgeInsets: UIEdgeInsets {
        get { contentEdgeInsets }
        set { contentEdgeInsets = newValue }
    }

    var secondCameraEditor_contentEdgeInsets: UIEdgeInsets {
        get { contentEdgeInsets }
        set { contentEdgeInsets = newValue }
    }

    var secondCameraEditor_imageEdgeInsets: UIEdgeInsets {
        get { imageEdgeInsets }
        set { imageEdgeInsets = newValue }
    }

    var secondCameraEditor_titleEdgeInsets: UIEdgeInsets {
        get { titleEdgeInsets }
        set { titleEdgeInsets = newValue }
    }
}

public extension UICollectionView {
    subscript(secondCameraEditor_safe indexPath: IndexPath) -> UICollectionViewCell? {
        guard indexPath.section < numberOfSections,
              indexPath.item < numberOfItems(inSection: indexPath.section) else {
            return nil
        }
        return cellForItem(at: indexPath)
    }
}

public protocol SecondCameraStickerPickerSheetDelegate: AnyObject {}

public enum SecondCameraEditorAppEnvironment {
    nonisolated(unsafe) public static var shared = SecondCameraEditorAppEnvironmentStub()
}

public struct SecondCameraEditorAppEnvironmentStub {
    public var callService = SecondCameraEditorCallServiceStub()
}

public struct SecondCameraEditorCallServiceStub {
    public var callServiceState = SecondCameraEditorCallServiceStateStub()
}

public struct SecondCameraEditorCallServiceStateStub {
    public var currentCall: Any? { nil }
}
