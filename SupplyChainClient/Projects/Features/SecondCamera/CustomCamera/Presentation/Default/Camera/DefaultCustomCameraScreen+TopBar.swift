//
//  DefaultCustomCameraScreen+TopBar.swift of MijickCamera
//
//  Created by Tomasz Kurylik. Sending ❤️ from Kraków!
//    - Mail: tomasz.kurylik@mijick.com
//    - GitHub: https://github.com/FulcrumOne
//    - Medium: https://medium.com/@mijick
//
//  Copyright ©2024 Mijick. All rights reserved.




import SwiftUI
import AVFoundation

extension DefaultCustomCameraScreen { struct TopBar: View {
    let parent: DefaultCustomCameraScreen


    var body: some View { if isTopBarActive {
        ZStack {
            createCloseButton()
            createCentralView()
            createRightSideView()
        }
        .frame(maxWidth: .infinity)
        .padding(.top, topPadding)
        .padding(.bottom, 8)
        .padding(.horizontal, 20)
        .background(Color(.mijickBackgroundPrimary80))
        .transition(.move(edge: .top))
    }}
}}
private extension DefaultCustomCameraScreen.TopBar {
    @ViewBuilder func createCloseButton() -> some View { if isCloseButtonActive {
        CloseButton(action: parent.closeCustomCameraAction)
            .frame(maxWidth: .infinity, alignment: .leading)
    }}
    @ViewBuilder func createCentralView() -> some View { if isCentralViewActive {
        Text(parent.recordingTime.toString())
            .font(.system(size: 20, weight: .medium))
            .foregroundColor(.init(.mijickTextPrimary))
    }}
    @ViewBuilder func createRightSideView() -> some View { if isRightSideViewActive {
        HStack(spacing: 12) {
            createGridButton()
            createFlipOutputButton()
            createLightButton()
            createFlashButton()
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }}
}
private extension DefaultCustomCameraScreen.TopBar {
    @ViewBuilder func createGridButton() -> some View { if isGridButtonActive {
        DefaultCustomCameraScreen.TopButton(
            icon: gridButtonIcon,
            iconRotationAngle: parent.iconAngle,
            action: changeGridVisibility
        )
    }}
    @ViewBuilder func createFlipOutputButton() -> some View { if isFlipOutputButtonActive {
        DefaultCustomCameraScreen.TopButton(
            icon: flipButtonIcon,
            iconRotationAngle: parent.iconAngle,
            action: changeMirrorOutput
        )
    }}
    @ViewBuilder func createLightButton() -> some View { if isLightButtonActive {
        DefaultCustomCameraScreen.TopButton(
            icon: .mijickIconLight,
            iconColor: lightButtonIconColor,
            iconRotationAngle: parent.iconAngle,
            action: changeLightMode
        )
        .disabled(!parent.isCameraControlsEnabled)
        .opacity(parent.isCameraControlsEnabled ? 1 : 0.5)
    }}
    @ViewBuilder func createFlashButton() -> some View { if isFlashButtonActive {
        DefaultCustomCameraScreen.TopButton(
            icon: flashButtonIcon,
            iconRotationAngle: parent.iconAngle,
            action: changeFlashMode
        )
        .disabled(!parent.isCameraControlsEnabled)
        .opacity(parent.isCameraControlsEnabled ? 1 : 0.5)
    }}
}

private extension DefaultCustomCameraScreen.TopBar {
    func changeGridVisibility() {
        parent.setGridVisibility(!parent.isGridVisible)
    }
    func changeMirrorOutput() {
        parent.setMirrorOutput(!parent.isOutputMirrored)
    }
    func changeLightMode() {
        do { try parent.setLightMode(parent.lightMode.next()) }
        catch {}
    }
    func changeFlashMode() {
        parent.setFlashMode(parent.flashMode.next())
    }
}

private extension DefaultCustomCameraScreen.TopBar {
    var topPadding: CGFloat { switch parent.deviceOrientation {
        case .portrait, .portraitUpsideDown: return 40
        default: return 20
    }}
}
private extension DefaultCustomCameraScreen.TopBar {
    var gridButtonIcon: ImageResource { switch parent.isGridVisible {
        case true: .mijickIconGridOn
        case false: .mijickIconGridOff
    }}
    var flipButtonIcon: ImageResource { switch parent.isOutputMirrored {
        case true: .mijickIconFlipOn
        case false: .mijickIconFlipOff
    }}
    var lightButtonIconColor: Color { switch parent.lightMode {
        case .on: .init(.mijickBackgroundYellow)
        case .off: .init(.mijickBackgroundInverted)
    }}
    var flashButtonIcon: ImageResource { switch parent.flashMode {
        case .off: .mijickIconFlashOff
        case .on: .mijickIconFlashOn
        case .auto: .mijickIconFlashAuto
    }}
}
private extension DefaultCustomCameraScreen.TopBar {
    var isTopBarActive: Bool { parent.isCameraControlsVisible }
    var isCloseButtonActive: Bool { parent.config.closeButtonAllowed && !parent.isRecording }
    var isCentralViewActive: Bool { parent.isRecording }
    var isRightSideViewActive: Bool { !parent.isRecording }
    var isGridButtonActive: Bool { parent.config.gridButtonAllowed }
    var isFlipOutputButtonActive: Bool { parent.config.flipButtonAllowed && parent.cameraPosition == .front }
    var isLightButtonActive: Bool { parent.config.lightButtonAllowed && parent.hasLight && parent.isCameraControlsVisible && !parent.isRecording }
    var isFlashButtonActive: Bool { parent.config.flashButtonAllowed && parent.hasFlash && parent.cameraOutputType == .photo }
}
