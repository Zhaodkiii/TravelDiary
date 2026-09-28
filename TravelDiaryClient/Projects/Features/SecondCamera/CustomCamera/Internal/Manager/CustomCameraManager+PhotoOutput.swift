//
//  CustomCameraManager+PhotoOutput.swift of MijickCamera
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

@MainActor class CustomCameraManagerPhotoOutput: NSObject {
    private(set) var parent: CustomCameraManager!
    private(set) var output: AVCapturePhotoOutput = .init()
    /// 拍摄瞬间的 `frameOrientation`，与实时预览一致，避免异步回调时方向已变化。
    private var captureFrameOrientation: CGImagePropertyOrientation?
}

// MARK: Setup
extension CustomCameraManagerPhotoOutput {
    func setup(parent: CustomCameraManager) throws(CustomCameraError) {
        self.parent = parent
        try self.parent.captureSession.add(output: output)
    }
}


// MARK: - CAPTURE PHOTO



// MARK: Capture
extension CustomCameraManagerPhotoOutput {
    func capture() {
        guard let parent else {
            SparkLogger.log(
                level: .error,
                module: .camera,
                message: "CustomCameraManagerPhotoOutput: 忽略拍照，parent 为空"
            )
            return
        }

        let settings = getPhotoOutputSettings(parent: parent)

        SparkLogger.log(
            level: .info,
            module: .camera,
            message: "CustomCameraManagerPhotoOutput: 开始拍照 flash=\(parent.attributes.flashMode) orientation=\(parent.attributes.deviceOrientation)"
        )
        captureFrameOrientation = parent.attributes.frameOrientation
        configureOutput(parent: parent)
        output.capturePhoto(with: settings, delegate: self)
        parent.cameraMetalView.performImageCaptureAnimation()
    }
}
private extension CustomCameraManagerPhotoOutput {
    func getPhotoOutputSettings(parent: CustomCameraManager) -> AVCapturePhotoSettings {
        let settings = AVCapturePhotoSettings()
        settings.flashMode = parent.attributes.flashMode.toDeviceFlashMode()
        return settings
    }
    func configureOutput(parent: CustomCameraManager) {
        guard let connection = output.connection(with: .video) else {
            SparkLogger.log(
                level: .warning,
                module: .camera,
                message: "CustomCameraManagerPhotoOutput: 配置照片输出时无视频连接"
            )
            return
        }

        guard connection.isVideoMirroringSupported else {
            SparkLogger.log(
                level: .warning,
                module: .camera,
                message: "CustomCameraManagerPhotoOutput: 不支持视频镜像"
            )
            connection.videoOrientation = parent.attributes.deviceOrientation
            return
        }

        connection.isVideoMirrored = parent.attributes.mirrorOutput ? parent.attributes.cameraPosition != .front : parent.attributes.cameraPosition == .front
        connection.videoOrientation = parent.attributes.deviceOrientation
    }
}

// MARK: Receive Data
extension CustomCameraManagerPhotoOutput: @preconcurrency AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: (any Error)?) {
        if let error {
            SparkLogger.log(
                level: .error,
                module: .camera,
                message: "CustomCameraManagerPhotoOutput: 照片处理完成，发生错误 error=\(error.localizedDescription)"
            )
        }

        guard let parent else {
            SparkLogger.log(
                level: .error,
                module: .camera,
                message: "CustomCameraManagerPhotoOutput: 照片处理完成，缺少 parent"
            )
            return
        }

        guard let imageData = photo.fileDataRepresentation() else {
            SparkLogger.log(
                level: .error,
                module: .camera,
                message: "CustomCameraManagerPhotoOutput: 照片处理完成，缺少图片数据"
            )
            return
        }

        guard let ciImage = CIImage(data: imageData) else {
            SparkLogger.log(
                level: .error,
                module: .camera,
                message: "CustomCameraManagerPhotoOutput: 照片处理完成，无法创建 CIImage bytes=\(imageData.count)"
            )
            return
        }

        let frameOrientation = captureFrameOrientation ?? parent.attributes.frameOrientation
        captureFrameOrientation = nil

        let filteredCIImage = prepareCIImage(ciImage, parent.attributes.cameraFilters)
        // 与实时预览一致：先归正像素方向，再按 frameOrientation 进入预览坐标系。
        let previewSpaceCIImage = filteredCIImage.oriented(.up).oriented(frameOrientation)
        guard let fullCGImage = prepareCGImage(previewSpaceCIImage) else {
            SparkLogger.log(
                level: .error,
                module: .camera,
                message: "CustomCameraManagerPhotoOutput: 照片处理完成，无法创建 CGImage"
            )
            return
        }
        // 使用 UIImage 裁剪路径（与竖屏原先正确逻辑一致），避免 CIImage extent 与预览流比例差异导致偏移。
        let fullUIImage = UIImage(cgImage: fullCGImage, scale: 1.0, orientation: .up)
        let capturedUIImage = parent.cropImageToViewfinderIfNeeded(fullUIImage) ?? fullUIImage
        guard let capturedMedia = CustomCameraMedia(data: capturedUIImage) else {
            SparkLogger.log(
                level: .error,
                module: .camera,
                message: "CustomCameraManagerPhotoOutput: 照片处理失败，无法构建 CustomCameraMedia"
            )
            return
        }

        SparkLogger.log(
            level: .info,
            module: .camera,
            message: "CustomCameraManagerPhotoOutput: 照片处理完成 success bytes=\(imageData.count) frameOrientation=\(frameOrientation) imageCreated=true"
        )
        parent.presentCapturedMedia(capturedMedia)
    }
}
private extension CustomCameraManagerPhotoOutput {
    func prepareCIImage(_ ciImage: CIImage, _ filters: [CIFilter]) -> CIImage {
        ciImage.applyingFilters(filters)
    }
    func prepareCGImage(_ ciImage: CIImage) -> CGImage? {
        CIContext().createCGImage(ciImage, from: ciImage.extent)
    }
}
