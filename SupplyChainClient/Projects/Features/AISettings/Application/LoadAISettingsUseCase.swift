import Foundation

struct LoadAISettingsUseCase: Sendable {
    let repository: any AISettingsRepository

    func execute(ownerAccountID: Int64?) async -> AISettingsSnapshot {
        await repository.loadSnapshot(ownerAccountID: ownerAccountID)
    }
}
