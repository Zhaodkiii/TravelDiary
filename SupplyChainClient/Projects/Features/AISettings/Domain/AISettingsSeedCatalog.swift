import Foundation

nonisolated enum AISettingsSeedCatalog {
    static let version = 6

    nonisolated static func getModelList() -> [AllModels] {
        AISettingsSeedLoader.loadAllModels() ?? []
    }

    nonisolated static func getScenarioBindings() -> [AIScenarioModelBinding] {
        AISettingsSeedLoader.loadScenarioBindings() ?? []
    }

    nonisolated static func getScenarioBindings(for models: [AllModels]) -> [AIScenarioModelBinding] {
        AISettingsSeedLoader.loadScenarioBindings(for: models) ?? []
    }

    nonisolated static func getAPIKeyList() -> [APIKeys] {
        AISettingsSeedLoader.loadAPIKeys() ?? []
    }

    nonisolated static func getSearchKeyList() -> [SearchKeys] {
        AISettingsDefaults.searchKeys
    }

    nonisolated static func getToolKeyList() -> [ToolKeys] {
        AISettingsDefaults.toolKeys
    }

    nonisolated static func getPromptList() -> [PromptRepo] {
        AISettingsDefaults.promptRepo
    }

    nonisolated static func getDefaultSearchToolPreferences() -> AISearchToolPreferences {
        AISettingsDefaults.searchToolPreferences
    }
}
