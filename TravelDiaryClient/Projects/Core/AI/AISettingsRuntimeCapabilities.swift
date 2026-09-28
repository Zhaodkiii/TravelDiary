import Foundation

extension AIScenarioRemoteBundlesCollection {
    /// 输入栏推理能力展示：以场景 bundle 行为准。
    func chatReasoningContext(selectedModelName: String?) -> ChatModelReasoningContext {
        let preferred = selectedModelName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        guard let row = resolveRow(for: .chat, preferredModelName: preferred) else {
            return .unknown
        }
        return ChatModelReasoningContext(
            providerCompany: row.providerID,
            supportsReasoning: row.supportsReasoning,
            reasoningControllable: row.reasoningControllable
        )
    }

    /// 对话多模态及厂商（用于图片送达策略）。
    func chatMultimodalCapabilities(selectedModelName: String?) -> (supportsMultimodal: Bool, providerCompanyUppercased: String?) {
        let preferred = selectedModelName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        guard let row = resolveRow(for: .chat, preferredModelName: preferred) else {
            return (false, nil)
        }
        return (row.supportsMultimodal, row.providerID.isEmpty ? nil : row.providerID)
    }

    /// Support 场景多模态能力（工单分析 / 知识问答等）。
    func supportMultimodalCapabilities(
        for scenario: AIScenario,
        preferredModelName: String?
    ) -> (supportsMultimodal: Bool, modelName: String?) {
        let preferred = preferredModelName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        guard let row = resolveRow(for: scenario, preferredModelName: preferred) else {
            return (false, nil)
        }
        let supportsMultimodal = row.supportsMultimodal && row.localFilename == nil
        return (supportsMultimodal, row.name)
    }
}

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
