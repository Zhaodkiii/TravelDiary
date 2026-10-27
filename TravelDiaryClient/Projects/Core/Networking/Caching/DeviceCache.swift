import Foundation

/// 网络模块的设备侧缓存中心。
/// 职责参考 purchases-ios 的 DeviceCache：
/// 1. 维护设备级缓存元数据
/// 2. 提供 UserDefaults + 文件系统双层存储
/// 3. 统一管理 ETag、本地响应体、用户/设备上下文、日志配置
final class DeviceCache: @unchecked Sendable {
    private enum Keys {
        static let currentUserID = "support.device_cache.current_user_id"
        static let trustedDeviceID = "support.device_cache.trusted_device_id"
        static let lastLoggedInAccountID = "support.device_cache.last_logged_in_account_id"
        static let logLevel = "support.device_cache.log_level"
        static let registrationSubmittedSnapshot = "support.device_cache.registration_submitted_snapshot"
    }

    private let userDefaults: UserDefaults
    private let fileManager: FileManager
    private let baseDirectory: URL
    private let logger: Logger

    private let cachedCurrentUserID: Atomic<String?>
    private let cachedTrustedDeviceID: Atomic<String?>
    private let cachedLastLoggedInAccountID: Atomic<String?>
    private let cachedLogLevel: Atomic<LogLevel?>

    init(
        userDefaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        baseDirectory: URL? = nil,
        logger: Logger = ConsoleLogger()
    ) {
        self.userDefaults = userDefaults
        self.fileManager = fileManager
        self.logger = logger

        if let baseDirectory {
            self.baseDirectory = baseDirectory
        } else {
            self.baseDirectory = StoragePaths.system.cache("NetworkResponses")
        }

        self.cachedCurrentUserID = Atomic(userDefaults.string(forKey: Keys.currentUserID))
        self.cachedTrustedDeviceID = Atomic(userDefaults.string(forKey: Keys.trustedDeviceID))
        self.cachedLastLoggedInAccountID = Atomic(userDefaults.string(forKey: Keys.lastLoggedInAccountID))

        if let storedLevelRaw = userDefaults.object(forKey: Keys.logLevel) as? Int,
           let level = LogLevel(rawValue: storedLevelRaw) {
            self.cachedLogLevel = Atomic(level)
        } else {
            self.cachedLogLevel = Atomic(nil)
        }
    }

    var currentUserID: String? { cachedCurrentUserID.value }
    var currentUserIDInt: Int? { cachedCurrentUserID.value.flatMap(Int.init) }
    var trustedDeviceID: String? { cachedTrustedDeviceID.value }
    var lastLoggedInAccountID: Int? { cachedLastLoggedInAccountID.value.flatMap(Int.init) }
    var persistedLogLevel: LogLevel? { cachedLogLevel.value }

    func cache(currentUserID: String) {
        userDefaults.set(currentUserID, forKey: Keys.currentUserID)
        cachedCurrentUserID.value = currentUserID
        logger.debug("已缓存当前用户 ID=\(currentUserID)", module: .cache)
    }

    func cache(currentUserID: Int64) {
        cache(currentUserID: String(currentUserID))
    }

    func cache(trustedDeviceID: String) {
        userDefaults.set(trustedDeviceID, forKey: Keys.trustedDeviceID)
        cachedTrustedDeviceID.value = trustedDeviceID
        logger.debug("已缓存可信设备 ID=\(trustedDeviceID)", module: .cache)
    }

    func cacheLastLoggedInAccountID(_ accountID: Int64) {
        let value = String(accountID)
        userDefaults.set(value, forKey: Keys.lastLoggedInAccountID)
        cachedLastLoggedInAccountID.value = value
        logger.debug("已缓存上次登录账号 ID=\(accountID)", module: .cache)
    }

    func cacheLastLoggedInAccountID(_ accountID: Int) {
        cacheLastLoggedInAccountID(Int64(accountID))
    }

    func cache(logLevel: LogLevel) {
        userDefaults.set(logLevel.rawValue, forKey: Keys.logLevel)
        cachedLogLevel.value = logLevel
        logger.info("已持久化日志级别=\(logLevel.symbol)", module: .cache)
    }

    var lastDeviceRegistrationSnapshot: DeviceRegistrationSubmittedSnapshot? {
        guard let data = userDefaults.data(forKey: Keys.registrationSubmittedSnapshot) else {
            return nil
        }
        return try? JSONDecoder.default.decode(DeviceRegistrationSubmittedSnapshot.self, from: data)
    }

    func cacheDeviceRegistrationSnapshot(_ snapshot: DeviceRegistrationSubmittedSnapshot) {
        guard let data = try? JSONEncoder.default.encode(snapshot) else { return }
        userDefaults.set(data, forKey: Keys.registrationSubmittedSnapshot)
        logger.debug("已持久化设备登记摘要 bundleID=\(snapshot.bundleID)", module: .cache)
    }

    func clearDeviceRegistrationSnapshot() {
        userDefaults.removeObject(forKey: Keys.registrationSubmittedSnapshot)
    }

    /// 登出/鉴权失效：清理当前会话相关设备缓存，保留 `lastLoggedInAccountID`（APP-STARTUP-000009）。
    func clearAuthenticatedDeviceState() {
        userDefaults.removeObject(forKey: Keys.currentUserID)
        userDefaults.removeObject(forKey: Keys.trustedDeviceID)
        userDefaults.removeObject(forKey: Keys.registrationSubmittedSnapshot)
        cachedCurrentUserID.value = nil
        cachedTrustedDeviceID.value = nil
    }

    func clearDeviceMetadata() {
        clearAuthenticatedDeviceState()
    }

    func clearAllCaches() {
        ResourceCache.shared.clear(category: "network-responses")
        clearAuthenticatedDeviceState()
        userDefaults.removeObject(forKey: Keys.lastLoggedInAccountID)
        cachedLastLoggedInAccountID.value = nil
        userDefaults.removeObject(forKey: Keys.logLevel)
        cachedLogLevel.value = nil

        if fileManager.fileExists(atPath: baseDirectory.path) {
            try? fileManager.removeItem(at: baseDirectory)
        }
    }

    /// 删除磁盘上的 HTTP 条件请求（ETag / 304 合并用）缓存，不影响 UserDefaults 中的设备元数据或日志级别。
    func clearETagResponseCache() {
        ResourceCache.shared.clear(category: "network-responses")
        if fileManager.fileExists(atPath: baseDirectory.path) {
            try? fileManager.removeItem(at: baseDirectory)
        }
        let responses = StoragePaths.system.cache("ETagResponses")
        if fileManager.fileExists(atPath: responses.path) { try? fileManager.removeItem(at: responses) }
    }

    fileprivate func metadataURL(for key: String) -> URL {
        baseDirectory.appendingPathComponent("\(key).meta.json", isDirectory: false)
    }

    fileprivate func bodyURL(for key: String) -> URL {
        baseDirectory.appendingPathComponent("\(key).body", isDirectory: false)
    }
}

extension DeviceCache: ETagStore {
    func record(forKey key: String) -> ETagCacheRecord? {
        let unified = ResourceETagCache(baseDirectory: baseDirectory)
        if unified.enabled { return unified.read(key)?.record }
        let url = metadataURL(for: key)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder.default.decode(ETagCacheRecord.self, from: data)
    }

    func cachedBody(forKey key: String) -> Data? {
        let unified = ResourceETagCache(baseDirectory: baseDirectory)
        if unified.enabled { return unified.read(key)?.body }
        return try? Data(contentsOf: bodyURL(for: key))
    }

    func store(record: ETagCacheRecord, body: Data, forKey key: String) throws {
        let unified = ResourceETagCache(baseDirectory: baseDirectory)
        if unified.enabled { try unified.store(record: record, body: body, identity: key); return }
        if !fileManager.fileExists(atPath: baseDirectory.path) {
            try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        }

        try AtomicFileWriter.write(try JSONEncoder.default.encode(record), to: metadataURL(for: key))
        try AtomicFileWriter.write(body, to: bodyURL(for: key))
    }

    func removeCache(forKey key: String) {
        ResourceETagCache(baseDirectory: baseDirectory).remove(key)
        try? fileManager.removeItem(at: metadataURL(for: key))
        try? fileManager.removeItem(at: bodyURL(for: key))
    }
}
