//
// Signal Camera - Extended UI stubs
//

import UIKit

public final class SecondCameraEditorActionSheetAction {
    public enum Style { case `default`, cancel, destructive }
    public let title: String
    public let style: Style
    public let handler: ((SecondCameraEditorActionSheetAction) -> Void)?
    public init(title: String, style: Style = .default, handler: ((SecondCameraEditorActionSheetAction) -> Void)? = nil) {
        self.title = title
        self.style = style
        self.handler = handler
    }
}

public class SecondCameraEditorActionSheetController: UIViewController {
    public private(set) var actions = [SecondCameraEditorActionSheetAction]()
    public var isCancelable = true
    public let actionSheetTitle: String?
    public let actionSheetMessage: String?

    public init(title: String? = nil, message: String? = nil) {
        self.actionSheetTitle = title
        self.actionSheetMessage = message
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    public func addAction(_ action: SecondCameraEditorActionSheetAction) {
        actions.append(action)
        if action.style == .cancel {
            isCancelable = true
        }
    }
}

public enum SecondCameraEditorCommonStrings {
    public static let cancelButton = "取消"
    public static let continueButton = "继续"
    public static let deleteButton = "删除"
    public static let saveButton = "保存"
    public static let setButton = "设置"
    public static let doneButton = "完成"
}

public enum SecondCameraEditorMessageStrings {}

public class SecondCameraEditorActivityIndicatorViewController: UIViewController {
    public enum Constants {
        public static let defaultPresentationDelay: TimeInterval = 0.05
    }

    private let canCancel: Bool
    private let presentationDelay: TimeInterval
    private var wasDismissed = false

    public init(canCancel: Bool = false, presentationDelay: TimeInterval = Constants.defaultPresentationDelay) {
        self.canCancel = canCancel
        self.presentationDelay = presentationDelay
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        view.backgroundColor = UIColor.black.withAlphaComponent(0.35)
    }

    required init?(coder: NSCoder) { fatalError() }

    @MainActor
    public class func present(
        fromViewController: UIViewController,
        canCancel: Bool,
        presentationDelay: TimeInterval = Constants.defaultPresentationDelay,
        backgroundBlock: @escaping (SecondCameraEditorActivityIndicatorViewController) -> Void,
    ) {
        let modal = SecondCameraEditorActivityIndicatorViewController(canCancel: canCancel, presentationDelay: presentationDelay)
        DispatchQueue.main.asyncAfter(deadline: .now() + presentationDelay) {
            guard !modal.wasDismissed else { return }
            fromViewController.present(modal, animated: false)
        }
        DispatchQueue.global(qos: .userInitiated).async {
            backgroundBlock(modal)
        }
    }

    public func dismiss(completion: (() -> Void)? = nil) {
        DispatchQueue.main.async {
            guard !self.wasDismissed else {
                completion?()
                return
            }
            self.wasDismissed = true
            self.dismiss(animated: false, completion: completion)
        }
    }
}

public final class SecondCameraEditorToastController {
    private let text: String

    public init(text: String) {
        self.text = text
    }

    public enum Position { case bottom, top }

    public func presentToastView(from position: Position, of view: UIView, inset: CGFloat) {
        let label = UILabel()
        label.text = text
        label.textColor = .white
        label.backgroundColor = UIColor.black.withAlphaComponent(0.75)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.layer.cornerRadius = 8
        label.clipsToBounds = true
        label.alpha = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            position == .bottom
                ? label.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -inset)
                : label.topAnchor.constraint(equalTo: view.topAnchor, constant: inset),
        ])
        UIView.animate(withDuration: 0.2) { label.alpha = 1 } completion: { _ in
            UIView.animate(withDuration: 0.2, delay: 2.0) { label.alpha = 0 } completion: { _ in
                label.removeFromSuperview()
            }
        }
    }
}

public class SecondCameraEditorSelectionButton: UIButton {}
public class SecondCameraEditorViewOnceTooltip: UIView {}
public struct SecondCameraStickerInfo: Hashable {
    public var packId: String = ""
    public var stickerId: String = ""

    nonisolated public init(packId: String = "", stickerId: String = "") {
        self.packId = packId
        self.stickerId = stickerId
    }

    nonisolated public func asKey() -> String { "\(packId).\(stickerId)" }
}

public protocol SecondCameraStickerPickerDelegate: AnyObject {
    func didSelectSecondCameraSticker(_ stickerInfo: SecondCameraStickerInfo)
}

public protocol SecondCameraStoryStickerPickerDelegate: AnyObject {}

public class SecondCameraStickerPickerSheet: UIViewController {
    public weak var sheetDelegate: SecondCameraStickerPickerSheetDelegate?
    private weak var pickerDelegate: SecondCameraStickerPickerDelegate?

    public init(pickerDelegate: SecondCameraStickerPickerDelegate) {
        self.pickerDelegate = pickerDelegate
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
        if let sheet = sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override public func viewDidLoad() {
        super.viewDidLoad()
        let picker = SecondCameraStickerPickerViewController()
        picker.pickerDelegate = self
        addChild(picker)
        view.addSubview(picker.view)
        picker.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            picker.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            picker.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            picker.view.topAnchor.constraint(equalTo: view.topAnchor),
            picker.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        picker.didMove(toParent: self)
    }
}

extension SecondCameraStickerPickerSheet: SecondCameraStickerPickerDelegate {
    public func didSelectSecondCameraSticker(_ stickerInfo: SecondCameraStickerInfo) {
        // Forward to the editor first so it can add the sticker, then dismiss
        // the sheet itself. This keeps the sheet responsible for its own
        // lifecycle and prevents the editor from accidentally being dismissed.
        pickerDelegate?.didSelectSecondCameraSticker(stickerInfo)
        dismiss(animated: true)
    }
}
public typealias SecondCameraEditorAci = String
public class SecondCameraEditorBodyRangesTextView: UITextView {}
public protocol SecondCameraEditorBodyRangesTextViewDelegate: AnyObject {}
@MainActor
public class SecondCameraEditorEditableMessageBodyTextStorage {}
public struct SecondCameraEditorHydratedMessageBody { public var text: String = "" }
public struct SecondCameraEditorMentionPickerStyle {}
public class SecondCameraEditorTableViewController: UIViewController {}

public extension SecondCameraEditorCommonStrings {
    static let attachmentTypeVideo = "视频"
    static let attachmentTypePhoto = "照片"
    static let attachmentTypeAnimated = "动图"
    static let backButton = "返回"
    static let dismissButton = "关闭"
}

public extension SecondCameraEditorHydratedMessageBody {
    struct DisplayConfiguration {}
}

public struct SecondCameraAttachmentApprovalViewControllerOptions {
    public static nonisolated(unsafe) let canAddMore = SecondCameraAttachmentApprovalViewControllerOptions()
    public static nonisolated(unsafe) let canChangeQualityLevel = SecondCameraAttachmentApprovalViewControllerOptions()
    public static nonisolated(unsafe) let canToggleViewOnce = SecondCameraAttachmentApprovalViewControllerOptions()
    public static nonisolated(unsafe) let disallowViewOnce = SecondCameraAttachmentApprovalViewControllerOptions()
    public static nonisolated(unsafe) let hasCancel = SecondCameraAttachmentApprovalViewControllerOptions()
    public static nonisolated(unsafe) let isNotFinalScreen = SecondCameraAttachmentApprovalViewControllerOptions()
}

public extension SecondCameraEditorEditableMessageBodyTextStorage {
    struct ReadTxProvider {}
}

public extension SecondCameraEditorTableViewController {
    static let defaultHOuterMargin: CGFloat = 16
    static func removeBackButtonText() {}
}

public extension SecondCameraEditorMentionPickerStyle {
    static var composingAttachment: SecondCameraEditorMentionPickerStyle { SecondCameraEditorMentionPickerStyle() }
}

public extension SecondCameraEditorViewOnceTooltip {
    static func present(from viewController: UIViewController) {}
}

public extension SecondCameraEditorActionSheetController {
    var customHeader: UIView? {
        get { nil }
        set {}
    }
}

public extension SecondCameraEditorSelectionButton {
    var allowsMultipleSelection: Bool {
        get { false }
        set {}
    }
    func reset() {}
}

public extension SecondCameraEditorDependenciesBridge {
    var db: SecondCameraEditorDBStub { SecondCameraEditorDBStub() }
    var currentCallProvider: SecondCameraEditorCallProviderStub { SecondCameraEditorCallProviderStub() }
}

public struct SecondCameraEditorDBStub {
    func read<T>(_ block: (SecondCameraEditorDBReadTransaction) -> T) -> T { block(SecondCameraEditorDBReadTransaction()) }
}

public struct SecondCameraEditorCallProviderStub {
    var currentCall: Any? { nil }
    var hasCurrentCall: Bool { false }
}

public extension SecondCameraEditorSSKEnvironment {
    var databaseStorageRef: SecondCameraEditorDBStub { SecondCameraEditorDBStub() }
    var preferencesRef: SecondCameraEditorPreferencesStub { SecondCameraEditorPreferencesStub() }
}

public struct SecondCameraEditorPreferencesStub {}

public extension UIViewController {
    func secondCameraEditor_askForMediaLibraryPermissions(runIfGranted: @escaping () -> Void) {
        runIfGranted()
    }
}

public final class SecondCameraEditorAttachmentTextToolbar: UIView {
    public weak var delegate: SecondCameraEditorAttachmentTextToolbarDelegate?
    public init() { super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError() }
}

public protocol SecondCameraEditorAttachmentTextToolbarDelegate: AnyObject {}

public final class SecondCameraEditorExpandableContactListView: UIView {
    public init() { super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError() }
}

public struct SecondCameraEditorDBReadTransaction {}
public struct SecondCameraEditorDBWriteTransaction {}

public struct SecondCameraEditorKeyValueStore {
    nonisolated public init(collection: String) {}
    nonisolated public func getUInt(_ key: String, transaction: SecondCameraEditorDBReadTransaction) -> UInt? { nil }
    nonisolated public func setUInt(_ value: UInt, key: String, transaction: SecondCameraEditorDBWriteTransaction) {}
    nonisolated public func removeValue(forKey key: String, transaction: SecondCameraEditorDBWriteTransaction) {}
}
