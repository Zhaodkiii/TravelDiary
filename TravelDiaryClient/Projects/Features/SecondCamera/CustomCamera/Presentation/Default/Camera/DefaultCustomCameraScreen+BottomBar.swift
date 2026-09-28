//
//  DefaultCustomCameraScreen+BottomBar.swift of MijickCamera
//
//  Created by Tomasz Kurylik. Sending ❤️ from Kraków!
//    - Mail: tomasz.kurylik@mijick.com
//    - GitHub: https://github.com/FulcrumOne
//    - Medium: https://medium.com/@mijick
//
//  Copyright ©2024 Mijick. All rights reserved.




import SwiftUI
import AVFoundation

extension DefaultCustomCameraScreen { struct BottomBar: View {
    let parent: DefaultCustomCameraScreen
    let onPresentPhotoLibrary: () -> Void


    var body: some View {
        ZStack(alignment: .top) {
            createFloatingCenterControl()
            createButtons()
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 44)
        .padding(.horizontal, 32)
    }
}}
private extension DefaultCustomCameraScreen.BottomBar {
    @ViewBuilder func createFloatingCenterControl() -> some View {
        if isOutputTypeSwitchVisible {
            DefaultCustomCameraScreen.CameraOutputSwitch(parent: parent)
                .offset(y: -80)
                .disabled(!parent.isCameraControlsEnabled)
                .opacity(parent.isCameraControlsEnabled ? 1 : 0.5)
        } else if isZoomSelectionVisible {
            DefaultCustomCameraScreen.ZoomSelection(parent: parent)
                .offset(y: -80)
                .disabled(!parent.isCameraControlsEnabled)
                .opacity(parent.isCameraControlsEnabled ? 1 : 0.5)
        }
    }
    func createButtons() -> some View {
        ZStack {
            createPhotoLibraryButton()
            createCaptureButton()
            createChangeCameraPositionButton()
        }.frame(height: 72)
    }
}
private extension DefaultCustomCameraScreen.BottomBar {
    @ViewBuilder func createPhotoLibraryButton() -> some View { if isPhotoLibraryButtonVisible {
        SystemBottomButton(
            systemName: "photo.on.rectangle",
            iconColor: .init(.mijickBackgroundInverted),
            backgroundColor: .init(.mijickBackgroundSecondary),
            rotationAngle: parent.iconAngle,
            action: onPresentPhotoLibrary
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .disabled(!parent.isCameraControlsEnabled)
        .opacity(parent.isCameraControlsEnabled ? 1 : 0.5)
        .transition(.scale)
        .accessibilityLabel("从相册选择")
    }}
    @ViewBuilder func createCaptureButton() -> some View { if isCaptureButtonVisible {
        DefaultCustomCameraScreen.CaptureButton(
            outputType: parent.cameraOutputType,
            isRecording: parent.isRecording,
            action: parent.captureOutput
        )
        .disabled(!parent.isCameraControlsEnabled)
        .opacity(parent.isCameraControlsEnabled ? 1 : 0.5)
        .transition(.scale)
    }}
    @ViewBuilder func createChangeCameraPositionButton() -> some View { if isChangeCameraPositionButtonVisible {
        BottomButton(
            icon: .mijickIconChangeCamera,
            iconColor: changeCameraPositionButtonIconColor,
            backgroundColor: .init(.mijickBackgroundSecondary),
            rotationAngle: parent.iconAngle,
            action: changeCameraPosition
        )
        .frame(maxWidth: .infinity, alignment: .trailing)
        .disabled(!parent.isCameraControlsEnabled)
        .opacity(parent.isCameraControlsEnabled ? 1 : 0.5)
        .transition(.scale)
    }}
}

private extension DefaultCustomCameraScreen.BottomBar {
    func changeCameraPosition() { Task {
        do { try await parent.setCameraPosition(parent.cameraPosition.next()) }
        catch {}
    }}
}

private extension DefaultCustomCameraScreen.BottomBar {
    var changeCameraPositionButtonIconColor: Color { .init(.mijickBackgroundInverted) }
}
private extension DefaultCustomCameraScreen.BottomBar {
    var isOutputTypeSwitchVisible: Bool {
        parent.config.cameraOutputSwitchAllowed
        && parent.isCameraControlsVisible
        && !parent.isRecording
    }
    var isZoomSelectionVisible: Bool {
        !parent.config.cameraOutputSwitchAllowed
        && parent.config.zoomSelectionAllowed
        && parent.isCameraControlsVisible
        && !parent.isRecording
        && parent.cameraPosition == .back
        && parent.availableZoomPresets.count > 1
    }
    var isPhotoLibraryButtonVisible: Bool {
        parent.config.photoLibraryButtonAllowed
        && parent.isCameraControlsVisible
        && !parent.isRecording
    }
    var isCaptureButtonVisible: Bool {
        parent.config.captureButtonAllowed
        && parent.isCameraControlsVisible
    }
    var isChangeCameraPositionButtonVisible: Bool {
        parent.config.cameraPositionButtonAllowed
        && parent.isCameraControlsVisible
        && !parent.isRecording
    }
}
