import Foundation

/// AI 能力场景枚举，用于配置分流与模型选择。
nonisolated enum AIScenario: String, Codable, CaseIterable, Identifiable, Sendable {
    /// 通用对话场景。
    case chat
    /// 向量模型场景。
    case embedding
    /// 语音模型场景。
    case voice
    /// 客服工单分析。
    case supportTicketAnalysis = "support_ticket_analysis"
    /// 客服回复草稿。
    case supportReplyDraft = "support_reply_draft"
    /// 客服知识问答。
    case supportKnowledgeAnswer = "support_knowledge_answer"
    /// 文本优化。
    case optimizationText = "optimization_text"
    /// 视觉优化。
    case optimizationVisual = "optimization_visual"
    /// 上下文折叠。
    case contextFolding = "context_folding"
    /// 路由分流。
    case router
    /// 模型配置。
    case modelConfig = "model_config"

    var id: String { rawValue }

    var serviceKey: String {
        switch self {
        case .chat: "chat"
        case .embedding: "embedding"
        case .voice: "voice"
        case .supportTicketAnalysis: "supportTicketAnalysis"
        case .supportReplyDraft: "supportReplyDraft"
        case .supportKnowledgeAnswer: "supportKnowledgeAnswer"
        case .optimizationText: "optimizationText"
        case .optimizationVisual: "optimizationVisual"
        case .contextFolding: "contextFolding"
        case .router: "router"
        case .modelConfig: "modelConfig"
        }
    }

    static func fromServiceKey(_ value: String) -> AIScenario? {
        if let scenario = AIScenario(rawValue: value) { return scenario }
        return allCases.first { $0.serviceKey == value }
    }
}

extension AIScenario {
    var localizedTitle: String {
        switch self {
        case .chat:
            return L10n.text("ai_settings.scenario.chat")
        case .embedding:
            return L10n.text("ai_settings.scenario.embedding")
        case .voice:
            return L10n.text("ai_settings.scenario.voice")
        case .supportTicketAnalysis:
            return L10n.text("ai_settings.scenario.support_ticket_analysis")
        case .supportReplyDraft:
            return L10n.text("ai_settings.scenario.support_reply_draft")
        case .supportKnowledgeAnswer:
            return L10n.text("ai_settings.scenario.support_knowledge_answer")
        case .optimizationText:
            return L10n.text("ai_settings.scenario.optimization_text")
        case .optimizationVisual:
            return L10n.text("ai_settings.scenario.optimization_visual")
        case .contextFolding:
            return L10n.text("ai_settings.scenario.context_folding")
        case .router:
            return L10n.text("ai_settings.scenario.router")
        case .modelConfig:
            return L10n.text("ai_settings.scenario.model_config")
        }
    }

    var introIconSystemName: String {
        switch self {
        case .chat:
            return "bubble.left.and.bubble.right"
        case .embedding:
            return "point.3.connected.trianglepath.dotted"
        case .voice:
            return "waveform"
        case .supportTicketAnalysis:
            return "cross.case"
        case .supportReplyDraft:
            return "square.and.pencil"
        case .supportKnowledgeAnswer:
            return "text.book.closed"
        case .optimizationText:
            return "paintbrush.pointed"
        case .optimizationVisual:
            return "paintbrush"
        case .contextFolding:
            return "rectangle.compress.vertical"
        case .router:
            return "arrow.triangle.branch"
        case .modelConfig:
            return "slider.horizontal.3"
        }
    }

    var localizedIntro: String {
        switch self {
        case .chat:
            return L10n.text("ai_settings.prefs.explain.chat", fallback: "Chat scenario.")
        case .embedding:
            return L10n.text("ai_settings.prefs.explain.embedding", fallback: "Embedding scenario.")
        case .voice:
            return L10n.text("ai_settings.prefs.explain.voice", fallback: "Voice scenario.")
        case .supportTicketAnalysis:
            return L10n.text("ai_settings.prefs.explain.support_ticket_analysis", fallback: "Support ticket analysis.")
        case .supportReplyDraft:
            return L10n.text("ai_settings.prefs.explain.support_reply_draft", fallback: "Support reply draft.")
        case .supportKnowledgeAnswer:
            return L10n.text("ai_settings.prefs.explain.support_knowledge_answer", fallback: "Support knowledge answer.")
        case .optimizationText:
            return L10n.text("ai_settings.prefs.explain.optimization_text", fallback: "Text optimization.")
        case .optimizationVisual:
            return L10n.text("ai_settings.prefs.explain.optimization_visual", fallback: "Visual optimization.")
        case .contextFolding:
            return L10n.text("ai_settings.prefs.explain.context_folding", fallback: "Context folding.")
        case .router:
            return L10n.text("ai_settings.prefs.explain.router", fallback: "Routing.")
        case .modelConfig:
            return L10n.text("ai_settings.prefs.explain.model_config", fallback: "Model configuration.")
        }
    }

    func matchesLocalizedSearch(_ searchText: String) -> Bool {
        guard searchText.isEmpty == false else { return true }
        let text = "\(localizedTitle) \(localizedIntro)".lowercased()
        return text.contains(searchText)
    }
}
