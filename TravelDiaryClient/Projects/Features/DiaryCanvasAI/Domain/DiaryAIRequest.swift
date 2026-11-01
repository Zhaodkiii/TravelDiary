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

nonisolated struct DiaryAIRequest: Codable, Equatable, Sendable {
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
    var textDensity = "简短补充"
    var strength = "保守"
    var understandsPhotos = true
    var canSubmit: Bool { background?.backgroundOnly == true || action != .custom || !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var canCreateText: Bool { (action == .writing && !["润色", "缩短", "只换样式"].contains(writingKind)) || (action != .writing && action != .beautify && allowsText) }
    var canRewrite: Bool { action == .writing ? writingKind != "只换样式" : action != .beautify && allowsRewrite }
    var canMove: Bool { action != .writing && (action != .custom || allowsPlacement) }
    static func defaults(_ action: DiaryAIAction) -> Self {
        var request = Self(action: action)
        if action == .relayout { request.style = "自动匹配" }
        if action == .custom { request.selectedOnly = true; request.allowsPlacement = false }
        return request
    }
}
