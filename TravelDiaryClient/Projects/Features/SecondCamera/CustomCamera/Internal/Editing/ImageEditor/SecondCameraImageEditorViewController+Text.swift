//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//


import UIKit
import PureLayout

// MARK: - Sticker

extension SecondCameraImageEditorViewController {
    func selectSecondCameraStickerItem(_ stickerItem: SecondCameraImageEditorStickerItem) {
        mode = .sticker
        model.append(item: stickerItem)
        secondCameraImageEditorView.selectedTransformableItemID = stickerItem.itemId
    }
}

// MARK: - Text

extension SecondCameraImageEditorViewController {

    func selectSecondCameraTextItem(_ textItem: SecondCameraImageEditorTextItem, isNewItem: Bool, startEditing: Bool) {
        mode = .text
        secondCameraCurrentTextItem = (textItem, isNewItem)
        secondCameraImageEditorView.selectedTransformableItemID = textItem.itemId
        if startEditing, isViewLoaded, view.window != nil {
            beginSecondCameraTextEditing()
        } else {
            startEditingTextOnViewAppear = startEditing
        }
    }

    var canBeginSecondCameraTextEditingOnViewAppear: Bool {
        guard mode == .text else {
            return false
        }
        return secondCameraCurrentTextItem != nil
    }

    private func initializeSecondCameraTextUIIfNeeded() {
        guard !textUIInitialized else { return }

        let toolbarSize = secondCameraTextViewAccessoryToolbar.systemLayoutSizeFitting(
            CGSize(width: view.width, height: .greatestFiniteMagnitude),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel,
        )
        secondCameraTextViewAccessoryToolbar.bounds.size = toolbarSize
        textView.inputAccessoryView = secondCameraTextViewAccessoryToolbar

        // Background view is necessary because animations of secondCameraTextViewContainer.frame
        // don't match animations of the keyboard and non-dimmed area was showing
        // in between the bottom edge of secondCameraTextViewContainer and the top of keyboard.
        let textContainerBackground = UIView()
        textContainerBackground.backgroundColor = .secondCameraEditor_blackAlpha40
        secondCameraTextViewContainer.addSubview(textContainerBackground)
        textContainerBackground.autoPinEdgesToSuperviewEdges(with: .zero, excludingEdge: .bottom)
        textContainerBackground.autoPinEdge(toSuperviewEdge: .bottom, withInset: -300)

        textViewBackgroundView.layer.cornerRadius = 8
        textViewWrapperView.addSubview(textViewBackgroundView)
        textViewWrapperView.addSubview(textView)
        textViewBackgroundView.autoSetDimension(.width, toSize: 36, relation: .greaterThanOrEqual)
        textViewBackgroundView.autoSetDimension(.height, toSize: 36, relation: .greaterThanOrEqual)
        textViewBackgroundView.autoPinWidthToSuperviewMargins(relation: .lessThanOrEqual)
        textViewBackgroundView.autoPinHeightToSuperviewMargins(relation: .lessThanOrEqual)
        textViewBackgroundView.autoCenterInSuperview()
        // These inset values provide the best visual match with CATextLayer's bounds when background color is set.
        textView.autoPinEdges(toEdgesOf: textViewBackgroundView, with: UIEdgeInsets(top: -6, left: 6, bottom: -7, right: 6))

        secondCameraTextViewContainer.addSubview(textViewWrapperView)
        textViewWrapperView.autoVCenterInSuperview()
        textViewWrapperView.autoPinWidthToSuperviewMargins()
        textViewWrapperView.autoPinHeightToSuperviewMargins(relation: .lessThanOrEqual)

        view.addSubview(secondCameraTextViewContainer)
        secondCameraTextViewContainer.translatesAutoresizingMaskIntoConstraints = false
        secondCameraTextViewContainer.autoPinEdgesToSuperviewEdges(with: .zero, excludingEdge: .bottom)
        NSLayoutConstraint.activate([
            secondCameraTextViewContainer.topAnchor.constraint(equalTo: view.topAnchor),
            secondCameraTextViewContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            secondCameraTextViewContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            secondCameraTextViewContainer.bottomAnchor.constraint(equalTo: keyboardLayoutGuide.topAnchor),
        ])

        secondCameraTextViewContainer.addGestureRecognizer(SecondCameraImageEditorPinchGestureRecognizer(target: self, action: #selector(handleSecondCameraTextPinchGesture(_:))))
        secondCameraTextViewContainer.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTapSecondCameraTextDimmerView(_:))))

        UIView.performWithoutAnimation {
            self.view.setNeedsLayout()
            self.view.layoutIfNeeded()
        }

        textUIInitialized = true
    }

    func updateSecondCameraTextControlsVisibility() {
        // Nothing to update
    }

    /**
     * Load all UITextView's attributes from SecondCameraImageEditorTextItem.
     * This method needs to be called when text item editing is about to begin.
     */
    private func updateSecondCameraTextViewAttributes(using textItem: SecondCameraImageEditorTextItem) {
        textView.updateWith(
            textForegroundColor: textItem.textForegroundColor,
            font: textItem.font,
            textAlignment: .center,
            textDecorationColor: textItem.textDecorationColor,
            decorationStyle: textItem.decorationStyle,
        )
        textViewBackgroundView.backgroundColor = textItem.textBackgroundColor
    }

    // Update UITextView to use style (font, color, decoration) as selected in provided TextToolbar.
    // This method needs to be called whenever user changes text styling while UITextView is active
    // in order to reflect the changes right away.
    func updateSecondCameraTextViewAttributes(using textToolbar: SecondCameraTextStylingToolbar) {
        let fontPointSize = textView.font?.pointSize ?? SecondCameraImageEditorTextItem.defaultFontSize
        textView.update(using: textToolbar, fontPointSize: fontPointSize)
        textViewBackgroundView.backgroundColor = textToolbar.textBackgroundColor
    }

    func updateSecondCameraTextUIVisibility() {
        switch mode {
        case .text:
            initializeSecondCameraTextUIIfNeeded()
            fallthrough
        case .sticker:
            secondCameraImageEditorView.delegate = self
        case .draw, .blur:
            guard textUIInitialized else { break }
            secondCameraImageEditorView.selectedTransformableItemID = nil
        }
    }

    func beginSecondCameraTextEditing() {
        guard let textItem = secondCameraCurrentTextItem?.textItem else { return }

        bottomBar.setIsHidden(true, animated: true)

        secondCameraTextViewAccessoryToolbar.currentColorPickerValue = textItem.color
        secondCameraTextViewAccessoryToolbar.textStyle = textItem.textStyle
        secondCameraTextViewAccessoryToolbar.decorationStyle = textItem.decorationStyle

        textView.text = textItem.text
        updateSecondCameraTextViewAttributes(using: textItem)

        secondCameraImageEditorView.canvasView.hiddenItemId = textItem.itemId

        UIView.animate(withDuration: 0.2) {
            self.secondCameraTextViewContainer.alpha = 1
        }
        textView.becomeFirstResponder()
    }

    func finishSecondCameraTextEditing(discardEdits: Bool = false) {
        guard textUIInitialized else { return }
        guard textView.isFirstResponder else { return }

        discardTextEditsOnEditingEnd = discardEdits

        textView.acceptAutocorrectSuggestion()
        textView.resignFirstResponder()
    }

    private func applySecondCameraTextEdits() {
        guard let secondCameraCurrentTextItem else { return }

        var textItem = secondCameraCurrentTextItem.textItem

        // Update text's width.
        let view = secondCameraImageEditorView.gestureReferenceView
        let viewBounds = view.bounds
        let imageFrame = SecondCameraImageEditorCanvasView.imageFrame(
            forViewSize: viewBounds.size,
            imageSize: model.srcImageSizePixels,
            transform: model.currentTransform(),
        )
        // 12 is the sum of horizontal insets around textView as set in `initializeSecondCameraTextUIIfNeeded`.
        let unitWidth = (textViewWrapperView.width - 12) / imageFrame.width
        textItem = textItem.copy(unitWidth: unitWidth)

        // Ensure continuity of the new text item's location with its apparent location in this text editor.
        if secondCameraCurrentTextItem.isNewItem {
            let locationInView = view.convert(textView.bounds.center, from: textView).clamp(view.bounds)
            let textCenterImageUnit = SecondCameraImageEditorCanvasView.locationImageUnit(
                forLocationInView: locationInView,
                viewBounds: viewBounds,
                model: model,
                transform: model.currentTransform(),
            )
            textItem = textItem.copy(unitCenter: textCenterImageUnit)
        }

        // Update font size.
        if let textViewFont = textView.font {
            textItem = textItem.copy(fontSize: textViewFont.pointSize)
        }

        // Update text and decoration style.
        textItem = textItem.copy(
            textStyle: secondCameraTextViewAccessoryToolbar.textStyle,
            decorationStyle: secondCameraTextViewAccessoryToolbar.decorationStyle,
        )

        // Deleting all text results in text object being deleted.
        guard let text = textView.text?.secondCameraEditor_stripped(), !text.isEmpty else {
            if model.has(itemForId: textItem.itemId) {
                model.remove(item: textItem)
            }
            return
        }

        // Update text.
        textItem = textItem.copy(withText: text, color: secondCameraTextViewAccessoryToolbar.currentColorPickerValue)

        guard secondCameraCurrentTextItem.textItem != textItem else {
            // No changes were made.  Cancel to avoid dirtying the undo stack.
            return
        }

        // Finally - update model with modified text item.
        if model.has(itemForId: textItem.itemId) {
            model.replace(item: textItem, suppressUndo: false)
        } else {
            model.append(item: textItem)
        }

        secondCameraImageEditorView.selectedTransformableItemID = textItem.itemId
    }

    @objc
    private func handleSecondCameraTextPinchGesture(_ gestureRecognizer: SecondCameraImageEditorPinchGestureRecognizer) {
        SecondCameraEditorAssertIsOnMainThread()

        guard mode == .text else {
            secondCameraEditorFailDebug("Incorrect mode [\(mode)]")
            return
        }

        guard let textViewFont = textView.font else {
            secondCameraEditorFailDebug("Text View font is nil")
            return
        }

        switch gestureRecognizer.state {
        case .began:
            pinchFontSizeStart = textViewFont.pointSize

        case .changed, .ended:
            var pointSize = pinchFontSizeStart
            if gestureRecognizer.pinchStateLast.distance > 0 {
                pointSize *= gestureRecognizer.pinchStateLast.distance / gestureRecognizer.pinchStateStart.distance
            }
            textView.font = textViewFont.withSize(pointSize.secondCameraEditor_clamp(12, 64))

        default:
            break
        }
    }

    @objc
    private func didTapSecondCameraTextDimmerView(_ gestureRecognizer: UITapGestureRecognizer) {
        finishSecondCameraTextEditing()
    }

    @objc
    func didTapSecondCameraTextStyleButton(sender: UIButton) {
        let textStyle = secondCameraTextViewAccessoryToolbar.textStyle.next()
        secondCameraTextViewAccessoryToolbar.textStyle = textStyle
        updateSecondCameraTextViewAttributes(using: secondCameraTextViewAccessoryToolbar)
    }

    @objc
    func didTapSecondCameraTextDecorationStyleButton(sender: UIButton) {
        var decorationStyle = secondCameraTextViewAccessoryToolbar.decorationStyle.next()
        if decorationStyle == .outline {
            decorationStyle = .none
        }
        secondCameraTextViewAccessoryToolbar.decorationStyle = decorationStyle
        updateSecondCameraTextViewAttributes(using: secondCameraTextViewAccessoryToolbar)
    }

    @objc
    func didTapSecondCameraTextEditingDoneButton(sender: UIButton) {
        finishSecondCameraTextEditing()
    }
}

// MARK: - UITextViewDelegate

extension SecondCameraImageEditorViewController: UITextViewDelegate {

    func textViewDidBeginEditing(_ textView: UITextView) {
        // Reset each time user starts editing text.
        discardTextEditsOnEditingEnd = false
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        bottomBar.setIsHidden(false, animated: true)

        // Save changes to the model unless we were told not to (eg when dismissing screen).
        if !discardTextEditsOnEditingEnd {
            applySecondCameraTextEdits()
        }

        // Existing text is made hidden on the canvas while user is editing.
        // This is the time to make it visible.
        UIView.animate(withDuration: 0.2) {
            self.secondCameraImageEditorView.canvasView.hiddenItemId = nil
            self.secondCameraTextViewContainer.alpha = 0
        }

        secondCameraCurrentTextItem = nil
    }
}

// MARK: - SecondCameraImageEditorViewDelegate

extension SecondCameraImageEditorViewController: SecondCameraImageEditorViewDelegate {

    func secondCameraImageEditorView(_ secondCameraImageEditorView: SecondCameraImageEditorView, didRequestAddTextItem textItem: SecondCameraImageEditorTextItem) {
        // No adding text via tap on image in this view controller.
        // Instead, tap on empty space deselects any selected text object
        // and switches the editor back to "draw" mode via `secondCameraImageEditorViewDidUpdateSelection()`.
    }

    func secondCameraImageEditorView(_ secondCameraImageEditorView: SecondCameraImageEditorView, didTapTextItem textItem: SecondCameraImageEditorTextItem) {
        secondCameraEditorAssertDebug(secondCameraImageEditorView.selectedTransformableItemID == textItem.itemId)
        secondCameraCurrentTextItem = (textItem, false)
        beginSecondCameraTextEditing()
    }

    func secondCameraImageEditorView(_ secondCameraImageEditorView: SecondCameraImageEditorView, didMoveTextItem textItem: SecondCameraImageEditorTextItem) {

    }

    func secondCameraImageEditorViewDidUpdateSelection(_ secondCameraImageEditorView: SecondCameraImageEditorView) {
        switch secondCameraImageEditorView.selectedTransformableItemID {
        case .some(let selectedTransformableItemID):
            let selectedItem = model.item(forId: selectedTransformableItemID)
            if let textItem = selectedItem as? SecondCameraImageEditorTextItem {
                mode = .text
                secondCameraTextViewAccessoryToolbar.currentColorPickerValue = textItem.color
                secondCameraTextViewAccessoryToolbar.textStyle = textItem.textStyle
                secondCameraTextViewAccessoryToolbar.decorationStyle = textItem.decorationStyle
            } else if selectedItem is SecondCameraImageEditorStickerItem {
                mode = .sticker
            } else {
                fallthrough
            }
        case .none:
            mode = .draw
        }

        updateSecondCameraTextUIVisibility()
    }

    func imageEditorDidRequestToolbarVisibilityUpdate(_ secondCameraImageEditorView: SecondCameraImageEditorView) {
        updateSecondCameraEditorControlsVisibility()
    }
}
