import Foundation

nonisolated enum DiaryAIAction: String, CaseIterable, Identifiable, Codable, Sendable {
    case beautify = "一键美化", relayout = "重新排版", writing = "写点文字", custom = "按要求改"
    var id: String { rawValue }
    var symbol: String {
        switch self { case .beautify: "sparkles"; case .relayout: "rectangle.3.group"; case .writing: "pencil.line"; case .custom: "text.bubble" }
    }
    var submitTitle: String {
        switch self { case .beautify: "开始美化"; case .relayout: "开始排版"; case .writing: "生成文字"; case .custom: "开始调整" }
    }
}

nonisolated enum DiaryAILayoutMode: String, CaseIterable, Codable, Sendable, Identifiable {
    case native, ai

    static let preferenceKey = "DiaryCanvasAI.layoutMode"
    static var preferred: Self {
        UserDefaults.standard.string(forKey: preferenceKey).flatMap(Self.init(rawValue:)) ?? .native
    }

    var id: String { rawValue }
    var title: String {
        switch self {
        case .native: "智能快速排版"
        case .ai: "AI 自由排版"
        }
    }
    var explanation: String {
        switch self {
        case .native: "本机安排照片、文字和贴纸，AI 生成文案与背景。适合 1–8 张照片的整页制作。"
        case .ai: "AI 规划整页构图与素材位置，制作通常需要更长时间。"
        }
    }
}

nonisolated struct DiaryAIRequest: Codable, Equatable, Sendable {
    var creationBrief: CreationBrief? = nil
    var creationNotes: [String: String]? = nil
    var design: DiaryAIDesignSelection? = nil
    var layoutMode: DiaryAILayoutMode? = nil
    var background: DiaryAIBackgroundOptions? = nil
    var action: DiaryAIAction
    var style = "保持当前风格"
    var moods: [String] = []
    var customMood = ""
    var scene = "不指定"
    var customScene = ""
    var location = ""
    var writesLocation = false
    var instruction = ""
    var selectedOnly = false
    var preservesBackground = true
    var allowsCrop = false
    var allowsFrames = false
    var allowsDecorations = false
    var allowsText = false
    var allowsRewrite = false
    var allowsPlacement = true
    var allowsMaterials = false
    var heroID: UUID?
    var materialIDs: [UUID] = []
    var writingKind = "随手一句"
    var textDensity = "丰富记录"
    var strength = "保守"
    var understandsPhotos = true
    var canSubmit: Bool { background?.backgroundOnly == true || action != .custom || !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var canCreateText: Bool { (action == .writing && !["润色", "缩短", "只换样式"].contains(writingKind)) || (action != .writing && action != .beautify && allowsText) }
    var canRewrite: Bool { action == .writing ? writingKind != "只换样式" : action != .beautify && allowsRewrite }
    var canMove: Bool { action != .writing && (action != .custom || allowsPlacement) }
    /// Defaults for a new user-facing task; internal callers can opt into each operation.
    static func editorDefaults(_ action: DiaryAIAction) -> Self {
        var request = defaults(action)
        if action == .relayout {
            request.design = DiaryAIDesignSelection()
            request.background = DiaryAIBackgroundOptions()
            request.allowsText = true
            request.allowsFrames = true
        }
        return request
    }
    static func defaults(_ action: DiaryAIAction) -> Self {
        var request = Self(action: action)
        if action == .relayout { request.style = "自动匹配" }
        if action == .custom { request.selectedOnly = true; request.allowsPlacement = false }
        return request
    }
}


extension DiaryAIRequest {
    var designBrief: String { design?.brief ?? DiaryAIStyleLibrary.brief(style) }
    /// Keep an explicit background-off choice. Normalize only its medium, never permissions.
    func coordinated() -> Self {
        var value = self
        if let brief = value.creationBrief {
            if brief.hasVisibleStoryEntries { value.allowsText = true }
            if let place = brief.storyEntries?.first(where: { $0.kind == .location }) {
                value.location = place.text; value.writesLocation = place.usage != .reference
            }
        }
        if let design, value.background != nil { value.background?.style = design.style.backgroundID }
        return value
    }
}


extension DiaryAIRequest {
    var executionDesignBrief: String {
        guard let design else { return designBrief }
        return "整页排版：\(design.layout.name)，\(design.layout.rules) 整页风格：\(design.style.name)，\(design.style.rules) 共同构图已确认，遵守它的主照、分组、色彩和文字角色；用户显式要求与锁定内容优先。"
    }
}
