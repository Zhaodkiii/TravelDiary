/// 自定义相机临时文件存储，预留后续上传前处理与清理能力。

import Foundation

enum CustomCameraFileStore {
    static var temporaryDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("custom-camera", isDirectory: true)
    }

    static func ensureTemporaryDirectory() throws {
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    static func removeExpiredTemporaryFiles(olderThan interval: TimeInterval = 24 * 60 * 60) {
        let fileManager = FileManager.default
        guard let urls = try? fileManager.contentsOfDirectory(
            at: temporaryDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let expirationDate = Date().addingTimeInterval(-interval)

        for url in urls {
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modifiedAt = values.contentModificationDate,
                  modifiedAt < expirationDate
            else { continue }

            try? fileManager.removeItem(at: url)
        }
    }
}
