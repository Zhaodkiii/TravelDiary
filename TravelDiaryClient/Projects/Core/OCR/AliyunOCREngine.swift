import CryptoKit
import Foundation
import UIKit

nonisolated struct AliyunOCREngine: OCRTextEngine {
    let name: String = "aliyun"

    private let endpoint: String
    private let apiVersion: String
    private let action: String
    private let credentialsProvider: OCRCredentialsProvider

    init(
        credentialsProvider: OCRCredentialsProvider,
        endpoint: String = "https://ocr-api.cn-hangzhou.aliyuncs.com",
        apiVersion: String = "2021-07-07",
        action: String = "RecognizeAllText"
    ) {
        self.credentialsProvider = credentialsProvider
        self.endpoint = endpoint
        self.apiVersion = apiVersion
        self.action = action
    }

    func recognize(imageData: Data, hints _: OCRRecognitionHints) async throws -> OCRTextOutput {
        let start = Date()
        let credentials = try await credentialsProvider.fetchAliyunOCRCredentials()
        let compressedData = try compressImageData(imageData)

        var params: [String: String] = [
            "AccessKeyId": credentials.accessKeyId,
            "Action": action,
            "Format": "JSON",
            "SignatureMethod": "HMAC-SHA1",
            "SignatureNonce": UUID().uuidString,
            "SignatureVersion": "1.0",
            "Timestamp": aliyunTimestamp(),
            "Version": apiVersion,
            "Type": "General"
        ]

        if let securityToken = credentials.securityToken, !securityToken.isEmpty {
            params["SecurityToken"] = securityToken
        }

        let signature = computeSignature(params: params, secret: credentials.accessKeySecret)
        params["Signature"] = signature

        guard let finalURL = buildSignedURL(base: endpoint, params: params) else {
            throw OCRError.response("invalid_aliyun_url")
        }

        var request = URLRequest(url: finalURL)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = compressedData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw OCRError.transport("aliyun_invalid_http_response")
            }
            guard (200...299).contains(http.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? ""
                throw OCRError.response("aliyun_http_\(http.statusCode):\(body)")
            }

            let text = try decodeAliyunText(from: data)
            let elapsed = Int(Date().timeIntervalSince(start) * 1000)
            return OCRTextOutput(engine: name, text: text, confidence: nil, elapsedMs: elapsed)
        } catch let error as OCRError {
            throw error
        } catch {
            throw OCRError.transport(error.localizedDescription)
        }
    }

    nonisolated private func compressImageData(_ data: Data) throws -> Data {
        guard let image = UIImage(data: data) else { throw OCRError.invalidImage }

        var quality: CGFloat = 0.9
        for _ in 0..<6 {
            if let jpeg = image.jpegData(compressionQuality: quality), jpeg.count < 3 * 1024 * 1024 {
                return jpeg
            }
            quality -= 0.1
        }

        guard let fallback = image.jpegData(compressionQuality: 0.4) else {
            throw OCRError.invalidImage
        }
        return fallback
    }

    nonisolated private func buildSignedURL(base: String, params: [String: String]) -> URL? {
        let query = params.keys.sorted().compactMap { key -> String? in
            guard let value = params[key] else { return nil }
            return "\(key.percentEncodedRFC3986())=\(value.percentEncodedRFC3986())"
        }.joined(separator: "&")
        return URL(string: "\(base)?\(query)")
    }

    nonisolated private func decodeAliyunText(from data: Data) throws -> String {
        struct Response: Decodable {
            struct DataField: Decodable {
                let content: String?

                init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodableKey.self)
                    content = try container.decodeIfPresent(String.self, forKey: .key("Content"))
                }
            }
            let data: DataField?
            let code: String?
            let message: String?
        }

        let decoded = try JSONDecoder.default.decode(Response.self, from: data)
        if let code = decoded.code, let message = decoded.message {
            throw OCRError.response("aliyun_error_\(code):\(message)")
        }
        return decoded.data?.content ?? ""
    }

    nonisolated private func computeSignature(params: [String: String], secret: String) -> String {
        let canonical = params.keys.sorted().compactMap { key -> String? in
            guard let value = params[key] else { return nil }
            return "\(key.percentEncodedRFC3986())=\(value.percentEncodedRFC3986())"
        }.joined(separator: "&")

        let stringToSign = "POST&%2F&\(canonical.percentEncodedRFC3986())"
        let key = SymmetricKey(data: Data((secret + "&").utf8))
        let signature = HMAC<Insecure.SHA1>.authenticationCode(for: Data(stringToSign.utf8), using: key)
        return Data(signature).base64EncodedString()
    }

    nonisolated private func aliyunTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return formatter.string(from: Date())
    }
}

private extension String {
    nonisolated func percentEncodedRFC3986() -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.~")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}
