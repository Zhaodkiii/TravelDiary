import Foundation

nonisolated struct DiaryAISavedCandidate: Codable, Sendable {
    var archive: Data
    var preview: Data
    var original: Data
    var summary: String
    var warnings: [String]
    var revision: Int
}
nonisolated struct DiaryAISavedSession: Codable, Sendable {
    var version = 1
    var updated = Date()
    var forms: [String: DiaryAIRequest]
    var candidates: [String: DiaryAISavedCandidate]
    var interrupted: Bool
}
actor DiaryAILocalTaskStore {
    private let directory: URL
    private var lastSequence = 0
    init(key: String, root: URL? = nil) {
        directory = (root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0])
            .appendingPathComponent("DiaryCanvasAI", isDirectory: true).appendingPathComponent(key, isDirectory: true)
    }
    func load() throws -> DiaryAISavedSession? {
        let url = directory.appendingPathComponent("session.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let date = (try url.resourceValues(forKeys: [.contentModificationDateKey])).contentModificationDate,
              Date().timeIntervalSince(date) < 7 * 86400 else { try FileManager.default.removeItem(at: directory); return nil }
        let value = try JSONDecoder().decode(DiaryAISavedSession.self, from: Data(contentsOf: url))
        guard value.version == 1 else { return nil }; return value
    }
    func save(_ value: DiaryAISavedSession, sequence: Int) throws {
        guard sequence > lastSequence else { return }; lastSequence = sequence
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var excluded = URLResourceValues(); excluded.isExcludedFromBackup = true
        var folder = directory; try folder.setResourceValues(excluded)
        try JSONEncoder().encode(value).write(to: directory.appendingPathComponent("session.json"), options: .atomic)
    }
}
