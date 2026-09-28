//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Vision
import UIKit
import PureLayout

// MARK: - Blur Tool

extension SecondCameraImageEditorViewController {

    private func initializeSecondCameraBlurToolUIIfNeeded() {
        guard !isSecondCameraBlurToolUIInitialized else { return }

        view.addSubview(secondCameraBlurToolbar)
        secondCameraBlurToolbar.autoHCenterInSuperview()
        secondCameraBlurToolbar.autoPinEdge(.bottom, to: .top, of: bottomBar, withOffset: -36)

        view.addGestureRecognizer(blurToolGestureRecognizer)

        isSecondCameraBlurToolUIInitialized = true
    }

    func updateSecondCameraBlurToolControlsVisibility() {
        secondCameraBlurToolbar.alpha = topBar.alpha
        secondCameraStrokeWidthSliderContainer.alpha = topBar.alpha
    }

    func updateSecondCameraBlurToolUIVisibility() {
        let visible = mode == .blur

        if visible {
            initializeSecondCameraBlurToolUIIfNeeded()
        } else {
            guard isSecondCameraBlurToolUIInitialized else { return }
        }

        secondCameraBlurToolbar.isHidden = !visible
        blurToolGestureRecognizer.isEnabled = visible

        if visible {
            secondCameraCurrentStrokeType = .blur
        }
    }

    @objc
    func didToggleSecondCameraAutoBlur(sender: UISwitch) {
        if let currentAutoBlurItem {
            model.remove(item: currentAutoBlurItem)
        }

        guard sender.isOn else { return }

        guard
            let srcImage = SecondCameraImageEditorCanvasView.loadSrcImage(model: model),
            let srcCGImage = srcImage.cgImage
        else {
            return
        }

        let cgOrientation = CGImagePropertyOrientation(srcImage.imageOrientation)

        // Wrap weak refs in @unchecked Sendable boxes so they can cross isolation
        // boundaries without triggering Swift 6 "sending risks data races" warnings.
        // All actual UI access is still dispatched to the main thread.
        let selfBox = SecondCameraEditorBlurWeakRef(self)
        let senderBox = SecondCameraEditorBlurWeakRef(sender)

        SecondCameraEditorActivityIndicatorViewController.present(
            fromViewController: self,
            canCancel: false,
            presentationDelay: 0.5,
        ) { modal in
            // Delegate Vision work to nonisolated static helper so the completion
            // closure is never inferred as @MainActor – avoids EXC_BREAKPOINT
            // (_swift_task_checkIsolatedSwift) when Vision calls back on its queue.
            SecondCameraImageEditorViewController.runSecondCameraFaceDetection(
                cgImage: srcCGImage,
                orientation: cgOrientation,
            ) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .failure(let error):
                        print("[ImageEditor] Face Detection Error: \(error)")
                        (senderBox.object as? UISwitch)?.isOn = false
                        modal.dismiss {}

                    case .success(let boxes) where boxes.isEmpty:
                        (senderBox.object as? UISwitch)?.isOn = false
                        modal.dismiss {}

                    case .success(let boxes):
                        guard let vc = selfBox.object as? SecondCameraImageEditorViewController else {
                            modal.dismiss {}
                            return
                        }
                        let item = SecondCameraImageEditorBlurRegionsItem(
                            itemId: SecondCameraImageEditorViewController.autoBlurItemIdentifier,
                            unitBoundingBoxes: boxes,
                        )
                        vc.model.append(item: item)
                        modal.dismiss {
                            let toast = SecondCameraEditorToastController(text: SecondCameraEditorLocalizedString(
                                "IMAGE_EDITOR_BLUR_TOAST",
                                comment: "A toast indicating that you can blur more faces after detection",
                            ))
                            let inset = vc.view.safeAreaInsets.bottom + 90
                            toast.presentToastView(from: .bottom, of: vc.view, inset: inset)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Face detection helper (nonisolated — safe to run on any thread)

    /// Runs Vision face detection completely outside @MainActor so the VN
    /// completion handler is never actor-isolated, preventing EXC_BREAKPOINT
    /// crashes when Vision dispatches its callback to a background queue.
    ///
    /// `completion` is intentionally NOT @Sendable; a @unchecked Sendable box is
    /// used internally so Vision's @Sendable callback can capture it without
    /// propagating the Sendable requirement to the call site.
    private nonisolated static func runSecondCameraFaceDetection(
        cgImage: CGImage,
        orientation: CGImagePropertyOrientation,
        completion: @escaping (Result<[CGRect], Error>) -> Void,
    ) {
        // Box lets the @Sendable VN callback capture a non-@Sendable completion.
        final class CompletionBox: @unchecked Sendable {
            let fn: (Result<[CGRect], Error>) -> Void
            init(_ fn: @escaping (Result<[CGRect], Error>) -> Void) { self.fn = fn }
        }
        let box = CompletionBox(completion)

        let request = VNDetectFaceRectanglesRequest { request, error in
            // nonisolated context — no @MainActor inference on this closure.
            if let error {
                box.fn(.failure(error))
                return
            }
            let boxes = (request.results as? [VNFaceObservation] ?? []).map { obs -> CGRect in
                var r = obs.boundingBox
                r.origin.y = 1 - r.origin.y - r.height
                return r
            }
            box.fn(.success(boxes))
        }

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
        do {
            try handler.perform([request])
        } catch {
            box.fn(.failure(error))
        }
    }

    @objc
    func handleSecondCameraBlurToolGesture(_ gestureRecognizer: SecondCameraImageEditorPanGestureRecognizer) {
        SecondCameraEditorAssertIsOnMainThread()

        secondCameraEditorAssertDebug(mode == .blur, "Incorrect mode [\(mode)]")

        func removeCurrentBlur() {
            if let blur = self.secondCameraCurrentStroke {
                self.model.remove(item: blur)
            }
            self.secondCameraCurrentStroke = nil
            self.secondCameraCurrentStrokeSamples.removeAll()
        }
        func tryToAppendBlurSample(_ locationInView: CGPoint) {
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

        let unitBlurStrokeWidth = secondCameraCurrentStrokeUnitWidth()

        switch gestureRecognizer.state {
        case .began:
            removeCurrentBlur()

            // Apply the location history of the gesture so that the blur reflects
            // the touch's movement before the gesture recognized.
            for location in gestureRecognizer.locationHistory {
                tryToAppendBlurSample(location)
            }

            let locationInView = gestureRecognizer.location(in: secondCameraImageEditorView.gestureReferenceView)
            tryToAppendBlurSample(locationInView)

            let blur = SecondCameraImageEditorStrokeItem(
                strokeType: .blur,
                unitSamples: secondCameraCurrentStrokeSamples,
                unitStrokeWidth: unitBlurStrokeWidth,
            )
            model.append(item: blur)
            secondCameraCurrentStroke = blur

        case .changed, .ended:
            let locationInView = gestureRecognizer.location(in: secondCameraImageEditorView.gestureReferenceView)
            tryToAppendBlurSample(locationInView)

            guard let lastBlur = self.secondCameraCurrentStroke else {
                secondCameraEditorFailDebug("Missing last blur.")
                removeCurrentBlur()
                return
            }

            // Model items are immutable; we _replace_ the
            // blur item rather than modify it.
            let blurStroke = SecondCameraImageEditorStrokeItem(
                itemId: lastBlur.itemId,
                strokeType: .blur,
                unitSamples: secondCameraCurrentStrokeSamples,
                unitStrokeWidth: unitBlurStrokeWidth,
            )
            model.replace(item: blurStroke, suppressUndo: true)

            if gestureRecognizer.state == .ended {
                secondCameraCurrentStroke = nil
                secondCameraCurrentStrokeSamples.removeAll()
            } else {
                secondCameraCurrentStroke = blurStroke
            }

        default:
            removeCurrentBlur()
        }
    }
}

// MARK: - Helpers

/// @unchecked Sendable weak-reference box used inside blur detection closures.
/// Actual object access must only happen on the main thread.
private final class SecondCameraEditorBlurWeakRef: @unchecked Sendable {
    weak var object: AnyObject?
    init(_ object: AnyObject?) { self.object = object }
}

private extension CGImagePropertyOrientation {

    init(_ uiImageOrientation: UIImage.Orientation) {
        switch uiImageOrientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        default: self = .up
        }
    }
}
