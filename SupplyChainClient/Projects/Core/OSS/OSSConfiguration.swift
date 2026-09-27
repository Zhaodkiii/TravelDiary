import Foundation

enum OSSConfiguration {
    private nonisolated(unsafe) static let endpointStorage = Atomic("")
    private nonisolated(unsafe) static let bucketStorage = Atomic("")
    private nonisolated(unsafe) static let regionStorage = Atomic("")

    nonisolated static var endpoint: String {
        get { endpointStorage.value }
        set { endpointStorage.value = newValue }
    }

    nonisolated static var bucket: String {
        get { bucketStorage.value }
        set { bucketStorage.value = newValue }
    }

    nonisolated static var region: String {
        get { regionStorage.value }
        set { regionStorage.value = newValue }
    }

    nonisolated static var useSTS: Bool { true }
}

struct OSSCredentials: Sendable {
    let accessKeyId: String
    let accessKeySecret: String
    let securityToken: String?
    let expiration: Date?

    nonisolated var isExpired: Bool {
        guard let expiration else { return false }
        return expiration.timeIntervalSinceNow < 300
    }

    nonisolated var isValid: Bool {
        !accessKeyId.isEmpty && !accessKeySecret.isEmpty && !isExpired
    }
}
