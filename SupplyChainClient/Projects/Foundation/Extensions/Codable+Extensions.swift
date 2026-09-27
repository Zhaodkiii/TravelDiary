import Foundation

/// 通用编码键：自定义灵活的 Codable 编码/解码键
nonisolated struct CodableKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init(_ stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(stringValue: String) {
        self.init(stringValue)
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

extension CodableKey {
    static func key(_ stringValue: String) -> CodableKey {
        CodableKey(stringValue)
    }
}

enum CodableDiagnostics: Sendable {
    nonisolated static func codingPath(_ path: [CodingKey]) -> String {
        guard path.isEmpty == false else { return "<root>" }
        return path.map(\.stringValue).joined(separator: ".")
    }

    nonisolated static func describe(_ error: Error) -> String {
        guard let decoding = error as? DecodingError else {
            return error.localizedDescription
        }
        switch decoding {
        case let .keyNotFound(key, context):
            return "keyNotFound key=\(key.stringValue) path=\(codingPath(context.codingPath)) debug=\(context.debugDescription)"
        case let .typeMismatch(type, context):
            return "typeMismatch type=\(type) path=\(codingPath(context.codingPath)) debug=\(context.debugDescription)"
        case let .valueNotFound(type, context):
            return "valueNotFound type=\(type) path=\(codingPath(context.codingPath)) debug=\(context.debugDescription)"
        case let .dataCorrupted(context):
            return "dataCorrupted path=\(codingPath(context.codingPath)) debug=\(context.debugDescription)"
        @unknown default:
            return decoding.localizedDescription
        }
    }
}
