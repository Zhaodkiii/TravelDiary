//
//  CaptureSession.swift of MijickCamera
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

protocol CaptureSession: Sendable {
    // MARK: Attributes
    var isRunning: Bool { get }
    var deviceInputs: [any CaptureDeviceInput] { get }
    var outputs: [AVCaptureOutput] { get }
    var sessionPreset: AVCaptureSession.Preset { get set }

    // MARK: Methods
    func startRunning()
    func stopRunningAndReturnNewInstance() -> CaptureSession
    func add(input: (any CaptureDeviceInput)?) throws(CustomCameraError)
    func remove(input: (any CaptureDeviceInput)?)
    func add(output: AVCaptureOutput?) throws(CustomCameraError)
}
