//
// Signal Camera - stubs for Signal chat/business dependencies
//

import Foundation
import UIKit

// MARK: - Logger

public enum SecondCameraEditorLogger {
    nonisolated public static func verbose(_ logString: @autoclosure () -> String, file: String = #fileID, function: String = #function, line: Int = #line) {
        #if DEBUG
        print("[VERBOSE] \(logString())")
        #endif
    }
    nonisolated public static func debug(_ logString: @autoclosure () -> String, file: String = #fileID, function: String = #function, line: Int = #line) {
        #if DEBUG
        print("[DEBUG] \(logString())")
        #endif
    }
    nonisolated public static func info(_ logString: @autoclosure () -> String, file: String = #fileID, function: String = #function, line: Int = #line) {
        print("[INFO] \(logString())")
    }
    nonisolated public static func warn(_ logString: @autoclosure () -> String, file: String = #fileID, function: String = #function, line: Int = #line) {
        print("[WARN] \(logString())")
    }
    nonisolated public static func error(_ logString: @autoclosure () -> String, file: String = #fileID, function: String = #function, line: Int = #line) {
        print("[ERROR] \(logString())")
    }
}

public struct SecondCameraEditorPrefixedLogger {
    private let prefix: String
    nonisolated public static func empty() -> SecondCameraEditorPrefixedLogger { SecondCameraEditorPrefixedLogger(prefix: "") }
    nonisolated public init(prefix: String) { self.prefix = prefix }
    nonisolated public func error(_ logString: @autoclosure () -> String, file: String = #fileID, function: String = #function, line: Int = #line) {
        let message = prefix.isEmpty ? logString() : "\(prefix): \(logString())"
        SecondCameraEditorLogger.error(message, file: file, function: function, line: line)
    }
    nonisolated public func flush() {}
}

// MARK: - Remote Config

public struct SecondCameraEditorRemoteConfig: Sendable {
    public static let current = SecondCameraEditorRemoteConfig()

    public var attachmentMaxEncryptedBytes: UInt64 { 100 * 1024 * 1024 }
    public var videoAttachmentMaxEncryptedBytes: UInt64 { 100 * 1024 * 1024 }
    public var attachmentMaxEncryptedReceiveBytes: UInt64 { 100 * 1024 * 1024 }

    nonisolated public func standardMediaQualityLevel(callingCode: Int?) -> SecondCameraEditorImageQualityLevel? {
        .two
    }
}

public struct SecondCameraEditorPaddingBucket {
    public let plaintextSize: UInt64
    public static func forEncryptedSizeLimit(_ limit: UInt64) -> SecondCameraEditorPaddingBucket {
        SecondCameraEditorPaddingBucket(plaintextSize: limit)
    }
}

// MARK: - Dependencies Bridge (stub)

public struct SecondCameraEditorDependenciesBridge: Sendable {
    nonisolated(unsafe) public static var shared = SecondCameraEditorDependenciesBridge()
    public var tsAccountManager = SecondCameraEditorTSAccountManagerStub()
    public var deviceSleepManager: SecondCameraEditorDeviceSleepManagerStub? = SecondCameraEditorDeviceSleepManagerStub()
}

public final class DeviceSleepBlockObject {
    public let blockReason: String

    public init(blockReason: String) {
        self.blockReason = blockReason
    }
}

@MainActor
public final class SecondCameraEditorDeviceSleepManagerStub: SecondCameraEditorDeviceSleepManager {
    public func addBlock(blockObject: DeviceSleepBlockObject) {}
    public func removeBlock(blockObject: DeviceSleepBlockObject) {}
}

public protocol SecondCameraEditorDeviceSleepManager {
    func addBlock(blockObject: DeviceSleepBlockObject)
    func removeBlock(blockObject: DeviceSleepBlockObject)
}

public struct SecondCameraEditorTSAccountManagerStub: Sendable {
    public var localIdentifiersWithMaybeSneakyTransaction: SecondCameraEditorLocalIdentifiers? { nil }
}

public struct SecondCameraEditorLocalIdentifiers: Sendable {}

// MARK: - SSK Environment (stub)

public struct SecondCameraEditorSSKEnvironment: Sendable {
    nonisolated(unsafe) public static var shared = SecondCameraEditorSSKEnvironment()
    public var phoneNumberUtilRef = SecondCameraEditorPhoneNumberUtilStub()
}

public struct SecondCameraEditorPhoneNumberUtilStub: Sendable {
    public func localCallingCode(localIdentifiers: SecondCameraEditorLocalIdentifiers) -> Int? { nil }
}

// MARK: - Preferences

public enum SecondCameraEditorPreferences {
    nonisolated(unsafe) public static var isFailDebugEnabled: Bool = false
    nonisolated public static func setIsFailDebugEnabled(_ value: Bool) { isFailDebugEnabled = value }
}

// MARK: - Debugger

nonisolated public func SecondCameraEditorIsDebuggerAttached() -> Bool {
    #if DEBUG
    return true
    #else
    return false
    #endif
}

nonisolated public func SecondCameraEditorTrapDebugger() {}

// MARK: - Database stubs

public struct SecondCameraEditorDatabaseError: Error {
    public enum ResultCode { case SQLITE_CORRUPT }
    public var resultCode: ResultCode { .SQLITE_CORRUPT }
    public var extendedResultCode: Int { 0 }
    public var grdbErrorForLogging: String { String(describing: self) }
}

public enum SecondCameraEditorDatabaseCorruptionState {
    public static func flagDatabaseAsCorrupted(userDefaults: UserDefaults) {}
}

// MARK: - Atomic types

public final class SecondCameraEditorAtomicBool: @unchecked Sendable {
    private nonisolated(unsafe) var value: Bool
    private nonisolated(unsafe) let lock = NSLock()

    nonisolated public init(_ initialValue: Bool, lock: NSLock) {
        self.value = initialValue
    }

    nonisolated public func get() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    nonisolated public func set(_ newValue: Bool) {
        lock.lock()
        defer { lock.unlock() }
        value = newValue
    }

    nonisolated public func tryToSetFlag() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if value { return false }
        value = true
        return true
    }
}

// MARK: - Dispatch helpers

public func SecondCameraEditorDispatchMainThreadSafe(_ block: @escaping () -> Void) {
    if Thread.isMainThread {
        block()
    } else {
        DispatchQueue.main.async(execute: block)
    }
}

// MARK: - LibSignalClient stubs

public struct SecondCameraEditorAciUuidPair {}
public struct SecondCameraEditorMessageBody {
    public init(text: String) { self.text = text }
    public var text: String
}

// MARK: - OWS Action Sheets

public enum SecondCameraEditorActionSheets {
    @MainActor
    public static func showActionSheet(
        title: String? = nil,
        message: String? = nil,
        buttonTitle: String,
        from viewController: UIViewController,
        completion: @escaping () -> Void,
    ) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: buttonTitle, style: .default) { _ in completion() })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        viewController.present(alert, animated: true)
    }

    @MainActor
    public static func showConfirmationAlert(
        title: String,
        message: String? = nil,
        proceedTitle: String,
        cancelTitle: String = SecondCameraEditorCommonStrings.cancelButton,
        from viewController: UIViewController,
        proceedAction: @escaping () -> Void,
    ) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: cancelTitle, style: .cancel))
        alert.addAction(UIAlertAction(title: proceedTitle, style: .default) { _ in proceedAction() })
        viewController.present(alert, animated: true)
    }

    @MainActor
    public static func showPendingChangesActionSheet(
        discardAction: @escaping () -> Void,
        from viewController: UIViewController? = nil,
    ) {
        guard let viewController else { return }
        let alert = UIAlertController(title: nil, message: "放弃未保存的更改？", preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "放弃更改", style: .destructive) { _ in discardAction() })
        alert.addAction(UIAlertAction(title: SecondCameraEditorCommonStrings.cancelButton, style: .cancel))
        viewController.present(alert, animated: true)
    }

    public static func showActionSheet(
        message: String,
        buttonAction: @escaping (SecondCameraEditorActionSheetAction) -> Void,
    ) {}

    public static func showActionSheet(
        title: String?,
        message: String?,
        buttonTitle: String,
        buttonAction: @escaping (SecondCameraEditorActionSheetAction) -> Void,
    ) {
        _ = title
        _ = message
        _ = buttonTitle
        _ = buttonAction
    }
}

// MARK: - User Error

public protocol SecondCameraEditorUserErrorDescriptionProvider {
    var localizedDescription: String { get }
}

// MARK: - OutgoingAttachmentLimits (stub)

public struct OutgoingAttachmentLimits: Sendable {
    public var maxPlaintextBytes: UInt64 { 100 * 1024 * 1024 }
    public var maxPlaintextVideoBytes: UInt64 { 100 * 1024 * 1024 }
    public var maxPlaintextAudioBytes: UInt64 { 100 * 1024 * 1024 }
    public var maxEncryptedBytes: UInt64 { 100 * 1024 * 1024 }
    public var maxEncryptedVideoBytes: UInt64 { 100 * 1024 * 1024 }

    public static let defaultLimits = OutgoingAttachmentLimits()
    public init() {}
}

// MARK: - MonotonicDate (stub)

public struct MonotonicDate: Sendable {
    private let value: UInt64

    public init() {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        value = mach_absolute_time()
    }

    public var nanoseconds: UInt64 { value }

    public static func - (lhs: MonotonicDate, rhs: MonotonicDate) -> MonotonicDateInterval {
        let diff = lhs.value > rhs.value ? lhs.value - rhs.value : 0
        return MonotonicDateInterval(nanoseconds: diff)
    }
}

public struct MonotonicDateInterval: Sendable {
    public let nanoseconds: UInt64
    public init(nanoseconds: UInt64) { self.nanoseconds = nanoseconds }
}

// MARK: - AVAssetExportSession.exportAsync

import AVFoundation

extension AVAssetExportSession {
    public func exportAsync(to outputURL: URL, as outputFileType: AVFileType) async throws {
        self.outputURL = outputURL
        self.outputFileType = outputFileType
        await export()
        if let error {
            throw error
        }
    }
}

// MARK: - NSTextStorage extensions

extension NSTextStorage {
    public var ows_entireRange: NSRange {
        NSRange(location: 0, length: length)
    }

    public func attributedString() -> NSAttributedString {
        NSAttributedString(attributedString: self)
    }
}
