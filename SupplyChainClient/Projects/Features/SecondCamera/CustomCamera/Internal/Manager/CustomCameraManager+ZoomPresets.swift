import AVFoundation
import Foundation

extension CustomCameraManager {
    static let maxDisplayZoomFactor: CGFloat = 3

    var availableZoomPresets: [CameraZoomPreset] {
        guard let device = getCameraInput()?.device else { return [] }
        return makeZoomPresets(for: device)
    }

    func setCameraZoomPreset(_ preset: CameraZoomPreset) throws {
        SparkLogger.log(
            level: .info,
            module: .camera,
            message: "SecondCamera ZoomPreset select display=\(preset.displayZoomFactor) device=\(preset.deviceZoomFactor) current=\(attributes.zoomFactor)"
        )
        try setCameraZoomFactor(preset.deviceZoomFactor)
    }

    func displayZoomFactor(for deviceZoomFactor: CGFloat) -> CGFloat {
        guard let device = getCameraInput()?.device else { return deviceZoomFactor }
        return Self.displayZoomFactor(from: deviceZoomFactor, device: device)
    }

    func selectedZoomPreset(for deviceZoomFactor: CGFloat) -> CameraZoomPreset? {
        let presets = availableZoomPresets
        guard let device = getCameraInput()?.device else { return presets.first }
        let displayZoom = Self.displayZoomFactor(from: deviceZoomFactor, device: device)
        return presets.reversed().first { displayZoom >= $0.displayZoomFactor - 0.05 }
    }

    func logAvailableZoomPresets() {
        guard let device = getCameraInput()?.device else { return }
        let presets = makeZoomPresets(for: device)
        SparkLogger.log(
            level: .info,
            module: .camera,
            message: "SecondCamera ZoomPresets position=\(attributes.cameraPosition) device=\(device.deviceType) min=\(device.minAvailableVideoZoomFactor) max=\(device.maxAvailableVideoZoomFactor) presets=\(presets.map(\.displayZoomFactor))"
        )
    }

    func applyDefaultWideZoomPreset() throws {
        guard let device = getCameraInput()?.device else { return }
        let wideDeviceFactor = clampDeviceZoom(
            deviceZoomFactor(for: 1, device: device),
            device: device
        )
        try setDeviceZoomFactor(wideDeviceFactor, device)
        attributes.zoomFactor = device.videoZoomFactor
    }

    func setDeviceZoomFactor(_ zoomFactor: CGFloat, _ device: any CaptureDevice) throws {
        try device.lockForConfiguration()
        device.videoZoomFactor = clampDeviceZoom(zoomFactor, device: device)
        device.unlockForConfiguration()
    }
}

private extension CustomCameraManager {
    func makeZoomPresets(for device: any CaptureDevice) -> [CameraZoomPreset] {
        var presets: [CameraZoomPreset] = []
        let maxDeviceZoom = maxDeviceZoom(for: device)

        if supportsUltraWide(device) {
            let displayFactor: CGFloat = 0.5
            let deviceFactor = deviceZoomFactor(for: displayFactor, device: device)
            presets.append(.init(
                id: "0.5",
                kind: .ultraWide,
                displayZoomFactor: displayFactor,
                deviceZoomFactor: clampDeviceZoom(deviceFactor, device: device)
            ))
        }

        let wideDisplayFactor: CGFloat = 1
        let wideDeviceFactor = clampDeviceZoom(deviceZoomFactor(for: wideDisplayFactor, device: device), device: device)
        if wideDeviceFactor <= maxDeviceZoom {
            presets.append(.init(
                id: "1",
                kind: .wide,
                displayZoomFactor: wideDisplayFactor,
                deviceZoomFactor: wideDeviceFactor
            ))
        }

        if let telephoto = makeTelephotoPreset(
            device: device,
            wideDeviceFactor: wideDeviceFactor,
            maxDeviceZoom: maxDeviceZoom
        ) {
            presets.append(telephoto)
        }

        return presets
    }

    func makeTelephotoPreset(
        device: any CaptureDevice,
        wideDeviceFactor: CGFloat,
        maxDeviceZoom: CGFloat
    ) -> CameraZoomPreset? {
        let displayFactor = Self.maxDisplayZoomFactor
        let deviceFactor = clampDeviceZoom(deviceZoomFactor(for: displayFactor, device: device), device: device)
        guard deviceFactor > wideDeviceFactor + 0.01 else { return nil }
        guard deviceFactor <= maxDeviceZoom else { return nil }
        return .init(
            id: "3",
            kind: .telephoto,
            displayZoomFactor: displayFactor,
            deviceZoomFactor: deviceFactor
        )
    }

    func clampDeviceZoom(_ factor: CGFloat, device: any CaptureDevice) -> CGFloat {
        max(min(factor, maxDeviceZoom(for: device)), device.minAvailableVideoZoomFactor)
    }

    func maxDeviceZoom(for device: any CaptureDevice) -> CGFloat {
        min(
            device.maxAvailableVideoZoomFactor,
            deviceZoomFactor(for: Self.maxDisplayZoomFactor, device: device)
        )
    }

    func deviceZoomFactor(for displayZoomFactor: CGFloat, device: any CaptureDevice) -> CGFloat {
        displayZoomFactor / zoomFactorMultiplier(for: device)
    }

    func supportsUltraWide(_ device: any CaptureDevice) -> Bool {
        if !device.virtualDeviceSwitchOverVideoZoomFactors.isEmpty {
            return true
        }
        switch device.deviceType {
        case .builtInTripleCamera, .builtInDualWideCamera:
            return true
        default:
            return device.minAvailableVideoZoomFactor < 1
        }
    }

    func zoomFactorMultiplier(for device: any CaptureDevice) -> CGFloat {
        supportsUltraWide(device) ? 0.5 : 1
    }

    static func displayZoomFactor(from deviceZoomFactor: CGFloat, device: any CaptureDevice) -> CGFloat {
        let multiplier: CGFloat = {
            if !device.virtualDeviceSwitchOverVideoZoomFactors.isEmpty { return 0.5 }
            switch device.deviceType {
            case .builtInTripleCamera, .builtInDualWideCamera:
                return 0.5
            default:
                return device.minAvailableVideoZoomFactor < 1 ? 0.5 : 1
            }
        }()
        return deviceZoomFactor * multiplier
    }
}
