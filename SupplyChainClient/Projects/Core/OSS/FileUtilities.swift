import CryptoKit
import Foundation
import UniformTypeIdentifiers

enum FileUtilities {
    nonisolated static func md5Hex(_ data: Data) -> String {
        let hash = Insecure.MD5.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    nonisolated static func mimeType(forName fileName: String) -> String {
        let ext = (fileName as NSString).pathExtension.lowercased()
        if let type = UTType(filenameExtension: ext), let mime = type.preferredMIMEType {
            return mime
        }

        switch ext {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "pdf": return "application/pdf"
        case "txt": return "text/plain"
        case "json": return "application/json"
        case "zip": return "application/zip"
        case "mp4": return "video/mp4"
        default: return "application/octet-stream"
        }
    }

    nonisolated static func sanitizeFileName(_ fileName: String) -> String {
        let invalidChars = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let components = fileName.components(separatedBy: invalidChars)
        let cleaned = components.joined(separator: "_").trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "unnamed_file" : cleaned
    }

    nonisolated static func makeObjectKey(prefix: String, uuidString: String, filename: String) -> String {
        let cleanedPrefix = prefix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return "\(cleanedPrefix)/\(uuidString)/\(sanitizeFileName(filename))"
    }
}
