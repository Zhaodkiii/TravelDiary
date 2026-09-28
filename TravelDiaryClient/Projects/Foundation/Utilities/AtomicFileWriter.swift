import Foundation

/// Writes a file by writing to a temp path and replacing the destination atomically.
nonisolated struct AtomicFileWriter {
    static func write(_ data: Data, to destinationURL: URL) throws {
        let fileManager = FileManager.default
        let directory = destinationURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        let tempURL = destinationURL.appendingPathExtension("tmp.\(UUID().uuidString)")
        try data.write(to: tempURL, options: [.atomic])
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.moveItem(at: tempURL, to: destinationURL)
    }
}

