import Foundation

/// JWT 过期时间解析器可能抛出的错误枚举
nonisolated enum JWTExpParserError: Error {
    case invalidJWT
    case invalidPayloadEncoding
    case invalidJSON
    case missingExp
}

/// 解析 JWT 的 Payload（负载）而不验证其签名。
/// 仅用于提取过期时间，以便执行 Token 刷新决策逻辑。
nonisolated enum JWTExpParser {
    struct Claims {
        let expDate: Date
        let subject: String?
    }

    static func parseClaims(_ jwt: String) throws -> Claims {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { throw JWTExpParserError.invalidJWT }

        let payloadB64 = String(parts[1])
        guard let payloadData = Base64URL.decodeToData(payloadB64) else {
            throw JWTExpParserError.invalidPayloadEncoding
        }

        let json = try JSONSerialization.jsonObject(with: payloadData, options: [])
        guard let dict = json as? [String: Any] else {
            throw JWTExpParserError.invalidJSON
        }

        let expValue = dict["exp"]
        let expSeconds: TimeInterval?
        if let n = expValue as? NSNumber {
            expSeconds = n.doubleValue
        } else if let s = expValue as? String, let d = Double(s) {
            expSeconds = d
        } else {
            expSeconds = nil
        }

        guard let expSeconds else { throw JWTExpParserError.missingExp }
        let subject = dict["sub"] as? String
        return Claims(expDate: Date(timeIntervalSince1970: expSeconds), subject: subject)
    }

    private enum Base64URL {
        static func decodeToData(_ base64url: String) -> Data? {
            var base64 = base64url
                .replacingOccurrences(of: "-", with: "+")
                .replacingOccurrences(of: "_", with: "/")

            let remainder = base64.count % 4
            if remainder > 0 {
                base64 += String(repeating: "=", count: 4 - remainder)
            }
            return Data(base64Encoded: base64)
        }
    }
}
