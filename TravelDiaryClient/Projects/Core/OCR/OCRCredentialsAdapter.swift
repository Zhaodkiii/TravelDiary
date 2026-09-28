import Foundation

struct BackendOCRCredentialsProvider: OCRCredentialsProvider {
    let api: SupportOCRAPI

    func fetchAliyunOCRCredentials() async throws -> OCRAliyunCredentials {
        let credentials = try await api.getSTSCredentials()
        return OCRAliyunCredentials(
            accessKeyId: credentials.accessKeyID,
            accessKeySecret: credentials.accessKeySecret,
            securityToken: credentials.securityToken
        )
    }
}
