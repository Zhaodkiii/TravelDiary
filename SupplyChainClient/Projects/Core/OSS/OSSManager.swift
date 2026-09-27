import Foundation
import AliyunOSSSDK

final class OSSManager {
    static let shared = OSSManager()

    private(set) var client: OSSClient?
    private var currentCredentials: OSSCredentials?
    var credentialsProvider: (@Sendable () async throws -> OSSCredentials)?

    private let lock = NSRecursiveLock()
    private var refreshingTask: Task<OSSCredentials, Error>?

    private init() {}

    func updateConfiguration(endpoint: String, bucket: String, region: String) {
        withLock {
            OSSConfiguration.endpoint = endpoint
            OSSConfiguration.bucket = bucket
            OSSConfiguration.region = region
        }
    }

    func updateCredentials(_ credentials: OSSCredentials) {
        withLock {
            guard credentials.isValid else { return }

            currentCredentials = credentials
            let credentialProvider = OSSStsTokenCredentialProvider(
                accessKeyId: credentials.accessKeyId,
                secretKeyId: credentials.accessKeySecret,
                securityToken: credentials.securityToken ?? ""
            )
            client = OSSClient(endpoint: OSSConfiguration.endpoint, credentialProvider: credentialProvider)
        }
    }

    func resetRuntimeCredentials() {
        withLock {
            currentCredentials = nil
            client = nil
            refreshingTask?.cancel()
            refreshingTask = nil
        }
    }

    func getValidCredentials() async throws -> OSSCredentials {
        let refreshTask: Task<OSSCredentials, Error> = withLock {
            if let credentials = currentCredentials, !credentials.isExpired {
                return Task { credentials }
            }
            if let existingTask = refreshingTask {
                return existingTask
            }
            guard let provider = credentialsProvider else {
                return Task { throw OSSError.credentialsProviderNotSet }
            }

            let task = Task { @Sendable in
                let newCredentials = try await provider()
                updateCredentials(newCredentials)
                withLock {
                    refreshingTask = nil
                }
                return newCredentials
            }
            refreshingTask = task
            return task
        }

        return try await refreshTask.value
    }

    func ensureInitialized() async throws {
        let (hasClient, needsRefresh) = withLock {
            (client != nil, currentCredentials?.isExpired ?? true)
        }

        if hasClient && !needsRefresh { return }
        _ = try await getValidCredentials()
    }

    private nonisolated func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}

enum OSSError: LocalizedError {
    case credentialsProviderNotSet
    case clientNotInitialized
    case uploadFailed(String)
    case downloadFailed(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .credentialsProviderNotSet:
            return "OSS credentials provider not set"
        case .clientNotInitialized:
            return "OSS client not initialized"
        case .uploadFailed(let message):
            return "OSS upload failed: \(message)"
        case .downloadFailed(let message):
            return "OSS download failed: \(message)"
        case .invalidResponse:
            return "OSS invalid response"
        }
    }
}
