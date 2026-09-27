//
//  Public+UI+CustomCameraErrorScreen.swift of MijickCamera
//
//  Created by Tomasz Kurylik. Sending ❤️ from Kraków!
//    - Mail: tomasz.kurylik@mijick.com
//    - GitHub: https://github.com/FulcrumOne
//    - Medium: https://medium.com/@mijick
//
//  Copyright ©2024 Mijick. All rights reserved.




import SwiftUI
import AVFoundation

/**
 Screen that displays an error message if one or more camera permissions are denied by the user.

 - important: A view conforming to **CustomCameraErrorScreen** has to be passed directly to ``CustomCameraView``. See ``CustomCameraView/setErrorScreen(_:)`` for more details.


 ## Usage
 ```swift
 struct ContentView: View {
    var body: some View {
        CustomCameraView()
            .setErrorScreen(CustomCameraErrorScreen.init)

            // MUST BE CALLED!
            .startSession()
    }
 }

 // MARK: Custom Camera Error Screen
 struct CustomCameraErrorScreen: CustomCameraErrorScreen {
    let error: CustomCameraError
    let closeCustomCameraAction: () -> ()


    var body: some View {
        Button(action: openAppSettings) { Text("Open Settings") }
    }
 }
 ```
 */
internal protocol CustomCameraErrorScreen: View {
    var error: CustomCameraError { get }
    var closeCustomCameraAction: () -> () { get }
}

// MARK: Methods
internal extension CustomCameraErrorScreen {
    func openAppSettings() { if let url = URL(string: UIApplication.openSettingsURLString) {
        UIApplication.shared.open(url)
    }}
}
