import Foundation
import UIKit

nonisolated struct LocalServerOCREngine: OCRTextEngine {
    let name: String = "local_server"

    private let baseURL: String
    private let timeoutMs: Int
    private let authToken: String?

    init(baseURL: String, timeoutMs: Int = 10_000, authToken: String? = nil) {
        self.baseURL = baseURL
        self.timeoutMs = timeoutMs
        self.authToken = authToken
    }

    func recognize(imageData: Data, hints _: OCRRecognitionHints) async throws -> OCRTextOutput {
        guard !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OCRError.engineUnavailable("local_server_base_url_empty")
        }

        guard let image = UIImage(data: imageData),
              let jpegData = image.jpegData(compressionQuality: 0.9),
              let url = URL(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines) + "/api/v1/ocr/recognize") else {
            throw OCRError.invalidImage
        }

        let start = Date()
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = TimeInterval(timeoutMs) / 1000.0

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let authToken, !authToken.isEmpty {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }

        request.httpBody = buildMultipartBody(boundary: boundary, imageData: jpegData)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw OCRError.transport("local_server_invalid_http_response")
            }
            guard (200...299).contains(http.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? ""
                throw OCRError.response("local_server_http_\(http.statusCode):\(body)")
            }

            let text = try decodeText(data)
            let elapsed = Int(Date().timeIntervalSince(start) * 1000)
            return OCRTextOutput(engine: name, text: text, confidence: nil, elapsedMs: elapsed)
        } catch let error as OCRError {
            throw error
        } catch {
            throw OCRError.transport(error.localizedDescription)
        }
    }

    nonisolated private func buildMultipartBody(boundary: String, imageData: Data) -> Data {
        var body = Data()
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"ocr.jpg\"\r\n")
        body.append("Content-Type: image/jpeg\r\n\r\n")
        body.append(imageData)
        body.append("\r\n")

        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"lang\"\r\n\r\n")
        body.append("ch\r\n")

        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"return_detail\"\r\n\r\n")
        body.append("false\r\n")

        body.append("--\(boundary)--\r\n")
        return body
    }

    nonisolated private func decodeText(_ data: Data) throws -> String {
        struct Response: Decodable {
            let success: Bool
            let text: String?
            let error: ErrorBody?

            struct ErrorBody: Decodable {
                let code: String?
                let message: String?
            }
        }

        let decoded = try JSONDecoder.default.decode(Response.self, from: data)
        if !decoded.success {
            let message = decoded.error?.message ?? "local_server_failed"
            throw OCRError.response(message)
        }
        return decoded.text ?? ""
    }
}

private extension Data {
    nonisolated mutating func append(_ string: String) {
        guard let data = string.data(using: .utf8) else { return }
        append(data)
    }
}
