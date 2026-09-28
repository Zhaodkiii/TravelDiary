import Foundation
import UniformTypeIdentifiers

/// Generic input model for unified file preview.
/// This type is intentionally feature-agnostic so chat/medical can reuse it.
struct FilePreviewInput: Identifiable, Equatable, Sendable {
    let id: UUID
    let fileURL: URL
    let displayName: String?
    let mimeType: String?
    let utTypeIdentifier: String?

    init(
        id: UUID = UUID(),
        fileURL: URL,
        displayName: String? = nil,
        mimeType: String? = nil,
        utTypeIdentifier: String? = nil
    ) {
        self.id = id
        self.fileURL = fileURL
        self.displayName = displayName
        self.mimeType = mimeType
        self.utTypeIdentifier = utTypeIdentifier
    }

    var resolvedDisplayName: String {
        if let displayName, displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return displayName
        }
        let filename = fileURL.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return filename.isEmpty ? "File" : filename
    }

    var inferredUTType: UTType? {
        if let utTypeIdentifier, let type = UTType(utTypeIdentifier) {
            return type
        }
        if let mimeType, let type = UTType(mimeType: mimeType) {
            return type
        }
        if fileURL.pathExtension.isEmpty == false {
            return UTType(filenameExtension: fileURL.pathExtension)
        }
        return nil
    }

    var isImage: Bool {
        if let type = inferredUTType {
            return type.conforms(to: .image)
        }
        return false
    }

    var isLocalFileAvailable: Bool {
        guard fileURL.isFileURL else { return true }
        return FileManager.default.fileExists(atPath: fileURL.path)
    }
}
