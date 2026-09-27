import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

public struct Theme: Sendable {
    public var textColor: Color
    public var secondaryTextColor: Color
    public var linkColor: Color
    public var backgroundColor: Color
    public var bodyFont: Font
    public var codeFont: Font
    public var codeForegroundColor: Color
    public var codeBackgroundColor: Color
    public var quoteBarColor: Color
    public var quoteBackgroundColor: Color
    public var borderColor: Color
    public var dividerColor: Color
    public var tableHeaderBackgroundColor: Color
    public var tableAlternateBackgroundColor: Color
    public var paragraphSpacing: CGFloat
    public var blockSpacing: CGFloat

    public init(
        textColor: Color = .primary,
        secondaryTextColor: Color = .secondary,
        linkColor: Color = .accentColor,
        backgroundColor: Color = .clear,
        bodyFont: Font = .body,
        codeFont: Font = .system(.footnote, design: .monospaced),
        codeForegroundColor: Color = .primary,
        codeBackgroundColor: Color = Color.primary.opacity(0.08),
        quoteBarColor: Color = .accentColor,
        quoteBackgroundColor: Color = Color.accentColor.opacity(0.08),
        borderColor: Color = Color.secondary.opacity(0.25),
        dividerColor: Color = Color.secondary.opacity(0.25),
        tableHeaderBackgroundColor: Color = Color.secondary.opacity(0.12),
        tableAlternateBackgroundColor: Color = Color.secondary.opacity(0.06),
        paragraphSpacing: CGFloat = 8,
        blockSpacing: CGFloat = 8
    ) {
        self.textColor = textColor
        self.secondaryTextColor = secondaryTextColor
        self.linkColor = linkColor
        self.backgroundColor = backgroundColor
        self.bodyFont = bodyFont
        self.codeFont = codeFont
        self.codeForegroundColor = codeForegroundColor
        self.codeBackgroundColor = codeBackgroundColor
        self.quoteBarColor = quoteBarColor
        self.quoteBackgroundColor = quoteBackgroundColor
        self.borderColor = borderColor
        self.dividerColor = dividerColor
        self.tableHeaderBackgroundColor = tableHeaderBackgroundColor
        self.tableAlternateBackgroundColor = tableAlternateBackgroundColor
        self.paragraphSpacing = paragraphSpacing
        self.blockSpacing = blockSpacing
    }
}

public extension Theme {
    static let basic = Theme()

    static let gitHub = Theme(
        textColor: .markdownGitHubText,
        secondaryTextColor: .markdownGitHubSecondaryText,
        linkColor: .markdownGitHubLink,
        backgroundColor: .markdownGitHubBackground,
        bodyFont: .body,
        codeFont: .system(.footnote, design: .monospaced),
        codeForegroundColor: .markdownGitHubText,
        codeBackgroundColor: .markdownGitHubSecondaryBackground,
        quoteBarColor: .markdownGitHubBorder,
        quoteBackgroundColor: .clear,
        borderColor: .markdownGitHubBorder,
        dividerColor: .markdownGitHubDivider,
        tableHeaderBackgroundColor: .markdownGitHubBackground,
        tableAlternateBackgroundColor: .markdownGitHubSecondaryBackground,
        paragraphSpacing: 8,
        blockSpacing: 0
    )

    static func chatBubble(foreground: Color) -> Theme {
        Theme(
            textColor: foreground,
            secondaryTextColor: foreground.opacity(0.78),
            linkColor: foreground.opacity(0.9),
            backgroundColor: .clear,
            bodyFont: .body,
            codeFont: .system(.footnote, design: .monospaced),
            codeForegroundColor: foreground,
            codeBackgroundColor: foreground.opacity(0.14),
            quoteBarColor: foreground.opacity(0.75),
            quoteBackgroundColor: foreground.opacity(0.08),
            borderColor: foreground.opacity(0.28),
            dividerColor: foreground.opacity(0.24),
            tableHeaderBackgroundColor: foreground.opacity(0.12),
            tableAlternateBackgroundColor: foreground.opacity(0.06),
            paragraphSpacing: 6,
            blockSpacing: 8
        )
    }
}

private struct MarkdownThemeKey: EnvironmentKey {
    static let defaultValue: Theme = .basic
}

private struct MarkdownSoftBreakModeKey: EnvironmentKey {
    static let defaultValue: MarkdownSoftBreakMode = .space
}

public extension EnvironmentValues {
    var markdownTheme: Theme {
        get { self[MarkdownThemeKey.self] }
        set { self[MarkdownThemeKey.self] = newValue }
    }

    var markdownSoftBreakMode: MarkdownSoftBreakMode {
        get { self[MarkdownSoftBreakModeKey.self] }
        set { self[MarkdownSoftBreakModeKey.self] = newValue }
    }
}

public extension View {
    func markdownTheme(_ theme: Theme) -> some View {
        environment(\.markdownTheme, theme)
    }

    func markdownTextStyle(_ style: MarkdownTextStyle, _ update: @escaping (inout Theme) -> Void) -> some View {
        modifier(MarkdownThemeTransformModifier { theme in
            switch style {
            case .body:
                update(&theme)
            case .code:
                update(&theme)
            case .link:
                update(&theme)
            }
        })
    }

    func markdownBlockStyle(_ style: MarkdownBlockStyle, _ update: @escaping (inout Theme) -> Void) -> some View {
        modifier(MarkdownThemeTransformModifier { theme in
            switch style {
            case .paragraph, .heading, .blockquote, .codeBlock, .table, .list, .thematicBreak:
                update(&theme)
            }
        })
    }

    func markdownSoftBreakMode(_ mode: MarkdownSoftBreakMode) -> some View {
        environment(\.markdownSoftBreakMode, mode)
    }
}

public enum MarkdownTextStyle: Sendable {
    case body
    case code
    case link
}

public enum MarkdownBlockStyle: Sendable {
    case paragraph
    case heading
    case blockquote
    case codeBlock
    case table
    case list
    case thematicBreak
}

private struct MarkdownThemeTransformModifier: ViewModifier {
    @Environment(\.markdownTheme) private var theme

    let transform: (inout Theme) -> Void

    func body(content: Content) -> some View {
        var transformedTheme = theme
        transform(&transformedTheme)
        return content.environment(\.markdownTheme, transformedTheme)
    }
}

private extension Color {
    static let markdownGitHubText = Color(light: Color(rgba: 0x0606_06ff), dark: Color(rgba: 0xfbfb_fcff))
    static let markdownGitHubSecondaryText = Color(light: Color(rgba: 0x6b6e_7bff), dark: Color(rgba: 0x9294_a0ff))
    static let markdownGitHubBackground = Color(light: .white, dark: Color(rgba: 0x1819_1dff))
    static let markdownGitHubSecondaryBackground = Color(light: Color(rgba: 0xf7f7_f9ff), dark: Color(rgba: 0x2526_2aff))
    static let markdownGitHubLink = Color(light: Color(rgba: 0x2c65_cfff), dark: Color(rgba: 0x4c8e_f8ff))
    static let markdownGitHubBorder = Color(light: Color(rgba: 0xe4e4_e8ff), dark: Color(rgba: 0x4244_4eff))
    static let markdownGitHubDivider = Color(light: Color(rgba: 0xd0d0_d3ff), dark: Color(rgba: 0x3334_38ff))

    init(rgba: UInt32) {
        self.init(
            red: Double((rgba >> 24) & 0xff) / 255,
            green: Double((rgba >> 16) & 0xff) / 255,
            blue: Double((rgba >> 8) & 0xff) / 255,
            opacity: Double(rgba & 0xff) / 255
        )
    }

    init(light: Color, dark: Color) {
        #if canImport(UIKit)
        self.init(.init { traitCollection in
            UIColor(traitCollection.userInterfaceStyle == .dark ? dark : light)
        })
        #elseif os(macOS)
        self.init(.init(name: nil) { appearance in
            let bestMatch = appearance.bestMatch(from: [.darkAqua, .aqua])
            return NSColor(bestMatch == .darkAqua ? dark : light)
        })
        #else
        self = light
        #endif
    }
}
