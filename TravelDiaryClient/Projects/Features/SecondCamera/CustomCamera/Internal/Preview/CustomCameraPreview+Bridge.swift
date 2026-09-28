//
//  CameraView+Bridge.swift of MijickCamera
//
//  Created by Tomasz Kurylik. Sending ❤️ from Kraków!
//    - Mail: tomasz.kurylik@mijick.com
//    - GitHub: https://github.com/FulcrumOne
//    - Medium: https://medium.com/@mijick
//
//  Copyright ©2024 Mijick. All rights reserved.




import AVFoundation
import MetalKit
import SwiftUI

struct CameraBridgeView: UIViewRepresentable {
    let cameraManager: CustomCameraManager
    let inputView: CameraBridgeContainerView = .init()
}
extension CameraBridgeView {
    func makeUIView(context: Context) -> some UIView {
        // Layout callbacks must only update UIKit frames — never `@Published` state.
        inputView.onLayoutSubviews = { [cameraManager] view in
            cameraManager.updatePreviewLayout(in: view)
        }
        // `initialize(in:)` binds the container and may schedule deferred `@Published` updates.
        cameraManager.initialize(in: inputView)
        cameraManager.updatePreviewLayout(in: inputView)
        setupTapGesture(context)
        setupPinchGesture(context)
        return inputView
    }
    func updateUIView(_ uiView: UIViewType, context: Context) {
        // UIKit layout only — must not mutate `@Published` attributes here.
        cameraManager.updatePreviewLayout(in: uiView)
    }
    func makeCoordinator() -> Coordinator { .init(self) }
}
private extension CameraBridgeView {
    func setupTapGesture(_ context: Context) {
        let tapRecognizer = UITapGestureRecognizer(target: context.coordinator, action: #selector(context.coordinator.onTapGesture))
        inputView.addGestureRecognizer(tapRecognizer)
    }
    func setupPinchGesture(_ context: Context) {
        let pinchRecognizer = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(context.coordinator.onPinchGesture))
        inputView.addGestureRecognizer(pinchRecognizer)
    }
}

// MARK: Equatable
extension CameraBridgeView: Equatable {
    nonisolated static func ==(lhs: Self, rhs: Self) -> Bool { true }
}

final class CameraBridgeContainerView: UIView {
    var onLayoutSubviews: ((UIView) -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayoutSubviews?(self)
    }
}


// MARK: - GESTURES
extension CameraBridgeView { class Coordinator: NSObject { init(_ parent: CameraBridgeView) { self.parent = parent }
    let parent: CameraBridgeView
}}

// MARK: On Tap
extension CameraBridgeView.Coordinator {
    @MainActor @objc func onTapGesture(_ tap: UITapGestureRecognizer) {
        do {
            let touchPoint = tap.location(in: parent.inputView)
            try parent.cameraManager.setCameraFocus(at: touchPoint)
        } catch {}
    }
}

// MARK: On Pinch
extension CameraBridgeView.Coordinator {
    @MainActor @objc func onPinchGesture(_ pinch: UIPinchGestureRecognizer) { if pinch.state == .changed {
        do {
            let desiredZoomFactor = parent.cameraManager.attributes.zoomFactor + atan2(pinch.velocity, 33)
            try parent.cameraManager.setCameraZoomFactor(desiredZoomFactor)
            SparkLogger.log(
                level: .debug,
                module: .camera,
                message: "SecondCamera pinch zoom=\(parent.cameraManager.attributes.zoomFactor)"
            )
        } catch {}
    }}
}
