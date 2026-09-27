//
// Signal Camera - Simplified SecondCameraEditorFileSystem for media capture
//

import Foundation

public enum SecondCameraEditorFileSystem {
    nonisolated public static func temporaryFileUrl(
        fileExtension: String,
        isAvailableWhileDeviceLocked: Bool = true,
    ) -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let filename = UUID().uuidString + "." + fileExtension
        return dir.appendingPathComponent(filename)
    }

    nonisolated public static func temporaryFilePath(fileExtension: String, isAvailableWhileDeviceLocked: Bool = true) -> String {
        temporaryFileUrl(fileExtension: fileExtension, isAvailableWhileDeviceLocked: isAvailableWhileDeviceLocked).path
    }

    nonisolated public static func deleteFile(url: URL) throws {
        try deleteFileIfExists(url: url)
    }

    nonisolated public static func fileSize(of url: URL) throws -> UInt64 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        return UInt64(values.fileSize ?? 0)
    }

    nonisolated public static func deleteFileIfExists(url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    nonisolated public static func ensureDirectoryExists(_ path: String, fileProtectionType: FileProtectionType = .completeUntilFirstUserAuthentication) -> Bool {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDir) {
            return isDir.boolValue
        }
        do {
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
            return true
        } catch {
            return false
        }
    }

    nonisolated public static func appDocumentDirectoryPath() -> String {
        NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!
    }

    nonisolated public static func appSharedDataDirectoryPath() -> String {
        appDocumentDirectoryPath()
    }

    nonisolated public static func appSharedDataDirectoryURL() -> URL {
        URL(fileURLWithPath: appSharedDataDirectoryPath(), isDirectory: true)
    }

    nonisolated public static func clearOldTemporaryDirectories() {}
}

public extension Error {
    var secondCameraEditor_shortDescription: String { localizedDescription }
}

public extension TimeInterval {
    var secondCameraEditor_clampedNanoseconds: UInt64 {
        UInt64(max(0, self) * 1_000_000_000)
    }
}
