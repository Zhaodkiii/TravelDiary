import Foundation

struct DeviceRegistrationRequest: Codable, Sendable, Equatable {
    var deviceID: String
    var userID: Int64?
    var pushToken: String?
    var notificationsEnabled: Bool?
    var appVersion: String
    var buildVersion: String
    var bundleIdentifier: String
    var bundleID: String
    var platform: String
    var systemVersion: String
    var deviceModel: String
    var deviceModelName: String
    var deviceName: String
    var screenSize: String
    var screenScale: Double
    var timeZone: String
    var languageCode: String
    var regionCode: String
    var countryCode: String
    var isSimulator: Bool

    enum CodingKeys: String, CodingKey {
        case deviceID = "deviceId"
        case userID = "userId"
        case pushToken = "pushToken"
        case notificationsEnabled = "notificationsEnabled"
        case appVersion = "appVersion"
        case buildVersion = "buildVersion"
        case bundleIdentifier = "bundleIdentifier"
        case bundleID = "bundleId"
        case platform
        case systemVersion = "systemVersion"
        case deviceModel = "deviceModel"
        case deviceModelName = "deviceModelName"
        case deviceName = "deviceName"
        case screenSize = "screenSize"
        case screenScale = "screenScale"
        case timeZone = "timeZone"
        case languageCode = "languageCode"
        case regionCode = "regionCode"
        case countryCode = "countryCode"
        case isSimulator = "isSimulator"
    }
}

struct DeviceRegistrationResponse: Decodable, Sendable {
    let deviceID: String?
    let userID: Int64?
    let registered: Bool?

    enum CodingKeys: String, CodingKey {
        case deviceID = "deviceId"
        case userID = "userId"
        case registered
    }
}


struct SupportDeviceAPI {
    let configuration: SupportBackendConfiguration

    init(configuration: SupportBackendConfiguration) {
        self.configuration = configuration
    }

    init(engine: SupportNetworkEngine) {
        self.configuration = SupportBackendConfiguration(engine: engine, logger: engine.networkLogger)
    }

    func register(_ request: DeviceRegistrationRequest, authenticated: Bool) async throws -> DeviceRegistrationResponse {
        let operation = CacheableSupportNetworkOperation(
            name: "Device.Register",
            apiName: "DeviceAPI",
            request: .init(
                method: .post,
                path: "/api/v1/device/register/",
                body: .json(AnyEncodable(request)),
                strategy: .init(requiresAuth: authenticated)
            )
        )
        return try await configuration.executeDecoded(DeviceRegistrationResponse.self, operation: operation)
    }
}

struct ManagedFileUploadPayload: Sendable {
    let data: Data
    let fileName: String
    let businessType: String
    let businessID: String
    let isPublic: Bool
    /// 上传进度 0.0 ... 1.0；在 OSS `putObject` 阶段回调（`OSSClientWrapper` 已在主线程派发）。
    let onUploadProgress: (@Sendable (Double) -> Void)?

    init(
        data: Data,
        fileName: String,
        businessType: String,
        businessID: String,
        isPublic: Bool,
        onUploadProgress: (@Sendable (Double) -> Void)? = nil
    ) {
        self.data = data
        self.fileName = fileName
        self.businessType = businessType
        self.businessID = businessID
        self.isPublic = isPublic
        self.onUploadProgress = onUploadProgress
    }
}

struct ManagedFileRecord: Codable, Identifiable, Sendable {
    let id: Int
    let fileUUID: String
    let filePath: String?
    let originalName: String
    let fileSize: Int
    let mimeType: String
    let fileMD5: String?
    let objectKey: String?
    let storageType: String?

    enum CodingKeys: String, CodingKey {
        case id
        case fileUUID = "fileUuid"
        case filePath = "filePath"
        case originalName = "originalName"
        case fileSize = "fileSize"
        case mimeType = "mimeType"
        case fileMD5 = "fileMd5"
        case objectKey = "objectKey"
        case storageType = "storageType"
    }
}

struct ManagedFileBusinessUpdateItem: Codable, Sendable {
    let fileId: Int
    let businessType: String
    let businessId: String

    enum CodingKeys: String, CodingKey {
        case fileId = "fileId"
        case businessType = "businessType"
        case businessId = "businessId"
    }
}

struct SupportFileAPI {
    let configuration: SupportBackendConfiguration

    init(configuration: SupportBackendConfiguration) {
        self.configuration = configuration
    }

    init(engine: SupportNetworkEngine) {
        self.configuration = SupportBackendConfiguration(engine: engine, logger: engine.networkLogger)
    }

    func registerFile(_ request: ManagedFileUploadRequest) async throws -> ManagedFileRecord {
        let operation = CacheableSupportNetworkOperation(
            name: "File.Register",
            apiName: "FileAPI",
            request: .init(
                method: .post,
                path: "/api/v1/files/register/",
                body: .json(AnyEncodable(request)),
                strategy: .init(requiresAuth: true)
            )
        )
        return try await configuration.executeDecoded(ManagedFileRecord.self, operation: operation)
    }

    func list(
        businessType: String? = nil,
        businessID: String? = nil,
        isPublic: Bool? = nil
    ) async throws -> [ManagedFileRecord] {
        var queryItems: [URLQueryItem] = []
        if let businessType, !businessType.isEmpty {
            queryItems.append(URLQueryItem(name: "business_type", value: businessType))
        }
        if let businessID, !businessID.isEmpty {
            queryItems.append(URLQueryItem(name: "business_id", value: businessID))
        }
        if let isPublic {
            queryItems.append(URLQueryItem(name: "is_public", value: isPublic ? "1" : "0"))
        }
        let operation = CacheableSupportNetworkOperation(
            name: "File.List",
            apiName: "FileAPI",
            request: .init(
                method: .get,
                path: "/api/v1/files/",
                queryItems: queryItems.isEmpty ? nil : queryItems,
                strategy: .init(
                    requiresAuth: true,
                    allowETag: true,
                    serialKey: "files.list",
                    isIdempotent: true,
                    etagTTL: 60
                )
            )
        )
        return try await configuration.executeDecoded([ManagedFileRecord].self, operation: operation)
    }

    func updateBusinessBinding(_ item: ManagedFileBusinessUpdateItem) async throws -> ManagedFileRecord {
        let operation = CacheableSupportNetworkOperation(
            name: "File.UpdateBinding",
            apiName: "FileAPI",
            request: .init(
                method: .patch,
                path: "/api/v1/files/business/update/",
                body: .json(AnyEncodable(item)),
                strategy: .init(requiresAuth: true)
            )
        )
        return try await configuration.executeDecoded(ManagedFileRecord.self, operation: operation)
    }

    func delete(fileID: Int) async throws {
        let operation = CacheableSupportNetworkOperation(
            name: "File.Delete",
            apiName: "FileAPI",
            request: .init(
                method: .delete,
                path: "/api/v1/files/\(fileID)/",
                strategy: .init(requiresAuth: true)
            )
        )
        _ = try await configuration.execute(operation)
    }
}

struct ManagedFileUploadRequest: Encodable, Sendable {
    let fileUUID: String
    let originalName: String
    let fileSize: Int
    let mimeType: String
    let filePath: String
    let objectKey: String
    let storageType: String
    let businessType: String
    let businessID: String
    let isPublic: Bool
    let fileMD5: String

    enum CodingKeys: String, CodingKey {
        case fileUUID = "fileUuid"
        case originalName = "originalName"
        case fileSize = "fileSize"
        case mimeType = "mimeType"
        case filePath = "filePath"
        case objectKey = "objectKey"
        case storageType = "storageType"
        case businessType = "businessType"
        case businessID = "businessId"
        case isPublic = "isPublic"
        case fileMD5 = "fileMd5"
    }
}

/// Aliyun STS payload（OCR + OSS endpoints share the same shape）。
/// 依赖全局 `JSONDecoder.default` 的 `convertFromSnakeCase`：`bucket_name` → `bucketName`。
struct OCRSTSCredentialsResponse: Decodable, Sendable {
    let accessKeyID: String
    let accessKeySecret: String
    let securityToken: String?
    let expiration: String?
    let bucketName: String?
    let region: String?
    let endpoint: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodableKey.self)
        self.accessKeyID =
            (try? container.decode(String.self, forKey: .key("accessKeyId"))) ??
            (try? container.decode(String.self, forKey: .key("accessKeyID"))) ?? ""
        self.accessKeySecret =
            (try? container.decode(String.self, forKey: .key("accessKeySecret"))) ?? ""
        self.securityToken =
            try? container.decode(String.self, forKey: .key("securityToken"))
        self.expiration = Self.decodeExpiration(from: container)
        self.bucketName =
            (try? container.decode(String.self, forKey: .key("bucketName"))) ??
            (try? container.decode(String.self, forKey: .key("bucket")))
        self.region = try? container.decode(String.self, forKey: .key("region"))
        self.endpoint = try? container.decode(String.self, forKey: .key("endpoint"))
    }

    init(
        accessKeyID: String,
        accessKeySecret: String,
        securityToken: String?,
        expiration: String?,
        bucketName: String? = nil,
        region: String? = nil,
        endpoint: String? = nil
    ) {
        self.accessKeyID = accessKeyID
        self.accessKeySecret = accessKeySecret
        self.securityToken = securityToken
        self.expiration = expiration
        self.bucketName = bucketName
        self.region = region
        self.endpoint = endpoint
    }

    private static func decodeExpiration(from container: KeyedDecodingContainer<CodableKey>) -> String? {
        if let s = try? container.decode(String.self, forKey: .key("expiration")), !s.isEmpty {
            return s
        }
        if let i = try? container.decode(Int64.self, forKey: .key("expiration")) {
            return String(i)
        }
        if let i = try? container.decode(Int.self, forKey: .key("expiration")) {
            return String(i)
        }
        if let d = try? container.decode(Double.self, forKey: .key("expiration")) {
            return String(Int64(d))
        }
        return nil
    }
}

struct OSSCredentialsResponse: Decodable, Sendable {
    let accessKeyId: String
    let accessKeySecret: String
    let securityToken: String
    let expiration: String?
    let endpoint: String
    let bucket: String
    let region: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodableKey.self)
        // 依赖全局 convertFromSnakeCase：access_key_id → accessKeyId，bucket_name → bucketName。
        self.accessKeyId =
            (try? container.decode(String.self, forKey: .key("accessKeyId"))) ??
            (try? container.decode(String.self, forKey: .key("accessKeyID"))) ?? ""
        self.accessKeySecret =
            (try? container.decode(String.self, forKey: .key("accessKeySecret"))) ?? ""
        self.securityToken =
            (try? container.decode(String.self, forKey: .key("securityToken"))) ?? ""
        if let s = try? container.decode(String.self, forKey: .key("expiration")), !s.isEmpty {
            self.expiration = s
        } else if let i = try? container.decode(Int64.self, forKey: .key("expiration")) {
            self.expiration = String(i)
        } else if let d = try? container.decode(Double.self, forKey: .key("expiration")) {
            self.expiration = String(Int64(d))
        } else {
            self.expiration = nil
        }
        self.endpoint =
            (try? container.decode(String.self, forKey: .key("endpoint"))) ?? ""
        self.bucket =
            (try? container.decode(String.self, forKey: .key("bucketName"))) ??
            (try? container.decode(String.self, forKey: .key("bucket"))) ?? ""
        self.region = try? container.decode(String.self, forKey: .key("region"))
    }
}

struct SupportOSSAPI {
    let configuration: SupportBackendConfiguration

    init(configuration: SupportBackendConfiguration) {
        self.configuration = configuration
    }

    init(engine: SupportNetworkEngine) {
        self.configuration = SupportBackendConfiguration(engine: engine, logger: engine.networkLogger)
    }

    func getSTSCredentials() async throws -> OSSCredentialsResponse {
        let operation = CacheableSupportNetworkOperation(
            name: "OSS.STS",
            apiName: "OSSAPI",
            request: .init(
                method: .get,
                path: "/api/v1/oss/sts/credentials/",
                strategy: .init(requiresAuth: true, serialKey: "oss.sts.credentials")
            )
        )
        return try await configuration.executeDecoded(OSSCredentialsResponse.self, operation: operation)
    }
}

struct SupportOCRAPI {
    let configuration: SupportBackendConfiguration

    init(configuration: SupportBackendConfiguration) {
        self.configuration = configuration
    }

    init(engine: SupportNetworkEngine) {
        self.configuration = SupportBackendConfiguration(engine: engine, logger: engine.networkLogger)
    }

    func getSTSCredentials() async throws -> OCRSTSCredentialsResponse {
        let operation = CacheableSupportNetworkOperation(
            name: "OCR.STS",
            apiName: "OCRAPI",
            request: .init(
                method: .get,
                path: "/api/v1/oss/ocr/sts/credentials/",
                strategy: .init(requiresAuth: true, serialKey: "ocr.sts.credentials")
            )
        )
        return try await configuration.executeDecoded(OCRSTSCredentialsResponse.self, operation: operation)
    }
}
