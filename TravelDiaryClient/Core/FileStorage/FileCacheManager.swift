import CryptoKit
import Foundation

/// 文件缓存管理器：负责本地文件的持久化存储、读取、校验与清理
actor FileCacheManager {
    static let shared = FileCacheManager()

    private let resourceCache: ResourceCache
    private let fileManager: FileManager
    private let logger: Logger
    private let baseDirectory: URL
    private var accountNamespace: String = "signed-out"

    init(fileManager: FileManager = .default, logger: Logger = ConsoleLogger(), baseDirectory: URL? = nil, resourceCache: ResourceCache = .shared) {
        self.resourceCache = resourceCache
        self.fileManager = fileManager
        self.logger = logger

        self.baseDirectory = baseDirectory ?? StoragePaths.system.fileCache
    }

    func accountContext() -> String { accountNamespace }
    func cachedFileURL(fileUUID: String, fileName: String, namespace: String? = nil) -> URL? {
        let normalizedUUID = fileUUID.lowercased()
        let destination = fileURL(fileUUID: normalizedUUID, fileName: fileName, namespace: namespace)
        guard fileManager.fileExists(atPath: destination.path) else {
            return nil
        }
        resourceCache.touch(url: destination)
        return destination
    }

    func markRebuildable(fileUUID: String, fileName: String, namespace: String) {
        let url = fileURL(fileUUID: fileUUID.lowercased(), fileName: fileName, namespace: namespace)
        let key = ResourceCacheKey(scope: namespace, category: "attachments", identity: fileUUID.lowercased() + ":" + fileName)
        resourceCache.register(url, for: key)
    }

    func activateAccountContext(_ accountID: Int64) {
        accountNamespace = StoragePaths.scopeKey(String(accountID))
        logger.info("文件缓存已切换到账号命名空间 accountID=\(accountID)", module: .cache)
    }

    func activateGuestContext() {
        accountNamespace = "signed-out"
        logger.info("文件缓存已切换到访客命名空间", module: .cache)
    }

    @discardableResult
    func save(data: Data, fileUUID: String, fileName: String, namespace: String? = nil, automaticallyEvictable: Bool = false) throws -> URL {
        let normalizedUUID = fileUUID.lowercased()
        let directory = directoryURL(for: normalizedUUID, namespace: namespace)

        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        let destination = fileURL(fileUUID: normalizedUUID, fileName: fileName, namespace: namespace)

        try data.write(to: destination, options: [.atomic])
        if automaticallyEvictable { markRebuildable(fileUUID: normalizedUUID, fileName: fileName, namespace: namespace ?? accountNamespace) }
        logger.debug("文件缓存写入成功，uuid=\(normalizedUUID)，name=\(fileName)", module: .cache)
        return destination
    }

    func validateMD5(fileUUID: String, fileName: String, expectedMD5: String, namespace: String? = nil) -> Bool {
        guard let url = cachedFileURL(fileUUID: fileUUID, fileName: fileName, namespace: namespace),
              let data = try? Data(contentsOf: url) else {
            return false
        }
        let digest = Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return digest.caseInsensitiveCompare(expectedMD5) == .orderedSame
    }

    func remove(fileUUID: String, namespace: String? = nil) throws {
        let directory = directoryURL(for: fileUUID.lowercased(), namespace: namespace)
        guard fileManager.fileExists(atPath: directory.path) else { return }
        for entry in resourceCache.entries() where StoragePaths.contains(entry.url, in: directory) { resourceCache.forget(url: entry.url) }
        try fileManager.removeItem(at: directory)
        logger.info("已移除文件缓存目录，uuid=\(fileUUID)", module: .cache)
    }

    func clearAll() throws {
        try clear(namespace: accountNamespace)
    }

    func clear(namespace: String) throws {
        guard namespace == "signed-out" || (namespace.count == 64 && namespace.allSatisfy({ $0.isHexDigit })) else { throw StorageFailure.unsafePath }
        let directory = baseDirectory.appendingPathComponent(namespace, isDirectory: true).appendingPathComponent("Attachments", isDirectory: true)
        guard fileManager.fileExists(atPath: directory.path) else { return }
        for entry in resourceCache.entries() where StoragePaths.contains(entry.url, in: directory) { resourceCache.forget(url: entry.url) }
        try fileManager.removeItem(at: directory)
        logger.info("已清理当前账号的附件缓存", module: .cache)
    }

    func cacheStatistics() -> (fileCount: Int, totalBytes: Int64) {
        let directory = baseDirectory.appendingPathComponent(accountNamespace, isDirectory: true).appendingPathComponent("Attachments", isDirectory: true)
        guard fileManager.fileExists(atPath: directory.path),
              let enumerator = fileManager.enumerator(
                at: directory,
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

    private func directoryURL(for fileUUID: String, namespace: String? = nil) -> URL {
        baseDirectory
            .appendingPathComponent(namespace ?? accountNamespace, isDirectory: true)
            .appendingPathComponent("Attachments", isDirectory: true)
            .appendingPathComponent(StoragePaths.digest(fileUUID.lowercased()), isDirectory: true)
    }

    private func fileURL(fileUUID: String, fileName: String, namespace: String? = nil) -> URL {
        directoryURL(for: fileUUID, namespace: namespace).appendingPathComponent(sanitizedFileName(fileName), isDirectory: false)
    }

    private func sanitizedFileName(_ raw: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let components = raw.components(separatedBy: invalid)
        let collapsed = components.joined(separator: "_")
        return collapsed.isEmpty ? "unnamed_file" : collapsed
    }
}
