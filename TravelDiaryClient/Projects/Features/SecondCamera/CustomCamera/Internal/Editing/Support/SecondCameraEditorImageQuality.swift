//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only

import UIKit
//

import Foundation

/// The user-selected quality for images. Users are offered a choice between
/// "standard" and "high" quality. The former may correspond to level "one"
/// or "two" (depending on a remote config); the latter always corresponds
/// to level "three". Most callers should use SecondCameraEditorImageQuality; typically only
/// the compression logic needs access to SecondCameraEditorImageQualityLevel.
public enum SecondCameraEditorImageQuality {
    /// Indirectly translates to SecondCameraEditorImageQualityLevel.one or SecondCameraEditorImageQualityLevel.two.
    case standard

    /// Always translates to SecondCameraEditorImageQualityLevel.three.
    case high

    private nonisolated(unsafe) static let keyValueStore = makeKeyValueStore()
    private static let userSelectedHighQualityKey = "defaultQuality"
    private static let userSelectedHighQualityValue = 3 as UInt

    nonisolated public static func fetchValue(tx: SecondCameraEditorDBReadTransaction) -> Self {
        .standard
    }

    nonisolated public static func setValue(_ imageQuality: Self, tx: SecondCameraEditorDBWriteTransaction) {}

    nonisolated public var localizedString: String {
        switch self {
        case .standard:
            return SecondCameraEditorLocalizedString("SENT_MEDIA_QUALITY_STANDARD", comment: "String describing standard quality sent media")
        case .high:
            return SecondCameraEditorLocalizedString("SENT_MEDIA_QUALITY_HIGH", comment: "String describing high quality sent media")
        }
    }
}

public enum SecondCameraEditorImageQualityLevel: UInt, Comparable {
    case one = 1
    case two = 2
    case three = 3

    // We calculate the "standard" media quality remotely based on country
    // code. For some regions, we use a lower "standard" quality than others.
    // High quality is always level three. If not remotely specified, standard
    // uses quality level two.
    nonisolated public static func standardQualityLevel(
        remoteConfig: SecondCameraEditorRemoteConfig,
        callingCode: Int?,
    ) -> SecondCameraEditorImageQualityLevel {
        return remoteConfig.standardMediaQualityLevel(callingCode: callingCode) ?? .two
    }

    nonisolated public var startingTier: SecondCameraEditorImageQualityTier {
        switch self {
        case .one: return .four
        case .two: return .five
        case .three: return .seven
        }
    }

    nonisolated public var maxFileSize: UInt {
        switch self {
        case .one: // 1MiB
            return 1024 * 1024
        case .two: // 1.5MiB
            return UInt(1.5 * 1024 * 1024)
        case .three: // 3.0MiB
            return 3 * 1024 * 1024
        }
    }

    nonisolated public var maxOriginalFileSize: UInt {
        switch self {
        case .one: // 200KiB
            return 200 * 1024
        case .two: // 300KiB
            return 300 * 1024
        case .three: // 400KiB
            return 400 * 1024
        }
    }

    nonisolated public static func maximumForSecondCameraEditorCurrentAppContext(
        _ currentSecondCameraEditorAppContext: any SecondCameraEditorAppContext
    ) -> Self {
        if currentSecondCameraEditorAppContext.isMainApp {
            return .three
        } else {
            // Outside of the main app (like in the share extension)
            // we have very tight memory restrictions, and cannot
            // allow sending high quality media.
            return .one
        }
    }

    /// Safe quality lookup that never force-unwraps a missing AppContext.
    /// Falls back to `.three` because SecondCamera editing runs in the main app.
    nonisolated public static func maximumForSecondCameraEditorCurrentRuntime() -> Self {
        guard let context = SecondCameraEditorCurrentAppContextIfAvailable() else {
            return .three
        }
        return maximumForSecondCameraEditorCurrentAppContext(context)
    }

    nonisolated public static func resolvedValue(
        imageQuality: SecondCameraEditorImageQuality,
        standardQualityLevel: Self,
        maximumForSecondCameraEditorCurrentAppContext: Self = .maximumForSecondCameraEditorCurrentRuntime(),
    ) -> SecondCameraEditorImageQualityLevel {
        let targetQualityLevel: Self
        switch imageQuality {
        case .high:
            targetQualityLevel = .three
        case .standard:
            targetQualityLevel = standardQualityLevel
        }
        // If the max quality we allow is less than the stored preference,
        // we have to restrict ourselves to the max allowed.
        return min(targetQualityLevel, maximumForSecondCameraEditorCurrentAppContext)
    }

    nonisolated public static func <(lhs: SecondCameraEditorImageQualityLevel, rhs: SecondCameraEditorImageQualityLevel) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

private extension SecondCameraEditorImageQuality {
    nonisolated static func makeKeyValueStore() -> SecondCameraEditorKeyValueStore {
        SecondCameraEditorKeyValueStore(collection: "SecondCameraEditorImageQualityLevel")
    }
}

public enum SecondCameraEditorImageQualityTier: UInt {
    case one = 1
    case two = 2
    case three = 3
    case four = 4
    case five = 5
    case six = 6
    case seven = 7

    public var maxEdgeSize: CGFloat {
        switch self {
        case .one: return 512
        case .two: return 768
        case .three: return 1024
        case .four: return 1600
        case .five: return 2048
        case .six: return 3072
        case .seven: return 4096
        }
    }

    public var reduced: SecondCameraEditorImageQualityTier? { .init(rawValue: rawValue - 1) }
    public var increased: SecondCameraEditorImageQualityTier? { .init(rawValue: rawValue + 1) }
}
