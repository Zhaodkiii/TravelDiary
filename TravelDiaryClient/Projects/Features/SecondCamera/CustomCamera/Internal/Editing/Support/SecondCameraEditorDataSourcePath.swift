//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class SecondCameraEditorDataSourcePath: @unchecked Sendable {
    public enum Ownership: Sendable {
        /// The `SecondCameraEditorDataSourcePath` owns this URL and may consume it.
        case owned

        /// The `SecondCameraEditorDataSourcePath` is borrowing a reference to this file and must not
        /// touch it.
        case borrowed
    }

    nonisolated public init(fileUrl: URL, ownership: Ownership) {
        secondCameraEditorPrecondition(fileUrl.isFileURL)
        self.fileUrl = fileUrl
        self.ownership = ownership
    }

    nonisolated public convenience init(filePath: String, ownership: Ownership) {
        let fileUrl = URL(fileURLWithPath: filePath)
        self.init(fileUrl: fileUrl, ownership: ownership)
    }

    nonisolated public convenience init(writingTempFileData: Data, fileExtension: String) throws {
        let fileUrl = SecondCameraEditorFileSystem.temporaryFileUrl(fileExtension: fileExtension, isAvailableWhileDeviceLocked: true)
        try writingTempFileData.write(to: fileUrl, options: .completeFileProtectionUntilFirstUserAuthentication)
        self.init(fileUrl: fileUrl, ownership: .owned)
    }

    nonisolated public convenience init(writingSyncMessageData: Data) throws {
        try self.init(writingTempFileData: writingSyncMessageData, fileExtension: SecondCameraEditorMimeTypeUtil.syncMessageFileExtension)
    }

    deinit {
        if case .owned = ownership, !isConsumed.get() {
            do {
                try SecondCameraEditorFileSystem.deleteFileIfExists(url: fileUrl)
            } catch {
                secondCameraEditorFailDebug("SecondCameraEditorDataSourcePath could not delete file: \(fileUrl), \(error)")
            }
        }
    }

    nonisolated(unsafe) public let fileUrl: URL
    nonisolated(unsafe) private let ownership: Ownership
    nonisolated(unsafe) private let isConsumed = SecondCameraEditorAtomicBool(false, lock: .init())

    nonisolated(unsafe) private var _sourceFilename: String?
    nonisolated public var sourceFilename: String? {
        get {
            return _sourceFilename
        }
        set {
            secondCameraEditorAssertDebug(!isConsumed.get())
            _sourceFilename = newValue?.secondCameraEditor_filterFilename()
        }
    }

    nonisolated public func readData() throws -> Data {
        secondCameraEditorAssertDebug(!isConsumed.get())
        return try Data(contentsOf: fileUrl, options: [.mappedIfSafe])
    }

    nonisolated public func readLength() throws -> UInt64 {
        secondCameraEditorAssertDebug(!isConsumed.get())
        return UInt64(try fileUrl.resourceValues(forKeys: [.fileSizeKey]).fileSize!)
    }

    nonisolated public func consumeAndDeleteIfNecessary() throws {
        secondCameraEditorAssertDebug(isConsumed.tryToSetFlag())
        if case .owned = ownership {
            try SecondCameraEditorFileSystem.deleteFileIfExists(url: fileUrl)
        }
    }

    nonisolated public func imageSource() throws -> any SecondCameraEditorImageSource {
        return try SecondCameraEditorDataImageSource.forPath(self.fileUrl.path)
    }
}
