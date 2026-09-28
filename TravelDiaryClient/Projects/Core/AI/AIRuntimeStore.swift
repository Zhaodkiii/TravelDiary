import Foundation

actor AIRuntimeStore {
    private var overrides: [AIScenario: AIScenarioConfig] = [:]

    func setOverride(_ config: AIScenarioConfig, for scenario: AIScenario) {
        overrides[scenario] = config
    }

    func runtimeOverride(for scenario: AIScenario) -> AIScenarioConfig? {
        overrides[scenario]
    }

    func clearOverride(for scenario: AIScenario) {
        overrides.removeValue(forKey: scenario)
    }

    func clearAll() {
        overrides.removeAll()
    }
}
