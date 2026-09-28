import Foundation

/// AI 配置中心
/// 统一管理 AI 模型、场景策略、运行时配置、远程配置、本地缓存
/// 负责配置解析、缓存刷新、偏好持久化、运行时覆盖
final class AIConfigCenter {
    // MARK: - 依赖组件
    /// AI 设置仓储（本地持久化）
    private let repository: any AISettingsRepository
    /// 远程配置提供者（可选）
    private let remoteProvider: (any AIRemoteConfigProvider)?
    /// AI 运行时存储（内存级覆盖配置）
    private let runtimeStore: AIRuntimeStore
    /// AI 运行时配置存储（内存级快照 + bundle）
    private let runtimeConfigStore: AIRuntimeConfigStore
    /// 会话快照存储（获取当前登录账号）
    private let sessionSnapshotStore: SessionSnapshotStore
    /// 场景策略解析器（根据场景选择模型/配置）
    private let resolver: ScenarioPolicyResolver
    /// 日志器
    private let logger: Logger

    // MARK: - 初始化
    init(
        repository: any AISettingsRepository,
        remoteProvider: (any AIRemoteConfigProvider)? = nil,
        runtimeStore: AIRuntimeStore,
        runtimeConfigStore: AIRuntimeConfigStore,
        sessionSnapshotStore: SessionSnapshotStore = SessionSnapshotStore(),
        resolver: ScenarioPolicyResolver = ScenarioPolicyResolver(),
        logger: Logger = ConsoleLogger()
    ) {
        self.repository = repository
        self.remoteProvider = remoteProvider
        self.runtimeStore = runtimeStore
        self.runtimeConfigStore = runtimeConfigStore
        self.sessionSnapshotStore = sessionSnapshotStore
        self.resolver = resolver
        self.logger = logger
    }

    // MARK: - 账号解析
    /// 解析最终归属的账号 ID
    /// - Parameters:
    ///   - explicitID: 显式传入的账号 ID
    /// - Returns: 最终使用的账号 ID（优先显式，否则从会话快照获取）
    private func resolvedOwnerAccountID(explicit explicitID: Int64?) async -> Int64? {
        if let explicitID {
            return explicitID
        }
        guard let session = await sessionSnapshotStore.load() else {
            logger.debug(
                "AIConfigCenter：SessionSnapshotStore 无可用 UserSession，ownerAccountID 解析为 nil",
                module: .aiConfig
            )
            return nil
        }
        return session.accountID
    }

    // MARK: - 场景配置解析
    /// 为指定场景解析最终可用的 AI 配置
    /// - Parameters:
    ///   - scenario: 业务场景
    ///   - preferredModelName: 用户偏好模型
    /// - Returns: 解析完成的配置
    func resolve(for scenario: AIScenario, preferredModelName: String? = nil) async throws -> AIResolvedConfig {
        let bundles = try await runtimeConfigStore.effectiveBundles()
        let resolved = try await resolver.resolve(
            scenario: scenario,
            bundles: bundles,
            runtimeStore: runtimeStore,
            preferredModelName: preferredModelName
        )
        logger.debug(
            "已解析场景=\(scenario.rawValue)，来源=\(resolved.source.rawValue)，模型=\(resolved.model)",
            module: .aiConfig
        )
        return resolved
    }

    // MARK: - 运行时缓存更新
    /// 从快照重建运行时缓存
    /// 会写入 AIRuntimeConfigStore，不覆盖已绑定的账号
    func rebuildRuntimeCache(from snapshot: AISettingsSnapshot) async {
        let ownerAccountID = await resolvedOwnerAccountID(explicit: nil)
        await runtimeConfigStore.applySnapshot(snapshot, ownerAccountID: ownerAccountID)
        logger.debug("AI 运行时快照与场景 bundle 已更新", module: .aiConfig)
    }

    /// 应用草稿快照（设置页预览用）
    /// 只更新内存，不影响持久化
    func applyDraftSnapshot(_ snapshot: AISettingsSnapshot) async {
        await runtimeConfigStore.applySnapshot(snapshot, ownerAccountID: nil)
        logger.debug("AI 运行时草稿快照已应用", module: .aiConfig)
    }

    // MARK: - 启动预热
    /// 启动预热：加载账号相关的 AI 配置
    /// 登录、切换账号时调用
    /// - Parameter ownerAccountID: 所属账号 ID（不传则自动从会话获取）
    func prewarm(ownerAccountID: Int64? = nil) async {
        let source = ownerAccountID.map { "ownerAccountID=\($0)" } ?? "ownerAccountID=nil（由仓储解析会话）"
        logger.info("AIConfigCenter.prewarm 开始 \(source)", module: .aiConfig)
        let snapshot = await repository.loadSnapshot(ownerAccountID: ownerAccountID)
        let resolvedOwner = await resolvedOwnerAccountID(explicit: ownerAccountID)
        logger.info(
            "AIConfigCenter.prewarm 已从仓储拿到快照 厂商Key=\(snapshot.apiKeys.count) 搜索厂商=\(snapshot.searchKeys.count) 模型=\(snapshot.allModels.count) 提示词=\(snapshot.promptRepo.count)，即将写入运行时缓存",
            module: .aiConfig
        )
        await runtimeConfigStore.applySnapshot(snapshot, ownerAccountID: resolvedOwner)
        let activeSearch = snapshot.searchKeys.first(where: { $0.isUsing })?.company ?? "none"
        let resolvedProvider = (try? await runtimeConfigStore.effectiveSearchConfig())?.provider.rawValue ?? "unresolved"
        logger.info(
            "AIConfigCenter.prewarm 结束，运行时本地 bundle 已更新 activeSearch=\(activeSearch) resolvedProvider=\(resolvedProvider)",
            module: .aiConfig
        )
    }

    // MARK: - 获取当前快照
    /// 获取当前生效的设置快照
    /// 优先读内存缓存，不存在则从仓储加载
    func currentSnapshot(ownerAccountID: Int64? = nil) async -> AISettingsSnapshot {
        let resolved = await resolvedOwnerAccountID(explicit: ownerAccountID)
        let source = ownerAccountID.map { "显式 ownerAccountID=\($0)" } ?? "仓储解析会话"
        logger.debug("AIConfigCenter.currentSnapshot 读链路开始（\(source)，resolved=\(String(describing: resolved))）", module: .aiConfig)

        if let hit = await runtimeConfigStore.cachedSnapshotIfMatches(ownerAccountID: resolved) {
            logger.debug(
                "AIConfigCenter.currentSnapshot 命中内存缓存 厂商Key=\(hit.apiKeys.count) 模型=\(hit.allModels.count) 提示词=\(hit.promptRepo.count)",
                module: .aiConfig
            )
            return hit
        }

        if resolved == nil, let boundOwner = await runtimeConfigStore.boundOwnerAccountIDForDiagnostics() {
            logger.warning(
                "AIConfigCenter.currentSnapshot 未命中缓存：resolved=nil 但运行时曾绑定 accountID=\(boundOwner)，即将回填空快照可能清空 bundle",
                module: .aiConfig
            )
        }

        let snapshot = await repository.loadSnapshot(ownerAccountID: ownerAccountID)
        await runtimeConfigStore.applySnapshot(snapshot, ownerAccountID: resolved)
        logger.debug(
            "AIConfigCenter.currentSnapshot 已从仓储回填缓存 厂商Key=\(snapshot.apiKeys.count) 模型=\(snapshot.allModels.count) 提示词=\(snapshot.promptRepo.count)",
            module: .aiConfig
        )
        return snapshot
    }

    /// 强制从本地仓储重载账号级 AI 设置，并重建本地运行时 bundle。
    func reloadLocalSnapshot(ownerAccountID: Int64? = nil) async -> AISettingsSnapshot {
        let resolved = await resolvedOwnerAccountID(explicit: ownerAccountID)
        let snapshot = await repository.loadSnapshot(ownerAccountID: ownerAccountID)
        await runtimeConfigStore.applySnapshot(snapshot, ownerAccountID: resolved)
        logger.info(
            "AIConfigCenter.reloadLocalSnapshot 已重载本地配置 厂商Key=\(snapshot.apiKeys.count) 搜索厂商=\(snapshot.searchKeys.count) 模型=\(snapshot.allModels.count) 提示词=\(snapshot.promptRepo.count) activeSearch=\(snapshot.searchKeys.first(where: \.isUsing)?.company ?? "none")",
            module: .aiConfig
        )
        return snapshot
    }

    // MARK: - 获取场景 bundle
    /// 获取当前生效的场景 bundle 集合（本地+远程合并）
    func effectiveScenarioBundles() async throws -> AIScenarioRemoteBundlesCollection {
        try await runtimeConfigStore.effectiveBundles()
    }

    /// 获取本地内置场景 bundle
    func localScenarioBundles() async -> AIScenarioRemoteBundlesCollection? {
        await runtimeConfigStore.localScenarioBundles()
    }

    /// 获取专业版/远程场景 bundle
    func proScenarioBundles() async -> AIScenarioRemoteBundlesCollection? {
        await runtimeConfigStore.proScenarioBundles()
    }

    /// 获取生效的小任务配置（快捷指令/工具）
    func effectiveSmallTasks() async -> [SmallTask] {
        await runtimeConfigStore.effectiveSmallTasks()
    }

    /// 获取搜索运行时配置
    func effectiveSearchConfig() async throws -> SearchRuntimeConfig {
        try await runtimeConfigStore.effectiveSearchConfig()
    }

    // MARK: - 用户偏好设置
    /// 更新场景的默认模型
    func updateScenarioDefaultModel(_ modelName: String, for scenario: AIScenario) async {
        await runtimeConfigStore.updateScenarioDefaultModel(modelName, for: scenario)
        await persistScenarioPreferenceMutation { snapshot in
            snapshot.setScenarioDefaultModelName(modelName, for: scenario)
        }
    }

    /// 更新场景的模型选择来源
    func updateScenarioModelSource(_ source: AIModelSelectionSource, for scenario: AIScenario) async {
        await runtimeConfigStore.updateScenarioModelSource(source, for: scenario)
        await persistScenarioPreferenceMutation { snapshot in
            snapshot.setScenarioModelSource(source, for: scenario)
        }
    }

    // MARK: - 远程配置
    /// 刷新远程 AI 配置
    func refreshRemoteConfig() async {
        guard let remoteProvider else { return }
        do {
            let patch = try await remoteProvider.fetchRemotePatch()
            await runtimeConfigStore.setProOverlay(patch.scenarioRemoteBundles, revision: patch.revision, smallTasks: patch.smallTasks)
            logger.info(
                "远程 AI 场景模型已载入内存，revision=\(patch.revision ?? "unknown")",
                module: .aiConfig
            )
        } catch {
            logger.error("\(error)")
            logger.error("远程 AI 配置刷新失败：\(error.localizedDescription)", module: .aiConfig)
        }
    }

    /// 兼容启动链路：账号级远程刷新（当前与无参版本相同，账号已由 prewarm 绑定）。
    func refreshRemoteConfig(ownerAccountID _: Int64?) async {
        await refreshRemoteConfig()
    }

    // MARK: - 运行时覆盖（调试/临时覆盖）
    /// 设置运行时覆盖配置（优先级最高，用于调试）
    func setRuntimeOverride(_ config: AIScenarioConfig, for scenario: AIScenario) async {
        await runtimeStore.setOverride(config, for: scenario)
    }

    /// 清除指定场景的运行时覆盖
    func clearRuntimeOverride(for scenario: AIScenario) async {
        await runtimeStore.clearOverride(for: scenario)
    }

    /// 清除所有场景的运行时覆盖
    func clearRuntimeOverrides() async {
        await runtimeStore.clearAll()
    }

    /// 重置所有运行时缓存（内存级重置）
    func resetRuntimeCaches() async {
        await runtimeConfigStore.reset()
        await runtimeStore.clearAll()
    }

    // MARK: - 持久化偏好变更
    /// 持久化场景偏好变更
    /// 统一封装：读快照 → 修改 → 存内存 → 存磁盘
    private func persistScenarioPreferenceMutation(
        _ mutate: @Sendable (inout AISettingsSnapshot) -> Void
    ) async {
        let ownerAccountID = await resolvedOwnerAccountID(explicit: nil)
        var snapshot = await currentSnapshot(ownerAccountID: ownerAccountID)
        mutate(&snapshot)
        await runtimeConfigStore.applySnapshot(snapshot, ownerAccountID: ownerAccountID)
        do {
            try await repository.save(snapshot: snapshot, ownerAccountID: ownerAccountID)
        } catch {
            logger.error("AI 场景偏好持久化失败：\(error.localizedDescription)", module: .aiConfig)
        }
    }
}
