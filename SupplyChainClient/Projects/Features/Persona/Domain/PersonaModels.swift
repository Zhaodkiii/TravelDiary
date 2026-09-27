import Foundation

/// 本地 Persona 配置，对齐 DeepTutorSerevr `workspace/personas/<name>/PERSONA.md` 语义。
nonisolated struct PersonaProfile: Codable, Equatable, Sendable, Identifiable {
    /// slug 名称，如 `tutor`、`coach`。
    var name: String
    var displayName: String
    var promptBody: String
    var updatedAt: Date

    var id: String { name }

    nonisolated init(
        name: String,
        displayName: String,
        promptBody: String,
        updatedAt: Date = Date()
    ) {
        self.name = name
        self.displayName = displayName
        self.promptBody = promptBody
        self.updatedAt = updatedAt
    }

    /// 渲染为 system prompt 块，对齐服务端 `PersonaService.load_for_context` 输出格式。
    nonisolated func renderedContextBlock() -> String {
        """
        ## Active Persona
        Embody the persona "\(displayName)" (\(name)).

        \(promptBody)
        """
    }
}

enum PersonaRepositoryError: Error, LocalizedError {
    case notFound(String)
    case invalidName

    var errorDescription: String? {
        switch self {
        case .notFound(let name):
            return "未找到 Persona：\(name)"
        case .invalidName:
            return "Persona 名称无效。"
        }
    }
}
