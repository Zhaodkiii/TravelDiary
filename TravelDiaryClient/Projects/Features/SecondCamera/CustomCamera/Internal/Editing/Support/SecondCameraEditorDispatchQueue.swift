//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension DispatchQueue {

    public nonisolated(unsafe) static let secondCameraEditor_sharedUserInteractive: DispatchQueue = {
        return DispatchQueue(
            label: "org.signal.serial-user-interactive",
            qos: .userInteractive,
            autoreleaseFrequency: .workItem,
        )
    }()

    public nonisolated(unsafe) static let secondCameraEditor_sharedUserInitiated: DispatchQueue = {
        return DispatchQueue(
            label: "org.signal.serial-user-initiated",
            qos: .userInitiated,
            autoreleaseFrequency: .workItem,
        )
    }()

    public nonisolated(unsafe) static let secondCameraEditor_sharedUtility: DispatchQueue = {
        return DispatchQueue(
            label: "org.signal.serial-utility",
            qos: .utility,
            autoreleaseFrequency: .workItem,
        )
    }()

    public nonisolated(unsafe) static let secondCameraEditor_sharedBackground: DispatchQueue = {
        return DispatchQueue(
            label: "org.signal.serial-background",
            qos: .background,
            autoreleaseFrequency: .workItem,
        )
    }()

    /// Returns the shared serial queue appropriate for the provided QoS
    public nonisolated static func secondCameraEditor_sharedQueue(at qos: DispatchQoS) -> DispatchQueue {
        switch qos {
        case .userInteractive:
            return DispatchQueue.secondCameraEditor_sharedUserInteractive

        case .userInitiated:
            return DispatchQueue.secondCameraEditor_sharedUserInitiated

        case .default, .utility:
            return DispatchQueue.secondCameraEditor_sharedUtility

        case .background, .unspecified:
            return DispatchQueue.global(qos: .background)

        default:
            return DispatchQueue.secondCameraEditor_sharedUtility
        }
    }
}

extension DispatchQoS.QoSClass {

    /// Floors a UInt32-backed qos_class_t to a valid QoSClass enum.
    nonisolated init(secondCameraEditor_flooring rawQoS: qos_class_t) {
        switch rawQoS.rawValue {

        case QOS_CLASS_BACKGROUND.rawValue..<QOS_CLASS_UTILITY.rawValue:
            self = .background

        case QOS_CLASS_UTILITY.rawValue..<QOS_CLASS_USER_INITIATED.rawValue:
            self = .utility

        case QOS_CLASS_USER_INITIATED.rawValue..<QOS_CLASS_USER_INTERACTIVE.rawValue:
            self = .userInitiated

        case QOS_CLASS_USER_INTERACTIVE.rawValue:
            self = .userInteractive

        default:
            // The provided QoS value is either greater than UserInteractive or less than Background
            // Fail safely to background QoS and assert.
            secondCameraEditorFailDebug("Invalid qos_class: \(rawQoS.rawValue). Defaulting background QoS.")
            self = .background
        }
    }
}
