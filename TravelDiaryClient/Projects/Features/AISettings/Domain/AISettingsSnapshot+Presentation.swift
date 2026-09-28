import Foundation

extension AISettingsSnapshot {
    /// 由本地目录构建的场景 bundle（不含 Pro 覆盖；用于设置页与即时展示）。
    func localScenarioBundles() -> AIScenarioRemoteBundlesCollection {
        return AILocalScenarioBundleBuilder.buildCollection(
            allModels: allModels,
            apiKeys: apiKeys,
            scenarioBindings: scenarioBindings
        )
    }

    func resolveScenarioRow(
        for scenario: AIScenario,
        preferredModelName: String? = nil
    ) -> AIScenarioRemoteModelRow? {
        let bundles = localScenarioBundles()
        let trimmed = preferredModelName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let preferred = (trimmed?.isEmpty == false) ? trimmed : nil
        return bundles.resolveRow(for: scenario, preferredModelName: preferred)
    }

}
