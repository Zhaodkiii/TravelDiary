import Foundation

nonisolated struct MasteryProgress: Codable, Equatable, Sendable {
    let pathID: String
    var masteredTopics: [String]
    var lastQuizAt: Date?

    init(pathID: String, masteredTopics: [String] = [], lastQuizAt: Date? = nil) {
        self.pathID = pathID
        self.masteredTopics = masteredTopics
        self.lastQuizAt = lastQuizAt
    }
}

protocol MasteryProgressRepository: Sendable {
    func load(pathID: String, accountID: Int64) async throws -> MasteryProgress?
    func save(_ progress: MasteryProgress, accountID: Int64) async throws
}

enum MasteryRepositoryError: Error {
    case invalidPathID
}
