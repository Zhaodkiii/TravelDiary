import CryptoKit
import Foundation

protocol OSSRuntimeConfiguring: AnyObject, Sendable {
    func updateConfiguration(endpoint: String, bucket: String, region: String)
    func resetRuntimeCredentials()
}

extension OSSManager: OSSRuntimeConfiguring {}

final class NoopOSSRuntimeConfigurator: OSSRuntimeConfiguring {
    func updateConfiguration(endpoint: String, bucket: String, region: String) {}
    func resetRuntimeCredentials() {}
}

enum SupportFileTransferError: LocalizedError {
    case invalidDownloadURL
    case md5Mismatch
    case emptyObjectKey

    var errorDescription: String? {
        switch self {
        case .invalidDownloadURL:
            return "附件直链无效，无法下载"
        case .md5Mismatch:
            return "下载文件校验失败"
        case .emptyObjectKey:
            return "objectKey 为空，无法生成下载链接"
        }
    }
}

/// 文件传输服务：负责文件的上传、下载、缓存管理及 MD5 校验
actor FileTransferService {
    private let api: SupportFileAPI
    private let ossAPI: SupportOSSAPI
    private let ossClient: OSSClientWrapper
    private let ossRuntimeConfigurator: any OSSRuntimeConfiguring
    private let ossConfigurationStore: SupportOSSConfigurationStore
    private let cacheManager: FileCacheManager
    private let logger: Logger

    init(
        api: SupportFileAPI,
        ossAPI: SupportOSSAPI,
        ossClient: OSSClientWrapper,
        ossRuntimeConfigurator: any OSSRuntimeConfiguring,
        ossConfigurationStore: SupportOSSConfigurationStore,
        cacheManager: FileCacheManager,
        logger: Logger = ConsoleLogger()
    ) {
        self.api = api
        self.ossAPI = ossAPI
        self.ossClient = ossClient
        self.ossRuntimeConfigurator = ossRuntimeConfigurator
        self.ossConfigurationStore = ossConfigurationStore
        self.cacheManager = cacheManager
        self.logger = logger
    }

    /// 账号切换/登出时统一清理 STS 与运行时 OSS client，防止跨账号复用旧临时凭证。
    func resetRuntimeCredentials() async {
        await MainActor.run {
            ossConfigurationStore.clear()
            ossRuntimeConfigurator.resetRuntimeCredentials()
        }
        logger.info("文件传输运行时凭证已清理", module: .oss)
    }

    @discardableResult
    func upload(_ payload: ManagedFileUploadPayload) async throws -> ManagedFileRecord {
        let fileUuid = UUID().uuidString
        let fileMD5 = FileUtilities.md5Hex(payload.data)
        let safeFileName = FileUtilities.sanitizeFileName(payload.fileName)

        _ = try await cacheManager.save(
            data: payload.data,
            fileUUID: fileUuid,
            fileName: safeFileName
        )

        let ymd = Self.dayFormatter.string(from: Date())
        let objectKey = FileUtilities.makeObjectKey(
            prefix: "SupplyChainClient/\(ymd)",
            uuidString: fileUuid,
            filename: safeFileName
        )
        let mimeType = FileUtilities.mimeType(forName: safeFileName)

        let runtimeConfig = try await ossConfigurationStore.configurationForUpload(using: ossAPI)
        await MainActor.run {
            ossRuntimeConfigurator.updateConfiguration(
                endpoint: runtimeConfig.endpointURL,
                bucket: runtimeConfig.bucketName,
                region: runtimeConfig.region
            )
        }

        try await ossClient.putObject(
            data: payload.data,
            objectKey: objectKey,
            contentType: mimeType,
            progressCallback: { [logger] progress in
                logger.debug(
                    "上传进度 progress=\(String(format: "%.2f", progress)) fileUUID=\(fileUuid)",
                    module: .file
                )
                payload.onUploadProgress?(progress)
            }
        )

        let uploaded = try await api.registerFile(
            ManagedFileUploadRequest(
                fileUUID: fileUuid,
                originalName: safeFileName,
                fileSize: payload.data.count,
                mimeType: mimeType,
                filePath: objectKey,
                objectKey: objectKey,
                storageType: "oss",
                businessType: payload.businessType,
                businessID: payload.businessID,
                isPublic: payload.isPublic,
                fileMD5: fileMD5
            )
        )

        let cacheMatches = await cacheManager.validateMD5(
            fileUUID: fileUuid,
            fileName: safeFileName,
            expectedMD5: fileMD5
        )
        if !cacheMatches {
            logger.warning(
                "上传完成后本地缓存 MD5 与预期不一致，uuid=\(fileUuid)，name=\(safeFileName)",
                module: .cache
            )
        }

        logger.info("文件上传完成，file_id=\(uploaded.id)，uuid=\(uploaded.fileUUID)", module: .cache)
        return uploaded
    }

    func publicHTTPSURLForObjectKey(_ objectKey: String?) async -> URL? {
        let trimmed = objectKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard trimmed.isEmpty == false else { return nil }
        do {
            let cfg = try await ossConfigurationStore.configurationForUpload(using: ossAPI)
            return Self.makePublicObjectURL(endpoint: cfg.endpointURL, bucket: cfg.bucketName, objectKey: trimmed)
        } catch {
            logger.debug("无法拼接 OSS 公网 URL：\(error.localizedDescription)", module: .cache)
            return nil
        }
    }

    func download(file: ManagedFileRecord, forceRefresh: Bool = false) async throws -> URL {
        if !forceRefresh,
           let cachedURL = await cacheManager.cachedFileURL(fileUUID: file.fileUUID, fileName: file.originalName) {
            if let fileMd5 = file.fileMD5 {
                let valid = await cacheManager.validateMD5(
                    fileUUID: file.fileUUID,
                    fileName: file.originalName,
                    expectedMD5: fileMd5
                )
                if valid {
                    logger.debug("命中本地缓存并通过 MD5 校验，file_id=\(file.id)", module: .cache)
                    return cachedURL
                }
                try? await cacheManager.remove(fileUUID: file.fileUUID)
            } else {
                logger.debug("命中本地缓存，file_id=\(file.id)", module: .cache)
                return cachedURL
            }
        }

        guard let rawPath = file.filePath?.trimmingCharacters(in: .whitespacesAndNewlines),
              rawPath.isEmpty == false,
              let downloadURL = URL(string: rawPath) else {
            throw SupportFileTransferError.invalidDownloadURL
        }
        logger.debug("使用附件直链下载，file_id=\(file.id)", module: .cache)
        let (data, _) = try await URLSession.shared.data(from: downloadURL)

        if let expectedMD5 = file.fileMD5 {
            let actualMD5 = Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard actualMD5.caseInsensitiveCompare(expectedMD5) == .orderedSame else {
                logger.error(
                    "下载文件 MD5 校验失败，file_id=\(file.id)，expected=\(expectedMD5)，actual=\(actualMD5)",
                    module: .cache
                )
                throw SupportFileTransferError.md5Mismatch
            }
        }

        let localURL = try await cacheManager.save(
            data: data,
            fileUUID: file.fileUUID,
            fileName: file.originalName
        )
        logger.info("文件下载并缓存完成，file_id=\(file.id)", module: .cache)
        return localURL
    }

    func cachedURL(file: ManagedFileRecord) async -> URL? {
        await cacheManager.cachedFileURL(fileUUID: file.fileUUID, fileName: file.originalName)
    }

    func makePresignedDownloadURL(objectKey: String, expires: TimeInterval = 3600) async throws -> URL {
        let trimmed = objectKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw SupportFileTransferError.emptyObjectKey
        }
        let runtimeConfig = try await ossConfigurationStore.configurationForUpload(using: ossAPI)
        await MainActor.run {
            ossRuntimeConfigurator.updateConfiguration(
                endpoint: runtimeConfig.endpointURL,
                bucket: runtimeConfig.bucketName,
                region: runtimeConfig.region
            )
        }
        return try await ossClient.presignedURL(objectKey: trimmed, expires: expires)
    }

    func list(
        businessType: String? = nil,
        businessID: String? = nil,
        isPublic: Bool? = nil
    ) async throws -> [ManagedFileRecord] {
        try await api.list(businessType: businessType, businessID: businessID, isPublic: isPublic)
    }

    @discardableResult
    func updateBusinessBinding(fileID: Int, businessType: String, businessID: String) async throws -> ManagedFileRecord {
        try await api.updateBusinessBinding(
            ManagedFileBusinessUpdateItem(
                fileId: fileID,
                businessType: businessType,
                businessId: businessID
            )
        )
    }

    func delete(fileID: Int) async throws {
        try await api.delete(fileID: fileID)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd"
        return formatter
    }()

    /// `https://{bucket}.{endpointHost}/{objectKey}`
    nonisolated static func makePublicObjectURL(endpoint: String, bucket: String, objectKey: String) -> URL? {
        let key = objectKey.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let bucketTrimmed = bucket.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.isEmpty == false, bucketTrimmed.isEmpty == false else { return nil }

        let endpointTrimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        var endpointString = endpointTrimmed
        if endpointString.hasPrefix("//") {
            endpointString = "https:" + endpointString
        }
        guard let endpointURL = URL(string: endpointString),
              let host = endpointURL.host else {
            return nil
        }
        let scheme = endpointURL.scheme ?? "https"
        return URL(string: "\(scheme)://\(bucketTrimmed).\(host)/\(key)")
    }
}
