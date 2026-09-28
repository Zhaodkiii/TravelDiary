//
//  DefaultCustomCameraScreen+TopButton.swift of MijickCamera
//
//  Created by Tomasz Kurylik. Sending ❤️ from Kraków!
//    - Mail: tomasz.kurylik@mijick.com
//    - GitHub: https://github.com/FulcrumOne
//    - Medium: https://medium.com/@mijick
//
//  Copyright ©2024 Mijick. All rights reserved.




import SwiftUI
import AVFoundation

extension DefaultCustomCameraScreen { struct TopButton: View {
    let icon: ImageResource
    var iconColor: Color = Color(.mijickBackgroundInverted)
    let iconRotationAngle: Angle
    let action: () -> ()


    var body: some View {
        Button(action: action, label: createButtonLabel)
    }
}}
private extension DefaultCustomCameraScreen.TopButton {
    func createButtonLabel() -> some View {
        Image(icon)
            .resizable()
            .frame(width: 16, height: 16)
            .foregroundColor(iconColor)
            .rotationEffect(iconRotationAngle)
            .frame(width: 32, height: 32)
            .background(Color(.mijickBackgroundSecondary))
            .mask(Circle())
    }
}
