import SwiftUI
import AVFoundation

extension DefaultCustomCameraScreen {
    class Config {
        var captureButtonAllowed: Bool = true
        var cameraOutputSwitchAllowed: Bool = true
        var zoomSelectionAllowed: Bool = true
        var cameraPositionButtonAllowed: Bool = true
        var flashButtonAllowed: Bool = true
        var lightButtonAllowed: Bool = true
        var photoLibraryButtonAllowed: Bool = true
        var photoLibrarySelectionLimit: Int = 1
        var flipButtonAllowed: Bool = true
        var gridButtonAllowed: Bool = true
        var closeButtonAllowed: Bool = true
    }
}

extension DefaultCustomCameraScreen {
    init(
        cameraManager: CustomCameraManager,
        namespace: Namespace.ID,
        closeCustomCameraAction: @escaping () -> Void
    ) {
        self.init(
            cameraManager: cameraManager,
            namespace: namespace,
            closeCustomCameraAction: closeCustomCameraAction,
            config: .init()
        )
    }
}

extension DefaultCustomCameraScreen {
    func captureButtonAllowed(_ value: Bool) -> Self { config.captureButtonAllowed = value; return self }
    func cameraOutputSwitchAllowed(_ value: Bool) -> Self { config.cameraOutputSwitchAllowed = value; return self }
    func zoomSelectionAllowed(_ value: Bool) -> Self { config.zoomSelectionAllowed = value; return self }
    func cameraPositionButtonAllowed(_ value: Bool) -> Self { config.cameraPositionButtonAllowed = value; return self }
    func flashButtonAllowed(_ value: Bool) -> Self { config.flashButtonAllowed = value; return self }
    func lightButtonAllowed(_ value: Bool) -> Self { config.lightButtonAllowed = value; return self }
    func photoLibraryButtonAllowed(_ value: Bool) -> Self { config.photoLibraryButtonAllowed = value; return self }
    func photoLibrarySelectionLimit(_ value: Int) -> Self { config.photoLibrarySelectionLimit = max(1, value); return self }
    func flipButtonAllowed(_ value: Bool) -> Self { config.flipButtonAllowed = value; return self }
    func gridButtonAllowed(_ value: Bool) -> Self { config.gridButtonAllowed = value; return self }
    func closeButtonAllowed(_ value: Bool) -> Self { config.closeButtonAllowed = value; return self }
}
