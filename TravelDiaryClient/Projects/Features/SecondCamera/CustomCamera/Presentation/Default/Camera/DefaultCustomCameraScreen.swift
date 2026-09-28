//
//  DefaultCustomCameraScreen.swift of MijickCamera
//
//  Created by Tomasz Kurylik. Sending ❤️ from Kraków!
//    - Mail: tomasz.kurylik@mijick.com
//    - GitHub: https://github.com/FulcrumOne
//    - Medium: https://medium.com/@mijick
//
//  Copyright ©2024 Mijick. All rights reserved.




import SwiftUI
import AVFoundation
import PhotosUI

@MainActor
struct DefaultCustomCameraScreen: CustomCameraScreen {
    @ObservedObject var cameraManager: CustomCameraManager
    internal let namespace: Namespace.ID
    internal let closeCustomCameraAction: () -> ()
    var config: Config = .init()

    @State private var isPhotoPickerPresented = false
    @State private var photoLibraryErrorMessage: String?


    internal var body: some View {
        ZStack {
            createContentView()
            createTopBar()
            createBottomBar()
        }
        .ignoresSafeArea()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.mijickBackgroundPrimary).ignoresSafeArea())
        .statusBarHidden()
        .animation(.mSpring)
        .sheet(isPresented: $isPhotoPickerPresented) {
            SecondCameraPhotoPickerView(
                selectionLimit: config.photoLibrarySelectionLimit,
                filter: .any(of: [.images, .videos]),
                onComplete: { mediaItems in
                    isPhotoPickerPresented = false
                    SparkLogger.log(
                        level: .info,
                        module: .camera,
                        message: "SecondCamera photo library will enter preview after sheet dismiss count=\(mediaItems.count)"
                    )
                    // 等 sheet 关闭完成后再进入预览，避免与 fullScreenCover 生命周期竞态。
                    Task { @MainActor in
                        await Task.yield()
                        handlePickedMedia(mediaItems)
                    }
                },
                onCancel: {
                    isPhotoPickerPresented = false
                    handlePhotoPickerCancel()
                },
                onFailure: { error in
                    isPhotoPickerPresented = false
                    handlePhotoPickerFailure(error)
                    photoLibraryErrorMessage = error.localizedDescription
                }
            )
        }
        .alert(
            "相册选择失败",
            isPresented: Binding(
                get: { photoLibraryErrorMessage != nil },
                set: { isPresented in
                    if !isPresented { photoLibraryErrorMessage = nil }
                }
            )
        ) {
            Button("确定", role: .cancel) {
                photoLibraryErrorMessage = nil
            }
        } message: {
            Text(photoLibraryErrorMessage ?? "")
        }
    }
}
private extension DefaultCustomCameraScreen {
    func createTopBar() -> some View {
        DefaultCustomCameraScreen.TopBar(parent: self)
            .frame(maxHeight: .infinity, alignment: .top)
    }
    func createContentView() -> some View {
        createCameraOutputView()
            .ignoresSafeArea()
    }
    func createBottomBar() -> some View {
        DefaultCustomCameraScreen.BottomBar(
            parent: self,
            onPresentPhotoLibrary: {
                guard isCameraControlsEnabled else { return }
                isPhotoPickerPresented = true
            }
        )
            .frame(maxHeight: .infinity, alignment: .bottom)
    }
}

extension DefaultCustomCameraScreen {
    var iconAngle: Angle { switch isOrientationLocked {
        case true: deviceOrientation.getAngle()
        case false: .zero
    }}
}
