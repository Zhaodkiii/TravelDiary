import Foundation

/// Optional on old documents; decoration and typography remain editable text data.
nonisolated struct DiaryTextAppearance: Codable, Equatable, Sendable {
    var template: DiaryTextTemplate = .plain
    var bold = false
    var italic = false
    var underline = false
    var strikethrough = false
    var vertical = false
    var opacity: Double = 1
    var strokeWidth: Double = 0
    var strokeColor = DiaryColor.white
    var shadowRadius: Double = 0
    var shadowColor = DiaryColor(red: 0, green: 0, blue: 0, alpha: 0.35)
    var background: DiaryColor? = nil

    var isValid: Bool {
        opacity.isFinite && (0...1).contains(opacity)
        && strokeWidth.isFinite && (0...12).contains(strokeWidth)
        && shadowRadius.isFinite && (0...30).contains(shadowRadius)
    }
}

nonisolated enum DiaryTextTemplate: String, Codable, CaseIterable, Identifiable, Sendable {
    case plain, label, tape, bubble, burst, ticket, postcard, capsule
    var id: Self { self }
    var title: String {
        switch self {
        case .plain: "普通"
        case .label: "复古标签"
        case .tape: "手帐胶带"
        case .bubble: "对话气泡"
        case .burst: "漫画爆炸框"
        case .ticket: "旅行票根"
        case .postcard: "旅行便签"
        case .capsule: "圆角标题"
        }
    }
    var background: DiaryColor {
        switch self {
        case .plain, .bubble: .white
        case .label, .ticket: .paper
        case .tape: .yellow
        case .burst: DiaryColor(red: 0.87, green: 0.84, blue: 1)
        case .postcard: .mint
        case .capsule: .pink
        }
    }
    var textColor: DiaryColor {
        self == .burst ? DiaryColor(red: 0.34, green: 0.20, blue: 0.75) : .brown
    }
}
