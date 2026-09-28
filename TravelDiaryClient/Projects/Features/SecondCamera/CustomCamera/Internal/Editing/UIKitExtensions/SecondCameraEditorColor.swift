import UIKit

extension UIColor {
    nonisolated static var secondCameraEditor_white: UIColor { .white }
    nonisolated static var secondCameraEditor_black: UIColor { .black }
    nonisolated static var secondCameraEditor_whiteAlpha40: UIColor { UIColor.white.withAlphaComponent(0.4) }
    nonisolated static var secondCameraEditor_whiteAlpha60: UIColor { UIColor.white.withAlphaComponent(0.6) }
    nonisolated static var secondCameraEditor_blackAlpha40: UIColor { UIColor.black.withAlphaComponent(0.4) }
    nonisolated static var secondCameraEditor_blackAlpha60: UIColor { UIColor.black.withAlphaComponent(0.6) }
    nonisolated static var secondCameraEditor_gray80: UIColor { UIColor(white: 0.8, alpha: 1) }

    nonisolated convenience init(rgbHex value: UInt32, alpha: CGFloat = 1) {
        let red = CGFloat((value >> 16) & 0xff) / 255.0
        let green = CGFloat((value >> 8) & 0xff) / 255.0
        let blue = CGFloat((value >> 0) & 0xff) / 255.0
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }

    nonisolated func blended(with otherColor: UIColor, alpha alphaParam: CGFloat) -> UIColor {
        var r0: CGFloat = 0
        var g0: CGFloat = 0
        var b0: CGFloat = 0
        var a0: CGFloat = 0
        getRed(&r0, green: &g0, blue: &b0, alpha: &a0)

        var r1: CGFloat = 0
        var g1: CGFloat = 0
        var b1: CGFloat = 0
        var a1: CGFloat = 0
        otherColor.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)

        let alpha = CGFloat.secondCameraEditor_clamp01(alphaParam)
        return UIColor(
            red: CGFloat.secondCameraEditor_lerp(left: r0, right: r1, alpha: alpha),
            green: CGFloat.secondCameraEditor_lerp(left: g0, right: g1, alpha: alpha),
            blue: CGFloat.secondCameraEditor_lerp(left: b0, right: b1, alpha: alpha),
            alpha: CGFloat.secondCameraEditor_lerp(left: a0, right: a1, alpha: alpha)
        )
    }

    nonisolated func isCloseToColor(_ color: UIColor) -> Bool {
        secondCameraEditor_isCloseToColor(color)
    }

    nonisolated func isEqualToColor(_ color: UIColor, tolerance: CGFloat = 0) -> Bool {
        var r1: CGFloat = 0
        var g1: CGFloat = 0
        var b1: CGFloat = 0
        var a1: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)

        var r2: CGFloat = 0
        var g2: CGFloat = 0
        var b2: CGFloat = 0
        var a2: CGFloat = 0
        color.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)

        return abs(r1 - r2) <= tolerance &&
            abs(g1 - g2) <= tolerance &&
            abs(b1 - b2) <= tolerance &&
            abs(a1 - a2) <= tolerance
    }
}

extension UIViewController {
    /// Presents editor actions via system `UIAlertController`.
    /// `SecondCameraEditorActionSheetController` is currently a data holder only;
    /// presenting it directly would show a blank white full-screen page.
    nonisolated func presentSecondCameraEditorActionSheet(_ actionSheet: SecondCameraEditorActionSheetController, animated: Bool = true) {
        let alert = UIAlertController(
            title: actionSheet.actionSheetTitle,
            message: actionSheet.actionSheetMessage,
            preferredStyle: .actionSheet
        )
        alert.overrideUserInterfaceStyle = actionSheet.overrideUserInterfaceStyle

        for action in actionSheet.actions {
            let style: UIAlertAction.Style = {
                switch action.style {
                case .default: return .default
                case .cancel: return .cancel
                case .destructive: return .destructive
                }
            }()
            alert.addAction(UIAlertAction(title: action.title, style: style) { _ in
                action.handler?(action)
            })
        }

        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.maxY - 1, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }

        present(alert, animated: animated)
    }
}
