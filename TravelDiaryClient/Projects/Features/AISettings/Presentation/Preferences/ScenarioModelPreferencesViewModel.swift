import Combine
import Foundation

@MainActor
final class ScenarioModelPreferencesViewModel: ObservableObject {
    @Published private(set) var localBundles: AIScenarioRemoteBundlesCollection?
    @Published private(set) var proBundles: AIScenarioRemoteBundlesCollection?
    @Published private(set) var mergedBundles: AIScenarioRemoteBundlesCollection?
    @Published private(set) var snapshot: AISettingsSnapshot?

    private var pendingSelections: [String: String] = [:]
    private var pendingSources: [String: AIModelSelectionSource] = [:]
    private let aiConfigCenter: AIConfigCenter?

    init(aiConfigCenter: AIConfigCenter?) {
        self.aiConfigCenter = aiConfigCenter
    }

    func reloadBundles() async {
        guard let aiConfigCenter else {
            localBundles = nil
            proBundles = nil
            mergedBundles = nil
            snapshot = nil
            return
        }
        async let local = aiConfigCenter.localScenarioBundles()
        async let pro = aiConfigCenter.proScenarioBundles()
        async let merged = try? aiConfigCenter.effectiveScenarioBundles()
        async let currentSnapshot = aiConfigCenter.currentSnapshot()
        localBundles = await local
        proBundles = await pro
        mergedBundles = await merged
        snapshot = await currentSnapshot
    }

    func bundle(for scenario: AIScenario, source: AIModelSelectionSource) -> AIScenarioRemoteBundle? {
        switch source {
        case .localKey:
            return localBundles?.bundle(for: scenario)
        case .trial:
            return proBundles?.bundle(for: scenario)
        }
    }

    func source(for scenario: AIScenario) -> AIModelSelectionSource {
        let stored = pendingSources[scenario.rawValue]
            ?? snapshot?.scenarioModelSource(for: scenario)
            ?? .localKey
        if stored == .trial,
           proBundles?.bundle(for: scenario).models.isEmpty != false
        {
            return .localKey
        }
        return stored
    }

    func setSource(_ source: AIModelSelectionSource, for scenario: AIScenario) {
        pendingSources[scenario.rawValue] = source
        snapshot?.setScenarioModelSource(source, for: scenario)
        pendingSelections[scenario.rawValue] = ""
        Task {
            await aiConfigCenter?.updateScenarioModelSource(source, for: scenario)
            await reloadBundles()
        }
    }

    func selectedModel(for scenario: AIScenario, sourceBundle: AIScenarioRemoteBundle) -> String {
        if let pending = pendingSelections[scenario.rawValue] {
            return pending
        }
        if let stored = snapshot?.scenarioDefaultModelName(for: scenario),
           sourceBundle.models.contains(where: { $0.model == stored })
        {
            return stored
        }
        let mergedDefault = mergedBundles?.bundle(for: scenario).defaultModelName ?? ""
        if mergedDefault.isEmpty == false,
           sourceBundle.models.contains(where: { $0.model == mergedDefault })
        {
            return mergedDefault
        }
        if sourceBundle.defaultModelName.isEmpty == false,
           sourceBundle.models.contains(where: { $0.model == sourceBundle.defaultModelName })
        {
            return sourceBundle.defaultModelName
        }
        return sourceBundle.models.first?.model ?? ""
    }

    func setSelectedModel(_ modelName: String, for scenario: AIScenario) {
        let trimmed = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingSelections[scenario.rawValue] = trimmed
        guard trimmed.isEmpty == false else { return }
        snapshot?.setScenarioDefaultModelName(trimmed, for: scenario)
        Task {
            await aiConfigCenter?.updateScenarioDefaultModel(trimmed, for: scenario)
            await reloadBundles()
        }
    }
}
