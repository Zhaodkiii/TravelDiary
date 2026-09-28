import Foundation


nonisolated enum AIRuntimeConfigAssembler {
    /// 按场景合并本地与 Pro bundle：【本地模型绝对优先】
    /// - 若 Pro `models` 为空：保留本地场景包；
    /// - 若 Pro `models` 非空：只保留本地模型 + Pro 里**不重名**的新增模型
    /// - 同名模型：**保留本地，丢弃 Pro 模型**
    static func merge(
        local: AIScenarioRemoteBundlesCollection,
        pro: AIScenarioRemoteBundlesCollection?
    ) -> AIScenarioRemoteBundlesCollection {
        guard let pro else { return local }
        var merged = local
        for scenario in AIScenario.allCases {
            let localBundle = local.bundle(for: scenario)
            let proBundle = pro.bundle(for: scenario)
            let mergedBundle = mergeBundle(local: localBundle, pro: proBundle)
            merged.setBundle(mergedBundle, for: scenario)
        }
        return merged
    }

    /// 合并单个场景包：本地模型优先，**同名 Pro 模型直接丢弃**
    private static func mergeBundle(
        local: AIScenarioRemoteBundle,
        pro: AIScenarioRemoteBundle
    ) -> AIScenarioRemoteBundle {
        // Pro 无模型 → 直接用本地
        guard !pro.models.isEmpty else { return local }

        // 1. 先把所有本地模型放进结果（优先级最高）
        var mergedModels = local.models
        
        // 2. Pro 模型只追加【本地不存在】的，同名直接丢弃
        let localModelNames = Set(local.models.map(\.name))
        for proRow in pro.models {
            // 本地已存在 → 丢弃 Pro 模型
            if localModelNames.contains(proRow.name) {
                continue
            }
            // 本地不存在 → 追加
            mergedModels.append(proRow)
        }

        // 默认模型优先级：本地默认 → Pro 默认 → 第一个模型
        let defaultModelName: String = {
            // 【本地优先】先看本地默认模型
            if !local.defaultModelName.isEmpty,
               mergedModels.contains(where: { $0.name == local.defaultModelName })
            {
                return local.defaultModelName
            }
            // 再看 Pro 默认模型
            if !pro.defaultModelName.isEmpty,
               mergedModels.contains(where: { $0.name == pro.defaultModelName })
            {
                return pro.defaultModelName
            }
            // 兜底
            return mergedModels.first?.name ?? ""
        }()

        // 标记哪个是默认模型
        let normalizedModels = mergedModels.map { row in
            var normalized = row
            normalized.isDefault = normalized.name == defaultModelName
            return normalized
        }
        
        return AIScenarioRemoteBundle(defaultModelName: defaultModelName, models: normalizedModels)
    }
}
