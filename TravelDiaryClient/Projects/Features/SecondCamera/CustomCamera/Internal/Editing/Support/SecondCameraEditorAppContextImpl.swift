//
// Signal Camera - Main App Context implementation
//

import Foundation
import UIKit

public final class SecondCameraEditorAppContextImpl: SecondCameraEditorAppContext {
    nonisolated public let type: SecondCameraEditorAppContextType = .main
    public var isMainAppAndActive: Bool { UIApplication.shared.applicationState == .active }
    @MainActor
    public var isMainAppAndActiveIsolated: Bool { UIApplication.shared.applicationState == .active }
    nonisolated public var isRTL: Bool { UIApplication.shared.userInterfaceLayoutDirection == .rightToLeft }
    public var isRunningTests: Bool { false }
    public var mainWindow: UIWindow?
    public var frame: CGRect { UIScreen.main.bounds }
    public var reportedApplicationState: UIApplication.State { UIApplication.shared.applicationState }

    public func isInBackground() -> Bool { reportedApplicationState == .background }
    public func isAppForegroundAndActive() -> Bool { reportedApplicationState == .active }

    public func beginBackgroundTask(with expirationHandler: @escaping SecondCameraEditorBackgroundTaskExpirationHandler) -> UIBackgroundTaskIdentifier {
        UIApplication.shared.beginBackgroundTask(expirationHandler: expirationHandler)
    }

    public func endBackgroundTask(_ backgroundTaskIdentifier: UIBackgroundTaskIdentifier) {
        UIApplication.shared.endBackgroundTask(backgroundTaskIdentifier)
    }

    public func frontmostViewController() -> UIViewController? {
        guard let window = mainWindow ?? {
            for scene in UIApplication.shared.connectedScenes {
                guard let windowScene = scene as? UIWindowScene else { continue }
                if let key = windowScene.windows.first(where: { $0.isKeyWindow }) {
                    return key
                }
            }
            return nil
        }() else {
            return nil
        }
        var top = window.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        if let nav = top as? UINavigationController {
            return nav.visibleViewController ?? nav
        }
        return top
    }

    public func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        open(url, completion: nil)
    }

    public func open(_ url: URL, completion: ((Bool) -> Void)?) {
        UIApplication.shared.open(url, options: [:], completionHandler: completion)
    }

    public func runNowOrWhenMainAppIsActive(_ block: @escaping SecondCameraEditorAppActiveBlock) {
        if isMainAppAndActive {
            block()
        } else {
            DispatchQueue.main.async(execute: block)
        }
    }

    public let appLaunchTime = Date()

    public func appDocumentDirectoryPath() -> String {
        let directory = StoragePaths.system.persistent("CameraEditor")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.path
    }

    public func appSharedDataDirectoryPath() -> String {
        appDocumentDirectoryPath()
    }

    public func appDatabaseBaseDirectoryPath() -> String {
        appDocumentDirectoryPath()
    }

    public func appUserDefaults() -> UserDefaults { .standard }

    public func mainApplicationStateOnLaunch() -> UIApplication.State {
        UIApplication.shared.applicationState
    }

    public func canPresentNotifications() -> Bool { true }
    public var shouldProcessIncomingMessages: Bool { false }
    public var hasUI: Bool { true }
    public var debugLogsDirPath: String { appDocumentDirectoryPath() }
}

public enum SecondCameraEditorAppContextImplBootstrap {
    private nonisolated(unsafe) static var didBootstrap = false

    public static func bootstrapIfNeeded() {
        guard !didBootstrap else { return }
        didBootstrap = true
        SetSecondCameraEditorCurrentAppContext(SecondCameraEditorAppContextImpl(), isRunningTests: false)
    }
}
