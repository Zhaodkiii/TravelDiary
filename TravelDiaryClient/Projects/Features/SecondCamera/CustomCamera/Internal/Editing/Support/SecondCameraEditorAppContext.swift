//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import CoreGraphics
import Foundation
public import UIKit

public typealias SecondCameraEditorBackgroundTaskExpirationHandler = @Sendable () -> Void
public typealias SecondCameraEditorAppActiveBlock = @Sendable () -> Void

public enum SecondCameraEditorAppContextType: CaseIterable, CustomStringConvertible {
    case main
    case nse
    case share

    public var description: String {
        // This appears to be the default behavior but it's not actually specified by the swift documentation
        // so we make it explicit just to be sure.
        switch self {
        case .main:
            return "main"
        case .nse:
            return "nse"
        case .share:
            return "share"
        }
    }
}

public protocol SecondCameraEditorAppContext {
    nonisolated var type: SecondCameraEditorAppContextType { get }
    var isMainAppAndActive: Bool { get }
    @MainActor
    var isMainAppAndActiveIsolated: Bool { get }
    /// Whether the user is using a right-to-left language like Arabic.
    nonisolated var isRTL: Bool { get }
    var isRunningTests: Bool { get }
    var mainWindow: UIWindow? { get set }
    var frame: CGRect { get }

    /// Unlike UIApplication.applicationState, this is thread-safe.
    /// It contains the "last known" application state.
    ///
    /// Because it is updated in response to "will/did-style" events, it is
    /// conservative and skews toward less-active and not-foreground:
    ///
    /// * It doesn't report "is active" until the app is active
    ///   and reports "inactive" as soon as it _will become_ inactive.
    /// * It doesn't report "is foreground (but inactive)" until the app is
    ///   foreground & inactive and reports "background" as soon as it _will
    ///   enter_ background.
    ///
    /// This conservatism is useful, since we want to err on the side of
    /// caution when, for example, we do work that should only be done
    /// when the app is foreground and active.
    var reportedApplicationState: UIApplication.State { get }

    /// A convenience accessor for reportedApplicationState.
    ///
    /// This method is thread-safe.
    func isInBackground() -> Bool

    /// A convenience accessor for reportedApplicationState.
    ///
    /// This method is thread-safe.
    func isAppForegroundAndActive() -> Bool

    /// Should start a background task if isMainApp is YES.
    /// Should just return UIBackgroundTaskInvalid if isMainApp is NO.
    func beginBackgroundTask(with expirationHandler: @escaping SecondCameraEditorBackgroundTaskExpirationHandler) -> UIBackgroundTaskIdentifier

    /// Should be a NOOP if isMainApp is NO.
    func endBackgroundTask(_ backgroundTaskIdentifier: UIBackgroundTaskIdentifier)

    /// Returns the VC that should be used to present alerts, modals, etc.
    func frontmostViewController() -> UIViewController?
    func openSystemSettings()
    func open(_ url: URL, completion: ((_ success: Bool) -> Void)?)
    func runNowOrWhenMainAppIsActive(_ block: @escaping SecondCameraEditorAppActiveBlock)

    var appLaunchTime: Date { get }

    func appDocumentDirectoryPath() -> String

    func appSharedDataDirectoryPath() -> String

    func appDatabaseBaseDirectoryPath() -> String
    func appUserDefaults() -> UserDefaults

    /// This method should only be called by the main app.
    func mainApplicationStateOnLaunch() -> UIApplication.State
    func canPresentNotifications() -> Bool
    var shouldProcessIncomingMessages: Bool { get }
    var hasUI: Bool { get }
    var debugLogsDirPath: String { get }
}

extension SecondCameraEditorAppContext {
    nonisolated public var isMainApp: Bool {
        return switch type {
        case .main: true
        case .nse, .share: false
        }
    }

    nonisolated public var isNSE: Bool {
        switch type {
        case .nse: true
        case .main, .share: false
        }
    }

    nonisolated public var isShareExtension: Bool {
        switch type {
        case .share: true
        case .main, .nse: false
        }
    }
}

// MARK: -

public final class SecondCameraEditorAppContextObjCBridge: NSObject, @unchecked Sendable {
    @objc
    @available(swift, obsoleted: 1)
    public static let shared = SecondCameraEditorAppContextObjCBridge()

    private var appContext: any SecondCameraEditorAppContext {
        SecondCameraEditorCurrentAppContext()
    }

    override private init() {}

    @objc
    public var isRunningTests: Bool {
        appContext.isRunningTests
    }
}

// MARK: -

// These are fired whenever the corresponding "main app" or "app extension"
// notification is fired.
//
// 1. This saves you the work of observing both.
// 2. This allows us to ensure that any critical work (e.g. re-opening
//    databases) has been done before app re-enters foreground, etc.
public extension Notification.Name {
    // TODO: Rename this to a more swift style name
    nonisolated(unsafe) static let SecondCameraEditorApplicationDidEnterBackground = Notification.Name("SecondCameraEditorApplicationDidEnterBackgroundNotification")
    nonisolated(unsafe) static let SecondCameraEditorApplicationWillEnterForeground = Notification.Name("SecondCameraEditorApplicationWillEnterForegroundNotification")
    nonisolated(unsafe) static let SecondCameraEditorApplicationWillResignActive = Notification.Name("SecondCameraEditorApplicationWillResignActiveNotification")
    nonisolated(unsafe) static let SecondCameraEditorApplicationDidBecomeActive = Notification.Name("SecondCameraEditorApplicationDidBecomeActiveNotification")
}

// MARK: -

private nonisolated(unsafe) var currentSecondCameraEditorAppContext: (any SecondCameraEditorAppContext)?

nonisolated public func SecondCameraEditorCurrentAppContextIfAvailable() -> (any SecondCameraEditorAppContext)? {
    currentSecondCameraEditorAppContext
}

nonisolated public func SecondCameraEditorCurrentAppContext() -> any SecondCameraEditorAppContext {
    guard let currentSecondCameraEditorAppContext else {
        preconditionFailure(
            "SecondCameraEditorAppContext is nil. Call SecondCameraEditorAppContextImplBootstrap.bootstrapIfNeeded() before using SecondCamera editing APIs."
        )
    }
    return currentSecondCameraEditorAppContext
}

nonisolated public func SetSecondCameraEditorCurrentAppContext(_ appContext: any SecondCameraEditorAppContext, isRunningTests: Bool) {
    secondCameraEditorPrecondition(currentSecondCameraEditorAppContext == nil || isRunningTests)
    currentSecondCameraEditorAppContext = appContext
}
