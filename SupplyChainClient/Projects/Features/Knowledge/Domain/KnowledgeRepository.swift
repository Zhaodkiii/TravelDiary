import Foundation

protocol KnowledgeRepository: Sendable {
    func listBases(accountID: Int64) async throws -> [KnowledgeBase]
    func loadBase(id: String, accountID: Int64) async throws -> KnowledgeBase?
    func saveBase(_ base: KnowledgeBase, accountID: Int64) async throws
    func deleteBase(id: String, accountID: Int64) async throws
    func allBaseIDs(accountID: Int64) async throws -> [String]
}
