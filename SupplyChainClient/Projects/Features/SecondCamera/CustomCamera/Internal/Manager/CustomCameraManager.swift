//
//  CustomCameraManager.swift of MijickCamera
//
//  Created by Tomasz Kurylik. Sending ❤️ from Kraków!
//    - Mail: tomasz.kurylik@mijick.com
//    - GitHub: https://github.com/FulcrumOne
//    - Medium: https://medium.com/@mijick
//
//  Copyright ©2024 Mijick. All rights reserved.




import AVFoundation
import AVKit
import Combine
import CoreImage
import Dispatch
import MetalKit
import SwiftUI

@MainActor
final class CustomCameraManager: NSObject, ObservableObject {
    @Published var attributes: CustomCameraManagerAttributes = .init()

    // MARK: Input
    private(set) var captureSession: any CaptureSession
    private(set) var frontCameraInput: (any CaptureDeviceInput)?
    private(set) var backCameraInput: (any CaptureDeviceInput)?

    // MARK: Output
    private(set) var photoOutput: CustomCameraManagerPhotoOutput = .init()
    private(set) var videoOutput: CustomCameraManagerVideoOutput = .init()

    // MARK: UI Elements
    private(set) var cameraView: UIView!
    private(set) var cameraLayer: AVCaptureVideoPreviewLayer = .init()
    private(set) var cameraMetalView: CameraMetalView = .init()
    private(set) var cameraGridView: CameraGridView = .init()

    // MARK: Others
    private(set) var permissionsManager: CustomCameraManagerPermissionsManager = .init()
    private(set) var motionManager: CustomCameraManagerMotionManager = .init()
    private(set) var notificationCenterManager: CustomCameraManagerNotificationCenter = .init()

    /// 取景框相对「预览视图」的归一化矩形（0...1）。设置后，拍摄到的照片会被裁剪到该范围内。
    /// 为 `nil` 时不裁剪（输出完整照片）。该值不参与 UI 刷新，故独立于 `attributes` 存储。
    ///
    /// 使用归一化比例（而非绝对坐标）可确保各拍摄方向下裁剪都正确：比例在 SwiftUI 坐标系内计算，
    /// 裁剪时再按当前预览实际尺寸还原，天然兼容竖屏 / 横屏。
    private(set) var captureViewfinderNormalizedRect: CGRect?

    private(set) var isAppBackgrounding = false
    private var isResumingSession = false

    // MARK: Initializer
    init<CS: CaptureSession, CDI: CaptureDeviceInput>(captureSession: CS, captureDeviceInputType: CDI.Type) {
        self.captureSession = captureSession
        self.frontCameraInput = CDI.get(mediaType: .video, position: .front)
        self.backCameraInput = CDI.get(mediaType: .video, position: .back)
        super.init()
    }
}

// MARK: Initialize
extension CustomCameraManager {
    /// Bind preview container. Must not synchronously mutate `@Published` —
    /// `makeUIView` / `updateUIView` / `layoutSubviews` may call this during a SwiftUI view update.
    func initialize(in view: UIView) {
        cameraView = view
        SparkLogger.log(
            level: .info,
            module: .camera,
            message: "CustomCameraManager: initialize bind cameraView"
        )
        if captureSession.isRunning, photoOutput.parent != nil {
            resumePreviewUI()
            scheduleSessionReadyPublish()
        }
        updatePreviewLayout(in: view)
    }
}

private extension CustomCameraManager {
    /// Defer `@Published` writes until after the current SwiftUI view-update stack unwinds.
    func scheduleSessionReadyPublish() {
        SparkLogger.log(
            level: .info,
            module: .camera,
            message: "CustomCameraManager: schedule session ready publish"
        )
        Task { @MainActor in
            await Task.yield()
            attributes.sessionState = .running
            attributes.isSessionReady = true
            SparkLogger.log(
                level: .info,
                module: .camera,
                message: "CustomCameraManager: session ready published after view update"
            )
        }
    }
}

// MARK: Setup
extension CustomCameraManager {
    func setup() async throws(CustomCameraError) {
        // 内置确认页重拍等场景会再次触发 onCameraAppear → setup()；
        // session 仍在运行时跳过重复初始化，避免 PhotoOutput 与 Fig session 脱节。
        if captureSession.isRunning, photoOutput.parent != nil {
            SparkLogger.log(
                level: .info,
                module: .camera,
                message: "CustomCameraManager: 跳过初始化，采集会话已在运行"
            )
            resumePreviewUI()
            attributes.sessionState = .running
            attributes.isSessionReady = true
            attributes.error = nil
            return
        }

        SparkLogger.log(
            level: .info,
            module: .camera,
            message: "CustomCameraManager: 开始初始化 output=\(attributes.outputType) position=\(attributes.cameraPosition) audio=\(attributes.isAudioSourceAvailable)"
        )
        attributes.sessionState = .starting
        attributes.isSessionReady = false
        attributes.error = nil

        try await permissionsManager.requestAccess(parent: self)

        setupCameraLayer()
        try setupDeviceInputs()
        try setupDeviceOutput()
        try setupFrameRecorder()
        notificationCenterManager.setup(parent: self)
        motionManager.setup(parent: self)
        try cameraMetalView.setup(parent: self)
        cameraGridView.setup(parent: self)

        startSession()
    }
}
private extension CustomCameraManager {
    /// 确认页重拍后 SwiftUI 会创建新的 `cameraView`，需把预览子视图重新挂回当前容器。
    func resumePreviewUI() {
        guard let cameraView else { return }

        cameraMetalView.removeFromSuperview()
        cameraGridView.removeFromSuperview()
        cameraLayer.removeFromSuperlayer()

        cameraMetalView.addToParent(cameraView)
        cameraGridView.parent = self
        cameraGridView.alpha = attributes.isGridVisible ? 1 : 0
        cameraGridView.addToParent(cameraView)

        cameraLayer.session = captureSession as? AVCaptureSession
        cameraLayer.videoGravity = .resizeAspectFill
        cameraLayer.isHidden = true
        cameraView.layer.addSublayer(cameraLayer)
        cameraMetalView.isHidden = false
        updatePreviewLayout(in: cameraView)
        cameraView.alpha = 1

        SparkLogger.log(
            level: .info,
            module: .camera,
            message: "CustomCameraManager: 恢复预览 UI，将 metal/grid/layer 重新绑定到 cameraView"
        )
    }

    func setupCameraLayer() {
        captureSession.sessionPreset = attributes.resolution

        cameraLayer.session = captureSession as? AVCaptureSession
        cameraLayer.videoGravity = .resizeAspectFill
        cameraLayer.isHidden = true
        cameraView.layer.addSublayer(cameraLayer)
        updatePreviewLayout(in: cameraView)
    }
    func setupDeviceInputs() throws(CustomCameraError) {
        try captureSession.add(input: getCameraInput())
        if let audioInput = getAudioInput() { try captureSession.add(input: audioInput) }
    }
    func setupDeviceOutput() throws(CustomCameraError) {
        try photoOutput.setup(parent: self)
        try videoOutput.setup(parent: self)
    }
    func setupFrameRecorder() throws(CustomCameraError) {
        let captureVideoOutput = AVCaptureVideoDataOutput()
        captureVideoOutput.setSampleBufferDelegate(cameraMetalView, queue: .main)

        try captureSession.add(output: captureVideoOutput)
    }
    func startSession() { Task {
        guard let device = getCameraInput()?.device else {
            SparkLogger.log(
                level: .error,
                module: .camera,
                message: "CustomCameraManager: 启动会话中止，position=\(attributes.cameraPosition) 无摄像头输入"
            )
            attributes.isSessionReady = false
            attributes.sessionState = .failed
            return
        }

        do {
            SparkLogger.log(
                level: .info,
                module: .camera,
                message: "CustomCameraManager: 开始启动会话 position=\(attributes.cameraPosition) preset=\(attributes.resolution.rawValue)"
            )
            try await startCaptureSession()
            SparkLogger.log(
                level: .info,
                module: .camera,
                message: "CustomCameraManager: 采集会话运行状态 running=\(captureSession.isRunning)"
            )
            guard captureSession.isRunning else {
                attributes.sessionState = .failed
                attributes.isSessionReady = false
                attributes.error = .cannotSetupOutput
                SparkLogger.log(
                    level: .error,
                    module: .camera,
                    message: "CustomCameraManager: 启动会话失败，startRunning 后采集会话未运行"
                )
                return
            }
            try setupDevice(device)
            try applyDefaultWideZoomPreset()
            resetAttributes(device: device)
            logAvailableZoomPresets()
            attributes.sessionState = .running
            attributes.isSessionReady = true
            SparkLogger.log(
                level: .info,
                module: .camera,
                message: "CustomCameraManager: 会话就绪 hasFlash=\(hasFlash) hasLight=\(hasLight) outputType=\(attributes.outputType)"
            )
            cameraMetalView.performCameraEntranceAnimation()
        } catch {
            attributes.sessionState = .failed
            attributes.isSessionReady = false
            attributes.error = error as? CustomCameraError
            SparkLogger.log(
                level: .error,
                module: .camera,
                message: "CustomCameraManager: 启动会话失败 error=\(String(describing: error))"
            )
        }
    }}
}
private extension CustomCameraManager {
    func getAudioInput() -> (any CaptureDeviceInput)? {
        guard attributes.isAudioSourceAvailable,
              let deviceInput = frontCameraInput ?? backCameraInput
        else { return nil }

        let captureDeviceInputType = type(of: deviceInput)
        let audioInput = captureDeviceInputType.get(mediaType: .audio, position: .unspecified)
        return audioInput
    }
    func startCaptureSession() async throws {
        let captureSession = captureSession

        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                SparkLogger.log(
                    level: .info,
                    module: .camera,
                    message: "CustomCameraManager: AVCaptureSession.startRunning 开始 backgroundThread=\(!Thread.isMainThread)"
                )
                captureSession.startRunning()
                SparkLogger.log(
                    level: .info,
                    module: .camera,
                    message: "CustomCameraManager: AVCaptureSession.startRunning 完成 isRunning=\(captureSession.isRunning)"
                )
                continuation.resume()
            }
        }
    }
    func setupDevice(_ device: any CaptureDevice) throws {
        try device.lockForConfiguration()
        device.setExposureMode(attributes.cameraExposure.mode, duration: attributes.cameraExposure.duration, iso: attributes.cameraExposure.iso)
        device.setExposureTargetBias(attributes.cameraExposure.targetBias)
        device.setFrameRate(attributes.frameRate)
        device.setLightMode(attributes.lightMode)
        device.hdrMode = attributes.hdrMode
        device.unlockForConfiguration()
    }
}

extension CustomCameraManager {
    /// Must not mutate `@Published` state. Called during UIView layout / SwiftUI view updates.
    func updatePreviewLayout(in view: UIView? = nil) {
        let targetView = view ?? cameraView
        guard let targetView else { return }

        let bounds = targetView.bounds
        guard bounds.isEmpty == false else { return }

        cameraLayer.frame = bounds
        if cameraLayer.superlayer !== targetView.layer {
            cameraLayer.removeFromSuperlayer()
            targetView.layer.insertSublayer(cameraLayer, at: 0)
        }

        cameraLayer.isHidden = true
        cameraMetalView.isHidden = false
    }
}

// MARK: Cancel
extension CustomCameraManager {
    func cancel() {
        SparkLogger.log(
            level: .info,
            module: .camera,
            message: "CustomCameraManager: 取消 ready=\(attributes.isSessionReady) running=\(captureSession.isRunning) state=\(attributes.sessionState)"
        )
        isAppBackgrounding = false
        attributes.sessionState = .idle
        attributes.isSessionReady = false
        attributes.multiCaptureStore.clear()
        attributes.capturedMedia = nil
        notificationCenterManager.reset()
        captureSession = captureSession.stopRunningAndReturnNewInstance()
        motionManager.reset()
        videoOutput.reset()
    }
}

// MARK: Lifecycle
extension CustomCameraManager {
    var shouldCancelWhenViewDisappears: Bool {
        !isAppBackgrounding
    }

    func prepareForInactive() {
        SparkLogger.log(
            level: .info,
            module: .camera,
            message: "CustomCameraManager: prepareForInactive state=\(attributes.sessionState) ready=\(attributes.isSessionReady) running=\(captureSession.isRunning)"
        )

        guard isAppBackgrounding else { return }
        Task { await resumeFromForegroundIfNeeded() }
    }

    func pauseForBackground() {
        guard attributes.sessionState != .backgrounded else { return }

        isAppBackgrounding = true
        attributes.sessionState = .backgrounded
        attributes.isSessionReady = false
        videoOutput.reset()
        attributes.lightMode = .off

        SparkLogger.log(
            level: .info,
            module: .camera,
            message: "CustomCameraManager: pauseForBackground state=\(attributes.sessionState) ready=\(attributes.isSessionReady) running=\(captureSession.isRunning)"
        )
    }

    func resumeFromForegroundIfNeeded() async {
        guard !isResumingSession else { return }

        let shouldResume = switch attributes.sessionState {
        case .backgrounded, .interrupted, .resuming, .failed:
            true
        case .running:
            !attributes.isSessionReady
        case .idle, .starting:
            false
        }

        guard shouldResume else { return }

        isResumingSession = true
        defer { isResumingSession = false }

        isAppBackgrounding = false
        attributes.sessionState = .resuming
        attributes.isSessionReady = false

        SparkLogger.log(
            level: .info,
            module: .camera,
            message: "CustomCameraManager: resumeFromForeground state=\(attributes.sessionState) ready=\(attributes.isSessionReady) running=\(captureSession.isRunning)"
        )

        if captureSession.isRunning, photoOutput.parent != nil {
            resumePreviewUI()
            attributes.sessionState = .running
            attributes.isSessionReady = true
            attributes.error = nil

            SparkLogger.log(
                level: .info,
                module: .camera,
                message: "CustomCameraManager: resumeFromForeground completed with existing session state=\(attributes.sessionState) ready=\(attributes.isSessionReady) running=\(captureSession.isRunning)"
            )
            return
        }

        do {
            try await setup()
        } catch {
            attributes.sessionState = .failed
            attributes.isSessionReady = false
            attributes.error = error

            SparkLogger.log(
                level: .error,
                module: .camera,
                message: "CustomCameraManager: resumeFromForeground failed error=\(String(describing: error))"
            )
        }
    }

    func rebuildSessionAfterRuntimeErrorIfNeeded() async {
        guard attributes.sessionState == .failed else { return }

        SparkLogger.log(
            level: .info,
            module: .camera,
            message: "CustomCameraManager: rebuildSessionAfterRuntimeError state=\(attributes.sessionState) running=\(captureSession.isRunning)"
        )

        attributes.sessionState = .idle
        attributes.isSessionReady = false
        notificationCenterManager.reset()
        captureSession = captureSession.stopRunningAndReturnNewInstance()
        motionManager.reset()
        videoOutput.reset()

        do {
            try await setup()
        } catch {
            attributes.sessionState = .failed
            attributes.isSessionReady = false
            attributes.error = error

            SparkLogger.log(
                level: .error,
                module: .camera,
                message: "CustomCameraManager: rebuildSessionAfterRuntimeError failed error=\(String(describing: error))"
            )
        }
    }
}


// MARK: - LIVE ACTIONS



// MARK: Capture Output
extension CustomCameraManager {
    func captureOutput() {
        SparkLogger.log(
            level: .info,
            module: .camera,
            message: "CustomCameraManager: 请求采集输出 ready=\(attributes.isSessionReady) isChanging=\(isChanging) outputType=\(attributes.outputType)"
        )

        guard attributes.isSessionReady else {
            SparkLogger.log(
                level: .warning,
                module: .camera,
                message: "CustomCameraManager: 忽略采集输出，会话未就绪 error=\(String(describing: attributes.error))"
            )
            return
        }

        guard !isChanging else {
            SparkLogger.log(
                level: .warning,
                module: .camera,
                message: "CustomCameraManager: 忽略采集输出，摄像头切换动画进行中"
            )
            return
        }

        switch attributes.outputType {
            case .photo: photoOutput.capture()
            case .video: videoOutput.toggleRecording()
        }
    }
}

// MARK: Set Captured Media
extension CustomCameraManager {
    /// 仅控制预览门闩。`nil` 回到相机页，不清空多图队列。
    func setCapturedMedia(_ capturedMedia: CustomCameraMedia?) { withAnimation(.mSpring) {
        SparkLogger.log(
            level: .info,
            module: .camera,
            message: "CustomCameraManager: 设置已采集媒体门闩 hasMedia=\(capturedMedia != nil) storeCount=\(attributes.multiCaptureStore.count)"
        )
        attributes.capturedMedia = capturedMedia
    }}

    /// 拍照：追加到多图队列并进入预览。
    func presentCapturedMedia(_ media: CustomCameraMedia) { withAnimation(.mSpring) {
        SparkLogger.log(
            level: .info,
            module: .camera,
            message: "CustomCameraManager: 追加并进入预览 hasImage=\(media.getImage() != nil) hasVideo=\(media.getVideo() != nil) storeCount=\(attributes.multiCaptureStore.count)"
        )
        attributes.multiCaptureStore.appendCamera(media)
        attributes.capturedMedia = media
    }}

    /// 相册多选：按选择顺序全部追加，并以选中项作为预览门闩。
    func presentPickedMedia(_ picked: [SecondCameraPickedMedia]) { withAnimation(.mSpring) {
        let before = attributes.multiCaptureStore.count
        attributes.multiCaptureStore.appendLibrary(picked)
        guard let selected = attributes.multiCaptureStore.selectedItem?.media else {
            SparkLogger.log(
                level: .warning,
                module: .camera,
                message: "CustomCameraManager: 相册进入预览失败 selectedCount=\(picked.count) before=\(before)"
            )
            return
        }
        SparkLogger.log(
            level: .info,
            module: .camera,
            message: "CustomCameraManager: 相册追加并进入预览 selectedCount=\(picked.count) before=\(before) after=\(attributes.multiCaptureStore.count) hasImage=\(selected.getImage() != nil) hasVideo=\(selected.getVideo() != nil)"
        )
        attributes.capturedMedia = selected
    }}

    /// 视频成片替换当前选中项（先帧后视频），避免重复入队。
    func replacePresentedCapturedMedia(_ media: CustomCameraMedia) { withAnimation(.mSpring) {
        if let selectedID = attributes.multiCaptureStore.selectedID {
            attributes.multiCaptureStore.updateItem(id: selectedID) { item in
                item.media = media
                item.editableImage = media.getImage()
                item.renderedPreviewImage = media.getImage()
                item.thumbnail = SecondCameraPreviewThumbnailBuilder.makeThumbnail(from: media)
                item.editorModel = nil
                item.approvalItem = nil
            }
        } else {
            attributes.multiCaptureStore.appendCamera(media)
        }
        attributes.capturedMedia = media
    }}

    /// 放弃或完成整个预览会话：清空队列并回到相机。
    func clearCapturedMediaSession() { withAnimation(.mSpring) {
        SparkLogger.log(
            level: .info,
            module: .camera,
            message: "CustomCameraManager: 清空多图预览会话 storeCount=\(attributes.multiCaptureStore.count)"
        )
        attributes.multiCaptureStore.clear()
        attributes.capturedMedia = nil
    }}
}

// MARK: Capture Viewfinder Crop
extension CustomCameraManager {
    /// 设置取景框相对预览视图的归一化矩形（0...1）。传入 `nil` 表示不裁剪。
    func setCaptureViewfinderNormalizedRect(_ rect: CGRect?) {
        captureViewfinderNormalizedRect = rect
    }

    /// 在「预览坐标系」的 `CIImage` 上裁剪到取景框范围；未设置取景框时原样返回。
    ///
    /// 传入的 `ciImage` 须已与实时预览同向（`oriented(.up).oriented(frameOrientation)`）。
    /// 直接在成片上按 aspect-fill 映射取景框，避免用预览帧缩放（预览流与成片宽高比不同会导致竖屏偏移）。
    func cropCIImageToViewfinderIfNeeded(_ ciImage: CIImage) -> CIImage {
        guard let cameraView,
              let viewfinderRect = viewfinderRectInPreviewBounds()
        else { return ciImage }

        let cropped = CameraCaptureCropper.crop(
            ciImage,
            viewfinderRect: viewfinderRect,
            containerBounds: cameraView.bounds,
            videoGravity: cameraLayer.videoGravity
        )

        SparkLogger.log(
            level: .info,
            module: .camera,
            message: "CustomCameraManager: 裁剪 CIImage 至取景框 original=\(Int(ciImage.extent.width))x\(Int(ciImage.extent.height)) cropped=\(Int(cropped.extent.width))x\(Int(cropped.extent.height))"
        )
        return cropped
    }

    /// 若已设置取景框，则把 `UIImage` 裁剪到取景框范围内；否则原样返回。
    func cropImageToViewfinderIfNeeded(_ image: UIImage?) -> UIImage? {
        guard let image else { return image }
        guard let viewfinderRect = viewfinderRectInPreviewBounds(), let cameraView else { return image }

        let cropped = CameraCaptureCropper.crop(
            image,
            viewfinderRect: viewfinderRect,
            containerBounds: cameraView.bounds,
            videoGravity: cameraLayer.videoGravity
        )

        SparkLogger.log(
            level: .info,
            module: .camera,
            message: "CustomCameraManager: 裁剪图片至取景框 original=\(Int(image.size.width))x\(Int(image.size.height)) cropped=\(Int(cropped.size.width))x\(Int(cropped.size.height))"
        )
        return cropped
    }
}

private extension CustomCameraManager {
    func viewfinderRectInPreviewBounds() -> CGRect? {
        guard let normalized = captureViewfinderNormalizedRect, let cameraView else { return nil }

        let container = cameraView.bounds
        guard container.width > 0, container.height > 0 else { return nil }

        return CGRect(
            x: container.minX + normalized.minX * container.width,
            y: container.minY + normalized.minY * container.height,
            width: normalized.width * container.width,
            height: normalized.height * container.height
        )
    }

}

// MARK: Set Camera Output
extension CustomCameraManager {
    func setOutputType(_ outputType: CameraOutputType) {
        guard outputType != attributes.outputType, !isChanging else { return }
        attributes.outputType = outputType
    }
}

// MARK: Set Camera Position
extension CustomCameraManager {
    func setCameraPosition(_ position: CameraPosition) async throws {
        guard position != attributes.cameraPosition, !isChanging else { return }

        await cameraMetalView.beginCameraFlipAnimation()
        try changeCameraInput(position)
        resetAttributesWhenChangingCamera(position)
        await cameraMetalView.finishCameraFlipAnimation()
    }
}
private extension CustomCameraManager {
    func changeCameraInput(_ position: CameraPosition) throws {
        if let input = getCameraInput() { captureSession.remove(input: input) }
        try captureSession.add(input: getCameraInput(position))
    }
    func resetAttributesWhenChangingCamera(_ position: CameraPosition) {
        resetAttributes(device: getCameraInput(position)?.device)
        attributes.cameraPosition = position
        do { try applyDefaultWideZoomPreset() } catch {}
        logAvailableZoomPresets()
    }
}

// MARK: Set Camera Zoom
extension CustomCameraManager {
    func setCameraZoomFactor(_ zoomFactor: CGFloat) throws {
        guard let device = getCameraInput()?.device, zoomFactor != attributes.zoomFactor, !isChanging else { return }

        try setDeviceZoomFactor(zoomFactor, device)
        attributes.zoomFactor = device.videoZoomFactor
    }
}

// MARK: Set Camera Focus
extension CustomCameraManager {
    func setCameraFocus(at touchPoint: CGPoint) throws {
        guard let device = getCameraInput()?.device, !isChanging else { return }

        let focusPoint = convertTouchPointToFocusPoint(touchPoint)
        try setDeviceCameraFocus(focusPoint, device)
        cameraMetalView.performCameraFocusAnimation(touchPoint: touchPoint)
    }
}
private extension CustomCameraManager {
    func convertTouchPointToFocusPoint(_ touchPoint: CGPoint) -> CGPoint { .init(
        x: touchPoint.y / cameraView.frame.height,
        y: 1 - touchPoint.x / cameraView.frame.width
    )}
    func setDeviceCameraFocus(_ focusPoint: CGPoint, _ device: any CaptureDevice) throws {
        try device.lockForConfiguration()
        device.setFocusPointOfInterest(focusPoint)
        device.setExposurePointOfInterest(focusPoint)
        device.unlockForConfiguration()
    }
}

// MARK: Set Flash Mode
extension CustomCameraManager {
    func setFlashMode(_ flashMode: CameraFlashMode) {
        guard let device = getCameraInput()?.device, device.hasFlash, flashMode != attributes.flashMode, !isChanging else { return }
        attributes.flashMode = flashMode
    }
}

// MARK: Set Light Mode
extension CustomCameraManager {
    func setLightMode(_ lightMode: CameraLightMode) throws {
        guard let device = getCameraInput()?.device, device.hasTorch, lightMode != attributes.lightMode, !isChanging else { return }

        try setDeviceLightMode(lightMode, device)
        attributes.lightMode = device.lightMode
    }
}
private extension CustomCameraManager {
    func setDeviceLightMode(_ lightMode: CameraLightMode, _ device: any CaptureDevice) throws {
        try device.lockForConfiguration()
        device.setLightMode(lightMode)
        device.unlockForConfiguration()
    }
}

// MARK: Set Mirror Output
extension CustomCameraManager {
    func setMirrorOutput(_ mirrorOutput: Bool) {
        guard mirrorOutput != attributes.mirrorOutput, !isChanging else { return }
        attributes.mirrorOutput = mirrorOutput
    }
}

// MARK: Set Grid Visibility
extension CustomCameraManager {
    func setGridVisibility(_ isGridVisible: Bool) {
        guard isGridVisible != attributes.isGridVisible, !isChanging else { return }
        cameraGridView.setVisibility(isGridVisible)
    }
}

// MARK: Set Camera Filters
extension CustomCameraManager {
    func setCameraFilters(_ cameraFilters: [CIFilter]) {
        guard cameraFilters != attributes.cameraFilters, !isChanging else { return }
        attributes.cameraFilters = cameraFilters
    }
}

// MARK: Set Exposure Mode
extension CustomCameraManager {
    func setExposureMode(_ exposureMode: AVCaptureDevice.ExposureMode) throws {
        guard let device = getCameraInput()?.device, exposureMode != attributes.cameraExposure.mode, !isChanging else { return }

        try setDeviceExposureMode(exposureMode, device)
        attributes.cameraExposure.mode = device.exposureMode
    }
}
private extension CustomCameraManager {
    func setDeviceExposureMode(_ exposureMode: AVCaptureDevice.ExposureMode, _ device: any CaptureDevice) throws {
        try device.lockForConfiguration()
        device.setExposureMode(exposureMode, duration: attributes.cameraExposure.duration, iso: attributes.cameraExposure.iso)
        device.unlockForConfiguration()
    }
}

// MARK: Set Exposure Duration
extension CustomCameraManager {
    func setExposureDuration(_ exposureDuration: CMTime) throws {
        guard let device = getCameraInput()?.device, exposureDuration != attributes.cameraExposure.duration, !isChanging else { return }

        try setDeviceExposureDuration(exposureDuration, device)
        attributes.cameraExposure.duration = device.exposureDuration
    }
}
private extension CustomCameraManager {
    func setDeviceExposureDuration(_ exposureDuration: CMTime, _ device: any CaptureDevice) throws {
        try device.lockForConfiguration()
        device.setExposureMode(.custom, duration: exposureDuration, iso: attributes.cameraExposure.iso)
        device.unlockForConfiguration()
    }
}

// MARK: Set ISO
extension CustomCameraManager {
    func setISO(_ iso: Float) throws {
        guard let device = getCameraInput()?.device, iso != attributes.cameraExposure.iso, !isChanging else { return }

        try setDeviceISO(iso, device)
        attributes.cameraExposure.iso = device.iso
    }
}
private extension CustomCameraManager {
    func setDeviceISO(_ iso: Float, _ device: any CaptureDevice) throws {
        try device.lockForConfiguration()
        device.setExposureMode(.custom, duration: attributes.cameraExposure.duration, iso: iso)
        device.unlockForConfiguration()
    }
}

// MARK: Set Exposure Target Bias
extension CustomCameraManager {
    func setExposureTargetBias(_ exposureTargetBias: Float) throws {
        guard let device = getCameraInput()?.device, exposureTargetBias != attributes.cameraExposure.targetBias, !isChanging else { return }

        try setDeviceExposureTargetBias(exposureTargetBias, device)
        attributes.cameraExposure.targetBias = device.exposureTargetBias
    }
}
private extension CustomCameraManager {
    func setDeviceExposureTargetBias(_ exposureTargetBias: Float, _ device: any CaptureDevice) throws {
        try device.lockForConfiguration()
        device.setExposureTargetBias(exposureTargetBias)
        device.unlockForConfiguration()
    }
}

// MARK: Set HDR Mode
extension CustomCameraManager {
    func setHDRMode(_ hdrMode: CameraHDRMode) throws {
        guard let device = getCameraInput()?.device, hdrMode != attributes.hdrMode, !isChanging else { return }

        try setDeviceHDRMode(hdrMode, device)
        attributes.hdrMode = hdrMode
    }
}
private extension CustomCameraManager {
    func setDeviceHDRMode(_ hdrMode: CameraHDRMode, _ device: any CaptureDevice) throws {
        try device.lockForConfiguration()
        device.hdrMode = hdrMode
        device.unlockForConfiguration()
    }
}

// MARK: Set Resolution
extension CustomCameraManager {
    func setResolution(_ resolution: AVCaptureSession.Preset) {
        guard resolution != attributes.resolution, resolution != attributes.resolution, !isChanging else { return }

        captureSession.sessionPreset = resolution
        attributes.resolution = resolution
    }
}

// MARK: Set Frame Rate
extension CustomCameraManager {
    func setFrameRate(_ frameRate: Int32) throws {
        guard let device = getCameraInput()?.device, frameRate != attributes.frameRate, !isChanging else { return }

        try setDeviceFrameRate(frameRate, device)
        attributes.frameRate = device.activeVideoMaxFrameDuration.timescale
    }
}
private extension CustomCameraManager {
    func setDeviceFrameRate(_ frameRate: Int32, _ device: any CaptureDevice) throws {
        try device.lockForConfiguration()
        device.setFrameRate(frameRate)
        device.unlockForConfiguration()
    }
}


// MARK: - HELPERS



// MARK: Attributes
extension CustomCameraManager {
    var hasFlash: Bool { getCameraInput()?.device.hasFlash ?? false }
    var hasLight: Bool { getCameraInput()?.device.hasTorch ?? false }
}
private extension CustomCameraManager {
    var isChanging: Bool { cameraMetalView.isAnimating }
}

// MARK: Methods
extension CustomCameraManager {
    func resetAttributes(device: (any CaptureDevice)?) {
        guard let device else { return }

        var newAttributes = attributes
        newAttributes.cameraExposure.mode = device.exposureMode
        newAttributes.cameraExposure.duration = device.exposureDuration
        newAttributes.cameraExposure.iso = device.iso
        newAttributes.cameraExposure.targetBias = device.exposureTargetBias
        newAttributes.frameRate = device.activeVideoMaxFrameDuration.timescale
        newAttributes.zoomFactor = device.videoZoomFactor
        newAttributes.lightMode = device.lightMode
        newAttributes.hdrMode = device.hdrMode

        attributes = newAttributes
    }
    func getCameraInput(_ position: CameraPosition? = nil) -> (any CaptureDeviceInput)? { switch position ?? attributes.cameraPosition {
        case .front: frontCameraInput
        case .back: backCameraInput
    }}
}
