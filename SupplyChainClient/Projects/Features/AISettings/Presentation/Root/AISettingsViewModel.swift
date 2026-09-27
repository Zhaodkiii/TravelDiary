import Combine
import Foundation
import UIKit

struct AISettingsMemoryTooling {
    let loadMemoryArchiveUseCase: LoadMemoryArchiveUseCase
    let saveMemoryUseCase: SaveMemoryUseCase
    let updateMemoryUseCase: UpdateMemoryUseCase
    let deleteMemoryUseCase: DeleteMemoryUseCase
    let memoryPreferencesUseCase: MemoryPreferencesUseCase
}

/// AI 设置页面的核心视图模型
/// 负责管理AI配置、模型、厂商密钥的加载、编辑、保存与状态同步
/// 所有UI操作均在主线程执行
@MainActor
final class AISettingsViewModel: ObservableObject {
    // MARK: - 发布属性（UI 绑定）
    /// AI 设置快照（当前编辑中的配置数据）
    @Published var snapshot: AISettingsSnapshot = .default
    /// 是否正在加载数据
    @Published private(set) var isLoading = false
    /// 是否正在保存数据
    @Published private(set) var isSaving = false
    /// 是否存在未保存的修改
    @Published private(set) var hasUnsavedChanges = false
    /// 错误提示信息
    @Published private(set) var errorMessage: String?
    /// 试用功能操作中
    @Published private(set) var trialOperationInFlight = false
    /// 本地与服务合并后的有效小任务列表（local 覆盖 service）
    @Published private(set) var effectiveSmallTasks: [SmallTask] = []

    /// 是否展示 Pro 试用入口：
    /// - 已经是 Pro（trial active）：默认展示入口（用于查看/续期/状态提示等）。
    /// - 非 Pro：仅中国大陆用户展示入口。
    var shouldShowTrialEntry: Bool {
        snapshot.trial.isActive || SupportSystemInfo.shared.isMostLikelyMainlandChina
    }

    // MARK: - 依赖服务
    /// 加载AI设置用例
    private let loadUseCase: LoadAISettingsUseCase
    /// 保存AI设置用例
    private let saveUseCase: SaveAISettingsUseCase
    /// 与 UserSession.accountID 一致时，不依赖会话快照解析顺序即可命中该账号的 Core Data 目录
    private let ownerAccountIDForLoad: Int64?
    private let coreDataStack: CoreDataStack?
    /// AI配置接口服务
    private let aiConfigAPI: SupportAIConfigAPI?
    /// AI配置中心
    private let aiConfigCenter: AIConfigCenter?
    /// Push（通知权限申请、APNs token 注册）
    private let pushAdapter: PushAdapter?
    /// 提示词工具
    let promptTooling: any AISettingsPromptToolingProviding
    /// 记忆档案工具
    private let memoryTooling: AISettingsMemoryTooling?
    /// 本地模型服务
    private let localModelService: LocalModelService
    /// 厂商模型目录服务
    private let providerModelCatalogService: ProviderModelCatalogService
    /// 厂商设置协调器
    private let providerCoordinator: ProviderSettingsCoordinator
    /// 模型目录协调器
    private let modelCoordinator: ModelCatalogCoordinator
    
    // MARK: - 私有属性
    /// 最后一次持久化的快照（用于对比是否有修改）
    private var lastPersistedSnapshot: AISettingsSnapshot = .default
    private var hasLoadedSnapshot = false
    private var cachedMemoryArchiveViewModel: MemoryArchiveSettingsViewModel?
    /// 订阅者集合
    private var cancellables: Set<AnyCancellable> = []

    // MARK: - 视图创建
    /// 创建场景模型偏好设置视图模型
    func makeScenarioModelPreferencesViewModel() -> ScenarioModelPreferencesViewModel {
        ScenarioModelPreferencesViewModel(aiConfigCenter: aiConfigCenter)
    }

    func makeMemoryArchiveSettingsViewModel() -> MemoryArchiveSettingsViewModel {
        if let cachedMemoryArchiveViewModel {
            return cachedMemoryArchiveViewModel
        }
        let fallbackRepository: any MemoryRepository
        if let ownerAccountIDForLoad, let coreDataStack {
            fallbackRepository = CoreDataMemoryRepository(
                coreDataStack: coreDataStack,
                ownerAccountID: ownerAccountIDForLoad
            )
        } else {
            fallbackRepository = InMemoryMemoryRepository()
        }
        let tooling = memoryTooling ?? AISettingsMemoryTooling(
            loadMemoryArchiveUseCase: LoadMemoryArchiveUseCase(repository: fallbackRepository),
            saveMemoryUseCase: SaveMemoryUseCase(repository: fallbackRepository),
            updateMemoryUseCase: UpdateMemoryUseCase(repository: fallbackRepository),
            deleteMemoryUseCase: DeleteMemoryUseCase(repository: fallbackRepository),
            memoryPreferencesUseCase: MemoryPreferencesUseCase(repository: fallbackRepository)
        )
        let created = MemoryArchiveSettingsViewModel(
            loadUseCase: tooling.loadMemoryArchiveUseCase,
            saveUseCase: tooling.saveMemoryUseCase,
            updateUseCase: tooling.updateMemoryUseCase,
            deleteUseCase: tooling.deleteMemoryUseCase,
            preferencesUseCase: tooling.memoryPreferencesUseCase
        )
        cachedMemoryArchiveViewModel = created
        return created
    }

    // MARK: - 初始化
    init(
        loadUseCase: LoadAISettingsUseCase,
        saveUseCase: SaveAISettingsUseCase,
        localModelService: LocalModelService = LocalModelService(),
        providerModelCatalogService: ProviderModelCatalogService = ProviderModelCatalogService(),
        providerCoordinator: ProviderSettingsCoordinator = ProviderSettingsCoordinator(),
        modelCoordinator: ModelCatalogCoordinator = ModelCatalogCoordinator(),
        ownerAccountIDForLoad: Int64? = nil,
        coreDataStack: CoreDataStack? = nil,
        aiConfigAPI: SupportAIConfigAPI? = nil,
        aiConfigCenter: AIConfigCenter? = nil,
        pushAdapter: PushAdapter? = nil,
        promptTooling: any AISettingsPromptToolingProviding = UnavailableAISettingsPromptTooling(),
        memoryTooling: AISettingsMemoryTooling? = nil
    ) {
        self.loadUseCase = loadUseCase
        self.saveUseCase = saveUseCase
        self.ownerAccountIDForLoad = ownerAccountIDForLoad
        self.coreDataStack = coreDataStack
        self.localModelService = localModelService
        self.providerModelCatalogService = providerModelCatalogService
        self.providerCoordinator = providerCoordinator
        self.modelCoordinator = modelCoordinator
        self.aiConfigAPI = aiConfigAPI
        self.aiConfigCenter = aiConfigCenter
        self.pushAdapter = pushAdapter
        self.promptTooling = promptTooling
        self.memoryTooling = memoryTooling
        // 绑定快照变化监听
        bindSnapshotChanges()

        NotificationCenter.default.addObserver(
            forName: .aiTrialApplicationResultReceived,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { await self.refreshProviderRuntimeConfiguration() }
        }
    }

    // MARK: - 数据加载与保存
    /// 加载AI设置数据
    func load() async {
        isLoading = true
        errorMessage = nil
        // 方法结束时自动结束加载状态
        defer { isLoading = false }
        
        let loaded: AISettingsSnapshot
        if let aiConfigCenter {
            // 优先从配置中心加载
            loaded = await aiConfigCenter.currentSnapshot(ownerAccountID: ownerAccountIDForLoad)
        } else {
            // 使用用例加载
            loaded = await loadUseCase.execute(ownerAccountID: ownerAccountIDForLoad)
        }
        
        // 更新本地快照与UI
        lastPersistedSnapshot = loaded
        snapshot = loaded
        hasLoadedSnapshot = true
        hasUnsavedChanges = false
        await refreshEffectiveSmallTasks()
    }

    /// 直接进入子设置页时，先确保账号级配置已从仓储/运行时载入。
    func loadIfNeeded() async {
        guard hasLoadedSnapshot == false else { return }
        await load()
    }

    /// 保存所有修改的设置
    func save() async {
        // 无修改则直接返回
        guard hasUnsavedChanges else { return }
        
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            snapshot.refreshSearchConfigRevision(previous: lastPersistedSnapshot)
            // 执行持久化保存
            try await performPersistToRepository()
            // 更新最后保存的快照
            lastPersistedSnapshot = snapshot
            hasUnsavedChanges = false
            // 重建运行时缓存
            await aiConfigCenter?.rebuildRuntimeCache(from: snapshot)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 厂商密钥编辑 Sheet 点「保存」后立即落盘（不等设置页工具栏「保存」）
    func persistSnapshotNow() async {
        await persistSnapshotNowReturningBool()
    }

    /// 执行数据持久化到仓库
    private func performPersistToRepository() async throws {
        try await saveUseCase.execute(snapshot: snapshot, ownerAccountID: ownerAccountIDForLoad)
    }

    /// 清除错误信息
    func clearError() {
        errorMessage = nil
    }

    // MARK: - 试用功能
    /// 刷新试用状态
    func refreshTrialStatus() async {
        guard let aiConfigAPI else { return }
        await loadIfNeeded()
        
        trialOperationInFlight = true
        defer { trialOperationInFlight = false }
        
        do {
            let state = try await aiConfigAPI.fetchTrialStatus()
            // 状态变化则更新快照
            if snapshot.trial != state {
                snapshot.trial = state
                _ = await persistSnapshotNowReturningBool()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 重新拉取 Pro 配置与本地持久化模型配置，并刷新试用状态。
    func refreshProviderRuntimeConfiguration() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        await aiConfigCenter?.refreshRemoteConfig()

        let loaded: AISettingsSnapshot
        if let aiConfigCenter {
            loaded = await aiConfigCenter.reloadLocalSnapshot(ownerAccountID: ownerAccountIDForLoad)
        } else {
            loaded = await loadUseCase.execute(ownerAccountID: ownerAccountIDForLoad)
        }
        lastPersistedSnapshot = loaded
        snapshot = loaded
        hasLoadedSnapshot = true
        hasUnsavedChanges = false
        await refreshEffectiveSmallTasks()
        await refreshTrialStatus()
    }

    /// 提交试用申请
    /// - Parameter note: 申请备注
    /// - Returns: 是否申请成功
    @discardableResult
    func submitTrialApplication(note: String = "") async -> Bool {
        guard let aiConfigAPI else { return false }
        
        trialOperationInFlight = true
        defer { trialOperationInFlight = false }
        
        do {
            let submission = try await aiConfigAPI.applyTrial(note: note)
            // 提交接口不返回最终审核结果：客户端仅更新为 pending 并等待通知刷新。
            snapshot.trial.status = submission.status
            snapshot.trial.isActive = false
            _ = await persistSnapshotNowReturningBool()
            await requestRemoteNotificationPermissionIfNeededAfterTrialSubmission()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// 提交成功后：若通知权限尚未决定，直接请求系统通知权限与 APNs 注册。
    private func requestRemoteNotificationPermissionIfNeededAfterTrialSubmission() async {
        _ = await pushAdapter?.requestAuthorizationIfNotDetermined()
    }

    // MARK: - 厂商连接测试
    /// 测试厂商API连接是否可用
    /// - Parameters:
    ///   - requestURL: 请求地址
    ///   - apiKey: API密钥
    ///   - model: 模型名称
    /// - Returns: 连接测试结果
    func testProviderConnection(requestURL: String, apiKey: String, model: String) async -> ProviderConnectionTestResult {
        guard let aiConfigAPI else {
            return ProviderConnectionTestResult(reachable: false, message: nil)
        }
        
        do {
            return try await aiConfigAPI.testProviderConnection(
                requestURL: requestURL,
                apiKey: apiKey,
                model: model
            )
        } catch {
            errorMessage = error.localizedDescription
            return ProviderConnectionTestResult(reachable: false, message: error.localizedDescription)
        }
    }

    // MARK: - 远程/本地模型管理
    /// 获取指定厂商的远程模型列表
    func fetchRemoteModels(for provider: APIKeys) async throws -> [ProviderRemoteModel] {
        try await providerModelCatalogService.fetchModels(for: provider)
    }

    /// 获取本地模型目录
    func localModelCatalog() -> [LocalModelCatalogItem] {
        localModelService.builtInCatalog()
    }

    /// 安装内置本地模型
    func installLocalModel(item: LocalModelCatalogItem) async throws {
        let installed = try await localModelService.downloadModel(item)
        upsertLocalBaseModel(installed)
    }

    /// 从文件导入本地模型
    func importLocalModel(from fileURL: URL, preferredDisplayName: String? = nil) async throws {
        let installed = try await localModelService.importModel(from: fileURL, preferredDisplayName: preferredDisplayName)
        upsertLocalBaseModel(installed)
    }

    // MARK: - 自定义模型添加
    /// 与 Health「添加在线模型」一致：写入唯一 name 后追加到目录
    func appendOnlineModel(
        name: String,
        displayName: String,
        providerID: String? = nil,
        company: String,
        priceTier: Int,
        isHidden: Bool,
        supportsText: Bool,
        supportsMultimodal: Bool,
        supportsReasoning: Bool,
        reasoningControllable: Bool,
        supportsToolUse: Bool,
        supportsImageGen: Bool,
        aiScenarios: [String] = [],
        aiToolScenarios: [String] = [],
        modelID: UUID = UUID(),
        scenarioBindings: [AIScenarioModelBinding]? = nil
    ) -> AllModels? {
        // 数据清洗与格式处理
        let baseName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseDisplay = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let co = company.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedProviderID = AIProviderIdentifier.normalize(providerID ?? co)
        
        // 基础参数校验
        guard !baseName.isEmpty, !baseDisplay.isEmpty, !co.isEmpty else { return nil }
        
        // 生成唯一名称，避免重复
        var uniqueName = baseName
        if snapshot.allModels.contains(where: { $0.name == uniqueName }) {
            uniqueName = baseName + "_" + UUID().uuidString.prefix(8).lowercased()
        }
        
        // 生成唯一显示名称
        var uniqueDisplay = baseDisplay
        if snapshot.allModels.contains(where: {
            $0.displayName == uniqueDisplay && $0.providerID == resolvedProviderID
        }) {
            uniqueDisplay = baseDisplay + " (\(UUID().uuidString.prefix(4)))"
        }
        
        // 计算模型排序位置
        let position = (snapshot.allModels.map(\.position).max() ?? 0) + 1
        // 价格等级限制在0-3之间
        let tier = min(max(priceTier, 0), 3)
        // 工具场景默认值
        let normalizedToolScenarios = aiToolScenarios.isEmpty ? SparkToolName.all : aiToolScenarios
        
        // 创建模型对象
        let model = AllModels(
            id: modelID,
            name: uniqueName,
            displayName: uniqueDisplay,
            identity: .model,
            position: position,
            providerID: resolvedProviderID,
            company: co,
            isHidden: isHidden,
            supportsSearch: true,
            supportsMultimodal: supportsMultimodal,
            supportsReasoning: supportsReasoning,
            supportsToolUse: supportsToolUse,
            supportsVoiceGen: false,
            supportsImageGen: supportsImageGen,
            source: .custom,
            timestamp: Date(),
            priceTier: tier,
            supportsText: supportsText,
            reasoningControllable: reasoningControllable,
            aiToolScenarios: normalizedToolScenarios
        )
        
        snapshot.allModels.append(model)
        if let scenarioBindings {
            appendPreparedScenarioBindings(scenarioBindings, for: model)
        } else {
            appendScenarioBindings(for: model, scenarios: aiScenarios, aiToolScenarios: normalizedToolScenarios)
        }
        return model
    }

    /// 添加或显示远程模型
    @discardableResult
    func appendOrRevealRemoteModel(_ remoteModel: ProviderRemoteModel, provider: APIKeys) -> Bool {
        let company = provider.company.trimmingCharacters(in: .whitespacesAndNewlines)
        let providerID = provider.providerID
        
        guard !company.isEmpty, !providerID.isEmpty else { return false }

        // 标准化模型key
        let incomingKey = normalizedRemoteModelKey(remoteModel.name)
        // 查找已存在的模型
        if let index = snapshot.allModels.firstIndex(where: {
            $0.identity == .model &&
            $0.providerID == providerID &&
            normalizedRemoteModelKey($0.name) == incomingKey
        }) {
            // 更新已有模型信息并显示
            snapshot.allModels[index].displayName = remoteModel.displayName
            snapshot.allModels[index].isHidden = false
            snapshot.allModels[index].timestamp = Date()
            return false
        }

        // 新增远程模型
        _ = appendOnlineModel(
            name: remoteModel.name,
            displayName: remoteModel.displayName,
            providerID: providerID,
            company: company,
            priceTier: inferredPriceTier(for: remoteModel),
            isHidden: false,
            supportsText: remoteModel.supportsText,
            supportsMultimodal: remoteModel.supportsMultimodal,
            supportsReasoning: remoteModel.supportsReasoning,
            reasoningControllable: remoteModel.supportsReasoning,
            supportsToolUse: remoteModel.supportsToolUse,
            supportsImageGen: remoteModel.supportsImageGen
        )
        return true
    }

    /// 删除模型并持久化
    @discardableResult
    func deleteModelAndPersist(id: UUID) async -> Bool {
        do {
            try modelCoordinator.deleteModel(id: id, in: &snapshot)
            snapshot.scenarioBindings.removeAll { $0.modelID == id }
            return await persistSnapshotNowReturningBool()
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// 替换目录中一条模型（触发 snapshot 更新）
    func replaceModel(_ model: AllModels) {
        guard let idx = snapshot.allModels.firstIndex(where: { $0.id == model.id }) else { return }
        snapshot.allModels[idx] = model
    }

    /// 替换整个模型列表
    func replaceAllModels(_ models: [AllModels]) {
        snapshot.allModels = models
    }

    /// 更新模型排序位置
    func updateModelPositions(_ positions: [UUID: Int]) {
        for index in snapshot.allModels.indices {
            guard let position = positions[snapshot.allModels[index].id] else { continue }
            snapshot.allModels[index].position = position
        }
    }

    // MARK: - 厂商管理
    /// 新增或更新厂商配置
    func upsertProvider(_ provider: APIKeys) {
        if let idx = snapshot.apiKeys.firstIndex(where: { $0.id == provider.id }) {
            snapshot.apiKeys[idx] = provider
        } else {
            snapshot.apiKeys.append(provider)
        }
    }

    /// 添加厂商并立即持久化
    @discardableResult
    func addProviderAndPersist(_ provider: APIKeys) async -> Bool {
        providerCoordinator.appendProvider(provider, in: &snapshot)
        return await persistSnapshotNowReturningBool()
    }

    /// 设置厂商启用状态并持久化
    @discardableResult
    func setProviderEnabledAndPersist(providerID: UUID, enabled: Bool) async -> Bool {
        do {
            _ = try providerCoordinator.setProviderEnabled(recordID: providerID, enabled: enabled, in: &snapshot)
            return await persistSnapshotNowReturningBool()
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// 从编辑器保存厂商配置并持久化
    @discardableResult
    func saveProviderFromEditorAndPersist(_ provider: APIKeys) async -> Bool {
        _ = providerCoordinator.saveProviderFromEditor(provider, in: &snapshot)
        return await persistSnapshotNowReturningBool()
    }

    /// 编辑器内启停厂商：先写入当前编辑字段，再应用启停逻辑（禁用时同步关闭旗下模型）并持久化。
    @discardableResult
    func setProviderEnabledFromEditorAndPersist(_ provider: APIKeys, enabled: Bool) async -> Bool {
        _ = providerCoordinator.saveProviderFromEditor(provider, in: &snapshot)
        do {
            _ = try providerCoordinator.setProviderEnabled(recordID: provider.id, enabled: enabled, in: &snapshot)
            return await persistSnapshotNowReturningBool()
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - 提示词库单独持久化
    /// 设置页提示词库新增、删除、排序、编辑后立即同步数据库与运行时缓存。
    @discardableResult
    func persistPromptRepoNow() async -> Bool {
        await persistPromptRepoNowReturningBool()
    }

    // MARK: - 搜索工具持久化
    /// 搜索偏好变更后立即持久化到账号级偏好载荷，并刷新运行时搜索配置版本。
    @discardableResult
    func updateSearchToolPreferencesAndPersist(_ preferences: AISearchToolPreferences) async -> Bool {
        snapshot.searchToolPreferences = preferences
        snapshot.refreshSearchConfigRevision(previous: lastPersistedSnapshot)
        return await persistSearchToolPreferencesNowReturningBool()
    }

    /// 搜索厂商编辑器保存后立即按单条 upsert 到数据库。
    @discardableResult
    func upsertSearchKeyAndPersist(_ searchKey: SearchKeys) async -> Bool {
        var changedIDs: Set<UUID> = [searchKey.id]
        if searchKey.isUsing {
            for index in snapshot.searchKeys.indices where snapshot.searchKeys[index].id != searchKey.id && snapshot.searchKeys[index].isUsing {
                snapshot.searchKeys[index].isUsing = false
                snapshot.searchKeys[index].timestamp = Date()
                snapshot.searchKeys[index].revision += 1
                changedIDs.insert(snapshot.searchKeys[index].id)
            }
        }

        if let index = snapshot.searchKeys.firstIndex(where: { $0.id == searchKey.id }) {
            snapshot.searchKeys[index] = searchKey
        } else {
            snapshot.searchKeys.append(searchKey)
        }
        snapshot.refreshSearchConfigRevision(previous: lastPersistedSnapshot)
        return await persistSearchKeysNowReturningBool(ids: changedIDs)
    }

    /// 搜索厂商启停后立即按变更行写入数据库。
    @discardableResult
    func setSearchProviderEnabledAndPersist(id: UUID, enabled: Bool) async -> Bool {
        guard let selectedIndex = snapshot.searchKeys.firstIndex(where: { $0.id == id }) else { return false }

        var changedIDs: Set<UUID> = [id]
        for index in snapshot.searchKeys.indices {
            if index == selectedIndex {
                snapshot.searchKeys[index].isUsing = enabled
                snapshot.searchKeys[index].timestamp = Date()
                snapshot.searchKeys[index].revision += 1
            } else if enabled, snapshot.searchKeys[index].isUsing {
                snapshot.searchKeys[index].isUsing = false
                snapshot.searchKeys[index].timestamp = Date()
                snapshot.searchKeys[index].revision += 1
                changedIDs.insert(snapshot.searchKeys[index].id)
            }
        }
        snapshot.refreshSearchConfigRevision(previous: lastPersistedSnapshot)
        return await persistSearchKeysNowReturningBool(ids: changedIDs)
    }

    /// 搜索厂商删除后立即从数据库删除对应行。
    @discardableResult
    func deleteSearchKeysAndPersist(ids: [UUID]) async -> Bool {
        guard ids.isEmpty == false else { return true }
        snapshot.searchKeys.removeAll { ids.contains($0.id) }
        snapshot.refreshSearchConfigRevision(previous: lastPersistedSnapshot)
        return await deleteSearchKeysNowReturningBool(ids: ids)
    }

    // MARK: - 模型单条持久化
    /// 保存按钮触发：先改缓存，再单条落库（模型）
    @discardableResult
    func replaceModelAndPersist(_ model: AllModels) async -> Bool {
        replaceModel(model)
        return await persistSnapshotNowReturningBool()
    }

    @discardableResult
    func persistScenarioBindingsNow() async -> Bool {
        await persistSnapshotNowReturningBool()
    }

    @discardableResult
    func persistScenarioBindingChange(_ change: ModelScenarioBindingPersistenceChange) async -> Bool {
        applyScenarioBindingChange(change)
        return await persistScenarioBindingChangeNowReturningBool(change)
    }

    @discardableResult
    func replaceScenarioBindingsAndPersist(
        modelID: UUID,
        identity: AIModelIdentity,
        bindings: [AIScenarioModelBinding]
    ) async -> Bool {
        snapshot.scenarioBindings.removeAll { $0.modelID == modelID && $0.identity == identity }
        for binding in bindings where AIScenario(rawValue: binding.scenario) != nil {
            var copy = binding
            copy.modelID = modelID
            copy.identity = identity
            copy.updatedAt = Date()
            snapshot.scenarioBindings.append(copy)
        }
        return await persistSnapshotNowReturningBool()
    }

    private func applyScenarioBindingChange(_ change: ModelScenarioBindingPersistenceChange) {
        if let deletedID = change.deletedID {
            snapshot.scenarioBindings.removeAll { $0.id == deletedID }
        }
        if let binding = change.upserted, AIScenario(rawValue: binding.scenario) != nil {
            if binding.isDefault {
                for index in snapshot.scenarioBindings.indices where snapshot.scenarioBindings[index].scenario == binding.scenario {
                    guard snapshot.scenarioBindings[index].id != binding.id else { continue }
                    snapshot.scenarioBindings[index].isDefault = false
                    snapshot.scenarioBindings[index].updatedAt = Date()
                }
            }
            if let index = snapshot.scenarioBindings.firstIndex(where: { $0.id == binding.id }) {
                snapshot.scenarioBindings[index] = binding
            } else {
                snapshot.scenarioBindings.append(binding)
            }
        }
    }

    /// 显隐切换：先改缓存，再单条落库（模型）
    @discardableResult
    func setModelVisibilityAndPersist(modelID: UUID, visible: Bool) async -> Bool {
        guard let index = snapshot.allModels.firstIndex(where: { $0.id == modelID }) else { return false }
        var model = snapshot.allModels[index]
        model.isHidden = !visible
        return await replaceModelAndPersist(model)
    }

    /// 保存按钮触发：先改缓存，再单条落库（厂商）
    @discardableResult
    func upsertProviderAndPersist(_ provider: APIKeys) async -> Bool {
        upsertProvider(provider)
        return await persistProviderNow(providerID: provider.id)
    }

    /// 新增模型并单条落库（新增时会是 upsert-insert）
    @discardableResult
    func appendOnlineModelAndPersist(
        name: String,
        displayName: String,
        providerID: String? = nil,
        company: String,
        priceTier: Int,
        isHidden: Bool,
        supportsText: Bool,
        supportsMultimodal: Bool,
        supportsReasoning: Bool,
        reasoningControllable: Bool,
        supportsToolUse: Bool,
        supportsImageGen: Bool,
        aiScenarios: [String] = [],
        aiToolScenarios: [String] = [],
        modelID: UUID = UUID(),
        scenarioBindings: [AIScenarioModelBinding]? = nil
    ) async -> Bool {
        guard let model = appendOnlineModel(
            name: name,
            displayName: displayName,
            providerID: providerID,
            company: company,
            priceTier: priceTier,
            isHidden: isHidden,
            supportsText: supportsText,
            supportsMultimodal: supportsMultimodal,
            supportsReasoning: supportsReasoning,
            reasoningControllable: reasoningControllable,
            supportsToolUse: supportsToolUse,
            supportsImageGen: supportsImageGen,
            aiScenarios: aiScenarios,
            aiToolScenarios: aiToolScenarios,
            modelID: modelID,
            scenarioBindings: scenarioBindings
        ) else {
            return false
        }
        return await persistSnapshotNowReturningBool()
    }

    // MARK: - 本地智能体管理
    /// 更新本地智能体（仅更新内存快照，不持久化）
    func updateLocalAgent(
        id: UUID,
        displayName: String,
        iconSymbol: String,
        baseModelName: String,
        systemPrompt: String,
        aiScenarios: [String] = [],
        aiToolScenarios: [String] = [],
        relatedTaskCodes: [String] = [],
        scenarioBindings: [AIScenarioModelBinding]? = nil
    ) {
        modelCoordinator.updateLocalAgent(
            id: id,
            displayName: displayName,
            iconSymbol: iconSymbol,
            baseModelName: baseModelName,
            systemPrompt: systemPrompt,
            aiScenarios: aiScenarios,
            aiToolScenarios: aiToolScenarios,
            relatedTaskCodes: relatedTaskCodes,
            in: &snapshot
        )
        if let model = snapshot.allModels.first(where: { $0.id == id }) {
            if let scenarioBindings {
                replacePreparedScenarioBindings(scenarioBindings, for: model, relatedTaskCodes: relatedTaskCodes)
            } else {
                replaceScenarioBindings(for: model, scenarios: aiScenarios, aiToolScenarios: aiToolScenarios, relatedTaskCodes: relatedTaskCodes)
            }
        }
    }

    /// 更新本地智能体并立即单条持久化到数据库
    @discardableResult
    func updateLocalAgentAndPersist(
        id: UUID,
        displayName: String,
        iconSymbol: String,
        baseModelName: String,
        systemPrompt: String,
        aiScenarios: [String] = [],
        aiToolScenarios: [String] = [],
        relatedTaskCodes: [String] = [],
        scenarioBindings: [AIScenarioModelBinding]? = nil
    ) async -> Bool {
        modelCoordinator.updateLocalAgent(
            id: id,
            displayName: displayName,
            iconSymbol: iconSymbol,
            baseModelName: baseModelName,
            systemPrompt: systemPrompt,
            aiScenarios: aiScenarios,
            aiToolScenarios: aiToolScenarios,
            relatedTaskCodes: relatedTaskCodes,
            in: &snapshot
        )
        if let model = snapshot.allModels.first(where: { $0.id == id }) {
            if let scenarioBindings {
                replacePreparedScenarioBindings(scenarioBindings, for: model, relatedTaskCodes: relatedTaskCodes)
            } else {
                replaceScenarioBindings(for: model, scenarios: aiScenarios, aiToolScenarios: aiToolScenarios, relatedTaskCodes: relatedTaskCodes)
            }
        }
        return await persistSnapshotNowReturningBool()
    }

    /// 移除本地模型（包含文件删除与配置清理）
    func removeLocalModel(_ model: AllModels) async throws {
        // 无本地文件，直接删除配置
        guard let filename = model.localFilename, !filename.isEmpty else {
            snapshot.allModels.removeAll { $0.id == model.id }
            return
        }
        
        // 删除模型文件
        try await localModelService.deleteModel(fileName: filename)
        // 删除模型配置与关联配置
        snapshot.allModels.removeAll { candidate in
            candidate.id == model.id || candidate.baseModelName == model.name
        }
        
        // 清空使用该模型的场景默认配置
        snapshot.scenarioBindings.removeAll { binding in
            binding.modelID == model.id || snapshot.allModels.contains { $0.id == binding.modelID && $0.baseModelName == model.name }
        }
    }

    /// 移除本地模型并持久化
    @discardableResult
    func removeLocalModelAndPersist(_ model: AllModels) async -> Bool {
        do {
            try await removeLocalModel(model)
            return await persistSnapshotNowReturningBool()
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// 检查模型是否有有效的API密钥
    func hasValidAPIKey(for model: AllModels) -> Bool {
        modelCoordinator.hasValidAPIKey(for: model, in: snapshot)
    }

    /// 创建本地智能体（仅更新内存快照，不持久化）
    func createLocalAgent(
        displayName: String,
        iconSymbol: String,
        baseModelName: String,
        systemPrompt: String,
        aiScenarios: [String] = [],
        aiToolScenarios: [String] = [],
        relatedTaskCodes: [String] = [],
        scenarioBindings: [AIScenarioModelBinding]? = nil
    ) {
        modelCoordinator.createLocalAgent(
            displayName: displayName,
            iconSymbol: iconSymbol,
            baseModelName: baseModelName,
            systemPrompt: systemPrompt,
            aiScenarios: aiScenarios,
            aiToolScenarios: aiToolScenarios,
            relatedTaskCodes: relatedTaskCodes,
            in: &snapshot
        )
        if let agent = snapshot.allModels.last, agent.identity == .agent {
            if let scenarioBindings {
                appendPreparedScenarioBindings(scenarioBindings, for: agent)
            } else {
                appendScenarioBindings(for: agent, scenarios: aiScenarios, aiToolScenarios: aiToolScenarios)
            }
        }
    }

    /// 创建本地智能体并立即单条持久化到数据库
    @discardableResult
    func createLocalAgentAndPersist(
        displayName: String,
        iconSymbol: String,
        baseModelName: String,
        systemPrompt: String,
        aiScenarios: [String] = [],
        aiToolScenarios: [String] = [],
        relatedTaskCodes: [String] = [],
        scenarioBindings: [AIScenarioModelBinding]? = nil
    ) async -> Bool {
        guard let agent = modelCoordinator.createLocalAgent(
            displayName: displayName,
            iconSymbol: iconSymbol,
            baseModelName: baseModelName,
            systemPrompt: systemPrompt,
            aiScenarios: aiScenarios,
            aiToolScenarios: aiToolScenarios,
            relatedTaskCodes: relatedTaskCodes,
            in: &snapshot
        ) else { return false }
        if let scenarioBindings {
            appendPreparedScenarioBindings(scenarioBindings, for: agent)
        } else {
            appendScenarioBindings(for: agent, scenarios: aiScenarios, aiToolScenarios: aiToolScenarios)
        }
        return await persistSnapshotNowReturningBool()
    }

    func upsertLocalSmallTaskAndPersist(_ task: SmallTask) async -> Bool {
        var normalized = task
        normalized.source = .local
        if let index = snapshot.smallTasks.firstIndex(where: { $0.code == normalized.code }) {
            snapshot.smallTasks[index] = normalized
        } else {
            snapshot.smallTasks.append(normalized)
        }
        return await persistSnapshotNowReturningBool()
    }

    func deleteLocalSmallTaskAndPersist(code: String) async -> Bool {
        snapshot.smallTasks.removeAll { $0.code == code && $0.source == .local }
        for index in snapshot.allModels.indices {
            snapshot.allModels[index].relatedTaskCodes.removeAll { $0 == code }
        }
        return await persistSnapshotNowReturningBool()
    }

    func nextLocalSmallTaskID() -> Int {
        (snapshot.smallTasks.filter { $0.source == .local }.map(\.id).max() ?? 0) + 1
    }

    /// 初始化模型可见性（如需要则持久化）
    @discardableResult
    func initializeModelVisibilityAndPersistIfNeeded() async -> Bool {
        guard modelCoordinator.initializeModelVisibility(in: &snapshot) else { return true }
        return await persistSnapshotNowReturningBool()
    }

    // MARK: - 私有工具方法
    /// 新增或更新本地基础模型
    private func upsertLocalBaseModel(_ installed: LocalModelInstalled) {
        let localCompany = LocalModelService.localCompany
        // 查找已存在的本地模型
        if let index = snapshot.allModels.firstIndex(where: {
            $0.localFilename == installed.fileName && $0.identity == .model
        }) {
            // 更新已有模型
            snapshot.allModels[index].displayName = installed.displayName
            snapshot.allModels[index].name = installed.modelName
            snapshot.allModels[index].providerID = LocalModelService.localProviderID
            snapshot.allModels[index].company = localCompany
            snapshot.allModels[index].isHidden = false
            snapshot.allModels[index].source = .custom
            snapshot.allModels[index].timestamp = Date()
            appendScenarioBindings(for: snapshot.allModels[index], scenarios: [AIScenario.chat.rawValue], aiToolScenarios: SparkToolName.all)
            return
        }

        // 新增本地模型
        let position = (snapshot.allModels.map(\.position).max() ?? 0) + 1
        snapshot.allModels.append(
            AllModels(
                name: installed.modelName,
                displayName: installed.displayName,
                identity: .model,
                position: position,
                providerID: LocalModelService.localProviderID,
                company: localCompany,
                isHidden: false,
                supportsSearch: true,
                supportsMultimodal: false,
                supportsReasoning: true,
                supportsToolUse: true,
                supportsVoiceGen: false,
                supportsImageGen: false,
                iconSymbol: "cpu",
                baseModelName: nil,
                localFilename: installed.fileName,
                systemPrompt: nil,
                source: .custom,
                timestamp: Date()
            )
        )
        if let model = snapshot.allModels.last {
            appendScenarioBindings(for: model, scenarios: [AIScenario.chat.rawValue], aiToolScenarios: SparkToolName.all)
        }
    }

    private func appendScenarioBindings(for model: AllModels, scenarios: [String], aiToolScenarios: [String]) {
        let validScenarios = scenarios.compactMap(AIScenario.init(rawValue:)).map(\.rawValue)
        for scenarioRaw in validScenarios {
            guard snapshot.scenarioBindings.contains(where: {
                $0.scenario == scenarioRaw && $0.modelID == model.id && $0.identity == model.identity
            }) == false else { continue }
            let existing = snapshot.scenarioBindings.filter { $0.scenario == scenarioRaw }
            let binding = AIScenarioModelBinding(
                scenario: scenarioRaw,
                identity: model.identity,
                modelID: model.id,
                temperature: AIScenarioModelBinding.defaultTemperature,
                maxTokens: AIScenarioModelBinding.defaultMaxTokens,
                position: (existing.map(\.position).max() ?? -1) + 1,
                isDefault: existing.contains(where: { $0.isDefault }) == false,
                systemProvision: model.systemProvision,
                briefDescription: model.briefDescription,
                aiToolScenarios: aiToolScenarios
            )
            snapshot.scenarioBindings.append(binding)
        }
    }

    private func appendPreparedScenarioBindings(_ bindings: [AIScenarioModelBinding], for model: AllModels) {
        for binding in bindings where AIScenario(rawValue: binding.scenario) != nil {
            guard snapshot.scenarioBindings.contains(where: {
                $0.scenario == binding.scenario && $0.modelID == model.id && $0.identity == model.identity
            }) == false else { continue }
            var copy = binding
            copy.modelID = model.id
            copy.identity = model.identity
            copy.aiToolScenarios = copy.aiToolScenarios.isEmpty ? model.aiToolScenarios : copy.aiToolScenarios
            copy.relatedTaskCodes = copy.relatedTaskCodes.isEmpty ? model.relatedTaskCodes : copy.relatedTaskCodes
            copy.updatedAt = Date()
            snapshot.scenarioBindings.append(copy)
        }
    }

    private func replaceScenarioBindings(
        for model: AllModels,
        scenarios: [String],
        aiToolScenarios: [String],
        relatedTaskCodes: [String]
    ) {
        snapshot.scenarioBindings.removeAll { $0.modelID == model.id && $0.identity == model.identity }
        appendScenarioBindings(for: model, scenarios: scenarios, aiToolScenarios: aiToolScenarios)
        for index in snapshot.scenarioBindings.indices where snapshot.scenarioBindings[index].modelID == model.id {
            snapshot.scenarioBindings[index].relatedTaskCodes = relatedTaskCodes.sorted()
            snapshot.scenarioBindings[index].updatedAt = Date()
        }
    }

    private func replacePreparedScenarioBindings(
        _ bindings: [AIScenarioModelBinding],
        for model: AllModels,
        relatedTaskCodes: [String]
    ) {
        snapshot.scenarioBindings.removeAll { $0.modelID == model.id && $0.identity == model.identity }
        appendPreparedScenarioBindings(bindings, for: model)
        for index in snapshot.scenarioBindings.indices where snapshot.scenarioBindings[index].modelID == model.id {
            if snapshot.scenarioBindings[index].relatedTaskCodes.isEmpty {
                snapshot.scenarioBindings[index].relatedTaskCodes = relatedTaskCodes.sorted()
            }
            snapshot.scenarioBindings[index].updatedAt = Date()
        }
    }

    /// 标准化远程模型key（去除空格、前缀，转小写）
    private func normalizedRemoteModelKey(_ name: String) -> String {
        name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "models/", with: "")
            .lowercased()
    }

    /// 根据模型名称推断价格等级
    private func inferredPriceTier(for model: ProviderRemoteModel) -> Int {
        let name = model.name.lowercased()
        // 图片生成模型为最高等级3
        if model.supportsImageGen {
            return 3
        }
        // 轻量模型等级1
        if name.contains("nano") || name.contains("mini") || name.contains("flash") || name.contains("lite") {
            return 1
        }
        // 高级推理模型等级3
        if name.contains("reasoner") || name.contains("max") || name.contains("opus") || name.contains("pro") {
            return 3
        }
        // 默认等级2
        return 2
    }

    /// 绑定快照变化监听
    private func bindSnapshotChanges() {
        // 监听快照变化，判断是否有未保存修改
        $snapshot
            .dropFirst()
            .sink { [weak self] latest in
                guard let self else { return }
                self.hasUnsavedChanges = latest != self.lastPersistedSnapshot
            }
            .store(in: &cancellables)

        // 快照变化防抖，自动应用草稿配置
        $snapshot
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] latest in
                guard let self else { return }
                Task { await self.aiConfigCenter?.applyDraftSnapshot(latest) }
            }
            .store(in: &cancellables)
    }

    /// 立即持久化快照并返回结果
    @discardableResult
    private func persistSnapshotNowReturningBool() async -> Bool {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        
        do {
            snapshot.refreshSearchConfigRevision(previous: lastPersistedSnapshot)
            try await performPersistToRepository()
            lastPersistedSnapshot = snapshot
            hasUnsavedChanges = false
            await aiConfigCenter?.rebuildRuntimeCache(from: snapshot)
            await refreshEffectiveSmallTasks()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// 单独持久化单个模型
    @discardableResult
    private func persistModelNow(modelID: UUID) async -> Bool {
        guard let model = snapshot.allModels.first(where: { $0.id == modelID }) else { return false }
        
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        
        do {
            try await saveUseCase.execute(model: model)
            markPersistedModel(model)
            hasUnsavedChanges = snapshot != lastPersistedSnapshot
            await aiConfigCenter?.rebuildRuntimeCache(from: snapshot)
            await refreshEffectiveSmallTasks()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// 单独持久化场景绑定变更：只 upsert 当前变更行，并按 id 删除指定行。
    @discardableResult
    private func persistScenarioBindingChangeNowReturningBool(_ change: ModelScenarioBindingPersistenceChange) async -> Bool {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            if let deletedID = change.deletedID {
                try await saveUseCase.executeDeletedScenarioBinding(
                    id: deletedID,
                    ownerAccountID: ownerAccountIDForLoad
                )
            }
            if let binding = change.upserted, AIScenario(rawValue: binding.scenario) != nil {
                try await saveUseCase.execute(
                    scenarioBinding: binding,
                    ownerAccountID: ownerAccountIDForLoad
                )
            }
            markPersistedScenarioBindingChange(change)
            hasUnsavedChanges = snapshot != lastPersistedSnapshot
            await aiConfigCenter?.rebuildRuntimeCache(from: snapshot)
            await refreshEffectiveSmallTasks()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// 单独持久化单个厂商
    @discardableResult
    private func persistProviderNow(providerID: UUID) async -> Bool {
        guard let provider = snapshot.apiKeys.first(where: { $0.id == providerID }) else { return false }
        
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        
        do {
            try await saveUseCase.execute(provider: provider)
            markPersistedProvider(provider)
            hasUnsavedChanges = snapshot != lastPersistedSnapshot
            await aiConfigCenter?.rebuildRuntimeCache(from: snapshot)
            await refreshEffectiveSmallTasks()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    private func persistPromptRepoNowReturningBool() async -> Bool {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            try await saveUseCase.execute(promptRepo: snapshot.promptRepo, ownerAccountID: ownerAccountIDForLoad)
            lastPersistedSnapshot.promptRepo = snapshot.promptRepo
            hasUnsavedChanges = snapshot != lastPersistedSnapshot
            await aiConfigCenter?.rebuildRuntimeCache(from: snapshot)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    private func persistSearchToolPreferencesNowReturningBool() async -> Bool {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            try await saveUseCase.execute(
                searchToolPreferences: snapshot.searchToolPreferences,
                revision: snapshot.searchConfigRevision,
                ownerAccountID: ownerAccountIDForLoad
            )
            lastPersistedSnapshot.searchToolPreferences = snapshot.searchToolPreferences
            lastPersistedSnapshot.searchConfigRevision = snapshot.searchConfigRevision
            hasUnsavedChanges = snapshot != lastPersistedSnapshot
            await aiConfigCenter?.rebuildRuntimeCache(from: snapshot)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    private func persistSearchKeysNowReturningBool(ids: Set<UUID>) async -> Bool {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            for id in ids {
                guard let searchKey = snapshot.searchKeys.first(where: { $0.id == id }) else { continue }
                try await saveUseCase.execute(searchKey: searchKey, ownerAccountID: ownerAccountIDForLoad)
            }
            try await saveUseCase.execute(
                searchToolPreferences: snapshot.searchToolPreferences,
                revision: snapshot.searchConfigRevision,
                searchKeys: snapshot.searchKeys,
                ownerAccountID: ownerAccountIDForLoad
            )
            lastPersistedSnapshot.searchKeys = snapshot.searchKeys
            lastPersistedSnapshot.searchConfigRevision = snapshot.searchConfigRevision
            hasUnsavedChanges = snapshot != lastPersistedSnapshot
            await aiConfigCenter?.rebuildRuntimeCache(from: snapshot)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    private func deleteSearchKeysNowReturningBool(ids: [UUID]) async -> Bool {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            try await saveUseCase.executeDeletedSearchKeys(ids: ids, ownerAccountID: ownerAccountIDForLoad)
            try await saveUseCase.execute(
                searchToolPreferences: snapshot.searchToolPreferences,
                revision: snapshot.searchConfigRevision,
                searchKeys: snapshot.searchKeys,
                ownerAccountID: ownerAccountIDForLoad
            )
            lastPersistedSnapshot.searchKeys = snapshot.searchKeys
            lastPersistedSnapshot.searchConfigRevision = snapshot.searchConfigRevision
            hasUnsavedChanges = snapshot != lastPersistedSnapshot
            await aiConfigCenter?.rebuildRuntimeCache(from: snapshot)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// 标记模型已持久化
    private func markPersistedModel(_ model: AllModels) {
        if let index = lastPersistedSnapshot.allModels.firstIndex(where: { $0.id == model.id }) {
            lastPersistedSnapshot.allModels[index] = model
        } else {
            lastPersistedSnapshot.allModels.append(model)
        }
    }

    /// 标记厂商已持久化
    private func markPersistedProvider(_ provider: APIKeys) {
        if let index = lastPersistedSnapshot.apiKeys.firstIndex(where: { $0.id == provider.id }) {
            lastPersistedSnapshot.apiKeys[index] = provider
        } else {
            lastPersistedSnapshot.apiKeys.append(provider)
        }
    }

    private func markPersistedScenarioBindingChange(_ change: ModelScenarioBindingPersistenceChange) {
        if let deletedID = change.deletedID {
            lastPersistedSnapshot.scenarioBindings.removeAll { $0.id == deletedID }
        }
        if let binding = change.upserted {
            if binding.isDefault {
                for index in lastPersistedSnapshot.scenarioBindings.indices where lastPersistedSnapshot.scenarioBindings[index].scenario == binding.scenario {
                    guard lastPersistedSnapshot.scenarioBindings[index].id != binding.id else { continue }
                    lastPersistedSnapshot.scenarioBindings[index].isDefault = false
                    lastPersistedSnapshot.scenarioBindings[index].updatedAt = Date()
                }
            }
            if let index = lastPersistedSnapshot.scenarioBindings.firstIndex(where: { $0.id == binding.id }) {
                lastPersistedSnapshot.scenarioBindings[index] = binding
            } else {
                lastPersistedSnapshot.scenarioBindings.append(binding)
            }
        }
    }

    /// 从 aiConfigCenter 刷新合并后的有效小任务（local 覆盖 service）；无 center 时退化为本地列表。
    func refreshEffectiveSmallTasks() async {
        if let center = aiConfigCenter {
            effectiveSmallTasks = await center.effectiveSmallTasks()
        } else {
            effectiveSmallTasks = snapshot.smallTasks
        }
    }

    // 国家/区域判断统一收敛到 SupportSystemInfo，避免各模块重复实现。
}
