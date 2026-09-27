//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public extension Bundle {
    nonisolated var secondCameraEditor_app: Bundle {
        if self.bundleURL.pathExtension == "appex" {
            let url = self.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
            if let otherBundle = Bundle(url: url) {
                return otherBundle
            }
            secondCameraEditorFailDebug("bundle of main app not found")
        }
        return self
    }
}

@inlinable
nonisolated public func SecondCameraEditorLocalizedString(_ key: String, tableName: String? = nil, value: String = "", comment: String) -> String {
    return NSLocalizedString(key, tableName: tableName, bundle: .main.secondCameraEditor_app, value: value, comment: comment)
}
