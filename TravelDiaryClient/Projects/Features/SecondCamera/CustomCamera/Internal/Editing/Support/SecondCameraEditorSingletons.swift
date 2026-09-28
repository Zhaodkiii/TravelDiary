//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class SecondCameraEditorSingletons: @unchecked Sendable {
    nonisolated(unsafe) private static let shared = SecondCameraEditorSingletons()

    private var registeredTypes = Set<ObjectIdentifier>()

    public func register(_ singleton: AnyObject) {
        assert({
            guard !SecondCameraEditorCurrentAppContext().isRunningTests else {
                // Allow multiple registrations while tests are running.
                return true
            }
            let singletonTypeIdentifier = ObjectIdentifier(type(of: singleton))
            let (justAdded, _) = registeredTypes.insert(singletonTypeIdentifier)
            return justAdded
        }(), "Duplicate singleton.")
    }

    public static func register(_ singleton: AnyObject) {
        shared.register(singleton)
    }
}
