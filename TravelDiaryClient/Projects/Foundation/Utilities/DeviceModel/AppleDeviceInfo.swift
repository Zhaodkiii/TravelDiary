import UIKit

/// Shared hardware identity. Layout size and live orientation remain UIKit responsibilities.
@MainActor enum AppleDeviceInfo {
    static let modelIdentifier: String = {
        #if targetEnvironment(simulator)
        return ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? Device.identifier
        #else
        return Device.identifier
        #endif
    }()

    static var model: Device { Device.mapToDevice(identifier: modelIdentifier).realDevice }
    static var modelName: String { modelName(for: modelIdentifier) }
    static var isDuo: Bool { isDuo(modelIdentifier: modelIdentifier) }
    static var systemVersion: String { UIDevice.current.systemVersion }
    static var deviceName: String { UIDevice.current.name }
    static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    // DeviceKit does not yet include Duo. Verified against the installed Duo simulator;
    // keep this override here until upstream supplies the model instead of editing its table.
    static func isDuo(modelIdentifier: String) -> Bool { modelIdentifier == "iPhone19,4" }
    static func modelName(for identifier: String) -> String {
        if isDuo(modelIdentifier: identifier) { return "iPhone Duo" }
        return Device.mapToDevice(identifier: identifier).realDevice.description
    }
}
