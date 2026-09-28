import Foundation

/// 场景策略解析器：按优先级解析当前场景最终生效的 AI 配置。
/// 优先级：显式首选模型 > 运行时覆盖 > bundle 默认解析链。
/// 场景策略解析器
/// 负责根据场景、远程配置、运行时配置、用户偏好模型，解析出最终要使用的AI模型配置
struct ScenarioPolicyResolver {

    /// 解析AI场景对应的最终执行配置（核心策略方法）
    /// - Parameters:
    ///   - scenario: AI业务场景（如：门诊病历、检查报告、发票等）
    ///   - bundles: 远程下发的AI模型配置集合
    ///   - runtimeStore: 运行时内存存储（用于动态覆盖配置）
    ///   - preferredModelName: 用户偏好指定的模型名称（可选）
    /// - Returns: 最终解析完成的AI执行配置
    /// - Throws: 配置解析失败时抛出异常
    func resolve(
        scenario: AIScenario,
        bundles: AIScenarioRemoteBundlesCollection,
        runtimeStore: AIRuntimeStore,
        preferredModelName: String? = nil
    ) async throws -> AIResolvedConfig {
        // 清理用户偏好模型名称：去除首尾空格和换行
        let trimmedPreferred = preferredModelName?.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 优先级1：如果用户指定了有效模型名称 → 优先使用指定模型
        if let trimmedPreferred, !trimmedPreferred.isEmpty {
            // 从远程配置中查找匹配的模型配置行
            if let row = bundles.resolveRow(for: scenario, preferredModelName: trimmedPreferred) {
                // 转换为最终配置并返回（来源：用户指定）
                return try row.asScenarioConfig().toResolvedConfig(source: row.configSource)
            }
            // 指定模型不存在 → 抛出异常
            throw AIConfigError.missingModelForScenario(scenario)
        }

        // 优先级2：无用户指定模型 → 检查运行时是否有动态覆盖配置
        if let runtimeConfig = await runtimeStore.runtimeOverride(for: scenario) {
            // 使用运行时覆盖配置（来源：运行时覆盖）
            return try runtimeConfig.toResolvedConfig(source: .runtimeOverride)
        }

        // 优先级3：无运行时覆盖 → 使用远程配置的默认模型
        guard let defaultRow = bundles.resolveRow(for: scenario, preferredModelName: nil) else {
            // 默认模型也不存在 → 抛出异常
            throw AIConfigError.missingModelForScenario(scenario)
        }
        
        // 返回默认配置（来源：远程默认配置）
        return try defaultRow.asScenarioConfig().toResolvedConfig(source: defaultRow.configSource)
    }
}
