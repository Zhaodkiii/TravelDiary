import CryptoKit
import Foundation

/// 文件缓存管理器：负责本地文件的持久化存储、读取、校验与清理
actor FileCacheManager {
    static let shared = FileCacheManager()

    private let fileManager: FileManager
    private let logger: Logger
    private let baseDirectory: URL
    private var accountNamespace: String = "guest"

    init(fileManager: FileManager = .default, logger: Logger = ConsoleLogger()) {
        self.fileManager = fileManager
        self.logger = logger

        if let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            self.baseDirectory = caches.appendingPathComponent("TravelDiary.FileCache", isDirectory: true)
        } else {
            self.baseDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("TravelDiary.FileCache", isDirectory: true)
        }
    }

    func cachedFileURL(fileUUID: String, fileName: String) -> URL? {
        let normalizedUUID = fileUUID.lowercased()
        let destination = fileURL(fileUUID: normalizedUUID, fileName: fileName)
        guard fileManager.fileExists(atPath: destination.path) else {
            return nil
        }
        return destination
    }

    func activateAccountContext(_ accountID: Int64) {
        accountNamespace = "account-\(accountID)"
        logger.info("文件缓存已切换到账号命名空间 accountID=\(accountID)", module: .cache)
    }

    func activateGuestContext() {
        accountNamespace = "guest"
        logger.info("文件缓存已切换到访客命名空间", module: .cache)
    }

    @discardableResult
    func save(data: Data, fileUUID: String, fileName: String) throws -> URL {
        let normalizedUUID = fileUUID.lowercased()
        let directory = directoryURL(for: normalizedUUID)

        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        let destination = fileURL(fileUUID: normalizedUUID, fileName: fileName)

        if fileManager.fileExists(atPath: destination.path),
           let attrs = try? fileManager.attributesOfItem(atPath: destination.path),
           let size = attrs[.size] as? NSNumber,
           size.intValue == data.count {
            return destination
        }

        try data.write(to: destination, options: [.atomic])
        logger.debug("文件缓存写入成功，uuid=\(normalizedUUID)，name=\(fileName)", module: .cache)
        return destination
    }

    func validateMD5(fileUUID: String, fileName: String, expectedMD5: String) -> Bool {
        guard let url = cachedFileURL(fileUUID: fileUUID, fileName: fileName),
              let data = try? Data(contentsOf: url) else {
            return false
        }
        let digest = Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return digest.caseInsensitiveCompare(expectedMD5) == .orderedSame
    }

    func remove(fileUUID: String) throws {
        let directory = directoryURL(for: fileUUID.lowercased())
        guard fileManager.fileExists(atPath: directory.path) else { return }
        try fileManager.removeItem(at: directory)
        logger.info("已移除文件缓存目录，uuid=\(fileUUID)", module: .cache)
    }

    func clearAll() throws {
        guard fileManager.fileExists(atPath: baseDirectory.path) else { return }
        try fileManager.removeItem(at: baseDirectory)
        logger.info("已清理所有文件缓存", module: .cache)
    }

    func cacheStatistics() -> (fileCount: Int, totalBytes: Int64) {
        guard fileManager.fileExists(atPath: baseDirectory.path),
              let enumerator = fileManager.enumerator(
                at: baseDirectory,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]
              ) else {
            return (0, 0)
        }

        var fileCount = 0
        var totalBytes: Int64 = 0
        while let fileURL = enumerator.nextObject() as? URL {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else {
                continue
            }
            fileCount += 1
            totalBytes += Int64(values.fileSize ?? 0)
        }
        return (fileCount, totalBytes)
    }

    private func directoryURL(for fileUUID: String) -> URL {
        baseDirectory
            .appendingPathComponent(accountNamespace, isDirectory: true)
            .appendingPathComponent(fileUUID, isDirectory: true)
    }

    private func fileURL(fileUUID: String, fileName: String) -> URL {
        directoryURL(for: fileUUID).appendingPathComponent(sanitizedFileName(fileName), isDirectory: false)
    }

    private func sanitizedFileName(_ raw: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let components = raw.components(separatedBy: invalid)
        let collapsed = components.joined(separator: "_")
        return collapsed.isEmpty ? "unnamed_file" : collapsed
    }
}
