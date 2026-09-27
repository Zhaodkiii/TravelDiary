import Foundation

struct SaveAISettingsUseCase: Sendable {
    let repository: any AISettingsRepository

    func execute(snapshot: AISettingsSnapshot, ownerAccountID: Int64? = nil) async throws {
        try await repository.save(snapshot: snapshot, ownerAccountID: ownerAccountID)
    }

    func execute(model: AllModels) async throws {
        try await repository.saveModel(model)
    }

    func execute(scenarioBinding: AIScenarioModelBinding, ownerAccountID: Int64? = nil) async throws {
        try await repository.saveScenarioBinding(scenarioBinding, ownerAccountID: ownerAccountID)
    }

    func executeDeletedScenarioBinding(id: UUID, ownerAccountID: Int64? = nil) async throws {
        try await repository.deleteScenarioBinding(id: id, ownerAccountID: ownerAccountID)
    }

    func execute(provider: APIKeys) async throws {
        try await repository.saveProvider(provider)
    }

    func execute(searchKey: SearchKeys, ownerAccountID: Int64? = nil) async throws {
        try await repository.saveSearchKey(searchKey, ownerAccountID: ownerAccountID)
    }

    func executeDeletedSearchKeys(ids: [UUID], ownerAccountID: Int64? = nil) async throws {
        try await repository.deleteSearchKeys(ids: ids, ownerAccountID: ownerAccountID)
    }

    func execute(
        searchToolPreferences: AISearchToolPreferences,
        revision: SearchRuntimeConfigRevision,
        searchKeys: [SearchKeys]? = nil,
        ownerAccountID: Int64? = nil
    ) async throws {
        try await repository.saveSearchToolPreferences(
            searchToolPreferences,
            revision: revision,
            searchKeys: searchKeys,
            ownerAccountID: ownerAccountID
        )
    }

    func execute(promptRepo: [PromptRepo], ownerAccountID: Int64? = nil) async throws {
        try await repository.savePromptRepo(promptRepo, ownerAccountID: ownerAccountID)
    }
}
