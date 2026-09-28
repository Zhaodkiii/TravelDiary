//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//


import UIKit
class SecondCameraImageAttachmentPrepViewController: SecondCameraAttachmentPrepViewController {

    private let model: SecondCameraImageEditorModel
    weak var secondCameraStickerSheetDelegate: SecondCameraStickerPickerSheetDelegate?

    private lazy var editorView = SecondCameraImageEditorView(model: model, delegate: self)

    override init?(attachmentApprovalItem: SecondCameraAttachmentApprovalItem) {
        guard let secondCameraImageEditorModel = attachmentApprovalItem.secondCameraImageEditorModel else {
            secondCameraEditorFailDebug("secondCameraImageEditorModel is empty.")
            return nil
        }

        self.model = secondCameraImageEditorModel

        super.init(attachmentApprovalItem: attachmentApprovalItem)
    }

    override var contentView: UIView {
        editorView
    }

    override func prepareContentView() {
        editorView.setHasRoundCorners(true)
        editorView.textInteractionModes = [.tap, .move]
        editorView.configureSecondCameraEditorSubviews()
    }

    override var shouldHideControls: Bool {
        editorView.shouldHideControls || super.shouldHideControls
    }

    override var canSaveMedia: Bool {
        if model.isDirty() {
            return true
        }
        return super.canSaveMedia
    }

    /**
     * Bottom toolbar in edit mode is always the same height and can be cached.
     */
    private static let editModeToolbarHeight: CGFloat = {
        let toolbar = SecondCameraImageEditorBottomBar(buttonProvider: nil)
        let size = toolbar.systemLayoutSizeFitting(
            CGSize(width: UIView.noIntrinsicMetric, height: .greatestFiniteMagnitude),
            withHorizontalFittingPriority: .fittingSizeLevel,
            verticalFittingPriority: .fittingSizeLevel,
        )
        return size.height
    }()

    override var mediaEditingToolbarHeight: CGFloat? {
        SecondCameraImageAttachmentPrepViewController.editModeToolbarHeight
    }

    // MARK: - Tools

    func makeSecondCameraImageEditorPresentationContext(
        previewController: SecondCameraAttachmentPreviewViewController
    ) -> SecondCameraImageEditorPresentationContext {
        SecondCameraImageEditorPresentationContext(
            model: model,
            secondCameraStickerSheetDelegate: secondCameraStickerSheetDelegate,
            previewController: previewController,
            prepController: self
        )
    }

    override func activateSecondCameraPenTool() {
        let viewController = SecondCameraImageEditorViewController(model: model, secondCameraStickerSheetDelegate: secondCameraStickerSheetDelegate)
        presentSecondCameraMediaTool(viewController: viewController)
    }

    override func activateSecondCameraCropTool() {
        guard let srcImage = SecondCameraImageEditorCanvasView.loadSrcImage(model: model) else {
            secondCameraEditorFailDebug("Couldn't load src image.")
            return
        }

        // We want to render a preview image that "flattens" all of the brush strokes, text items,
        // into the background image without applying the transform (e.g. rotating, etc.), so we
        // use a default transform.
        let previewTransform = SecondCameraImageEditorTransform.defaultTransform(srcImageSizePixels: model.srcImageSizePixels)
        guard let previewImage = SecondCameraImageEditorCanvasView.renderForOutput(model: model, transform: previewTransform) else {
            secondCameraEditorFailDebug("Couldn't generate preview image.")
            return
        }

        let cropTool = SecondCameraImageEditorCropViewController(model: model, srcImage: srcImage, previewImage: previewImage)
        presentSecondCameraMediaTool(viewController: cropTool)
    }
}

// MARK: -

extension SecondCameraImageAttachmentPrepViewController: SecondCameraImageEditorViewDelegate {

    private func openTextTool(with textItem: SecondCameraImageEditorTextItem, isNewItem: Bool, editText: Bool) {
        let textEditor = SecondCameraImageEditorViewController(model: model, secondCameraStickerSheetDelegate: secondCameraStickerSheetDelegate)
        textEditor.selectSecondCameraTextItem(textItem, isNewItem: isNewItem, startEditing: editText)
        presentSecondCameraMediaTool(viewController: textEditor)
    }

    func secondCameraImageEditorView(_: SecondCameraImageEditorView, didRequestAddTextItem textItem: SecondCameraImageEditorTextItem) {
        openTextTool(with: textItem, isNewItem: true, editText: true)
    }

    func secondCameraImageEditorView(_: SecondCameraImageEditorView, didTapTextItem textItem: SecondCameraImageEditorTextItem) {
        openTextTool(with: textItem, isNewItem: false, editText: false)
    }

    func secondCameraImageEditorView(_ secondCameraImageEditorView: SecondCameraImageEditorView, didMoveTextItem textItem: SecondCameraImageEditorTextItem) {
        openTextTool(with: textItem, isNewItem: false, editText: false)
    }

    func secondCameraImageEditorViewDidUpdateSelection(_ secondCameraImageEditorView: SecondCameraImageEditorView) { }

    func imageEditorDidRequestToolbarVisibilityUpdate(_: SecondCameraImageEditorView) {
        prepDelegate?.attachmentPrepViewControllerDidRequestUpdateControlsVisibility(self, completion: nil)
    }
}
