import Foundation

/// 当前登录账号的 AI 运行时缓存：本地场景 bundle + Pro 内存 overlay + 与 bundle 同源的 `AISettingsSnapshot`。
actor AIRuntimeConfigStore {
    private var localBundles: AIScenarioRemoteBundlesCollection?
    private var proBundles: AIScenarioRemoteBundlesCollection?
    private var localSmallTasks: [SmallTask] = []
    private var proSmallTasks: [SmallTask] = []
    private(set) var proRevision: String?
    private var cachedSearchConfig: Result<SearchRuntimeConfig, SearchRuntimeError>?

    /// 与 `localBundles` 同源的上次快照；供设置页与推理侧避免重复读库。
    private var cachedSnapshot: AISettingsSnapshot?
    /// 与 `cachedSnapshot` 绑定的账号；`nil` 表示尚未与具体账号绑定（仅草稿更新时可能保持 `nil`）。
    private var cachedOwnerAccountID: Int64?

    /// 写入快照并重建各场景本地 bundle。
    /// - Parameter ownerAccountID: 非 `nil` 时绑定缓存键；为 `nil` 时仅更新快照内容（设置页草稿），不覆盖已绑定账号。
    func applySnapshot(_ snapshot: AISettingsSnapshot, ownerAccountID: Int64?) {
        if let ownerAccountID {
            cachedOwnerAccountID = ownerAccountID
        }
        var working = snapshot
        if working.searchToolPreferences.useSearch {
            working.normalizeSearchProviderSelection()
            let hasActiveWebProfile = working.searchKeys.contains {
                $0.searchClass.lowercased() == "web" && $0.isUsing
            }
            if hasActiveWebProfile == false {
                if working.searchKeys.isEmpty {
                    working.searchKeys = [SearchProviderCatalog.makeDefaultDuckDuckGoProfile()]
                } else if let duckIndex = working.searchKeys.firstIndex(where: { SearchProviderID(company: $0.company) == .duckduckgo }) {
                    working.searchKeys[duckIndex].isUsing = true
                } else {
                    working.searchKeys.append(SearchProviderCatalog.makeDefaultDuckDuckGoProfile())
                }
            }
        }
        cachedSnapshot = working
        localBundles = AILocalScenarioBundleBuilder.buildCollection(
            allModels: working.allModels,
            apiKeys: working.apiKeys,
            scenarioBindings: working.scenarioBindings
        )
        localSmallTasks = working.smallTasks.filter { $0.source == .local }
        cachedSearchConfig = Result { try SearchRuntimeConfigResolver.resolve(from: working) }
            .mapError { error in
                error as? SearchRuntimeError ?? .invalidResponse(error.localizedDescription)
            }
    }

    /// 仅当缓存存在且账号与当前解析一致时返回，避免跨账号误用。
    func cachedSnapshotIfMatches(ownerAccountID: Int64?) -> AISettingsSnapshot? {
        guard let cached = cachedSnapshot else { return nil }
        guard cachedOwnerAccountID == ownerAccountID else { return nil }
        return cached
    }

    /// 诊断：当前运行时缓存绑定的账号（`nil` 表示未绑定或仅草稿）。
    func boundOwnerAccountIDForDiagnostics() -> Int64? {
        cachedOwnerAccountID
    }

    func setProOverlay(_ bundles: AIScenarioRemoteBundlesCollection?, revision: String?, smallTasks: [SmallTask] = []) {
        proBundles = bundles
        proRevision = revision
        proSmallTasks = smallTasks.filter { $0.source == .service }
    }

    func clearProOverlay() {
        proBundles = nil
        proRevision = nil
        proSmallTasks = []
    }

    func reset() {
        localBundles = nil
        proBundles = nil
        proRevision = nil
        cachedSnapshot = nil
        cachedOwnerAccountID = nil
        localSmallTasks = []
        proSmallTasks = []
        cachedSearchConfig = nil
    }

    func localScenarioBundles() -> AIScenarioRemoteBundlesCollection? {
        localBundles
    }

    func proScenarioBundles() -> AIScenarioRemoteBundlesCollection? {
        proBundles
    }

    func effectiveSmallTasks() -> [SmallTask] {
        var merged: [String: SmallTask] = [:]
        for task in proSmallTasks {
            merged[task.code] = task
        }
        for task in localSmallTasks {
            merged[task.code] = task
        }
        return merged.values.sorted { $0.code < $1.code }
    }

    func effectiveSearchConfig() throws -> SearchRuntimeConfig {
        guard let cachedSearchConfig else {
            throw AIConfigError.runtimeNotBootstrapped
        }
        return try cachedSearchConfig.get()
    }

    /// 场景默认模型变更后，同步更新运行时缓存快照与已缓存 bundle。
    func updateScenarioDefaultModel(_ modelName: String, for scenario: AIScenario) {
        let trimmed = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }

        if cachedSnapshot != nil {
            cachedSnapshot?.setScenarioDefaultModelName(trimmed, for: scenario)
        }

        if localBundles != nil {
            localBundles = applyingDefaultModel(trimmed, to: localBundles, for: scenario)
        }
        if proBundles != nil {
            proBundles = applyingDefaultModel(trimmed, to: proBundles, for: scenario)
        }
    }

    func updateScenarioModelSource(_ source: AIModelSelectionSource, for scenario: AIScenario) {
        cachedSnapshot?.setScenarioModelSource(source, for: scenario)
    }

    /// 合并后的最终场景集合。
    func effectiveBundles() throws -> AIScenarioRemoteBundlesCollection {
        guard let local = localBundles else {
            throw AIConfigError.runtimeNotBootstrapped
        }
        let merged = AIRuntimeConfigAssembler.merge(local: local, pro: proBundles)
        return merged
    }

    private func applyingDefaultModel(
        _ modelName: String,
        to bundles: AIScenarioRemoteBundlesCollection?,
        for scenario: AIScenario
    ) -> AIScenarioRemoteBundlesCollection? {
        guard var bundles else { return nil }
        var bundle = bundles.bundle(for: scenario)
        guard bundle.models.contains(where: { $0.name == modelName }) else { return bundles }
        bundle.defaultModelName = modelName
        bundle.models = bundle.models.map { row in
            var copy = row
            copy.isDefault = (row.name == modelName)
            return copy
        }
        bundles.setBundle(bundle, for: scenario)
        return bundles
    }
}
