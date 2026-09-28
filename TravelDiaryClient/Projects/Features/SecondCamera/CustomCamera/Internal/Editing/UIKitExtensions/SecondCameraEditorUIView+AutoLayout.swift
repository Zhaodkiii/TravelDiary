import UIKit
import PureLayout

extension UIView {

    // MARK: Horizontal edges to superview margins

    @discardableResult
    func autoPinLeadingToSuperviewMargin(withInset inset: CGFloat = 0) -> NSLayoutConstraint {
        autoPinEdge(toSuperviewMargin: .leading, withInset: inset)
    }

    @discardableResult
    func autoPinTrailingToSuperviewMargin(withInset inset: CGFloat = 0) -> NSLayoutConstraint {
        autoPinEdge(toSuperviewMargin: .trailing, withInset: inset)
    }

    @discardableResult
    func autoPinWidthToSuperviewMargins(withInset inset: CGFloat) -> [NSLayoutConstraint] {
        [
            autoPinEdge(toSuperviewMargin: .leading, withInset: inset),
            autoPinEdge(toSuperviewMargin: .trailing, withInset: inset),
        ]
    }

    @discardableResult
    func autoPinWidthToSuperviewMargins(relation: NSLayoutConstraint.Relation = .equal) -> [NSLayoutConstraint] {
        let resolvedRelation = relation.secondCameraEditorInverse
        return [
            autoPinEdge(toSuperviewMargin: .leading, relation: resolvedRelation),
            autoPinEdge(toSuperviewMargin: .trailing, relation: resolvedRelation),
        ]
    }

    // MARK: Vertical edges to superview margins

    @discardableResult
    func autoPinTopToSuperviewMargin(withInset inset: CGFloat = 0) -> NSLayoutConstraint {
        autoPinEdge(toSuperviewMargin: .top, withInset: inset)
    }

    @discardableResult
    func autoPinBottomToSuperviewMargin(withInset inset: CGFloat = 0) -> NSLayoutConstraint {
        autoPinEdge(toSuperviewMargin: .bottom, withInset: inset)
    }

    @discardableResult
    func autoPinHeightToSuperviewMargins(relation: NSLayoutConstraint.Relation = .equal) -> [NSLayoutConstraint] {
        let resolvedRelation = relation.secondCameraEditorInverse
        return [
            autoPinEdge(toSuperviewMargin: .top, relation: resolvedRelation),
            autoPinEdge(toSuperviewMargin: .bottom, relation: resolvedRelation),
        ]
    }

    // MARK: Width / height to superview

    @discardableResult
    func autoHCenterInSuperview() -> NSLayoutConstraint {
        autoAlignAxis(.vertical, toSameAxisOf: superview!)
    }

    @discardableResult
    func autoVCenterInSuperview() -> NSLayoutConstraint {
        autoAlignAxis(.horizontal, toSameAxisOf: superview!)
    }

    @discardableResult
    func autoPinWidthToSuperview(withMargin margin: CGFloat = 0, relation: NSLayoutConstraint.Relation = .equal) -> [NSLayoutConstraint] {
        let resolvedRelation = relation.secondCameraEditorInverse
        return [
            autoPinEdge(toSuperviewEdge: .leading, withInset: margin, relation: resolvedRelation),
            autoPinEdge(toSuperviewEdge: .trailing, withInset: margin, relation: resolvedRelation),
        ]
    }

    @discardableResult
    func autoPinHeightToSuperview(withMargin margin: CGFloat = 0, relation: NSLayoutConstraint.Relation = .equal) -> [NSLayoutConstraint] {
        let resolvedRelation = relation.secondCameraEditorInverse
        return [
            autoPinEdge(toSuperviewEdge: .top, withInset: margin, relation: resolvedRelation),
            autoPinEdge(toSuperviewEdge: .bottom, withInset: margin, relation: resolvedRelation),
        ]
    }

    // MARK: Edges to another view's edges

    @discardableResult
    func autoPinEdges(toEdgesOf view: UIView, with insets: UIEdgeInsets = .zero) -> [NSLayoutConstraint] {
        [
            autoPinEdge(.leading, to: .leading, of: view, withOffset: insets.leading),
            autoPinEdge(.top, to: .top, of: view, withOffset: insets.top),
            autoPinEdge(.trailing, to: .trailing, of: view, withOffset: -insets.trailing),
            autoPinEdge(.bottom, to: .bottom, of: view, withOffset: -insets.bottom),
        ]
    }

    // MARK: Aspect Ratio

    @discardableResult
    func autoPinToSquareAspectRatio() -> NSLayoutConstraint {
        autoPin(toAspectRatio: 1)
    }

    @discardableResult
    func autoPin(toAspectRatio ratio: CGFloat, relation: NSLayoutConstraint.Relation = .equal) -> NSLayoutConstraint {
        let clampedRatio = CGFloat.secondCameraEditor_clamp(ratio, min: 0.05, max: 95.0)
        if clampedRatio != ratio {
            secondCameraEditorFailDebug("Invalid aspect ratio: \(ratio) for view: \(self)")
        }

        translatesAutoresizingMaskIntoConstraints = false
        let constraint = NSLayoutConstraint(
            item: self,
            attribute: .width,
            relatedBy: relation,
            toItem: self,
            attribute: .height,
            multiplier: clampedRatio,
            constant: 0
        )
        constraint.autoInstall()
        return constraint
    }

    // MARK: Content Hugging and Compression Resistance

    func setContentHuggingLow() {
        setContentHuggingHorizontalLow()
        setContentHuggingVerticalLow()
    }

    func setContentHuggingHigh() {
        setContentHuggingHorizontalHigh()
        setContentHuggingVerticalHigh()
    }

    func setContentHuggingHorizontalLow() {
        setContentHuggingPriority(.defaultLow, for: .horizontal)
    }

    func setContentHuggingHorizontalHigh() {
        setContentHuggingPriority(.required, for: .horizontal)
    }

    func setContentHuggingVerticalLow() {
        setContentHuggingPriority(.defaultLow, for: .vertical)
    }

    func setContentHuggingVerticalHigh() {
        setContentHuggingPriority(.required, for: .vertical)
    }

    func setCompressionResistanceLow() {
        setCompressionResistanceHorizontalLow()
        setCompressionResistanceVerticalLow()
    }

    func setCompressionResistanceHigh() {
        setCompressionResistanceHorizontalHigh()
        setCompressionResistanceVerticalHigh()
    }

    func setCompressionResistanceHorizontalLow() {
        setContentCompressionResistancePriority(.init(0), for: .horizontal)
    }

    func setCompressionResistanceHorizontalHigh() {
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    func setCompressionResistanceVerticalLow() {
        setContentCompressionResistancePriority(.init(0), for: .vertical)
    }

    func setCompressionResistanceVerticalHigh() {
        setContentCompressionResistancePriority(.required, for: .vertical)
    }
}

private extension NSLayoutConstraint.Relation {
    var secondCameraEditorInverse: NSLayoutConstraint.Relation {
        switch self {
        case .lessThanOrEqual: return .greaterThanOrEqual
        case .equal: return .equal
        case .greaterThanOrEqual: return .lessThanOrEqual
        @unknown default: return .equal
        }
    }
}
