import CoreData
import Foundation

/// 账号级 AI 设置仓储：`AllModels` / `APIKeys` / `SearchKeys` / `PromptRepo` 存 Core Data；其余轻量偏好用 `AISettingsSnapshot.PreferencesPayload` 存 UserDefaults。
/// 种子 JSON 仅在「该账号首次初始化」时写入 Core Data，之后只读本地库，不按版本从 bundle 重灌。
/// Pro 场景 bundle 等运行时数据不在此持久化。
nonisolated final class DefaultAISettingsRepository: AISettingsRepository, @unchecked Sendable {
    private enum EntityName {
        static let provider = "AIProviderEntity"
        static let searchProvider = "AISearchProviderEntity"
        static let model = "AIModelEntity"
        static let scenarioBinding = "AIScenarioModelBindingEntity"
        static let smallTask = "AISmallTaskEntity"
        static let promptRepo = "PromptRepoEntity"
        static let seedState = "AISettingsSeedStateEntity"
    }

    private enum Field {
        static let id = "id"
        static let ownerAccountID = "ownerAccountID"
        static let providerID = "providerID"
        static let name = "name"
        static let company = "company"
        static let key = "key"
        static let requestURL = "requestURL"
        static let help = "help"
        static let from = "from"
        static let privacyPolicyURL = "privacyPolicyURL"
        static let isEnabled = "isEnabled"
        static let isUsing = "isUsing"
        static let searchClass = "searchClass"
        static let authType = "authType"
        static let priority = "priority"
        static let enabledScopesData = "enabledScopesData"
        static let revision = "revision"
        static let source = "source"
        static let privacyPolicyAccepted = "privacyPolicyAccepted"
        static let privacyPolicyAcceptedAt = "privacyPolicyAcceptedAt"
        static let timestamp = "timestamp"
        static let displayName = "displayName"
        static let identity = "identity"
        static let position = "position"
        static let price = "price"
        static let supportsSearch = "supportsSearch"
        static let supportsTextGen = "supportsTextGen"
        static let supportsMultimodal = "supportsMultimodal"
        static let supportsReasoning = "supportsReasoning"
        static let supportReasoningChange = "supportReasoningChange"
        static let supportsImageGen = "supportsImageGen"
        static let supportsVoiceGen = "supportsVoiceGen"
        static let supportsToolUse = "supportsToolUse"
        static let systemProvision = "systemProvision"
        static let icon = "icon"
        static let briefDescription = "briefDescription"
        static let characterDesign = "characterDesign"
        static let aiToolScenariosData = "aiToolScenariosData"
        static let relatedTaskCodesData = "relatedTaskCodesData"
        static let scenario = "scenario"
        static let modelID = "modelID"
        static let temperature = "temperature"
        static let maxTokens = "maxTokens"
        static let isDefault = "isDefault"
        static let isActive = "isActive"
        static let createdAt = "createdAt"
        static let baseModelName = "baseModelName"
        static let localFilename = "localFilename"
        static let code = "code"
        static let brief = "brief"
        static let prompt = "prompt"
        static let toolListData = "toolListData"
        static let title = "title"
        static let content = "content"
        static let isSystem = "isSystem"
        static let localizationKey = "localizationKey"
        static let catalogVersion = "catalogVersion"
        static let updatedAt = "updatedAt"
    }

    private enum UserDefaultsKey {
        /// 按账号隔离：`AISettingsSnapshot.PreferencesPayload` 的 JSON（与快照非目录字段一致）。
        static func aiPreferences(_ accountID: Int64) -> String {
            "support.ai.prefs.payload.\(accountID)"
        }
    }

    private let coreDataStack: CoreDataStack
    private let snapshotStore: SessionSnapshotStore
    private let encoder = JSONEncoder.default
    private let decoder = JSONDecoder.default
    private let logger: Logger
    private let defaults: UserDefaults

    init(
        coreDataStack: CoreDataStack,
        snapshotStore: SessionSnapshotStore = SessionSnapshotStore(),
        defaults: UserDefaults = .standard,
        logger: Logger = ConsoleLogger()
    ) {
        self.coreDataStack = coreDataStack
        self.snapshotStore = snapshotStore
        self.defaults = defaults
        self.logger = logger
    }

    /// 加载当前账号的完整快照：Core Data 中的 `AllModels` / `APIKeys` / `SearchKeys` / `SmallTask` / `PromptRepo` + UserDefaults 中的轻量偏好载荷。
    /// `ownerAccountID` 由登录引导显式传入时，不依赖会话快照读取顺序，保证「首次登录即灌种子」。
    func loadSnapshot(ownerAccountID explicitAccountID: Int64?) async -> AISettingsSnapshot {
        let ownerAccountID: Int64?
        let ownerSource: String
        if let explicitAccountID {
            ownerAccountID = explicitAccountID
            ownerSource = "显式参数"
        } else {
            ownerAccountID = await currentOwnerAccountID()
            ownerSource = "SessionSnapshotStore"
        }

        guard let ownerAccountID else {
            logger.warning(
                "AI loadSnapshot 读链路结束：无 ownerAccountID（来源=\(ownerSource)），返回空目录；新建对话/模型校验将失败",
                module: .aiConfig
            )
            return AISettingsSnapshot(
                allModels: [],
                apiKeys: []
            )
        }

        logger.debug(
            "AI loadSnapshot 读链路开始 ownerAccountID=\(ownerAccountID) 账号来源=\(ownerSource)",
            module: .aiConfig
        )

        do {
            // 该账号尚未初始化时，才把 bundle 内种子写入 Core Data（仅一次）。
            _ = try await ensureSeedDataIfNeeded(ownerAccountID: ownerAccountID)
            return try await loadSnapshotFromStore(ownerAccountID: ownerAccountID)
        } catch {
            logger.warning("AI 设置加载失败，返回空快照：\(error.localizedDescription)", module: .aiConfig)
            return AISettingsSnapshot(allModels: [], apiKeys: [])
        }
    }

    /// 持久化：目录、搜索厂商、小任务与提示词库进 Core Data；其余偏好整包编码进 UserDefaults。
    func save(snapshot: AISettingsSnapshot) async throws {
        try await save(snapshot: snapshot, ownerAccountID: nil)
    }

    func save(snapshot: AISettingsSnapshot, ownerAccountID explicitAccountID: Int64?) async throws {
        let ownerAccountID: Int64?
        if let explicitAccountID {
            ownerAccountID = explicitAccountID
        } else {
            ownerAccountID = await currentOwnerAccountID()
        }
        guard let ownerAccountID else {
            logger.info("未登录，跳过 AI 设置持久化", module: .aiConfig)
            return
        }
        try await persist(snapshot: snapshot, ownerAccountID: ownerAccountID)
        savePreferencesPayload(snapshot.preferencesPayload, ownerAccountID: ownerAccountID)
        logger.info(
            "AI save 写链路完成 ownerAccountID=\(ownerAccountID) Core Data 厂商Key行=\(snapshot.apiKeys.count) 搜索厂商行=\(snapshot.searchKeys.count) 模型行=\(snapshot.allModels.count) 小任务行=\(snapshot.smallTasks.count) 提示词行=\(snapshot.promptRepo.count)，偏好已写入 UserDefaults",
            module: .aiConfig
        )
    }

    func saveModel(_ model: AllModels) async throws {
        guard let ownerAccountID = await currentOwnerAccountID() else {
            logger.info("未登录，跳过模型单条持久化", module: .aiConfig)
            return
        }
        try await coreDataStack.performBackgroundTask { context in
            try Self.upsertModel(model, ownerAccountID: ownerAccountID, context: context)
        }
    }

    func saveScenarioBinding(_ binding: AIScenarioModelBinding, ownerAccountID explicitAccountID: Int64?) async throws {
        let ownerAccountID: Int64?
        if let explicitAccountID {
            ownerAccountID = explicitAccountID
        } else {
            ownerAccountID = await currentOwnerAccountID()
        }
        guard let ownerAccountID else {
            logger.info("未登录，跳过场景绑定单条持久化", module: .aiConfig)
            return
        }
        try await coreDataStack.performBackgroundTask { context in
            var copy = binding
            copy.ownerAccountID = ownerAccountID
            if copy.isDefault {
                try Self.clearDefaultScenarioBindings(
                    scenario: copy.scenario,
                    excludingID: copy.id,
                    ownerAccountID: ownerAccountID,
                    context: context
                )
            }
            try Self.upsertScenarioBinding(copy, ownerAccountID: ownerAccountID, context: context)
        }
        logger.info(
            "AI 场景绑定单条写链路完成 ownerAccountID=\(ownerAccountID) id=\(binding.id)",
            module: .aiConfig
        )
    }

    func deleteScenarioBinding(id: UUID, ownerAccountID explicitAccountID: Int64?) async throws {
        let ownerAccountID: Int64?
        if let explicitAccountID {
            ownerAccountID = explicitAccountID
        } else {
            ownerAccountID = await currentOwnerAccountID()
        }
        guard let ownerAccountID else {
            logger.info("未登录，跳过场景绑定删除持久化", module: .aiConfig)
            return
        }
        try await coreDataStack.performBackgroundTask { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.scenarioBinding)
            request.fetchLimit = 1
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                Self.ownerPredicate(ownerAccountID),
                NSPredicate(format: "\(Field.id) == %@", id as CVarArg),
            ])
            for object in try context.fetch(request) {
                context.delete(object)
            }
        }
        logger.info(
            "AI 场景绑定删除链路完成 ownerAccountID=\(ownerAccountID) id=\(id)",
            module: .aiConfig
        )
    }

    func saveProvider(_ provider: APIKeys) async throws {
        guard let ownerAccountID = await currentOwnerAccountID() else {
            logger.info("未登录，跳过厂商单条持久化", module: .aiConfig)
            return
        }
        try await coreDataStack.performBackgroundTask { context in
            Self.upsertProvider(provider, ownerAccountID: ownerAccountID, context: context)
        }
    }

    func saveSearchKey(_ searchKey: SearchKeys, ownerAccountID explicitAccountID: Int64?) async throws {
        let ownerAccountID: Int64?
        if let explicitAccountID {
            ownerAccountID = explicitAccountID
        } else {
            ownerAccountID = await currentOwnerAccountID()
        }
        guard let ownerAccountID else {
            logger.info("未登录，跳过搜索厂商单条持久化", module: .aiConfig)
            return
        }
        try await coreDataStack.performBackgroundTask { context in
            try Self.upsertSearchKey(searchKey, ownerAccountID: ownerAccountID, context: context)
        }
        logger.info(
            "AI 搜索厂商单条写链路完成 ownerAccountID=\(ownerAccountID) id=\(searchKey.id) company=\(searchKey.company)",
            module: .aiConfig
        )
    }

    func deleteSearchKeys(ids: [UUID], ownerAccountID explicitAccountID: Int64?) async throws {
        let ownerAccountID: Int64?
        if let explicitAccountID {
            ownerAccountID = explicitAccountID
        } else {
            ownerAccountID = await currentOwnerAccountID()
        }
        guard let ownerAccountID else {
            logger.info("未登录，跳过搜索厂商删除持久化", module: .aiConfig)
            return
        }
        guard ids.isEmpty == false else { return }
        try await coreDataStack.performBackgroundTask { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.searchProvider)
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                Self.ownerPredicate(ownerAccountID),
                NSPredicate(format: "\(Field.id) IN %@", ids),
            ])
            for object in try context.fetch(request) {
                context.delete(object)
            }
        }
        logger.info(
            "AI 搜索厂商删除写链路完成 ownerAccountID=\(ownerAccountID) ids=\(ids.count)",
            module: .aiConfig
        )
    }

    func saveSearchToolPreferences(
        _ preferences: AISearchToolPreferences,
        revision: SearchRuntimeConfigRevision,
        searchKeys: [SearchKeys]?,
        ownerAccountID explicitAccountID: Int64?
    ) async throws {
        let ownerAccountID: Int64?
        if let explicitAccountID {
            ownerAccountID = explicitAccountID
        } else {
            ownerAccountID = await currentOwnerAccountID()
        }
        guard let ownerAccountID else {
            logger.info("未登录，跳过搜索工具偏好持久化", module: .aiConfig)
            return
        }
        var payload = loadDecodedPreferencesPayload(ownerAccountID: ownerAccountID)
        payload.searchToolPreferences = preferences
        payload.searchConfigRevision = revision
        if let searchKeys {
            payload.searchKeys = searchKeys
        }
        savePreferencesPayload(payload, ownerAccountID: ownerAccountID)
        logger.info(
            "AI 搜索工具偏好写链路完成 ownerAccountID=\(ownerAccountID) revision=\(revision.localRevision)",
            module: .aiConfig
        )
    }

    func savePromptRepo(_ promptRepo: [PromptRepo], ownerAccountID explicitAccountID: Int64?) async throws {
        let ownerAccountID: Int64?
        if let explicitAccountID {
            ownerAccountID = explicitAccountID
        } else {
            ownerAccountID = await currentOwnerAccountID()
        }
        guard let ownerAccountID else {
            logger.info("未登录，跳过提示词库持久化", module: .aiConfig)
            return
        }
        try await coreDataStack.performBackgroundTask { context in
            try Self.replacePromptRepo(promptRepo, ownerAccountID: ownerAccountID, context: context)
        }
        logger.info(
            "AI 提示词库写链路完成 ownerAccountID=\(ownerAccountID) PromptRepoEntity 行=\(promptRepo.count)",
            module: .aiConfig
        )
    }

    private func currentOwnerAccountID() async -> Int64? {
        await snapshotStore.load()?.accountID
    }

    /// 判断当前账号是否尚未完成首次初始化（无 `AISettingsSeedStateEntity` 行）。
    /// 与 `AISettingsSeedCatalog.version` 解耦：版本号仅写入种子状态供排查，不触发从 bundle 重灌。
    /// - Returns: 本次调用是否执行了「首次灌库」（含 Core Data 目录 + UserDefaults 偏好 + 种子状态行）。
    @discardableResult
    private func ensureSeedDataIfNeeded(ownerAccountID: Int64) async throws -> Bool {
        let needsFirstInit = try await coreDataStack.performBackgroundTask { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.seedState)
            request.fetchLimit = 1
            request.predicate = Self.ownerPredicate(ownerAccountID)
            return try context.fetch(request).first == nil
        }

        guard needsFirstInit else { return false }

        let seedModels = AISettingsSeedCatalog.getModelList()
        let seedSnapshot = AISettingsSnapshot(
            allModels: seedModels,
            scenarioBindings: AISettingsSeedCatalog.getScenarioBindings(for: seedModels),
            apiKeys: AISettingsSeedCatalog.getAPIKeyList(),
            smallTasks: [],
            searchKeys: AISettingsSeedCatalog.getSearchKeyList()
        )
        let keyCount = seedSnapshot.apiKeys.count
        let searchKeyCount = seedSnapshot.searchKeys.count
        let modelCount = seedSnapshot.allModels.count
        let promptRepoCount = seedSnapshot.promptRepo.count
        logger.info(
            "AI 首次登录灌库写链路开始 ownerAccountID=\(ownerAccountID) bundle 种子：厂商Key=\(keyCount) 搜索厂商=\(searchKeyCount) 模型=\(modelCount) 提示词=\(promptRepoCount) catalogVersion=\(AISettingsSeedCatalog.version)",
            module: .aiConfig
        )
        guard seedSnapshot.allModels.isEmpty == false else {
            logger.error(
                "AI 种子 AllModels.json 为空，跳过灌库与初始化标记，下次仍视为未初始化",
                module: .aiConfig
            )
            return false
        }
        logger.debug(
            "AI 首次登录灌库：Core Data performBackgroundTask → syncProviders / syncModels / upsertSeedState",
            module: .aiConfig
        )
        try await persist(snapshot: seedSnapshot, ownerAccountID: ownerAccountID)
        savePreferencesPayload(seedSnapshot.preferencesPayload, ownerAccountID: ownerAccountID)
        logger.info(
            "AI 首次登录灌库写链路完成 ownerAccountID=\(ownerAccountID) 已写入 厂商Key行=\(keyCount) 搜索厂商行=\(searchKeyCount) 模型行=\(modelCount) 提示词行=\(promptRepoCount)；UserDefaults 偏好已写入；AISettingsSeedStateEntity 已标记",
            module: .aiConfig
        )
        return true
    }

    /// 替换 Core Data 中的账号级 AI 目录、搜索、小任务、提示词库及种子状态行。
    private func persist(snapshot: AISettingsSnapshot, ownerAccountID: Int64) async throws {
        try await coreDataStack.performBackgroundTask { context in
            try Self.replaceProviders(snapshot.apiKeys, ownerAccountID: ownerAccountID, context: context)
            try Self.replaceSearchKeys(snapshot.searchKeys, ownerAccountID: ownerAccountID, context: context)
            try Self.replaceModels(snapshot.allModels, ownerAccountID: ownerAccountID, context: context)
            try Self.replaceScenarioBindings(snapshot.scenarioBindings, ownerAccountID: ownerAccountID, context: context)
            try Self.replaceSmallTasks(snapshot.smallTasks, ownerAccountID: ownerAccountID, context: context)
            try Self.replacePromptRepo(snapshot.promptRepo, ownerAccountID: ownerAccountID, context: context)
            try Self.upsertSeedState(ownerAccountID: ownerAccountID, context: context)
        }
    }

    private func loadSnapshotFromStore(ownerAccountID: Int64) async throws -> AISettingsSnapshot {
        logger.debug(
            "AI loadSnapshot 读链路：Core Data fetch AIProviderEntity + AISearchProviderEntity + AIModelEntity + AISmallTaskEntity + PromptRepoEntity ownerAccountID=\(ownerAccountID)",
            module: .aiConfig
        )
        let stored = try await coreDataStack.performBackgroundTask { context -> ([APIKeys], [SearchKeys], [AllModels], [AIScenarioModelBinding], [SmallTask], [PromptRepo]) in
            let apiKeys = try Self.fetchProviders(ownerAccountID: ownerAccountID, context: context)
            let searchKeys = try Self.fetchSearchKeys(ownerAccountID: ownerAccountID, context: context)
            let allModels = try Self.fetchModels(ownerAccountID: ownerAccountID, context: context)
            let scenarioBindings = try Self.fetchScenarioBindings(ownerAccountID: ownerAccountID, context: context)
            let smallTasks = try Self.fetchSmallTasks(ownerAccountID: ownerAccountID, context: context)
            let promptRepo = try Self.fetchPromptRepo(ownerAccountID: ownerAccountID, context: context)
            return (apiKeys, searchKeys, allModels, scenarioBindings, smallTasks, promptRepo)
        }
        let hasStoredPreferencesPayload = defaults.data(forKey: UserDefaultsKey.aiPreferences(ownerAccountID)) != nil
        var preferences = loadDecodedPreferencesPayload(ownerAccountID: ownerAccountID)
        var searchKeys = try await searchKeysFromStoreOrMigratedPreferences(
            storedSearchKeys: stored.1,
            preferences: &preferences,
            hasStoredPreferencesPayload: hasStoredPreferencesPayload,
            ownerAccountID: ownerAccountID
        )
        searchKeys = try await ensureSearchProfilesBackfillIfNeeded(
            searchKeys: searchKeys,
            preferences: &preferences,
            ownerAccountID: ownerAccountID
        )
        let prefsSource = hasStoredPreferencesPayload ? "UserDefaults 已存在载荷" : "UserDefaults 使用默认偏好"
        logger.debug(
            "AI loadSnapshot 读链路完成 ownerAccountID=\(ownerAccountID) 读到 厂商Key=\(stored.0.count) 搜索厂商=\(searchKeys.count) 模型=\(stored.2.count) 场景绑定=\(stored.3.count) 小任务=\(stored.4.count) 提示词=\(stored.5.count)；偏好：\(prefsSource)",
            module: .aiConfig
        )
        var snapshot = AISettingsSnapshot(
            allModels: stored.2,
            scenarioBindings: stored.3,
            apiKeys: stored.0,
            smallTasks: stored.4,
            promptRepo: stored.5,
            preferences: preferences
        )
        snapshot.searchKeys = searchKeys
        snapshot.refreshSearchConfigRevision(previous: nil)
        return snapshot
    }

    /// 将 `PreferencesPayload` 编码写入 UserDefaults（结构与 `AISettingsSnapshot` 非目录字段一致）。
    private func savePreferencesPayload(_ payload: AISettingsSnapshot.PreferencesPayload, ownerAccountID: Int64) {
        if let data = try? encoder.encode(payload) {
            defaults.set(data, forKey: UserDefaultsKey.aiPreferences(ownerAccountID))
        }
    }

    /// 整包解码 `PreferencesPayload`；缺失或损坏时使用与 `PreferencesPayload.default` 对齐的默认值。
    private func loadDecodedPreferencesPayload(ownerAccountID: Int64) -> AISettingsSnapshot.PreferencesPayload {
        let decoded: AISettingsSnapshot.PreferencesPayload
        if let data = defaults.data(forKey: UserDefaultsKey.aiPreferences(ownerAccountID)),
           let payload = try? decoder.decode(AISettingsSnapshot.PreferencesPayload.self, from: data) {
            decoded = payload
        } else {
            decoded = .default
        }
        return decoded
    }

    private func searchKeysFromStoreOrMigratedPreferences(
        storedSearchKeys: [SearchKeys],
        preferences: inout AISettingsSnapshot.PreferencesPayload,
        hasStoredPreferencesPayload: Bool,
        ownerAccountID: Int64
    ) async throws -> [SearchKeys] {
        if storedSearchKeys.isEmpty == false {
            return storedSearchKeys
        }

        let migrationSource: [SearchKeys]
        if preferences.searchKeys.isEmpty {
            migrationSource = AISettingsSeedCatalog.getSearchKeyList()
        } else if hasStoredPreferencesPayload {
            migrationSource = preferences.searchKeys
        } else {
            migrationSource = AISettingsSeedCatalog.getSearchKeyList()
        }
        guard migrationSource.isEmpty == false else { return [] }

        try await coreDataStack.performBackgroundTask { context in
            try Self.replaceSearchKeys(migrationSource, ownerAccountID: ownerAccountID, context: context)
        }
        preferences.searchKeys = migrationSource
        savePreferencesPayload(preferences, ownerAccountID: ownerAccountID)
        logger.info(
            "AI 联网搜索厂商迁移完成 ownerAccountID=\(ownerAccountID) 已从偏好/默认配置写入 AISearchProviderEntity 行=\(migrationSource.count)",
            module: .aiConfig
        )
        return migrationSource
    }

    private func ensureSearchProfilesBackfillIfNeeded(
        searchKeys: [SearchKeys],
        preferences: inout AISettingsSnapshot.PreferencesPayload,
        ownerAccountID: Int64
    ) async throws -> [SearchKeys] {
        guard preferences.searchToolPreferences.useSearch else { return searchKeys }

        var keys = searchKeys
        let hasActiveWebProfile = keys.contains {
            $0.searchClass.lowercased() == "web" && $0.isUsing
        }
        guard keys.isEmpty || hasActiveWebProfile == false else { return keys }

        if keys.isEmpty {
            keys = [SearchProviderCatalog.makeDefaultDuckDuckGoProfile()]
        } else if let duckIndex = keys.firstIndex(where: { SearchProviderID(company: $0.company) == .duckduckgo }) {
            keys[duckIndex].isUsing = true
            keys[duckIndex].requestURL = SearchProviderCatalog.defaultRequestURL(for: .duckduckgo)
            keys[duckIndex].timestamp = Date()
            keys[duckIndex].revision += 1
        } else {
            keys.append(SearchProviderCatalog.makeDefaultDuckDuckGoProfile())
        }

        let persistedKeys = keys
        try await coreDataStack.performBackgroundTask { context in
            try Self.replaceSearchKeys(persistedKeys, ownerAccountID: ownerAccountID, context: context)
        }
        preferences.searchKeys = persistedKeys
        savePreferencesPayload(preferences, ownerAccountID: ownerAccountID)
        logger.info(
            "AI 联网搜索默认 profile 回填完成 ownerAccountID=\(ownerAccountID) 搜索厂商行=\(persistedKeys.count) 激活项=\(persistedKeys.filter(\.isUsing).count)",
            module: .aiConfig
        )
        return persistedKeys
    }

    /// 增量同步当前账号的厂商 Key 行：upsert 快照内条目，仅删除快照已移除的旧 id。
    private static func replaceProviders(
        _ apiKeys: [APIKeys],
        ownerAccountID: Int64,
        context: NSManagedObjectContext
    ) throws {
        let desiredIDs = Set(apiKeys.map(\.id))
        try Self.deleteObjectsMissingFromSnapshot(
            entityName: EntityName.provider,
            desiredIDs: desiredIDs,
            ownerAccountID: ownerAccountID,
            context: context
        )
        for apiKey in apiKeys {
            try Self.upsertProvider(apiKey, ownerAccountID: ownerAccountID, context: context)
        }
    }

    /// 增量同步当前账号的联网搜索厂商 Key 行：与模型厂商一样按账号隔离、按 id upsert。
    private static func replaceSearchKeys(
        _ searchKeys: [SearchKeys],
        ownerAccountID: Int64,
        context: NSManagedObjectContext
    ) throws {
        let desiredIDs = Set(searchKeys.map(\.id))
        try Self.deleteObjectsMissingFromSnapshot(
            entityName: EntityName.searchProvider,
            desiredIDs: desiredIDs,
            ownerAccountID: ownerAccountID,
            context: context
        )
        for searchKey in searchKeys {
            try Self.upsertSearchKey(searchKey, ownerAccountID: ownerAccountID, context: context)
        }
    }

    /// 增量同步当前账号的模型目录行：upsert 快照内条目，仅删除快照已移除的旧 id。
    private static func replaceModels(
        _ allModels: [AllModels],
        ownerAccountID: Int64,
        context: NSManagedObjectContext
    ) throws {
        let desiredIDs = Set(allModels.map(\.id))
        try Self.deleteObjectsMissingFromSnapshot(
            entityName: EntityName.model,
            desiredIDs: desiredIDs,
            ownerAccountID: ownerAccountID,
            context: context
        )
        for model in allModels {
            try Self.upsertModel(model, ownerAccountID: ownerAccountID, context: context)
        }
    }

    private static func replaceScenarioBindings(
        _ bindings: [AIScenarioModelBinding],
        ownerAccountID: Int64,
        context: NSManagedObjectContext
    ) throws {
        let desiredIDs = Set(bindings.map(\.id))
        try Self.deleteObjectsMissingFromSnapshot(
            entityName: EntityName.scenarioBinding,
            desiredIDs: desiredIDs,
            ownerAccountID: ownerAccountID,
            context: context
        )
        for binding in Self.normalizedDefaultBindings(bindings, ownerAccountID: ownerAccountID) {
            try Self.upsertScenarioBinding(binding, ownerAccountID: ownerAccountID, context: context)
        }
    }

    private static func replaceSmallTasks(
        _ smallTasks: [SmallTask],
        ownerAccountID: Int64,
        context: NSManagedObjectContext
    ) throws {
        let desiredCodes = Set(smallTasks.map(\.code))
        let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.smallTask)
        request.predicate = Self.ownerPredicate(ownerAccountID)
        for object in try context.fetch(request) {
            guard let code = object.value(forKey: Field.code) as? String, desiredCodes.contains(code) else {
                context.delete(object)
                continue
            }
        }
        for task in smallTasks {
            Self.upsertSmallTask(task, ownerAccountID: ownerAccountID, context: context)
        }
    }

    private static func replacePromptRepo(
        _ promptRepo: [PromptRepo],
        ownerAccountID: Int64,
        context: NSManagedObjectContext
    ) throws {
        let desiredIDs = Set(promptRepo.map(\.id))
        try Self.deleteObjectsMissingFromSnapshot(
            entityName: EntityName.promptRepo,
            desiredIDs: desiredIDs,
            ownerAccountID: ownerAccountID,
            context: context
        )
        for (index, prompt) in promptRepo.enumerated() {
            try Self.upsertPromptRepo(prompt, position: index, ownerAccountID: ownerAccountID, context: context)
        }
    }

    private static func upsertProvider(
        _ provider: APIKeys,
        ownerAccountID: Int64,
        context: NSManagedObjectContext
    ) {
        let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.provider)
        request.fetchLimit = 1
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Self.ownerPredicate(ownerAccountID),
            NSPredicate(format: "\(Field.id) == %@", provider.id as CVarArg),
        ])
        let object = (try? context.fetch(request).first)
            ?? NSEntityDescription.insertNewObject(forEntityName: EntityName.provider, into: context)
        object.setValue(provider.id, forKey: Field.id)
        object.setValue(ownerAccountID, forKey: Field.ownerAccountID)
        object.setValue(provider.providerID, forKey: Field.providerID)
        object.setValue(provider.name, forKey: Field.name)
        object.setValue(provider.company, forKey: Field.company)
        object.setValue(provider.key, forKey: Field.key)
        object.setValue(provider.requestURL, forKey: Field.requestURL)
        object.setValue(provider.help, forKey: Field.help)
        object.setValue(provider.from, forKey: Field.from)
        object.setValue(provider.privacyPolicyURL, forKey: Field.privacyPolicyURL)
        object.setValue(provider.isEnabled, forKey: Field.isEnabled)
        object.setValue(provider.source.rawValue, forKey: Field.source)
        object.setValue(provider.privacyPolicyAccepted, forKey: Field.privacyPolicyAccepted)
        object.setValue(provider.privacyPolicyAcceptedAt, forKey: Field.privacyPolicyAcceptedAt)
        object.setValue(provider.timestamp, forKey: Field.timestamp)
    }

    private static func upsertSearchKey(
        _ searchKey: SearchKeys,
        ownerAccountID: Int64,
        context: NSManagedObjectContext
    ) throws {
        let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.searchProvider)
        request.fetchLimit = 1
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Self.ownerPredicate(ownerAccountID),
            NSPredicate(format: "\(Field.id) == %@", searchKey.id as CVarArg),
        ])
        let object = try context.fetch(request).first
            ?? NSEntityDescription.insertNewObject(forEntityName: EntityName.searchProvider, into: context)
        object.setValue(searchKey.id, forKey: Field.id)
        object.setValue(ownerAccountID, forKey: Field.ownerAccountID)
        object.setValue(searchKey.name, forKey: Field.name)
        object.setValue(searchKey.company, forKey: Field.company)
        object.setValue(searchKey.key, forKey: Field.key)
        object.setValue(searchKey.requestURL, forKey: Field.requestURL)
        object.setValue(searchKey.isUsing, forKey: Field.isUsing)
        object.setValue(searchKey.searchClass, forKey: Field.searchClass)
        object.setValue(searchKey.help, forKey: Field.help)
        object.setValue(searchKey.source.rawValue, forKey: Field.source)
        object.setValue(searchKey.timestamp, forKey: Field.timestamp)
        object.setValue(searchKey.authType.rawValue, forKey: Field.authType)
        object.setValue(Int32(searchKey.priority), forKey: Field.priority)
        object.setValue(try Self.encodeStringArray(searchKey.enabledScopes), forKey: Field.enabledScopesData)
        object.setValue(Int32(searchKey.revision), forKey: Field.revision)
    }

    private static func upsertModel(
        _ model: AllModels,
        ownerAccountID: Int64,
        context: NSManagedObjectContext
    ) throws {
        let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.model)
        request.fetchLimit = 1
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Self.ownerPredicate(ownerAccountID),
            NSPredicate(format: "\(Field.id) == %@", model.id as CVarArg),
        ])
        let object = try context.fetch(request).first
            ?? NSEntityDescription.insertNewObject(forEntityName: EntityName.model, into: context)
        object.setValue(model.id, forKey: Field.id)
        object.setValue(ownerAccountID, forKey: Field.ownerAccountID)
        object.setValue(model.name, forKey: Field.name)
        object.setValue(model.displayName, forKey: Field.displayName)
        object.setValue(model.identity.rawValue, forKey: Field.identity)
        object.setValue(Int32(model.position), forKey: Field.position)
        object.setValue(model.providerID, forKey: Field.providerID)
        object.setValue(model.company, forKey: Field.company)
        object.setValue(Int32(model.price), forKey: Field.price)
        object.setValue(model.isEnabled, forKey: Field.isEnabled)
        object.setValue(model.supportsSearch, forKey: Field.supportsSearch)
        object.setValue(model.supportsTextGen, forKey: Field.supportsTextGen)
        object.setValue(model.supportsMultimodal, forKey: Field.supportsMultimodal)
        object.setValue(model.supportsReasoning, forKey: Field.supportsReasoning)
        object.setValue(model.supportReasoningChange, forKey: Field.supportReasoningChange)
        object.setValue(model.supportsImageGen, forKey: Field.supportsImageGen)
        object.setValue(model.supportsVoiceGen, forKey: Field.supportsVoiceGen)
        object.setValue(model.supportsToolUse, forKey: Field.supportsToolUse)
        object.setValue(model.systemProvision, forKey: Field.systemProvision)
        object.setValue(model.icon, forKey: Field.icon)
        object.setValue(model.briefDescription, forKey: Field.briefDescription)
        object.setValue(model.characterDesign, forKey: Field.characterDesign)
        object.setValue(try Self.encodeStringArray(model.aiToolScenarios), forKey: Field.aiToolScenariosData)
        object.setValue(try Self.encodeStringArray(model.relatedTaskCodes), forKey: Field.relatedTaskCodesData)
        object.setValue(model.baseModelName, forKey: Field.baseModelName)
        object.setValue(model.localFilename, forKey: Field.localFilename)
        object.setValue(model.source.rawValue, forKey: Field.source)
        object.setValue(model.timestamp, forKey: Field.timestamp)
    }

    private static func upsertScenarioBinding(
        _ binding: AIScenarioModelBinding,
        ownerAccountID: Int64,
        context: NSManagedObjectContext
    ) throws {
        let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.scenarioBinding)
        request.fetchLimit = 1
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Self.ownerPredicate(ownerAccountID),
            NSPredicate(format: "\(Field.id) == %@", binding.id as CVarArg),
        ])
        let object = try context.fetch(request).first
            ?? NSEntityDescription.insertNewObject(forEntityName: EntityName.scenarioBinding, into: context)
        object.setValue(binding.id, forKey: Field.id)
        object.setValue(ownerAccountID, forKey: Field.ownerAccountID)
        object.setValue(binding.scenario, forKey: Field.scenario)
        object.setValue(binding.identity.rawValue, forKey: Field.identity)
        object.setValue(binding.modelID, forKey: Field.modelID)
        object.setValue(binding.temperature, forKey: Field.temperature)
        object.setValue(Int32(binding.maxTokens), forKey: Field.maxTokens)
        object.setValue(Int32(binding.position), forKey: Field.position)
        object.setValue(binding.isDefault, forKey: Field.isDefault)
        object.setValue(binding.isActive, forKey: Field.isActive)
        object.setValue(binding.systemProvision, forKey: Field.systemProvision)
        object.setValue(binding.briefDescription, forKey: Field.briefDescription)
        object.setValue(try Self.encodeStringArray(binding.aiToolScenarios), forKey: Field.aiToolScenariosData)
        object.setValue(try Self.encodeStringArray(binding.relatedTaskCodes), forKey: Field.relatedTaskCodesData)
        object.setValue(binding.createdAt, forKey: Field.createdAt)
        object.setValue(binding.updatedAt, forKey: Field.updatedAt)
    }

    private static func clearDefaultScenarioBindings(
        scenario: String,
        excludingID: UUID,
        ownerAccountID: Int64,
        context: NSManagedObjectContext
    ) throws {
        let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.scenarioBinding)
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Self.ownerPredicate(ownerAccountID),
            NSPredicate(format: "\(Field.scenario) == %@", scenario),
            NSPredicate(format: "\(Field.isDefault) == YES"),
            NSPredicate(format: "\(Field.id) != %@", excludingID as CVarArg),
        ])
        for object in try context.fetch(request) {
            object.setValue(false, forKey: Field.isDefault)
            object.setValue(Date(), forKey: Field.updatedAt)
        }
    }

    private static func upsertSmallTask(
        _ task: SmallTask,
        ownerAccountID: Int64,
        context: NSManagedObjectContext
    ) {
        let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.smallTask)
        request.fetchLimit = 1
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Self.ownerPredicate(ownerAccountID),
            NSPredicate(format: "\(Field.code) == %@", task.code),
        ])
        let object = (try? context.fetch(request).first)
            ?? NSEntityDescription.insertNewObject(forEntityName: EntityName.smallTask, into: context)
        object.setValue(Int64(task.id), forKey: Field.id)
        object.setValue(ownerAccountID, forKey: Field.ownerAccountID)
        object.setValue(task.name, forKey: Field.name)
        object.setValue(task.code, forKey: Field.code)
        object.setValue(task.brief, forKey: Field.brief)
        object.setValue(task.prompt, forKey: Field.prompt)
        object.setValue(task.icon, forKey: Field.icon)
        object.setValue(try? Self.encodeStringArray(task.toolList), forKey: Field.toolListData)
        object.setValue(task.source.rawValue, forKey: Field.source)
        object.setValue(Date(), forKey: Field.timestamp)
    }

    private static func upsertPromptRepo(
        _ prompt: PromptRepo,
        position: Int,
        ownerAccountID: Int64,
        context: NSManagedObjectContext
    ) throws {
        let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.promptRepo)
        request.fetchLimit = 1
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Self.ownerPredicate(ownerAccountID),
            NSPredicate(format: "\(Field.id) == %@", prompt.id as CVarArg),
        ])
        let object = try context.fetch(request).first
            ?? NSEntityDescription.insertNewObject(forEntityName: EntityName.promptRepo, into: context)
        object.setValue(prompt.id, forKey: Field.id)
        object.setValue(ownerAccountID, forKey: Field.ownerAccountID)
        object.setValue(prompt.title, forKey: Field.title)
        object.setValue(prompt.content, forKey: Field.content)
        object.setValue(prompt.isSystem, forKey: Field.isSystem)
        object.setValue(Int32(position), forKey: Field.position)
        object.setValue(prompt.timestamp, forKey: Field.timestamp)
        object.setValue(prompt.localizationKey, forKey: Field.localizationKey)
    }

    /// 记录该账号已完成种子初始化；`catalogVersion` 仅为当前 bundle 种子版本快照，不用于触发重灌。
    private static func upsertSeedState(ownerAccountID: Int64, context: NSManagedObjectContext) throws {
        let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.seedState)
        request.fetchLimit = 1
        request.predicate = Self.ownerPredicate(ownerAccountID)
        let object = try context.fetch(request).first
            ?? NSEntityDescription.insertNewObject(forEntityName: EntityName.seedState, into: context)
        object.setValue(ownerAccountID, forKey: Field.ownerAccountID)
        object.setValue(Int32(AISettingsSeedCatalog.version), forKey: Field.catalogVersion)
        object.setValue(Date(), forKey: Field.updatedAt)
    }

    /// 从实体组装 `[APIKeys]`（读路径与 `replaceProviders` 对称）。
    private static func fetchProviders(
        ownerAccountID: Int64,
        context: NSManagedObjectContext
    ) throws -> [APIKeys] {
        let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.provider)
        request.predicate = Self.ownerPredicate(ownerAccountID)
        request.sortDescriptors = [
            NSSortDescriptor(key: Field.company, ascending: true),
            NSSortDescriptor(key: Field.name, ascending: true),
        ]

        return try context.fetch(request).map { object in
            APIKeys(
                id: object.value(forKey: Field.id) as? UUID ?? UUID(),
                providerID: object.value(forKey: Field.providerID) as? String,
                name: object.value(forKey: Field.name) as? String ?? "",
                company: object.value(forKey: Field.company) as? String ?? "",
                key: object.value(forKey: Field.key) as? String ?? "",
                requestURL: object.value(forKey: Field.requestURL) as? String ?? "",
                help: object.value(forKey: Field.help) as? String ?? "",
                from: object.value(forKey: Field.from) as? String ?? AIRecordSource.system.rawValue,
                privacyPolicyURL: object.value(forKey: Field.privacyPolicyURL) as? String ?? "",
                isEnabled: object.value(forKey: Field.isEnabled) as? Bool ?? true,
                source: AIRecordSource(rawValue: object.value(forKey: Field.source) as? String ?? "") ?? .system,
                privacyPolicyAccepted: object.value(forKey: Field.privacyPolicyAccepted) as? Bool ?? false,
                privacyPolicyAcceptedAt: object.value(forKey: Field.privacyPolicyAcceptedAt) as? Date,
                timestamp: object.value(forKey: Field.timestamp) as? Date ?? Date()
            )
        }
    }

    /// 从实体组装 `[SearchKeys]`（读路径与 `replaceSearchKeys` 对称）。
    private static func fetchSearchKeys(
        ownerAccountID: Int64,
        context: NSManagedObjectContext
    ) throws -> [SearchKeys] {
        let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.searchProvider)
        request.predicate = Self.ownerPredicate(ownerAccountID)
        request.sortDescriptors = [
            NSSortDescriptor(key: Field.priority, ascending: false),
            NSSortDescriptor(key: Field.company, ascending: true),
            NSSortDescriptor(key: Field.name, ascending: true),
        ]

        return try context.fetch(request).map { object in
            let enabledScopes = try Self.decodeStringArray(object.value(forKey: Field.enabledScopesData) as? Data)
            return SearchKeys(
                id: object.value(forKey: Field.id) as? UUID ?? UUID(),
                name: object.value(forKey: Field.name) as? String ?? "",
                company: object.value(forKey: Field.company) as? String ?? "",
                key: object.value(forKey: Field.key) as? String ?? "",
                requestURL: object.value(forKey: Field.requestURL) as? String ?? "",
                isUsing: object.value(forKey: Field.isUsing) as? Bool ?? false,
                searchClass: object.value(forKey: Field.searchClass) as? String ?? "web",
                help: object.value(forKey: Field.help) as? String ?? "",
                source: AIRecordSource(rawValue: object.value(forKey: Field.source) as? String ?? "") ?? .system,
                timestamp: object.value(forKey: Field.timestamp) as? Date ?? Date(),
                authType: SearchProviderAuthType(rawValue: object.value(forKey: Field.authType) as? String ?? "") ?? .bearer,
                priority: Int(object.value(forKey: Field.priority) as? Int32 ?? 0),
                enabledScopes: enabledScopes.isEmpty ? ["chat", "small_task"] : enabledScopes,
                revision: Int(object.value(forKey: Field.revision) as? Int32 ?? 1)
            )
        }
    }

    /// 从实体组装 `[AllModels]`（读路径与 `replaceModels` 对称）。
    private static func fetchModels(
        ownerAccountID: Int64,
        context: NSManagedObjectContext
    ) throws -> [AllModels] {
        let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.model)
        request.predicate = Self.ownerPredicate(ownerAccountID)
        request.sortDescriptors = [
            NSSortDescriptor(key: Field.position, ascending: true),
            NSSortDescriptor(key: Field.displayName, ascending: true),
        ]

        return try context.fetch(request).map { object in
            AllModels(
                id: object.value(forKey: Field.id) as? UUID ?? UUID(),
                name: object.value(forKey: Field.name) as? String ?? "",
                displayName: object.value(forKey: Field.displayName) as? String ?? "",
                identity: AIModelIdentity(rawValue: object.value(forKey: Field.identity) as? String ?? "") ?? .model,
                position: Int(object.value(forKey: Field.position) as? Int32 ?? 0),
                providerID: object.value(forKey: Field.providerID) as? String,
                company: object.value(forKey: Field.company) as? String ?? "",
                price: Int(object.value(forKey: Field.price) as? Int32 ?? 0),
                isEnabled: object.value(forKey: Field.isEnabled) as? Bool ?? true,
                supportsSearch: object.value(forKey: Field.supportsSearch) as? Bool ?? false,
                supportsTextGen: object.value(forKey: Field.supportsTextGen) as? Bool ?? true,
                supportsMultimodal: object.value(forKey: Field.supportsMultimodal) as? Bool ?? false,
                supportsReasoning: object.value(forKey: Field.supportsReasoning) as? Bool ?? false,
                supportReasoningChange: object.value(forKey: Field.supportReasoningChange) as? Bool ?? false,
                supportsImageGen: object.value(forKey: Field.supportsImageGen) as? Bool ?? false,
                supportsVoiceGen: object.value(forKey: Field.supportsVoiceGen) as? Bool ?? false,
                supportsToolUse: object.value(forKey: Field.supportsToolUse) as? Bool ?? false,
                systemProvision: object.value(forKey: Field.systemProvision) as? String ?? "",
                icon: object.value(forKey: Field.icon) as? String ?? "",
                briefDescription: object.value(forKey: Field.briefDescription) as? String ?? "",
                characterDesign: object.value(forKey: Field.characterDesign) as? String ?? "",
                aiToolScenarios: try Self.decodeStringArray(object.value(forKey: Field.aiToolScenariosData) as? Data),
                relatedTaskCodes: try Self.decodeStringArray(object.value(forKey: Field.relatedTaskCodesData) as? Data),
                baseModelName: object.value(forKey: Field.baseModelName) as? String,
                localFilename: object.value(forKey: Field.localFilename) as? String,
                source: AIRecordSource(rawValue: object.value(forKey: Field.source) as? String ?? "") ?? .system,
                timestamp: object.value(forKey: Field.timestamp) as? Date ?? Date()
            )
        }
    }

    private static func fetchScenarioBindings(
        ownerAccountID: Int64,
        context: NSManagedObjectContext
    ) throws -> [AIScenarioModelBinding] {
        let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.scenarioBinding)
        request.predicate = Self.ownerPredicate(ownerAccountID)
        request.sortDescriptors = [
            NSSortDescriptor(key: Field.scenario, ascending: true),
            NSSortDescriptor(key: Field.position, ascending: true),
            NSSortDescriptor(key: Field.createdAt, ascending: true),
        ]

        return try context.fetch(request).map { object in
            AIScenarioModelBinding(
                id: object.value(forKey: Field.id) as? UUID ?? UUID(),
                ownerAccountID: object.value(forKey: Field.ownerAccountID) as? Int64 ?? ownerAccountID,
                scenario: object.value(forKey: Field.scenario) as? String ?? AIScenario.chat.rawValue,
                identity: AIModelIdentity(rawValue: object.value(forKey: Field.identity) as? String ?? "") ?? .model,
                modelID: object.value(forKey: Field.modelID) as? UUID ?? UUID(),
                temperature: object.value(forKey: Field.temperature) as? Double ?? AIScenarioModelBinding.defaultTemperature,
                maxTokens: Int(object.value(forKey: Field.maxTokens) as? Int32 ?? Int32(AIScenarioModelBinding.defaultMaxTokens)),
                position: Int(object.value(forKey: Field.position) as? Int32 ?? 0),
                isDefault: object.value(forKey: Field.isDefault) as? Bool ?? false,
                isActive: object.value(forKey: Field.isActive) as? Bool ?? true,
                systemProvision: object.value(forKey: Field.systemProvision) as? String ?? "",
                briefDescription: object.value(forKey: Field.briefDescription) as? String ?? "",
                aiToolScenarios: try Self.decodeStringArray(object.value(forKey: Field.aiToolScenariosData) as? Data),
                relatedTaskCodes: try Self.decodeStringArray(object.value(forKey: Field.relatedTaskCodesData) as? Data),
                createdAt: object.value(forKey: Field.createdAt) as? Date ?? Date(),
                updatedAt: object.value(forKey: Field.updatedAt) as? Date ?? Date()
            )
        }
    }

    private static func fetchSmallTasks(
        ownerAccountID: Int64,
        context: NSManagedObjectContext
    ) throws -> [SmallTask] {
        let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.smallTask)
        request.predicate = Self.ownerPredicate(ownerAccountID)
        request.sortDescriptors = [NSSortDescriptor(key: Field.code, ascending: true)]
        return try context.fetch(request).compactMap { object in
            let code = object.value(forKey: Field.code) as? String ?? ""
            guard code.isEmpty == false else { return nil }
            return SmallTask(
                id: Int(object.value(forKey: Field.id) as? Int64 ?? 0),
                name: object.value(forKey: Field.name) as? String ?? "",
                code: code,
                brief: object.value(forKey: Field.brief) as? String ?? "",
                prompt: object.value(forKey: Field.prompt) as? String ?? "",
                icon: object.value(forKey: Field.icon) as? String ?? "",
                toolList: (try? Self.decodeStringArray(object.value(forKey: Field.toolListData) as? Data)) ?? [],
                source: TaskSource(rawValue: object.value(forKey: Field.source) as? String ?? "") ?? .local
            )
        }
    }

    private static func fetchPromptRepo(
        ownerAccountID: Int64,
        context: NSManagedObjectContext
    ) throws -> [PromptRepo] {
        let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.promptRepo)
        request.predicate = Self.ownerPredicate(ownerAccountID)
        request.sortDescriptors = [
            NSSortDescriptor(key: Field.position, ascending: true),
            NSSortDescriptor(key: Field.timestamp, ascending: false),
        ]
        return try context.fetch(request).map { object in
            PromptRepo(
                id: object.value(forKey: Field.id) as? UUID ?? UUID(),
                title: object.value(forKey: Field.title) as? String ?? "",
                content: object.value(forKey: Field.content) as? String ?? "",
                isSystem: object.value(forKey: Field.isSystem) as? Bool ?? true,
                timestamp: object.value(forKey: Field.timestamp) as? Date ?? Date(),
                localizationKey: object.value(forKey: Field.localizationKey) as? String
            )
        }
    }

    private static func deleteObjectsMissingFromSnapshot(
        entityName: String,
        desiredIDs: Set<UUID>,
        ownerAccountID: Int64,
        context: NSManagedObjectContext
    ) throws {
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        request.predicate = Self.ownerPredicate(ownerAccountID)
        for object in try context.fetch(request) {
            guard let id = object.value(forKey: Field.id) as? UUID else {
                context.delete(object)
                continue
            }
            if desiredIDs.contains(id) == false {
                context.delete(object)
            }
        }
    }

    private static func ownerPredicate(_ ownerAccountID: Int64) -> NSPredicate {
        NSPredicate(format: "\(Field.ownerAccountID) == %lld", ownerAccountID)
    }

    private static func encodeStringArray(_ value: [String]) throws -> Data {
        try JSONEncoder.default.encode(value)
    }

    private static func decodeStringArray(_ data: Data?) throws -> [String] {
        guard let data else { return [] }
        return try JSONDecoder.default.decode([String].self, from: data)
    }

    private static func normalizedDefaultBindings(
        _ bindings: [AIScenarioModelBinding],
        ownerAccountID: Int64
    ) -> [AIScenarioModelBinding] {
        var seenDefaults: Set<String> = []
        return bindings.map { binding in
            var copy = binding
            copy.ownerAccountID = ownerAccountID
            if copy.isDefault {
                if seenDefaults.contains(copy.scenario) {
                    copy.isDefault = false
                } else {
                    seenDefaults.insert(copy.scenario)
                }
            }
            return copy
        }
    }
}
