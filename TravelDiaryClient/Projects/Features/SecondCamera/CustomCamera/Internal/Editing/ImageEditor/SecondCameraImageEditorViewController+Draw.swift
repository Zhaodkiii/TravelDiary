//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//


import UIKit
import PureLayout

// MARK: - Draw Tool

extension SecondCameraImageEditorViewController {

    private func initializeSecondCameraDrawToolUIIfNeeded() {
        guard !isSecondCameraDrawToolUIInitialized else { return }

        view.addSubview(secondCameraDrawToolbar)
        secondCameraDrawToolbar.autoPinWidthToSuperview()
        secondCameraDrawToolbar.autoPinEdge(.bottom, to: .top, of: bottomBar)

        view.addGestureRecognizer(secondCameraDrawToolGestureRecognizer)

        isSecondCameraDrawToolUIInitialized = true
    }

    func updateSecondCameraDrawToolControlsVisibility() {
        secondCameraDrawToolbar.alpha = topBar.alpha
        secondCameraStrokeWidthSliderContainer.alpha = topBar.alpha
    }

    func updateSecondCameraDrawToolUIVisibility() {
        let visible = mode == .draw

        if visible {
            initializeSecondCameraDrawToolUIIfNeeded()
        } else {
            guard isSecondCameraDrawToolUIInitialized else { return }
        }

        secondCameraDrawToolbar.isHidden = !visible
        secondCameraDrawToolGestureRecognizer.isEnabled = visible

        if visible {
            secondCameraCurrentStrokeType = secondCameraDrawToolbar.strokeTypeButton.isSelected ? .highlighter : .pen
        }
    }

    static var secondCameraHighlighterStrokeOpacity: CGFloat = 0.5

    @objc
    func handleSecondCameraDrawToolGesture(_ gestureRecognizer: SecondCameraImageEditorPanGestureRecognizer) {
        SecondCameraEditorAssertIsOnMainThread()

        secondCameraEditorAssertDebug(mode == .draw, "Incorrect mode [\(mode)]")

        let removeCurrentStroke = {
            if let stroke = self.secondCameraCurrentStroke {
                self.model.remove(item: stroke)
            }
            self.secondCameraCurrentStroke = nil
            self.secondCameraCurrentStrokeSamples.removeAll()
        }
        let tryToAppendStrokeSample = { (locationInView: CGPoint) in
            let view = self.secondCameraImageEditorView.gestureReferenceView
            let viewBounds = view.bounds
            let newSample = SecondCameraImageEditorCanvasView.locationImageUnit(
                forLocationInView: locationInView,
                viewBounds: viewBounds,
                model: self.model,
                transform: self.model.currentTransform(),
            )

            if
                let prevSample = self.secondCameraCurrentStrokeSamples.last,
                prevSample == newSample
            {
                // Ignore duplicate samples.
                return
            }
            self.secondCameraCurrentStrokeSamples.append(newSample)
        }

        var strokeColor = secondCameraDrawToolbar.colorPickerView.selectedValue.color
        if secondCameraCurrentStrokeType == .highlighter {
            strokeColor = strokeColor.withAlphaComponent(Self.secondCameraHighlighterStrokeOpacity)
        }
        let unitStrokeWidth = secondCameraCurrentStrokeUnitWidth()

        switch gestureRecognizer.state {
        case .began:
            setStrokeWidthSlider(revealed: false)

            removeCurrentStroke()

            // Apply the location history of the gesture so that the stroke reflects
            // the touch's movement before the gesture recognized.
            for location in gestureRecognizer.locationHistory {
                tryToAppendStrokeSample(location)
            }

            let locationInView = gestureRecognizer.location(in: secondCameraImageEditorView.gestureReferenceView)
            tryToAppendStrokeSample(locationInView)

            let stroke = SecondCameraImageEditorStrokeItem(
                color: strokeColor,
                strokeType: secondCameraCurrentStrokeType,
                unitSamples: secondCameraCurrentStrokeSamples,
                unitStrokeWidth: unitStrokeWidth,
            )
            model.append(item: stroke)
            secondCameraCurrentStroke = stroke

        case .changed, .ended:
            let locationInView = gestureRecognizer.location(in: secondCameraImageEditorView.gestureReferenceView)
            tryToAppendStrokeSample(locationInView)

            guard let lastStroke = self.secondCameraCurrentStroke else {
                secondCameraEditorFailDebug("Missing last stroke.")
                removeCurrentStroke()
                return
            }

            // Model items are immutable; we _replace_ the
            // stroke item rather than modify it.
            let stroke = SecondCameraImageEditorStrokeItem(
                itemId: lastStroke.itemId,
                color: strokeColor,
                strokeType: secondCameraCurrentStrokeType,
                unitSamples: secondCameraCurrentStrokeSamples,
                unitStrokeWidth: unitStrokeWidth,
            )
            model.replace(item: stroke, suppressUndo: true)

            if gestureRecognizer.state == .ended {
                secondCameraCurrentStroke = nil
                secondCameraCurrentStrokeSamples.removeAll()
            } else {
                secondCameraCurrentStroke = stroke
            }

        default:
            removeCurrentStroke()
        }
    }

    class DrawToolbar: UIView {

        let colorPickerView: SecondCameraColorPickerBarView

        let strokeTypeButton = SecondCameraRoundMediaButton(
            image: UIImage(imageLiteralResourceName: "brush-pen"),
            backgroundStyle: .blur,
        )

        init(currentColor: SecondCameraColorPickerBarColor) {
            self.colorPickerView = SecondCameraColorPickerBarView(currentColor: currentColor)
            super.init(frame: .zero)

            layoutMargins.top = 0
            layoutMargins.bottom = 2

            strokeTypeButton.setImage(UIImage(imageLiteralResourceName: "brush-highlighter"), for: .selected)

            // A container with width capped at a predefined size,
            // centered in superview and constrained to layout margins.
            let stackViewLayoutGuide = UILayoutGuide()
            addLayoutGuide(stackViewLayoutGuide)
            addConstraints([
                stackViewLayoutGuide.centerXAnchor.constraint(equalTo: centerXAnchor),
                stackViewLayoutGuide.leadingAnchor.constraint(greaterThanOrEqualTo: layoutMarginsGuide.leadingAnchor),
                stackViewLayoutGuide.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor),
                stackViewLayoutGuide.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor),
            ])
            addConstraint({
                let constraint = stackViewLayoutGuide.widthAnchor.constraint(equalToConstant: SecondCameraImageEditorViewController.preferredToolbarContentWidth)
                constraint.priority = .defaultHigh
                return constraint
            }())

            // I had to use a custom layout guide because stack view isn't centered
            // but instead has slight offset towards the trailing edge.
            let stackView = UIStackView(arrangedSubviews: [colorPickerView, strokeTypeButton])
            stackView.translatesAutoresizingMaskIntoConstraints = false
            stackView.alignment = .center
            stackView.spacing = 8
            addSubview(stackView)
            addConstraints([
                stackView.leadingAnchor.constraint(equalTo: stackViewLayoutGuide.leadingAnchor),
                stackView.trailingAnchor.constraint(
                    equalTo: stackViewLayoutGuide.trailingAnchor,
                    constant: strokeTypeButton.layoutMargins.trailing,
                ),
                stackView.topAnchor.constraint(equalTo: stackViewLayoutGuide.topAnchor),
                stackView.bottomAnchor.constraint(equalTo: stackViewLayoutGuide.bottomAnchor),
            ])
        }

        @available(iOS, unavailable, message: "Use init(currentColor:)")
        required init(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
}
