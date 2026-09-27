//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//


import UIKit
import PureLayout

protocol SecondCameraImageEditorViewDelegate: AnyObject {

    func secondCameraImageEditorView(_ secondCameraImageEditorView: SecondCameraImageEditorView, didRequestAddTextItem textItem: SecondCameraImageEditorTextItem)

    func secondCameraImageEditorView(_ secondCameraImageEditorView: SecondCameraImageEditorView, didTapTextItem textItem: SecondCameraImageEditorTextItem)

    func secondCameraImageEditorView(_ secondCameraImageEditorView: SecondCameraImageEditorView, didMoveTextItem textItem: SecondCameraImageEditorTextItem)

    func secondCameraImageEditorViewDidUpdateSelection(_ secondCameraImageEditorView: SecondCameraImageEditorView)

    func imageEditorDidRequestToolbarVisibilityUpdate(_ secondCameraImageEditorView: SecondCameraImageEditorView)
}

// MARK: -

// A view for editing outgoing image attachments.
// It can also be used to render the final output.
class SecondCameraImageEditorView: UIView {

    weak var delegate: SecondCameraImageEditorViewDelegate?

    let model: SecondCameraImageEditorModel

    let canvasView: SecondCameraImageEditorCanvasView

    private let trashViewSize: CGFloat = 42
    private lazy var trashView: UIView = {
        let backgroundView = UIView()
        backgroundView.layoutMargins = .init(margin: 9)

        let image = UIImage(named: "trash")
        let imageView = UIImageView(image: image)
        imageView.tintColor = .white
        imageView.contentMode = .scaleAspectFill
        imageView.isUserInteractionEnabled = false

        backgroundView.layer.cornerRadius = trashViewSize / 2
        backgroundView.backgroundColor = .secondCameraEditor_blackAlpha40
        backgroundView.isUserInteractionEnabled = false
        backgroundView.addSubview(imageView)
        imageView.autoPinEdgesToSuperviewMargins()

        return backgroundView
    }()

    private var isTrashShowing: Bool {
        get {
            trashView.alpha > 0
        }
        set {
            trashView.alpha = newValue ? 1 : 0
        }
    }

    private var isHoveringOverTrash = false {
        didSet {
            guard isHoveringOverTrash != oldValue else { return }
            updateTrash(isHoveringOverTrash: isHoveringOverTrash)
        }
    }

    init(model: SecondCameraImageEditorModel, delegate: SecondCameraImageEditorViewDelegate?) {
        self.model = model
        self.delegate = delegate
        self.canvasView = SecondCameraImageEditorCanvasView(model: model)

        super.init(frame: .zero)

        model.add(observer: self)
    }

    @available(*, unavailable, message: "use other init() instead.")
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Views

    private lazy var moveTextGestureRecognizer: SecondCameraImageEditorPanGestureRecognizer = {
        let gestureRecognizer = SecondCameraImageEditorPanGestureRecognizer(target: self, action: #selector(handleMoveTextGesture(_:)))
        gestureRecognizer.maximumNumberOfTouches = 1
        gestureRecognizer.referenceView = gestureReferenceView
        gestureRecognizer.delegate = self
        return gestureRecognizer
    }()

    private lazy var tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTapGesture(_:)))
    private lazy var pinchGestureRecognizer: SecondCameraImageEditorPinchGestureRecognizer = {
        let gestureRecognizer = SecondCameraImageEditorPinchGestureRecognizer(target: self, action: #selector(handlePinchGesture(_:)))
        gestureRecognizer.referenceView = gestureReferenceView
        return gestureRecognizer
    }()

    func configureSecondCameraEditorSubviews() {
        canvasView.configureSecondCameraEditorSubviews()
        addSubview(canvasView)
        canvasView.autoPinEdgesToSuperviewEdges()

        canvasView.contentView.addSubview(trashView)

        // Center trash view instead of aligning the bottom so that it
        // resizes from the center when hovering over it.
        // 20 spacing to bottom + half the height for the center point.
        let distanceFromCenterToBottom = 20 + trashViewSize / 2
        trashView.centerYAnchor.constraint(
            equalTo: canvasView.contentView.bottomAnchor,
            constant: -distanceFromCenterToBottom,
        )
        .isActive = true

        trashView.autoHCenterInSuperview()
        trashView.autoSetDimensions(to: .square(trashViewSize))
        trashView.layer.zPosition = SecondCameraImageEditorCanvasView.trashLazerZ
        isTrashShowing = false

        addGestureRecognizer(moveTextGestureRecognizer)
        addGestureRecognizer(tapGestureRecognizer)
        addGestureRecognizer(pinchGestureRecognizer)
        updateGestureRecognizers()

        let doubleTapGesture = UITapGestureRecognizer(target: nil, action: nil)
        doubleTapGesture.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTapGesture)
        tapGestureRecognizer.require(toFail: doubleTapGesture)
    }

    private func updateGestureRecognizers() {
        // Remove all gesture recognizers when interaction with text objects is disabled
        // so that they don't interfere with gesture recognizers added in view controller.

        moveTextGestureRecognizer.isEnabled = textInteractionModes.contains(.move)
        tapGestureRecognizer.isEnabled = textInteractionModes.contains(.tap)
        pinchGestureRecognizer.isEnabled = textInteractionModes.contains(.resize)
    }

    final var gestureReferenceView: UIView {
        canvasView.gestureReferenceView
    }

    // MARK: - Navigation Bar

    private func updateControls() {
        delegate?.imageEditorDidRequestToolbarVisibilityUpdate(self)

        let shouldShowTrash: Bool
        switch movingItem {
        case is SecondCameraImageEditorStickerItem, is SecondCameraImageEditorTextItem:
            shouldShowTrash = true
        default:
            shouldShowTrash = false
        }

        guard shouldShowTrash != isTrashShowing else { return }
        UIView.animate(withDuration: 0.15) {
            self.isTrashShowing = shouldShowTrash
        }
    }

    private func updateTrash(isHoveringOverTrash: Bool) {
        canvasView.shouldFadeTransformableItem = isHoveringOverTrash

        UIView.animate(withDuration: 0.15) {
            self.trashView.transform = isHoveringOverTrash ? .scale(4 / 3) : .identity
        }

        if isHoveringOverTrash {
            SecondCameraEditorImpactHapticFeedback.impactOccurred(style: .light)
        }
    }

    var shouldHideControls: Bool {
        // Hide controls during "text item move".
        return movingItem != nil
    }

    struct TextInteractionModes: OptionSet {
        let rawValue: Int

        static let tap = TextInteractionModes(rawValue: 1 << 0)
        static let select = TextInteractionModes(rawValue: 1 << 1 | 1 << 0) // "select" requires "tap" to be supported
        static let move = TextInteractionModes(rawValue: 1 << 2)
        static let resize = TextInteractionModes(rawValue: 1 << 3)

        static let all: TextInteractionModes = [.tap, .select, .move, .resize]
    }

    var textInteractionModes: TextInteractionModes = [] {
        didSet {
            updateGestureRecognizers()
        }
    }

    // MARK: - Tap Gesture

    var selectedTransformableItemID: String? {
        get {
            canvasView.selectedTransformableItemID
        }
        set {
            let newValueIsDifferent = canvasView.selectedTransformableItemID != newValue
            canvasView.selectedTransformableItemID = newValue
            // Update the tooltip when a new item is selected.
            // Dragging a sticker hides the tooltip, so avoid
            // showing it if it was selected by a drag.
            if newValueIsDifferent, movingItem == nil {
                canvasView.updateTooltip()
            }
        }
    }

    func updateSelectedTextItem(withColor color: SecondCameraColorPickerBarColor) {
        if
            let selectedTextItemId = selectedTransformableItemID,
            let textItem = model.item(forId: selectedTextItemId) as? SecondCameraImageEditorTextItem
        {
            let newTextItem = textItem.copy(color: color)
            model.replace(item: newTextItem)
        }
    }

    func createNewTextItem(
        withColor color: SecondCameraColorPickerBarColor = SecondCameraColorPickerBarColor.white,
        textStyle: SecondCameraMediaTextView.TextStyle = .regular,
        decorationStyle: SecondCameraMediaTextView.DecorationStyle = .none,
    ) -> SecondCameraImageEditorTextItem {
        let viewSize = canvasView.gestureReferenceView.bounds.size
        let imageSize = model.srcImageSizePixels
        let imageFrame = SecondCameraImageEditorCanvasView.imageFrame(
            forViewSize: viewSize,
            imageSize: imageSize,
            transform: model.currentTransform(),
        )

        let textWidthPoints = viewSize.width * SecondCameraImageEditorTextItem.kDefaultUnitWidth
        let textWidthUnit = textWidthPoints / imageFrame.size.width

        // New items should be aligned "upright", so they should have the _opposite_
        // of the current transform rotation.
        let rotationRadians = -model.currentTransform().rotationRadians
        // Similarly, the size of the text item shuo
        let scaling = 1 / model.currentTransform().scaling

        let textItem = SecondCameraImageEditorTextItem.empty(
            withColor: color,
            textStyle: textStyle,
            decorationStyle: decorationStyle,
            unitWidth: textWidthUnit,
            fontReferenceImageWidth: imageFrame.size.width,
            scaling: scaling,
            rotationRadians: rotationRadians,
        )
        return textItem
    }

    func createNewStickerItem(with sticker: SecondCameraEditorSticker) -> SecondCameraImageEditorStickerItem {
        let viewSize = canvasView.gestureReferenceView.bounds.size
        let imageSize = model.srcImageSizePixels
        let imageFrame = SecondCameraImageEditorCanvasView.imageFrame(
            forViewSize: viewSize,
            imageSize: imageSize,
            transform: model.currentTransform(),
        )

        let rotationRadians = -model.currentTransform().rotationRadians
        let scaling = 1 / model.currentTransform().scaling

        return SecondCameraImageEditorStickerItem(
            sticker: sticker,
            referenceImageWidth: imageFrame.size.width,
            rotationRadians: rotationRadians,
            scaling: scaling,
        )
    }

    @objc
    private func handleTapGesture(_ gestureRecognizer: UIGestureRecognizer) {
        SecondCameraEditorAssertIsOnMainThread()

        guard gestureRecognizer.state == .recognized else {
            secondCameraEditorFailDebug("Unexpected state.")
            return
        }

        guard textInteractionModes.contains(.tap) else {
            secondCameraEditorFailDebug("Unexpected text interaction mode [\(textInteractionModes)].")
            return
        }

        let location = gestureRecognizer.location(in: canvasView.gestureReferenceView)
        guard let textLayer = transformableLayer(forLocation: location) else {
            // Different behavior when user taps on an empty area.

            // 1. Text objects are selectable: deselect anything previously selected.
            if textInteractionModes.contains(.select) {
                if selectedTransformableItemID != nil {
                    selectedTransformableItemID = nil
                    delegate?.secondCameraImageEditorViewDidUpdateSelection(self)
                }
                return
            }

            // 2. Text objects aren't selectable: add a new text object.
            let newTextItem = createNewTextItem()
            delegate?.secondCameraImageEditorView(self, didRequestAddTextItem: newTextItem)
            return
        }

        guard
            let itemID = textLayer.name,
            let item = model.item(forId: itemID) as? SecondCameraImageEditorTransformable
        else {
            secondCameraEditorFailDebug("Missing or invalid text item.")
            return
        }

        // Text objects are selectable: select object if not selected yet...
        if textInteractionModes.contains(.select), item.itemId != selectedTransformableItemID {
            selectedTransformableItemID = item.itemId
            delegate?.secondCameraImageEditorViewDidUpdateSelection(self)
        }
        // ..otherwise report tap to delegate (this includes taps on selected text objects).
        else if let textItem = item as? SecondCameraImageEditorTextItem {
            delegate?.secondCameraImageEditorView(self, didTapTextItem: textItem)
        }
        // Change special sticker style
        else if
            let stickerItem = item as? SecondCameraImageEditorStickerItem,
            case .story(let storySticker) = stickerItem.sticker
        {
            switch storySticker {
            case .clockDigital(let clockStyle):
                let newSticker = clockStyle.stickerWithNextStyle()
                let newStickerItem = stickerItem.copy(sticker: newSticker)
                model.replace(item: newStickerItem)
            case .clockAnalog(let clockStyle):
                let newSticker = clockStyle.stickerWithNextStyle()
                let newStickerItem = stickerItem.copy(sticker: newSticker)
                model.replace(item: newStickerItem)
            }
            SecondCameraEditorImpactHapticFeedback.impactOccurred(style: .medium)
            canvasView.hideTooltip()
        }
    }

    // MARK: - Pinch Gesture

    // These properties are valid while moving a text item.
    private var pinchingItem: (any SecondCameraImageEditorTransformable)?
    private var pinchHasChanged = false

    @objc
    private func handlePinchGesture(_ gestureRecognizer: SecondCameraImageEditorPinchGestureRecognizer) {
        SecondCameraEditorAssertIsOnMainThread()

        // We could undo an in-progress pinch if the gesture is cancelled, but it seems gratuitous.

        switch gestureRecognizer.state {
        case .began:
            let pinchState = gestureRecognizer.pinchStateStart
            guard
                let textLayer = transformableLayer(forLocation: pinchState.centroid),
                let itemID = textLayer.name,
                itemID == selectedTransformableItemID
            else {
                // The pinch needs to start centered on selected text item.
                return
            }
            guard let item = model.item(forId: itemID) as? SecondCameraImageEditorTransformable else {
                secondCameraEditorFailDebug("Missing or invalid text item.")
                return
            }
            pinchingItem = item
            pinchHasChanged = false

        case .changed, .ended:
            guard let item = pinchingItem else {
                return
            }

            let view = canvasView.gestureReferenceView
            let viewBounds = view.bounds
            let locationStart = gestureRecognizer.pinchStateStart.centroid
            let locationNow = gestureRecognizer.pinchStateLast.centroid
            let gestureStartImageUnit = SecondCameraImageEditorCanvasView.locationImageUnit(
                forLocationInView: locationStart,
                viewBounds: viewBounds,
                model: model,
                transform: model.currentTransform(),
            )
            let gestureNowImageUnit = SecondCameraImageEditorCanvasView.locationImageUnit(
                forLocationInView: locationNow,
                viewBounds: viewBounds,
                model: model,
                transform: model.currentTransform(),
            )
            let gestureDeltaImageUnit = gestureNowImageUnit.minus(gestureStartImageUnit)
            let unitCenter = CGPoint.secondCameraEditor_clamp01(item.unitCenter.plus(gestureDeltaImageUnit))

            // NOTE: We use max(1, ...) to avoid divide-by-zero.
            let newScaling = CGFloat.secondCameraEditor_clamp(
                item.scaling * gestureRecognizer.pinchStateLast.distance / max(1.0, gestureRecognizer.pinchStateStart.distance),
                min: SecondCameraImageEditorTextItem.kMinScaling,
                max: SecondCameraImageEditorTextItem.kMaxScaling,
            )

            let newRotationRadians = item.rotationRadians + gestureRecognizer.pinchStateLast.angleRadians - gestureRecognizer.pinchStateStart.angleRadians

            let newItem = item.copy(unitCenter: unitCenter).copy(
                scaling: newScaling,
                rotationRadians: newRotationRadians,
            )

            if pinchHasChanged {
                model.replace(item: newItem, suppressUndo: true)
            } else {
                model.replace(item: newItem, suppressUndo: false)
                pinchHasChanged = true
            }

            if gestureRecognizer.state == .ended {
                pinchingItem = nil
            }

        default:
            pinchingItem = nil
        }
    }

    // MARK: - Pan Gesture

    // These properties are valid while moving a text item.
    private var movingItem: (any SecondCameraImageEditorTransformable)? {
        didSet {
            updateControls()
        }
    }

    private var movingTextStartUnitCenter: CGPoint?
    private var movingTextHasMoved = false

    private func transformableLayer(forLocation locationInView: CGPoint) -> CALayer? {
        let viewBounds = self.canvasView.gestureReferenceView.bounds
        let affineTransform = self.model.currentTransform().affineTransform(viewSize: viewBounds.size)
        let locationInCanvas = locationInView.minus(viewBounds.center).applyingInverse(affineTransform).plus(viewBounds.center)
        return canvasView.transformableLayer(forLocation: locationInCanvas)
    }

    @objc
    private func handleMoveTextGesture(_ gestureRecognizer: SecondCameraImageEditorPanGestureRecognizer) {
        SecondCameraEditorAssertIsOnMainThread()

        guard textInteractionModes.contains(.move) else {
            secondCameraEditorFailDebug("Unexpected text interaction mode [\(textInteractionModes)].")
            return
        }

        // We could undo an in-progress move if the gesture is cancelled, but it seems gratuitous.

        switch gestureRecognizer.state {
        case .began:
            guard let locationStart = gestureRecognizer.locationFirst else {
                secondCameraEditorFailDebug("Missing locationStart.")
                return
            }
            guard let textLayer = transformableLayer(forLocation: locationStart) else {
                secondCameraEditorFailDebug("No text layer")
                return
            }
            guard
                let itemID = textLayer.name,
                let item = model.item(forId: itemID) as? SecondCameraImageEditorTransformable
            else {
                secondCameraEditorFailDebug("Missing or invalid text item.")
                return
            }

            movingItem = item
            movingTextStartUnitCenter = item.unitCenter
            movingTextHasMoved = false
            canvasView.hideTooltip()

            // Automatically make item selected if selections are allowed.
            if textInteractionModes.contains(.select) {
                selectedTransformableItemID = item.itemId
            }

        case .changed, .ended:
            guard let item = movingItem else {
                return
            }
            guard let locationStart = gestureRecognizer.locationFirst else {
                secondCameraEditorFailDebug("Missing locationStart.")
                return
            }
            guard let movingTextStartUnitCenter else {
                secondCameraEditorFailDebug("Missing movingTextStartUnitCenter.")
                return
            }

            let view = canvasView.gestureReferenceView
            let viewBounds = view.bounds
            let locationInView = gestureRecognizer.location(in: view)
            let gestureStartImageUnit = SecondCameraImageEditorCanvasView.locationImageUnit(
                forLocationInView: locationStart,
                viewBounds: viewBounds,
                model: model,
                transform: model.currentTransform(),
            )
            let gestureNowImageUnit = SecondCameraImageEditorCanvasView.locationImageUnit(
                forLocationInView: locationInView,
                viewBounds: viewBounds,
                model: model,
                transform: model.currentTransform(),
            )
            let gestureDeltaImageUnit = gestureNowImageUnit.minus(gestureStartImageUnit)
            let unitCenter = CGPoint.secondCameraEditor_clamp01(movingTextStartUnitCenter.plus(gestureDeltaImageUnit))
            let newItem = item.copy(unitCenter: unitCenter)

            if movingTextHasMoved {
                model.replace(item: newItem, suppressUndo: true)
            } else {
                model.replace(item: newItem, suppressUndo: false)
                movingTextHasMoved = true
            }

            isHoveringOverTrash = trashView.containsGestureLocation(gestureRecognizer)

            if gestureRecognizer.state == .ended {
                // Report that text object was moved.
                if let movingTextItem = movingItem as? SecondCameraImageEditorTextItem {
                    delegate?.secondCameraImageEditorView(self, didMoveTextItem: movingTextItem)
                }

                if isHoveringOverTrash, isTrashShowing {
                    // The last operation was moving the image over the trash.
                    // Pop that off the stack, so when the user presses undo
                    // after trashing an item, it goes to the position before
                    // the trash, instead of appearing over the trash.
                    model.undo()

                    model.remove(item: newItem)
                }

                movingItem = nil
                isHoveringOverTrash = false
            }

        default:
            movingItem = nil
        }
    }
}

// MARK: - Corner Radius

extension SecondCameraImageEditorView {

    static let defaultCornerRadius: CGFloat = 18

    func setHasRoundCorners(_ roundCorners: Bool, animationDuration: TimeInterval = 0) {
        canvasView.setCornerRadius(
            roundCorners ? SecondCameraImageEditorView.defaultCornerRadius : 0,
            animationDuration: animationDuration,
        )
    }
}

// MARK: -

extension SecondCameraImageEditorView: UIGestureRecognizerDelegate {

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard moveTextGestureRecognizer == gestureRecognizer else {
            secondCameraEditorFailDebug("Unexpected gesture.")
            return false
        }

        let location = touch.location(in: canvasView.gestureReferenceView)
        let isInTextArea = self.transformableLayer(forLocation: location) != nil
        return isInTextArea
    }
}

// MARK: -

extension SecondCameraImageEditorView: SecondCameraImageEditorModelObserver {

    func secondCameraImageEditorModelDidChange(before: SecondCameraImageEditorContents, after: SecondCameraImageEditorContents) {
    }

    func secondCameraImageEditorModelDidChange(changedItemIds: [String]) {
    }
}
