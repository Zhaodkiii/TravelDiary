import Foundation

nonisolated private struct PersonaStorePayload: Codable, Sendable {
    var profiles: [PersonaProfile]
}

nonisolated private enum PersonaFileStore {
    nonisolated static func load(accountID: Int64, fileManager: FileManager = .default) throws -> PersonaStorePayload {
        let url = storeURL(accountID: accountID, fileManager: fileManager)
        guard fileManager.fileExists(atPath: url.path) else {
            return PersonaStorePayload(profiles: JSONFilePersonaRepository.defaultProfiles())
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PersonaStorePayload.self, from: data)
    }

    nonisolated static func save(_ payload: PersonaStorePayload, accountID: Int64, fileManager: FileManager = .default) throws {
        let url = storeURL(accountID: accountID, fileManager: fileManager)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        try data.write(to: url, options: .atomic)
    }

    nonisolated private static func storeURL(accountID: Int64, fileManager: FileManager) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return base
            .appending(path: "TravelDiary", directoryHint: .isDirectory)
            .appending(path: "Personas", directoryHint: .isDirectory)
            .appending(path: "\(accountID)", directoryHint: .isDirectory)
            .appending(path: "personas.json")
    }
}

/// 按账号将 Persona 列表持久化到 Application Support 下的 JSON 文件。
final class JSONFilePersonaRepository: PersonaRepository, @unchecked Sendable {
    static let shared = JSONFilePersonaRepository()

    func list(accountID: Int64) async throws -> [PersonaProfile] {
        try PersonaFileStore.load(accountID: accountID).profiles.sorted { $0.name < $1.name }
    }

    func load(name: String, accountID: Int64) async throws -> PersonaProfile? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }
        return try PersonaFileStore.load(accountID: accountID).profiles.first { $0.name == trimmed }
    }

    func save(_ profile: PersonaProfile, accountID: Int64) async throws {
        guard Self.isValidName(profile.name) else { throw PersonaRepositoryError.invalidName }
        var store = try PersonaFileStore.load(accountID: accountID)
        if let index = store.profiles.firstIndex(where: { $0.name == profile.name }) {
            store.profiles[index] = profile
        } else {
            store.profiles.append(profile)
        }
        try PersonaFileStore.save(store, accountID: accountID)
    }

    func delete(name: String, accountID: Int64) async throws {
        var store = try PersonaFileStore.load(accountID: accountID)
        store.profiles.removeAll { $0.name == name }
        try PersonaFileStore.save(store, accountID: accountID)
    }

    nonisolated static func isValidName(_ name: String) -> Bool {
        let pattern = #"^[a-z0-9][a-z0-9-]{0,63}$"#
        return name.range(of: pattern, options: .regularExpression) != nil
    }

    nonisolated static func defaultProfiles() -> [PersonaProfile] {
        [
            PersonaProfile(
                name: "tutor",
                displayName: "耐心导师",
                promptBody: "你是一位耐心、鼓励型的学习导师。用清晰的分步讲解回答问题，适时给出例子，避免居高临下的语气。"
            ),
            PersonaProfile(
                name: "coach",
                displayName: "行动教练",
                promptBody: "你是一位务实的行动教练。优先给出可执行的建议与下一步行动，语言简洁直接，聚焦结果与习惯养成。"
            ),
        ]
    }
}
