import UIKit
import PureLayout

extension UIView {

    class TransparentView: UIView {
        override open class var layerClass: AnyClass {
            CATransformLayer.self
        }
    }

    class func hStretchingSpacer() -> UIView {
        let view = TransparentView()
        view.setContentHuggingHorizontalLow()
        view.setCompressionResistanceHorizontalLow()
        return view
    }

    class func vStretchingSpacer(minHeight: CGFloat? = nil, maxHeight: CGFloat? = nil) -> UIView {
        let view = TransparentView()
        view.setContentHuggingVerticalLow()
        view.setCompressionResistanceVerticalLow()

        if let minHeight {
            view.autoSetDimension(.height, toSize: minHeight, relation: .greaterThanOrEqual)
        }
        if let maxHeight {
            NSLayoutConstraint.autoSetPriority(.defaultLow) {
                view.autoSetDimension(.height, toSize: maxHeight)
            }
        }

        return view
    }

    var width: CGFloat { frame.width }
    var height: CGFloat { frame.height }

    func removeAllSubviews() {
        for subview in subviews {
            subview.removeFromSuperview()
        }
    }

    typealias UIViewVisitorBlock = (UIView) -> Void

    func traverseHierarchyDownward(with visitor: UIViewVisitorBlock) {
        visitor(self)
        for subview in subviews {
            subview.traverseHierarchyDownward(with: visitor)
        }
    }

    func renderAsImage() -> UIImage {
        renderAsImage(opaque: false, scale: UIScreen.main.scale)
    }

    func renderAsImage(opaque: Bool, scale: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = opaque
        let renderer = UIGraphicsImageRenderer(bounds: bounds, format: format)
        return renderer.image { context in
            layer.render(in: context.cgContext)
        }
    }
}

extension UITextView {
    func acceptAutocorrectSuggestion() {
        inputDelegate?.selectionWillChange(self)
        inputDelegate?.selectionDidChange(self)
    }

    func disableAiWritingTools() {
        if #available(iOS 18, *) {
            writingToolsBehavior = .none
        }
    }
}

extension UITextField {
    func acceptAutocorrectSuggestion() {
        inputDelegate?.selectionWillChange(self)
        inputDelegate?.selectionDidChange(self)
    }

    func disableAiWritingTools() {
        if #available(iOS 18, *) {
            writingToolsBehavior = .none
        }
    }
}

extension Notification.Name {
    static let themeDidChange = Notification.Name("SecondCameraEditorThemeDidChangeNotification")
}

extension UIView {

    func addBorder(with color: UIColor) {
        layer.borderColor = color.cgColor
        layer.borderWidth = 1
    }

    func containsGestureLocation(
        _ gestureRecognizer: UIGestureRecognizer,
        hotAreaInsets: UIEdgeInsets? = nil
    ) -> Bool {
        let location = gestureRecognizer.location(in: self)
        var hotArea = bounds
        if let hotAreaInsets, hotAreaInsets.isNonEmpty {
            hotArea = hotArea.inset(by: hotAreaInsets)
        }
        return hotArea.contains(location)
    }

    func setIsHidden(_ isHidden: Bool, animated: Bool = false, completion: ((Bool) -> Void)? = nil) {
        if animated {
            UIView.animate(withDuration: 0.2, animations: {
                self.isHidden = isHidden
            }, completion: completion)
        } else {
            self.isHidden = isHidden
            completion?(true)
        }
    }

    static func container() -> UIView {
        let view = UIView()
        view.layoutMargins = .zero
        return view
    }

    static func transparentContainer() -> UIView {
        let view = TransparentView()
        view.layoutMargins = .zero
        return view
    }

    static func transparentSpacer() -> UIView {
        let view = TransparentView()
        view.setContentHuggingHorizontalLow()
        view.setCompressionResistanceHorizontalLow()
        return view
    }
}

extension UIButton {
    func setImage(_ image: UIImage?, animated: Bool) {
        if animated {
            UIView.transition(with: self, duration: 0.2, options: .transitionCrossDissolve, animations: {
                self.setImage(image, for: .normal)
            })
        } else {
            setImage(image, for: .normal)
        }
    }
}
