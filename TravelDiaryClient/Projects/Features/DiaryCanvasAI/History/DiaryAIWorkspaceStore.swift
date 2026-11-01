import Foundation

/// Serializes checkpoint writes and deletion so a late write cannot resurrect a discarded session.
actor DiaryAIWorkspaceStore {
    private let url: URL
    private var sequence = 0
    init(url: URL) { self.url = url }
    func load() throws -> DiaryAIWorkspaceArchive? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(DiaryAIWorkspaceArchive.self, from: Data(contentsOf: url))
    }
    func save(_ archive: DiaryAIWorkspaceArchive, sequence: Int) throws {
        guard sequence > self.sequence else { return }
        let data = try JSONEncoder().encode(archive)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        self.sequence = sequence
    }
    func remove(sequence: Int) throws {
        guard sequence > self.sequence else { return }
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        self.sequence = sequence
    }
}
