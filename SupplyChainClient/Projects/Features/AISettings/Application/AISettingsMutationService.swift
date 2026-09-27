import Foundation

/// AI 设置模块 - 数据变更错误枚举
/// 所有修改服务商、模型时可能抛出的业务异常
enum AISettingsMutationError: LocalizedError {
    /// 未找到对应的服务商
    case providerNotFound
    /// 启用服务商必须填写 API Key（关联服务商名称）
    case providerKeyRequired(String)
    /// 未找到对应的模型
    case modelNotFound
    /// 系统内置模型不允许删除
    case systemModelCannotBeDeleted

    /// 错误描述（用于界面展示）
    var errorDescription: String? {
        switch self {
        case .providerNotFound, .modelNotFound:
            return L10n.text("common.operation_failed")
        case .providerKeyRequired(let displayName):
            return L10n.format("ai_settings.providers.error.key_required_with_name", displayName)
        case .systemModelCannotBeDeleted:
            return L10n.text("ai_settings.models.alert.cannot_delete_system")
        }
    }
}

// MARK: - 服务商配置协调器
/// 负责处理【服务商】的增、删、改、启用/禁用、隐藏等数据变更
struct ProviderSettingsCoordinator: Sendable {
    /// 添加新的服务商到数据快照
    func appendProvider(_ provider: APIKeys, in snapshot: inout AISettingsSnapshot) {
        snapshot.apiKeys.append(provider)
    }

    /// 设置服务商启用/禁用状态
    /// 禁用时同步隐藏该服务商下所有模型；启用时不批量修改模型状态。
    @discardableResult
    func setProviderEnabled(recordID: UUID, enabled: Bool, in snapshot: inout AISettingsSnapshot) throws -> APIKeys {
        // 查找服务商索引
        guard let index = snapshot.apiKeys.firstIndex(where: { $0.id == recordID }) else {
            throw AISettingsMutationError.providerNotFound
        }
        let provider = snapshot.apiKeys[index]

        // 启用时必须填写 API Key
        if enabled && provider.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw AISettingsMutationError.providerKeyRequired(provider.localizedDisplayName)
        }

        // 更新启用状态与时间戳
        snapshot.apiKeys[index].isHidden = !enabled
        snapshot.apiKeys[index].timestamp = Date()

        if enabled == false {
            setModelsHidden(providerID: provider.providerID, hidden: true, in: &snapshot)
        }
        return snapshot.apiKeys[index]
    }

    /// 从编辑页保存服务商配置（新增/更新）
    /// 仅更新厂商本身，不同步旗下模型的启用/禁用状态。
    @discardableResult
    func saveProviderFromEditor(_ provider: APIKeys, in snapshot: inout AISettingsSnapshot) -> APIKeys {
        var updated = provider
        updated.privacyPolicyAcceptedAt = updated.privacyPolicyAccepted ? Date() : nil
        updated.timestamp = Date()

        if let index = snapshot.apiKeys.firstIndex(where: { $0.id == updated.id }) {
            snapshot.apiKeys[index] = updated
        } else {
            snapshot.apiKeys.append(updated)
        }
        return updated
    }

    /// 批量设置某个服务商下所有模型的隐藏状态
    private func setModelsHidden(providerID: String, hidden: Bool, in snapshot: inout AISettingsSnapshot) {
        for index in snapshot.allModels.indices where snapshot.allModels[index].providerID == providerID {
            snapshot.allModels[index].isHidden = hidden
        }
    }
}

// MARK: - 模型目录协调器
/// 负责处理【模型/智能体】的初始化可见性、删除、创建、更新等数据操作
struct ModelCatalogCoordinator: Sendable {
    /// 初始化模型可见性
    /// 没有有效 API Key 的模型自动隐藏
    @discardableResult
    func initializeModelVisibility(in snapshot: inout AISettingsSnapshot) -> Bool {
        var didChange = false
        for index in snapshot.allModels.indices {
            let model = snapshot.allModels[index]
            // 只处理：未隐藏 + 无有效 API Key 的模型
            guard model.isHidden == false, hasValidAPIKey(for: model, in: snapshot) == false else {
                continue
            }
            snapshot.allModels[index].isHidden = true
            didChange = true
        }
        return didChange
    }

    /// 判断模型对应的服务商是否有**有效 API Key**
    func hasValidAPIKey(for model: AllModels, in snapshot: AISettingsSnapshot) -> Bool {
        // 本地模型（离线）不需要 API Key
        if AIProviderAdapterRegistry.adapter(for: model.providerID).isLocal {
            return true
        }
        // 检查服务商是否启用且 Key 不为空
        return snapshot.apiKeys.contains { key in
            key.providerID == model.providerID &&
            key.isHidden == false &&
            key.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
    }

    /// 删除模型（支持自定义模型，系统模型可放开注释限制）
    func deleteModel(id: UUID, in snapshot: inout AISettingsSnapshot) throws {
        guard let model = snapshot.allModels.first(where: { $0.id == id }) else {
            throw AISettingsMutationError.modelNotFound
        }
        // 系统模型不允许删除（如需启用取消注释）
//        guard model.source != .system else {
//            throw AISettingsMutationError.systemModelCannotBeDeleted
//        }
        snapshot.allModels.removeAll { $0.id == id }
    }

    /// 创建本地自定义智能体（Agent）
    @discardableResult
    func createLocalAgent(
        displayName: String,
        iconSymbol: String,
        baseModelName: String,
        systemPrompt: String,
        aiScenarios: [String] = [],
        aiToolScenarios: [String] = [],
        relatedTaskCodes: [String] = [],
        in snapshot: inout AISettingsSnapshot
    ) -> AllModels? {
        // 查找基础模型
        guard let baseModel = snapshot.allModels.first(where: { $0.name == baseModelName }) else {
            return nil
        }
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedName.isEmpty == false else {
            return nil
        }

        // 智能体排序位置
        let agentPositions = snapshot.allModels.filter { $0.identity == .agent }.map(\.position)
        let position = (agentPositions.max() ?? 999) + 1

        // 生成唯一名称避免冲突
        let uniqueName = "agent-\(UUID().uuidString)"

        // 构建智能体模型
        let agent = AllModels(
            name: uniqueName,
            displayName: trimmedName,
            identity: .agent,
            position: position,
            providerID: baseModel.providerID,
            company: baseModel.company,
            isHidden: false,
            supportsSearch: baseModel.supportsSearch,
            supportsMultimodal: baseModel.supportsMultimodal,
            supportsReasoning: baseModel.supportsReasoning,
            supportsToolUse: baseModel.supportsToolUse,
            supportsVoiceGen: baseModel.supportsVoiceGen,
            supportsImageGen: baseModel.supportsImageGen,
            iconSymbol: iconSymbol,
            baseModelName: baseModel.name,
            localFilename: nil,
            systemPrompt: systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines),
            source: .custom,
            timestamp: Date(),
            priceTier: baseModel.priceTier,
            supportsText: baseModel.supportsText,
            reasoningControllable: baseModel.reasoningControllable,
            aiToolScenarios: aiToolScenarios,
            relatedTaskCodes: relatedTaskCodes
        )

        snapshot.allModels.append(agent)
        return agent
    }

    /// 更新本地自定义智能体
    func updateLocalAgent(
        id: UUID,
        displayName: String,
        iconSymbol: String,
        baseModelName: String,
        systemPrompt: String,
        aiScenarios: [String] = [],
        aiToolScenarios: [String] = [],
        relatedTaskCodes: [String] = [],
        in snapshot: inout AISettingsSnapshot
    ) {
        // 查找智能体
        guard let index = snapshot.allModels.firstIndex(where: { $0.id == id }) else {
            return
        }
        var model = snapshot.allModels[index]

        // 只允许修改自定义智能体
        guard model.identity == .agent, model.source != .system else {
            return
        }

        // 更新基础信息
        model.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        model.iconSymbol = iconSymbol
        model.baseModelName = baseModelName
        model.systemPrompt = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        model.selectedToolNames = Set(aiToolScenarios)
        model.relatedTaskCodes = relatedTaskCodes.sorted()

        // 从基础模型同步能力
        if let base = snapshot.allModels.first(where: { $0.name == baseModelName && $0.identity == .model }) {
            model.providerID = base.providerID
            model.company = base.company
            model.supportsSearch = base.supportsSearch
            model.supportsMultimodal = base.supportsMultimodal
            model.supportsReasoning = base.supportsReasoning
            model.supportsToolUse = base.supportsToolUse
            model.supportsVoiceGen = base.supportsVoiceGen
            model.supportsImageGen = base.supportsImageGen
            model.supportsText = base.supportsText
            model.reasoningControllable = base.reasoningControllable
            model.priceTier = base.priceTier
        }

        snapshot.allModels[index] = model
    }
}
