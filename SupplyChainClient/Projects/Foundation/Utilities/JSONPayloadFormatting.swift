import Foundation

/// JSON / 原始字节在日志、ETag 合并、调试预览中的统一格式化（与业务 `Decodable` 无关）。
enum JSONPayloadFormatting: Sendable {

    /// HTTP body、ETag 磁盘缓存体、任意 UTF-8 JSON：能解析为 JSON 对象/数组时输出 `prettyPrinted` + `sortedKeys`；否则输出 UTF-8 原文；非 UTF-8 返回占位。
    nonisolated static func prettyUTF8StringForLog(from data: Data) -> String {
        guard data.isEmpty == false else { return "<empty>" }
        guard let utf8 = String(data: data, encoding: .utf8) else {
            return "<非 UTF-8 二进制，\(data.count) 字节>"
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data, options: []),
              JSONSerialization.isValidJSONObject(obj) else {
            return utf8
        }
        guard let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: pretty, encoding: .utf8) else {
            return utf8
        }
        return text
    }

    /// `Encodable` → 与 `prettyUTF8StringForLog(from:)` 同风格的 pretty 字符串（内部先编码再统一走 JSON 美化路径）。
    nonisolated static func prettyString<T: Encodable>(from value: T, encoder: JSONEncoder = JSONEncoder.default) throws -> String {
        let data = try encoder.encode(value)
        return prettyUTF8StringForLog(from: data)
    }
}
