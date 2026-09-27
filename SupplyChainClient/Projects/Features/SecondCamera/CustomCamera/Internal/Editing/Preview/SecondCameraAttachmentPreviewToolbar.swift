import UIKit
import PureLayout

protocol SecondCameraAttachmentPreviewToolbarDelegate: AnyObject {
    func secondCameraPreviewToolbarDidTapPen(_ toolbar: SecondCameraAttachmentPreviewToolbar)
    func secondCameraPreviewToolbarDidTapCrop(_ toolbar: SecondCameraAttachmentPreviewToolbar)
    func secondCameraPreviewToolbarDidTapQuality(_ toolbar: SecondCameraAttachmentPreviewToolbar)
    func secondCameraPreviewToolbarDidTapSave(_ toolbar: SecondCameraAttachmentPreviewToolbar)
    func secondCameraPreviewToolbarDidTapDone(_ toolbar: SecondCameraAttachmentPreviewToolbar)
}

final class SecondCameraAttachmentPreviewToolbar: UIView {

    struct Configuration: Equatable {
        var showsPen = false
        var showsCrop = false
        var showsQuality = false
        var showsSave = false
        var isHighQuality = false
    }

    weak var delegate: SecondCameraAttachmentPreviewToolbarDelegate?

    private var configuration = Configuration()

    private static let buttonBackgroundColor = SecondCameraRoundMediaButton.defaultBackgroundColor

    private lazy var penButton = makeToolButton(
        imageName: "brush-pen-28",
        accessibilityLabel: SecondCameraEditorL10n.Editor.draw,
        action: #selector(penTapped)
    )
    private lazy var cropButton = makeToolButton(
        imageName: "crop-rotate-28",
        accessibilityLabel: SecondCameraEditorL10n.Editor.crop,
        action: #selector(cropTapped)
    )
    private lazy var qualityButton = makeToolButton(
        imageName: "quality-standard",
        accessibilityLabel: SecondCameraEditorL10n.Quality.title,
        action: #selector(qualityTapped)
    )
    private lazy var saveButton = makeToolButton(
        imageName: "save-28",
        accessibilityLabel: SecondCameraEditorL10n.Preview.save,
        action: #selector(saveTapped)
    )
    private lazy var doneButton: UIButton = {
        let button = SecondCameraRoundMediaButton(
            image: UIImage.secondCameraEditor(named: "check-28", systemName: "checkmark"),
            backgroundStyle: .solid(Self.buttonBackgroundColor),
        )
        button.accessibilityLabel = SecondCameraEditorL10n.Preview.done
        button.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
        return button
    }()

    private lazy var stackView: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [
            penButton,
            cropButton,
            qualityButton,
            saveButton,
            UIView.transparentSpacer(),
            doneButton,
        ])
        stack.axis = .horizontal
        stack.spacing = 4
        stack.alignment = .center
        stack.preservesSuperviewLayoutMargins = true
        return stack
    }()

    private lazy var backgroundView: UIVisualEffectView = {
        UIVisualEffectView(effect: UIBlurEffect(style: .dark))
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        installSubviews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: CGSize { .zero }

    var opaqueAreaHeight: CGFloat {
        layoutIfNeeded()
        return stackView.bounds.height + layoutMargins.bottom
    }

    func update(configuration: Configuration, animated: Bool) {
        guard self.configuration != configuration else { return }
        self.configuration = configuration

        penButton.setIsHidden(!configuration.showsPen, animated: animated)
        cropButton.setIsHidden(!configuration.showsCrop, animated: animated)
        qualityButton.setIsHidden(!configuration.showsQuality, animated: animated)
        saveButton.setIsHidden(!configuration.showsSave, animated: animated)

        let qualityImageName = configuration.isHighQuality ? "quality-high" : "quality-standard"
        qualityButton.setImage(UIImage.secondCameraEditor(named: qualityImageName, systemName: "photo"), animated: animated)
    }

    private func installSubviews() {
        preservesSuperviewLayoutMargins = true
        layoutMargins.bottom = 0

        addSubview(backgroundView)
        backgroundView.autoPinWidthToSuperview()
        backgroundView.autoPinEdge(toSuperviewEdge: .top)
        backgroundView.autoPinEdge(toSuperviewEdge: .bottom, withInset: -30)

        addSubview(stackView)
        stackView.autoPinLeadingToSuperviewMargin(withInset: -penButton.layoutMargins.leading)
        doneButton.layoutMarginsGuide.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor).isActive = true
        stackView.autoPinEdge(toSuperviewEdge: .top)
        stackView.autoPinEdge(toSuperviewMargin: .bottom)
        let bottomInset: CGFloat = UIDevice.current.secondCameraEditor_hasIPhoneXNotch ? 0 : 8
        stackView.autoPinEdge(toSuperviewEdge: .bottom, withInset: bottomInset)
    }

    private func makeToolButton(imageName: String, accessibilityLabel: String, action: Selector) -> UIButton {
        let button = SecondCameraRoundMediaButton(
            image: UIImage.secondCameraEditor(named: imageName, systemName: "circle"),
            backgroundStyle: .solid(Self.buttonBackgroundColor),
        )
        button.accessibilityLabel = accessibilityLabel
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    @objc private func penTapped() { delegate?.secondCameraPreviewToolbarDidTapPen(self) }
    @objc private func cropTapped() { delegate?.secondCameraPreviewToolbarDidTapCrop(self) }
    @objc private func qualityTapped() { delegate?.secondCameraPreviewToolbarDidTapQuality(self) }
    @objc private func saveTapped() { delegate?.secondCameraPreviewToolbarDidTapSave(self) }
    @objc private func doneTapped() { delegate?.secondCameraPreviewToolbarDidTapDone(self) }
}
