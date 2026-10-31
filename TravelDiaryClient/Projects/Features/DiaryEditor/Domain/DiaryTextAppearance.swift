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

    // Optional fields preserve decoding of existing documents.
    var titleLayout: DiaryTitleLayout? = nil
    var paper: DiaryTextPaper? = nil
    /// User-set card height; content may grow beyond it without clipping.
    var minimumCardHeight: Double? = nil

    var isValid: Bool {
        (minimumCardHeight.map { $0.isFinite && (0...20000).contains($0) } ?? true)
        && (paper?.isValid ?? true) && opacity.isFinite && (0...1).contains(opacity)
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

nonisolated enum DiaryTitleLayout: String, Codable, CaseIterable, Identifiable, Sendable {
    case headline, handwriting, balanced, vertical
    var id: Self { self }
    var title: String {
        switch self {
        case .headline: "醒目大标题"
        case .handwriting: "手写短句"
        case .balanced: "两行标题"
        case .vertical: "竖排题字"
        }
    }
}

nonisolated struct DiaryTextPaper: Codable, Equatable, Sendable {
    enum Kind: String, Codable, CaseIterable, Identifiable, Sendable {
        case none, torn, tape, note
        var id: Self { self }
        var title: String {
            switch self { case .none: "无背景"; case .torn: "手撕纸"; case .tape: "胶带"; case .note: "便签" }
        }
    }
    var kind: Kind = .none
    var color: DiaryColor = .paper
    var roughness: Double = 0.45
    var seed: Int = 1
    var horizontalPadding: Double = 0.7
    var verticalPadding: Double = 0.45
    var shadow: Double = 0.15
    var cornerRadius: Double = 0.15
    var isValid: Bool {
        roughness.isFinite && (0...1).contains(roughness)
        && horizontalPadding.isFinite && (0.1...2).contains(horizontalPadding)
        && verticalPadding.isFinite && (0.1...2).contains(verticalPadding)
        && shadow.isFinite && (0...1).contains(shadow)
        && cornerRadius.isFinite && (0...1).contains(cornerRadius)
    }
}

/// Personal presets contain appearance only, never the user's text or canvas position.
nonisolated struct DiarySavedTextStyle: Codable, Identifiable, Sendable {
    var id = UUID()
    var name: String
    var appearance: DiaryTextAppearance
    var font: DiaryFontReference?
    var color: DiaryColor?
    var alignment: DiaryTextAlignment?
    var lineHeight: Double?
    var letterSpacing: Double?
    var fontSize: CGFloat
    var width: CGFloat
}
