//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit
import PureLayout

// Base class for all tool view controllers.

class SecondCameraImageEditorViewController: SecondCameraEditorViewController {

    let model: SecondCameraImageEditorModel
    private weak var secondCameraStickerSheetDelegate: SecondCameraStickerPickerSheetDelegate?

    // We only want to let users undo changes made in this view.
    // So we snapshot any older "operation id" and prevent
    // users from undoing it.
    private let firstUndoOperationId: String?

    let secondCameraImageEditorView: SecondCameraImageEditorView

    let topBar = SecondCameraImageEditorTopBar()

    lazy var bottomBar: SecondCameraImageEditorBottomBar = SecondCameraImageEditorBottomBar(buttonProvider: self)

    enum Mode: Int {
        case draw = 1
        case blur
        case text
        case sticker
    }

    var mode: Mode = .draw {
        didSet {
            if oldValue != mode, isViewLoaded {
                updateSecondCameraEditorUIForCurrentMode()
            }
        }
    }

    /// When set, completion/cancel dismisses via SwiftUI `fullScreenCover` instead of UIKit `dismiss`.
    var secondCameraFullScreenCoverDismissHandler: (() -> Void)?

    /**
     * Returns maximum width for the area with tool-specific UI elements in the toolbar at the bottom.
     * Such tool-specific elements are: color picker (for both text and drawing tools), text style selection button etc.
     * This maximum width is calculated as:
     * iPhone: screen width in portrait orientation minus standard horizontal margins.
     * iPad: value from iPhone 13 Max (428 - 2x20)
     */
    static let preferredToolbarContentWidth: CGFloat = {
        if UIDevice.current.secondCameraEditor_isIPad {
            return 388
        } else {
            let screenWidth = min(UIScreen.main.bounds.width, UIScreen.main.bounds.height)
            let inset: CGFloat = UIDevice.current.secondCameraEditor_isPlusSizePhone ? 20 : 16
            return screenWidth - 2 * inset
        }
    }()

    // Pen Tool UI
    var isSecondCameraDrawToolUIInitialized = false
    lazy var secondCameraDrawToolbar: DrawToolbar = {
        let toolbar = DrawToolbar(currentColor: model.color)
        toolbar.preservesSuperviewLayoutMargins = true
        toolbar.colorPickerView.delegate = self
        toolbar.strokeTypeButton.addTarget(self, action: #selector(strokeTypeButtonTapped(sender:)), for: .touchUpInside)
        return toolbar
    }()

    lazy var secondCameraDrawToolGestureRecognizer: SecondCameraImageEditorPanGestureRecognizer = {
        let gestureRecognizer = SecondCameraImageEditorPanGestureRecognizer(target: self, action: #selector(handleSecondCameraDrawToolGesture(_:)))
        gestureRecognizer.maximumNumberOfTouches = 1
        gestureRecognizer.referenceView = secondCameraImageEditorView.gestureReferenceView
        gestureRecognizer.delegate = self
        return gestureRecognizer
    }()

    // Blur Tool UI
    var isSecondCameraBlurToolUIInitialized = false
    lazy var secondCameraBlurToolbar: UIStackView = {
        let drawAnywhereHint = UILabel()
        drawAnywhereHint.font = .dynamicTypeCaption1
        drawAnywhereHint.textColor = SecondCameraEditorTheme.darkThemePrimaryColor
        drawAnywhereHint.textAlignment = .center
        drawAnywhereHint.numberOfLines = 0
        drawAnywhereHint.lineBreakMode = .byWordWrapping
        drawAnywhereHint.text = SecondCameraEditorLocalizedString(
            "IMAGE_EDITOR_BLUR_HINT",
            comment: "The image editor hint that you can draw blur",
        )
        drawAnywhereHint.layer.shadowColor = UIColor.black.cgColor
        drawAnywhereHint.layer.shadowRadius = 2
        drawAnywhereHint.layer.shadowOpacity = 0.66
        drawAnywhereHint.layer.shadowOffset = .zero

        let stackView = UIStackView()
        stackView.alignment = .center
        stackView.axis = .vertical
        stackView.spacing = 14
        stackView.addArrangedSubviews([secondCameraFaceBlurContainer, drawAnywhereHint])
        return stackView
    }()

    lazy var secondCameraFaceBlurContainer: UIView = {
        let containerView = SecondCameraPillView()
        containerView.layoutMargins = UIEdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 8)

        let blurBackgroundView = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
        containerView.addSubview(blurBackgroundView)
        blurBackgroundView.autoPinEdgesToSuperviewEdges()

        let autoBlurLabel = UILabel()
        autoBlurLabel.text = SecondCameraEditorLocalizedString(
            "IMAGE_EDITOR_BLUR_SETTING",
            comment: "The image editor setting to blur faces",
        )
        autoBlurLabel.font = .dynamicTypeSubheadlineClamped
        autoBlurLabel.textColor = SecondCameraEditorTheme.darkThemePrimaryColor

        let stackView = UIStackView(arrangedSubviews: [autoBlurLabel, secondCameraFaceBlurSwitch])
        stackView.spacing = 12
        stackView.alignment = .center
        stackView.axis = .horizontal
        containerView.addSubview(stackView)
        stackView.autoPinEdgesToSuperviewMargins()

        return containerView
    }()

    lazy var secondCameraFaceBlurSwitch: UISwitch = {
        let secondCameraFaceBlurSwitch = UISwitch()
        secondCameraFaceBlurSwitch.addTarget(self, action: #selector(didToggleSecondCameraAutoBlur), for: .valueChanged)
        secondCameraFaceBlurSwitch.isOn = currentAutoBlurItem != nil
        return secondCameraFaceBlurSwitch
    }()

    lazy var blurToolGestureRecognizer: SecondCameraImageEditorPanGestureRecognizer = {
        let gestureRecognizer = SecondCameraImageEditorPanGestureRecognizer(target: self, action: #selector(handleSecondCameraBlurToolGesture(_:)))
        gestureRecognizer.maximumNumberOfTouches = 1
        gestureRecognizer.referenceView = secondCameraImageEditorView.gestureReferenceView
        gestureRecognizer.delegate = self
        return gestureRecognizer
    }()

    // We persist an auto blur identifier for this session so
    // we can keep the toggle switch in sync with undo/redo behavior
    static let autoBlurItemIdentifier = "autoBlur"
    var currentAutoBlurItem: SecondCameraImageEditorBlurRegionsItem? {
        return model.item(forId: SecondCameraImageEditorViewController.autoBlurItemIdentifier) as? SecondCameraImageEditorBlurRegionsItem
    }

    // Pen / Blur Drawing
    lazy var secondCameraStrokeWidthSlider: SecondCameraImageEditorSlider = {
        let slider = SecondCameraImageEditorSlider()
        slider.minimumValue = 0.2
        slider.maximumValue = 2
        slider.value = 1
        slider.addTarget(self, action: #selector(handleSliderTouchEvents(slider:)), for: .allTouchEvents)
        slider.addTarget(self, action: #selector(handleSliderValueChanged(slider:)), for: .valueChanged)
        return slider
    }()

    lazy var secondCameraStrokeWidthSliderContainer = UIView()
    lazy var strokeWidthPreviewDot: UIView = {
        let view = SecondCameraCircleView()
        view.layer.borderColor = UIColor.white.cgColor
        view.layer.borderWidth = 2
        strokeWidthPreviewDotSize = view.autoSetDimension(.width, toSize: 20)
        view.autoPinToSquareAspectRatio()
        return view
    }()

    var strokeWidthPreviewDotSize: NSLayoutConstraint?
    var secondCameraStrokeWidthSliderIsTrackingObservation: NSKeyValueObservation?
    var secondCameraStrokeWidthSliderRevealed = false
    var hideStrokeWidthSliderTimer: Timer?
    var secondCameraStrokeWidthSliderPosition: NSLayoutConstraint?
    var strokeWidthValues: [SecondCameraImageEditorStrokeItem.StrokeType: Float] = [:]
    var secondCameraCurrentStrokeType: SecondCameraImageEditorStrokeItem.StrokeType = .pen {
        didSet {
            updateStrokeWidthSliderValue()
            updateStrokeWidthPreviewSize()
            updateStrokeWidthPreviewColor()
        }
    }

    var secondCameraCurrentStroke: SecondCameraImageEditorStrokeItem? {
        didSet {
            updateSecondCameraEditorControlsVisibility()
            updateSecondCameraEditorTopBar()
        }
    }

    var secondCameraCurrentStrokeSamples = [SecondCameraImageEditorStrokeItem.StrokeSample]()
    func secondCameraCurrentStrokeUnitWidth() -> CGFloat {
        let unitStrokeWidth = SecondCameraImageEditorStrokeItem.unitStrokeWidth(
            forStrokeType: secondCameraCurrentStrokeType,
            widthAdjustmentFactor: CGFloat(secondCameraStrokeWidthSlider.value),
        )
        return unitStrokeWidth / model.currentTransform().scaling
    }

    // Text UI
    var textUIInitialized = false
    var startEditingTextOnViewAppear = false
    var discardTextEditsOnEditingEnd = false
    var secondCameraCurrentTextItem: (textItem: SecondCameraImageEditorTextItem, isNewItem: Bool)?
    var pinchFontSizeStart: CGFloat = SecondCameraImageEditorTextItem.defaultFontSize
    lazy var secondCameraTextViewContainer: UIView = {
        let view = UIView(frame: view.bounds)
        view.preservesSuperviewLayoutMargins = true
        view.alpha = 0
        return view
    }()

    lazy var textView: SecondCameraMediaTextView = {
        let textView = SecondCameraMediaTextView()
        textView.delegate = self
        return textView
    }()

    lazy var textViewWrapperView = UIView()
    lazy var textViewBackgroundView = UIView()
    lazy var secondCameraTextViewAccessoryToolbar: SecondCameraTextStylingToolbar = {
        let toolbar = SecondCameraTextStylingToolbar(currentColor: secondCameraCurrentTextItem?.textItem.color)
        toolbar.preservesSuperviewLayoutMargins = true
        toolbar.addTarget(self, action: #selector(secondCameraTextColorDidChange), for: .valueChanged)
        toolbar.textStyleButton.addTarget(self, action: #selector(didTapSecondCameraTextStyleButton(sender:)), for: .touchUpInside)
        toolbar.decorationStyleButton.addTarget(self, action: #selector(didTapSecondCameraTextDecorationStyleButton(sender:)), for: .touchUpInside)
        toolbar.doneButton.addTarget(self, action: #selector(didTapSecondCameraTextEditingDoneButton(sender:)), for: .touchUpInside)
        return toolbar
    }()

    init(model: SecondCameraImageEditorModel, secondCameraStickerSheetDelegate: SecondCameraStickerPickerSheetDelegate?) {
        self.model = model
        self.secondCameraStickerSheetDelegate = secondCameraStickerSheetDelegate
        self.secondCameraImageEditorView = SecondCameraImageEditorView(model: model, delegate: nil)
        self.firstUndoOperationId = model.currentUndoOperationId()

        super.init()

        model.add(observer: self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .black

        secondCameraImageEditorView.configureSecondCameraEditorSubviews()
        view.addSubview(secondCameraImageEditorView)
        secondCameraImageEditorView.autoPinWidthToSuperview()
        secondCameraImageEditorView.autoPinEdge(toSuperviewSafeArea: .top)

        // Top toolbar
        updateSecondCameraEditorTopBar()
        topBar.undoButton.addTarget(self, action: #selector(didTapSecondCameraUndo(sender:)), for: .touchUpInside)
        topBar.clearAllButton.addTarget(self, action: #selector(didTapSecondCameraClearAll(sender:)), for: .touchUpInside)
        topBar.install(in: view)

        // Bottom toolbar
        view.addSubview(bottomBar)
        bottomBar.autoPinWidthToSuperview()
        bottomBar.autoPinEdge(toSuperviewEdge: .bottom)
        bottomBar.autoPinEdge(.top, to: .bottom, of: secondCameraImageEditorView)
        bottomBar.cancelButton.addTarget(self, action: #selector(didTapSecondCameraCancel(sender:)), for: .touchUpInside)
        bottomBar.doneButton.addTarget(self, action: #selector(didTapSecondCameraDone(sender:)), for: .touchUpInside)

        // Stroke width slider
        secondCameraStrokeWidthSliderContainer.addSubview(secondCameraStrokeWidthSlider)
        secondCameraStrokeWidthSlider.autoPinEdgesToSuperviewMargins()
        secondCameraStrokeWidthSliderContainer.layoutMargins = UIEdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0)
        secondCameraStrokeWidthSliderContainer.transform = CGAffineTransform(rotationAngle: -.secondCameraEditor_halfPi)
        view.addSubview(secondCameraStrokeWidthSliderContainer)
        secondCameraStrokeWidthSliderContainer.autoVCenterInSuperview()
        secondCameraStrokeWidthSliderPosition = secondCameraStrokeWidthSliderContainer.centerXAnchor.constraint(equalTo: view.leadingAnchor)
        secondCameraStrokeWidthSliderPosition?.autoInstall()
        secondCameraStrokeWidthSliderContainer.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleSliderContainerTap(_:))))

        updateSecondCameraEditorUIForCurrentMode()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        UIView.performWithoutAnimation {
            transitionSecondCameraEditorUI(toState: .initial, animated: false)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        transitionSecondCameraEditorUI(toState: .final, animated: true) { finished in
            guard finished else { return }
            if self.startEditingTextOnViewAppear, self.canBeginSecondCameraTextEditingOnViewAppear {
                self.beginSecondCameraTextEditing()
            }
            self.startEditingTextOnViewAppear = false
        }
    }

    override var prefersStatusBarHidden: Bool {
        !UIDevice.current.secondCameraEditor_hasIPhoneXNotch && !UIDevice.current.secondCameraEditor_isIPad && !SecondCameraEditorDependenciesBridge.shared.currentCallProvider.hasCurrentCall
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        .lightContent
    }

    // MARK: -

    private func updateSecondCameraEditorUIForCurrentMode() {
        switch mode {
        case .draw, .blur:
            secondCameraStrokeWidthSliderContainer.isHidden = false
            finishSecondCameraTextEditing()
            secondCameraImageEditorView.textInteractionModes = .select
        case .text, .sticker:
            secondCameraStrokeWidthSliderContainer.isHidden = true
            secondCameraImageEditorView.textInteractionModes = .all
        }

        updateSecondCameraDrawToolUIVisibility()
        updateSecondCameraBlurToolUIVisibility()
        updateSecondCameraTextUIVisibility()

        for button in bottomBar.buttons {
            button.isSelected = mode.rawValue == button.tag
        }
    }

    private func updateSecondCameraEditorTopBar() {
        let canUndo = canUndo
        topBar.isUndoButtonHidden = !canUndo
        topBar.isClearAllButtonHidden = !canUndo
    }

    private var shouldHideControls: Bool {
        switch mode {
        case .draw, .blur:
            return secondCameraCurrentStroke != nil

        case .text, .sticker:
            return secondCameraImageEditorView.shouldHideControls
        }
    }

    private var canUndo: Bool {
        model.canUndo() && firstUndoOperationId != model.currentUndoOperationId()
    }

    func updateSecondCameraEditorControlsVisibility() {
        setControls(hidden: shouldHideControls, animated: true, slideButtonsInOut: false)
    }

    private func setControls(hidden: Bool, animated: Bool, slideButtonsInOut: Bool, completion: ((Bool) -> Void)? = nil) {
        if animated {
            UIView.animate(
                withDuration: 0.15,
                animations: {
                    self.setControls(hidden: hidden, slideButtonsInOut: slideButtonsInOut)

                    // Animate layout changes made within bottomBar.setControls(hidden:).
                    if slideButtonsInOut {
                        self.bottomBar.setNeedsDisplay()
                        self.bottomBar.layoutIfNeeded()
                    }
                },
                completion: completion,
            )
        } else {
            setControls(hidden: hidden, slideButtonsInOut: slideButtonsInOut)
            completion?(true)
        }
    }

    private func setControls(hidden: Bool, slideButtonsInOut: Bool) {
        let alpha: CGFloat = hidden ? 0 : 1
        topBar.alpha = alpha
        bottomBar.alpha = alpha
        if slideButtonsInOut {
            bottomBar.setControls(hidden: hidden)
        }

        switch mode {
        case .draw:
            updateSecondCameraDrawToolControlsVisibility()

        case .blur:
            updateSecondCameraBlurToolControlsVisibility()

        case .text, .sticker:
            updateSecondCameraTextControlsVisibility()
        }
    }

    private func secondCameraEditorModelDidChange() {
        updateSecondCameraEditorTopBar()

        if isSecondCameraBlurToolUIInitialized {
            // If we undo/redo, we may remove or re-apply the auto blur
            secondCameraFaceBlurSwitch.isOn = currentAutoBlurItem != nil
        }
    }

    private func undo() {
        guard canUndo else {
            secondCameraEditorFailDebug("Can't undo.")
            return
        }
        model.undo()
    }

    private func clearAll() {
        if mode == .text {
            finishSecondCameraTextEditing(discardEdits: true)
        }

        while canUndo {
            model.undo()
        }
    }
}

// MARK: - Presenting / Dismissing {

extension SecondCameraImageEditorViewController {

    private func prepareSecondCameraEditorToDismiss(completion: ((Bool) -> Void)?) {
        if mode == .text {
            finishSecondCameraTextEditing(discardEdits: true)
        }
        transitionSecondCameraEditorUI(toState: .initial, animated: true, completion: completion)
    }

    private func prepareSecondCameraEditorToFinish(completion: ((Bool) -> Void)?) {
        if mode == .text {
            finishSecondCameraTextEditing()
        }
        transitionSecondCameraEditorUI(toState: .initial, animated: true, completion: completion)
    }

    private func dismissSecondCameraEditor() {
        if let secondCameraFullScreenCoverDismissHandler {
            secondCameraFullScreenCoverDismissHandler()
        } else {
            dismiss(animated: false)
        }
    }

    private func discardAndDismissSecondCameraEditor() {
        if canUndo {
            askToDiscardAllSecondCameraEditorChanges {
                self.prepareSecondCameraEditorToDismiss { finished in
                    guard finished else { return }
                    self.dismissSecondCameraEditor()
                }
            }
        } else {
            prepareSecondCameraEditorToDismiss { finished in
                guard finished else { return }
                self.dismissSecondCameraEditor()
            }
        }
    }

    private func completeAndDismissSecondCameraEditor() {
        prepareSecondCameraEditorToFinish { finished in
            guard finished else { return }
            self.dismissSecondCameraEditor()
        }
    }

    private func askToDiscardAllSecondCameraEditorChanges(_ completionHandler: (() -> Void)?) {
        let actionSheetTitle = SecondCameraEditorLocalizedString(
            "MEDIA_EDITOR_DISCARD_ALL_CONFIRMATION_TITLE",
            comment: "Media Editor: Title for the 'Discard Changes' confirmation prompt.",
        )
        let actionSheetMessage = SecondCameraEditorLocalizedString(
            "MEDIA_EDITOR_DISCARD_ALL_CONFIRMATION_MESSAGE",
            comment: "Media Editor: Message for the 'Discard Changes' confirmation prompt.",
        )
        let discardChangesButton = SecondCameraEditorLocalizedString(
            "MEDIA_EDITOR_DISCARD_ALL_BUTTON",
            comment: "Media Editor: Title for the button in 'Discard Changes' confirmation prompt.",
        )
        let actionSheet = SecondCameraEditorActionSheetController(title: actionSheetTitle, message: actionSheetMessage)
        actionSheet.overrideUserInterfaceStyle = .dark
        actionSheet.addAction(SecondCameraEditorActionSheetAction(title: discardChangesButton, style: .destructive, handler: { _ in
            self.clearAll()
            if let completionHandler {
                completionHandler()
            }
        }))
        actionSheet.addAction(SecondCameraEditorActionSheetAction(title: SecondCameraEditorCommonStrings.cancelButton, style: .cancel, handler: nil))
        presentSecondCameraEditorActionSheet(actionSheet)
    }

    private enum UIState {
        case initial
        case final
    }

    private func transitionSecondCameraEditorUI(toState state: UIState, animated: Bool, completion: ((Bool) -> Void)? = nil) {
        setControls(hidden: state == .initial, animated: animated, slideButtonsInOut: true, completion: completion)
        secondCameraImageEditorView.setHasRoundCorners(state == .initial, animationDuration: animated ? 0.15 : 0)
    }
}

// MARK: - Actions

extension SecondCameraImageEditorViewController {

    @objc
    private func didTapSecondCameraUndo(sender: UIButton) {
        undo()
    }

    @objc
    private func didTapSecondCameraClearAll(sender: UIButton) {
        askToDiscardAllSecondCameraEditorChanges(nil)
    }

    @objc
    private func didTapSecondCameraCancel(sender: UIButton) {
        discardAndDismissSecondCameraEditor()
    }

    @objc
    private func didTapSecondCameraDone(sender: UIButton) {
        completeAndDismissSecondCameraEditor()
    }

    @objc
    private func didTapSecondCameraPen(sender: UIButton) {
        // Second tap on Pen icon switches editor to "text" mode.
        mode = (mode == .draw) ? .text : .draw
    }

    @objc
    private func didTapSecondCameraAddText(sender: UIButton) {
        let decorationStyle = secondCameraTextViewAccessoryToolbar.decorationStyle
        let textColor = secondCameraTextViewAccessoryToolbar.currentColorPickerValue
        let textItem = secondCameraImageEditorView.createNewTextItem(withColor: textColor, decorationStyle: decorationStyle)
        selectSecondCameraTextItem(textItem, isNewItem: true, startEditing: true)
    }

    @objc
    private func didTapSecondCameraAddSticker(sender: UIButton) {
        let stickerPicker = SecondCameraStickerPickerSheet(pickerDelegate: self)
        stickerPicker.sheetDelegate = secondCameraStickerSheetDelegate
        present(stickerPicker, animated: true)
    }

    @objc
    private func didTapSecondCameraBlur(sender: UIButton) {
        // Second tap on Blur icon switches editor to "text" mode.
        mode = (mode == .blur) ? .text : .blur
    }

    @objc
    private func secondCameraTextColorDidChange(sender: SecondCameraTextStylingToolbar) {
        let textItemColor = sender.currentColorPickerValue
        secondCameraImageEditorView.updateSelectedTextItem(withColor: textItemColor)
        if textView.isFirstResponder {
            updateSecondCameraTextViewAttributes(using: secondCameraTextViewAccessoryToolbar)
        }
    }
}

// MARK: - Bottom Bar

extension SecondCameraImageEditorViewController: SecondCameraImageEditorBottomBarButtonProvider {

    var middleButtons: [UIButton] {
        let penButton = SecondCameraRoundMediaButton(
            image: UIImage(imageLiteralResourceName: "edit-28"),
            backgroundStyle: .solid(.clear),
        )
        penButton.tag = Mode.draw.rawValue
        penButton.addTarget(self, action: #selector(didTapSecondCameraPen(sender:)), for: .touchUpInside)

        let textButton = SecondCameraRoundMediaButton(
            image: UIImage(imageLiteralResourceName: "text-28"),
            backgroundStyle: .solid(.clear),
        )
        textButton.addTarget(self, action: #selector(didTapSecondCameraAddText(sender:)), for: .touchUpInside)

        let stickerButton = SecondCameraRoundMediaButton(
            image: UIImage(imageLiteralResourceName: "sticker-smiley-28"),
            backgroundStyle: .solid(.clear),
        )
        stickerButton.addTarget(self, action: #selector(didTapSecondCameraAddSticker(sender:)), for: .touchUpInside)

        let blurButton = SecondCameraRoundMediaButton(
            image: UIImage(imageLiteralResourceName: "blur-28"),
            backgroundStyle: .solid(.clear),
        )
        blurButton.tag = Mode.blur.rawValue
        blurButton.addTarget(self, action: #selector(didTapSecondCameraBlur(sender:)), for: .touchUpInside)

        let buttons = [penButton, textButton, stickerButton, blurButton]
        for button in buttons {
            button.setBackgroundColor(.secondCameraEditor_white, for: .highlighted)
            button.setBackgroundColor(.secondCameraEditor_white, for: .selected)
            if let image = button.image(for: .normal) {
                let tintedImage = image.withTintColor(.secondCameraEditor_black, renderingMode: .alwaysOriginal)
                button.setImage(tintedImage, for: .highlighted)
                button.setImage(tintedImage, for: .selected)
            }
        }

        return buttons
    }
}

// MARK: - UIGestureRecognizerDelegate

extension SecondCameraImageEditorViewController: UIGestureRecognizerDelegate {

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Ignore touches that begin inside the control areas.
        switch mode {
        case .draw:
            guard !secondCameraDrawToolbar.bounds.contains(touch.location(in: secondCameraDrawToolbar)) else {
                return false
            }
            guard !secondCameraStrokeWidthSliderContainer.bounds.contains(touch.location(in: secondCameraStrokeWidthSliderContainer)) else {
                return false
            }
            return true

        case .blur:
            return !secondCameraBlurToolbar.bounds.contains(touch.location(in: secondCameraBlurToolbar))

        default:
            return true
        }
    }
}

// MARK: - SecondCameraImageEditorModelObserver

extension SecondCameraImageEditorViewController: SecondCameraImageEditorModelObserver {

    func secondCameraImageEditorModelDidChange(before: SecondCameraImageEditorContents, after: SecondCameraImageEditorContents) {
        secondCameraEditorModelDidChange()
    }

    func secondCameraImageEditorModelDidChange(changedItemIds: [String]) {
        secondCameraEditorModelDidChange()
    }
}

// MARK: - SecondCameraImageEditorPaletteViewDelegate

extension SecondCameraImageEditorViewController: SecondCameraColorPickerBarViewDelegate {

    func secondCameraColorPickerBarView(_ pickerView: SecondCameraColorPickerBarView, didSelectColor color: SecondCameraColorPickerBarColor) {
        switch mode {
        case .draw:
            model.color = color
            updateStrokeWidthPreviewColor()

        default:
            secondCameraEditorAssertDebug(false, "Invalid mode [\(mode)]")
        }
    }
}

// MARK: - SecondCameraStickerPickerDelegate

extension SecondCameraImageEditorViewController: SecondCameraStickerPickerDelegate {

    func didSelectSecondCameraSticker(_ stickerInfo: SecondCameraStickerInfo) {
        let stickerItem = secondCameraImageEditorView.createNewStickerItem(with: .regular(stickerInfo))
        selectSecondCameraStickerItem(stickerItem)
        // Do NOT call dismiss here. SecondCameraStickerPickerSheet dismisses itself after
        // forwarding the selection, keeping the editor alive on screen.
    }
}

extension SecondCameraImageEditorViewController: SecondCameraStoryStickerPickerDelegate {

    func didSelectSecondCameraStorySticker(_ storySticker: SecondCameraEditorSticker.StorySticker) {
        let stickerItem = secondCameraImageEditorView.createNewStickerItem(with: .story(storySticker))
        selectSecondCameraStickerItem(stickerItem)
        // Do NOT call dismiss here — same reason as didSelectSecondCameraSticker above.
    }
}
