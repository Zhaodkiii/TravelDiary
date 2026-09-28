//
//  CustomCameraManager+NotificationCenter.swift of MijickCamera
//
//  Created by Tomasz Kurylik. Sending ❤️ from Kraków!
//    - Mail: tomasz.kurylik@mijick.com
//    - GitHub: https://github.com/FulcrumOne
//    - Medium: https://medium.com/@mijick
//
//  Copyright ©2024 Mijick. All rights reserved.




import AVFoundation
import Combine
import Foundation

@MainActor class CustomCameraManagerNotificationCenter {
    private(set) var parent: CustomCameraManager!
    private var observedSession: (any CaptureSession)?
}

// MARK: Setup
extension CustomCameraManagerNotificationCenter {
    func setup(parent: CustomCameraManager) {
        reset()
        self.parent = parent
        let session = parent.captureSession
        observedSession = session

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSessionWasInterrupted),
            name: .AVCaptureSessionWasInterrupted,
            object: session
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSessionInterruptionEnded),
            name: .AVCaptureSessionInterruptionEnded,
            object: session
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSessionRuntimeError),
            name: .AVCaptureSessionRuntimeError,
            object: session
        )
    }
}
private extension CustomCameraManagerNotificationCenter {
    @objc func handleSessionWasInterrupted(_ notification: Notification) {
        parent.attributes.lightMode = .off
        parent.attributes.isSessionReady = false
        parent.attributes.sessionState = .interrupted
        parent.videoOutput.reset()

        SparkLogger.log(
            level: .info,
            module: .camera,
            message: "CustomCameraManager: AVCaptureSessionWasInterrupted state=\(parent.attributes.sessionState) ready=\(parent.attributes.isSessionReady) running=\(parent.captureSession.isRunning)"
        )
    }

    @objc func handleSessionInterruptionEnded(_ notification: Notification) {
        SparkLogger.log(
            level: .info,
            module: .camera,
            message: "CustomCameraManager: AVCaptureSessionInterruptionEnded state=\(parent.attributes.sessionState) ready=\(parent.attributes.isSessionReady) running=\(parent.captureSession.isRunning)"
        )

        Task { await parent.resumeFromForegroundIfNeeded() }
    }

    @objc func handleSessionRuntimeError(_ notification: Notification) {
        parent.attributes.isSessionReady = false
        parent.attributes.sessionState = .failed

        SparkLogger.log(
            level: .error,
            module: .camera,
            message: "CustomCameraManager: AVCaptureSessionRuntimeError state=\(parent.attributes.sessionState) ready=\(parent.attributes.isSessionReady) running=\(parent.captureSession.isRunning)"
        )

        Task { await parent.rebuildSessionAfterRuntimeErrorIfNeeded() }
    }
}

// MARK: Reset
extension CustomCameraManagerNotificationCenter {
    func reset() {
        guard let observedSession else { return }

        NotificationCenter.default.removeObserver(self, name: .AVCaptureSessionWasInterrupted, object: observedSession)
        NotificationCenter.default.removeObserver(self, name: .AVCaptureSessionInterruptionEnded, object: observedSession)
        NotificationCenter.default.removeObserver(self, name: .AVCaptureSessionRuntimeError, object: observedSession)
        self.observedSession = nil
    }
}
