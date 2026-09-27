//
//  CustomCameraManager+PermissionsManager.swift of MijickCamera
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

@MainActor class CustomCameraManagerPermissionsManager {}

// MARK: Request Access
extension CustomCameraManagerPermissionsManager {
    func requestAccess(parent: CustomCameraManager) async throws(CustomCameraError) {
        do {
            try await getAuthorizationStatus(for: .video)
            if parent.attributes.isAudioSourceAvailable { try await getAuthorizationStatus(for: .audio) }
        }
        catch {
            parent.attributes.error = error
            throw error
        }
    }
}
private extension CustomCameraManagerPermissionsManager {
    func getAuthorizationStatus(for mediaType: AVMediaType) async throws(CustomCameraError) { switch AVCaptureDevice.authorizationStatus(for: mediaType) {
        case .denied, .restricted: throw getPermissionsError(mediaType)
        case .notDetermined: try await requestAccess(for: mediaType)
        default: return
    }}
}
private extension CustomCameraManagerPermissionsManager {
    func requestAccess(for mediaType: AVMediaType) async throws(CustomCameraError) {
        let isGranted = await AVCaptureDevice.requestAccess(for: mediaType)
        if !isGranted { throw getPermissionsError(mediaType) }
    }
    func getPermissionsError(_ mediaType: AVMediaType) -> CustomCameraError { switch mediaType {
        case .audio: .microphonePermissionsNotGranted
        case .video: .cameraPermissionsNotGranted
        default: fatalError()
    }}
}
