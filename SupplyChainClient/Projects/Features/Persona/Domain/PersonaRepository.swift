import Foundation

protocol PersonaRepository: Sendable {
    func list(accountID: Int64) async throws -> [PersonaProfile]
    func load(name: String, accountID: Int64) async throws -> PersonaProfile?
    func save(_ profile: PersonaProfile, accountID: Int64) async throws
    func delete(name: String, accountID: Int64) async throws
}
