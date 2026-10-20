/// 自定义相机临时文件存储，预留后续上传前处理与清理能力。

import Foundation

enum CustomCameraFileStore {
    static var temporaryDirectory: URL {
        StoragePaths.system.camera
    }

    static func ensureTemporaryDirectory() throws {
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    static func removeExpiredTemporaryFiles(olderThan interval: TimeInterval = 24 * 60 * 60) {
        // Age alone cannot prove that a capture is saved or unused. The owning session
        // removes its abandoned files explicitly; unfinished media is preserved.
        _ = interval
    }
}
