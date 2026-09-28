//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//


import UIKit
extension SecondCameraImageEditorViewController {

    func updateStrokeWidthSliderValue() {
        secondCameraStrokeWidthSlider.value = strokeWidthValues[secondCameraCurrentStrokeType] ?? 1
        updateStrokeWidthPreviewSize()
    }

    private func setupStrokeWidthPreviewIfNecessary() {
        guard secondCameraStrokeWidthSliderIsTrackingObservation == nil else { return }

        view.addSubview(strokeWidthPreviewDot)
        strokeWidthPreviewDot.autoHCenterInSuperview()
        strokeWidthPreviewDot.autoVCenterInSuperview()

        secondCameraStrokeWidthSliderIsTrackingObservation = secondCameraStrokeWidthSlider.observe(\.isTracking, options: [.new]) { [weak self] _, _ in
            self?.updateStrokeWidthPreviewVisibility()
        }
        updateStrokeWidthPreviewVisibility()
    }

    private func updateStrokeWidthPreviewVisibility() {
        strokeWidthPreviewDot.alpha = secondCameraStrokeWidthSlider.isTracking ? 1 : 0
    }

    func updateStrokeWidthPreviewSize() {
        guard let strokeWidthPreviewDotSize else { return }

        let unitStrokeWidth = secondCameraCurrentStrokeUnitWidth()
        let viewSize = secondCameraImageEditorView.gestureReferenceView.bounds.size
        let strokeWidth = SecondCameraImageEditorStrokeItem.strokeWidth(
            forUnitStrokeWidth: unitStrokeWidth,
            dstSize: viewSize,
        )
        var dotSize = max(strokeWidth, 1)
        if secondCameraCurrentStrokeType != .blur {
            dotSize += 2 * strokeWidthPreviewDot.layer.borderWidth
        }
        strokeWidthPreviewDotSize.constant = dotSize
    }

    func updateStrokeWidthPreviewColor() {
        switch secondCameraCurrentStrokeType {
        case .pen: strokeWidthPreviewDot.backgroundColor = model.color.color
        case .highlighter: strokeWidthPreviewDot.backgroundColor = model.color.color.withAlphaComponent(Self.secondCameraHighlighterStrokeOpacity)
        case .blur: strokeWidthPreviewDot.backgroundColor = .white
        }
    }

    @objc
    func strokeTypeButtonTapped(sender: UIButton) {
        secondCameraEditorAssertDebug(secondCameraCurrentStroke == nil)
        secondCameraDrawToolbar.strokeTypeButton.isSelected = !secondCameraDrawToolbar.strokeTypeButton.isSelected
        secondCameraCurrentStrokeType = secondCameraDrawToolbar.strokeTypeButton.isSelected ? .highlighter : .pen
    }

    @objc
    func handleSliderContainerTap(_ gesture: UITapGestureRecognizer) {
        setStrokeWidthSlider(revealed: !secondCameraStrokeWidthSliderRevealed)

        // Hide slider after delay if user doesn't interact with it.
        if secondCameraStrokeWidthSliderRevealed {
            secondCameraEditorAssertDebug(hideStrokeWidthSliderTimer == nil)

            hideStrokeWidthSliderTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in
                guard let self else { return }

                self.setStrokeWidthSlider(revealed: false)
            }
        }
    }

    @objc
    func handleSliderTouchEvents(slider: UISlider) {
        guard slider.isTracking != secondCameraStrokeWidthSliderRevealed else { return }

        setStrokeWidthSlider(revealed: slider.isTracking)
    }

    @objc
    func handleSliderValueChanged(slider: UISlider) {
        strokeWidthValues[secondCameraCurrentStrokeType] = slider.value
        updateStrokeWidthPreviewSize()
    }

    func setStrokeWidthSlider(revealed: Bool) {
        guard secondCameraStrokeWidthSliderRevealed != revealed else { return }

        secondCameraStrokeWidthSliderRevealed = revealed
        updateStrokeWidthSliderPosition()

        if secondCameraStrokeWidthSliderRevealed {
            setupStrokeWidthPreviewIfNecessary()
        }

        if let timer = hideStrokeWidthSliderTimer {
            timer.invalidate()
            hideStrokeWidthSliderTimer = nil
        }
    }

    private func updateStrokeWidthSliderPosition() {
        secondCameraStrokeWidthSliderPosition?.constant = secondCameraStrokeWidthSliderRevealed
            ? secondCameraStrokeWidthSliderContainer.bounds.height / 2 - 12
            : 0
        UIView.animate(withDuration: 0.2) {
            if !self.secondCameraStrokeWidthSliderRevealed {
                self.strokeWidthPreviewDot.alpha = 0
            }
            self.view.setNeedsLayout()
            self.view.layoutIfNeeded()
        }
    }
}
