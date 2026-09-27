import UIKit

extension UIStackView {
    func addArrangedSubviews(_ subviews: [UIView]) {
        for subview in subviews {
            addArrangedSubview(subview)
        }
    }
}

extension UIView {
    var isHiddenInStackView: Bool {
        get { isHidden }
        set {
            if isHidden != newValue {
                isHidden = newValue
            }
            alpha = newValue ? 0 : 1
        }
    }
}
