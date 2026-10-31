#if DEBUG
import Foundation

enum DiaryBookSourceExporter {
    enum ExportError: LocalizedError {
        case archiveFailed
        var errorDescription: String? { "源文件打包失败，请重试。" }
    }

    static func export(book: DiaryBook, store: DiaryDocumentStore) async throws -> URL {
        let parent = StoragePaths.system.temporaryRoot.appendingPathComponent("SourceExport-\(UUID())", isDirectory: true)
        let source = parent.appendingPathComponent("\(safeName(book.title))", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        do {
            try await store.exportSourceFiles(book, to: source)
            try Task.checkCancellation()
            let archive = parent.appendingPathComponent("\(safeName(book.title)).zip")
            try await Task.detached {
                var coordinationError: NSError?
                var archiveError: Error?
                NSFileCoordinator().coordinate(readingItemAt: source, options: .forUploading, error: &coordinationError) { zippedURL in
                    do { try FileManager.default.copyItem(at: zippedURL, to: archive) }
                    catch { archiveError = error }
                }
                if let coordinationError { throw coordinationError }
                if let archiveError { throw archiveError }
                guard FileManager.default.fileExists(atPath: archive.path) else { throw ExportError.archiveFailed }
            }.value
            try Task.checkCancellation()
            return archive
        } catch {
            try? FileManager.default.removeItem(at: parent)
            throw error
        }
    }

    private static func safeName(_ title: String) -> String {
        let value = String(title.unicodeScalars.filter {
            !CharacterSet.controlCharacters.contains($0) && !"/\\:".unicodeScalars.contains($0)
        }.map(String.init).joined().prefix(80)).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "我的手帐" : value
    }
}
#endif
