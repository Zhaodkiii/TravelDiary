import Foundation

public protocol MarkdownContentProtocol {
    var _markdownContent: MarkdownContent { get }
}

public struct MarkdownContent: Equatable, Sendable, MarkdownContentProtocol {
    public let markdown: String

    public var _markdownContent: MarkdownContent { self }

    public init(_ markdown: String) {
        self.markdown = markdown
    }

    public init(@MarkdownContentBuilder content: () -> MarkdownContent) {
        self = content()
    }
}

public protocol InlineContentProtocol {
    var _inlineMarkdown: String { get }
}

extension String: InlineContentProtocol {
    public var _inlineMarkdown: String { self }
}

@resultBuilder
public enum InlineContentBuilder {
    public static func buildBlock(_ components: InlineContentProtocol...) -> String {
        components.map(\._inlineMarkdown).joined()
    }

    public static func buildExpression(_ expression: InlineContentProtocol) -> String {
        expression._inlineMarkdown
    }

    public static func buildExpression(_ expression: String) -> String {
        expression
    }

    public static func buildArray(_ components: [InlineContentProtocol]) -> String {
        components.map(\._inlineMarkdown).joined()
    }

    public static func buildOptional(_ component: InlineContentProtocol?) -> String {
        component?._inlineMarkdown ?? ""
    }

    public static func buildEither(first component: InlineContentProtocol) -> String {
        component._inlineMarkdown
    }

    public static func buildEither(second component: InlineContentProtocol) -> String {
        component._inlineMarkdown
    }
}

public struct Heading: MarkdownContentProtocol {
    public enum Level: Int, Sendable {
        case level1 = 1
        case level2 = 2
        case level3 = 3
        case level4 = 4
        case level5 = 5
        case level6 = 6
    }

    public let _markdownContent: MarkdownContent

    public init(_ level: Level, @InlineContentBuilder content: () -> String) {
        _markdownContent = MarkdownContent(String(repeating: "#", count: level.rawValue) + " " + content())
    }
}

public struct Paragraph: MarkdownContentProtocol {
    public let _markdownContent: MarkdownContent

    public init(@InlineContentBuilder content: () -> String) {
        _markdownContent = MarkdownContent(content())
    }
}

public struct Strong: InlineContentProtocol {
    public let _inlineMarkdown: String

    public init(_ text: String) {
        _inlineMarkdown = "**\(text)**"
    }

    public init(@InlineContentBuilder content: () -> String) {
        _inlineMarkdown = "**\(content())**"
    }
}

public struct Emphasis: InlineContentProtocol {
    public let _inlineMarkdown: String

    public init(_ text: String) {
        _inlineMarkdown = "*\(text)*"
    }
}

public struct Strikethrough: InlineContentProtocol {
    public let _inlineMarkdown: String

    public init(_ text: String) {
        _inlineMarkdown = "~~\(text)~~"
    }
}

public struct Code: InlineContentProtocol {
    public let _inlineMarkdown: String

    public init(_ text: String) {
        _inlineMarkdown = "`\(text)`"
    }
}

public struct InlineLink: InlineContentProtocol {
    public let _inlineMarkdown: String

    public init(_ text: String, destination: URL) {
        _inlineMarkdown = "[\(text)](\(destination.absoluteString))"
    }

    public init(_ text: String, destination: String) {
        _inlineMarkdown = "[\(text)](\(destination))"
    }
}

public struct InlineImage: InlineContentProtocol {
    public let _inlineMarkdown: String

    public init(_ alt: String, source: URL) {
        _inlineMarkdown = "![\(alt)](\(source.absoluteString))"
    }

    public init(_ alt: String, source: String) {
        _inlineMarkdown = "![\(alt)](\(source))"
    }
}

public struct BulletedList: MarkdownContentProtocol {
    public let _markdownContent: MarkdownContent

    public init(_ items: [String]) {
        _markdownContent = MarkdownContent(items.map { "- \($0)" }.joined(separator: "\n"))
    }
}

public struct NumberedList: MarkdownContentProtocol {
    public let _markdownContent: MarkdownContent

    public init(_ items: [String], start: Int = 1) {
        _markdownContent = MarkdownContent(items.enumerated().map { index, item in
            "\(start + index). \(item)"
        }.joined(separator: "\n"))
    }
}

public struct TaskList: MarkdownContentProtocol {
    public struct Item: Sendable {
        public let text: String
        public let isCompleted: Bool

        public init(_ text: String, isCompleted: Bool = false) {
            self.text = text
            self.isCompleted = isCompleted
        }
    }

    public let _markdownContent: MarkdownContent

    public init(_ items: [Item]) {
        _markdownContent = MarkdownContent(items.map { "- [\($0.isCompleted ? "x" : " ")] \($0.text)" }.joined(separator: "\n"))
    }
}

public struct CodeBlock: MarkdownContentProtocol {
    public let _markdownContent: MarkdownContent

    public init(_ code: String, language: String? = nil) {
        let fence = "```"
        _markdownContent = MarkdownContent([fence + (language ?? ""), code, fence].joined(separator: "\n"))
    }
}

public struct TextTable: MarkdownContentProtocol {
    public let _markdownContent: MarkdownContent

    public init(header: [String], rows: [[String]]) {
        let headerRow = "| " + header.joined(separator: " | ") + " |"
        let separator = "| " + header.map { _ in "---" }.joined(separator: " | ") + " |"
        let bodyRows = rows.map { "| " + $0.joined(separator: " | ") + " |" }
        _markdownContent = MarkdownContent(([headerRow, separator] + bodyRows).joined(separator: "\n"))
    }
}

@resultBuilder
public enum MarkdownContentBuilder {
    public static func buildBlock(_ components: MarkdownContentProtocol...) -> MarkdownContent {
        MarkdownContent(components.map(\._markdownContent.markdown).joined(separator: "\n"))
    }

    public static func buildExpression(_ expression: MarkdownContentProtocol) -> MarkdownContent {
        expression._markdownContent
    }

    public static func buildExpression(_ expression: String) -> MarkdownContent {
        MarkdownContent(expression)
    }

    public static func buildArray(_ components: [MarkdownContentProtocol]) -> MarkdownContent {
        MarkdownContent(components.map(\._markdownContent.markdown).joined(separator: "\n"))
    }

    public static func buildOptional(_ component: MarkdownContentProtocol?) -> MarkdownContent {
        component?._markdownContent ?? MarkdownContent("")
    }

    public static func buildEither(first component: MarkdownContentProtocol) -> MarkdownContent {
        component._markdownContent
    }

    public static func buildEither(second component: MarkdownContentProtocol) -> MarkdownContent {
        component._markdownContent
    }
}
