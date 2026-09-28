import SwiftUI

public struct MarkdownCodeSyntaxHighlighter: Sendable {
    public var highlight: @Sendable (_ code: String, _ language: String?) -> AttributedString

    public init(highlight: @escaping @Sendable (_ code: String, _ language: String?) -> AttributedString) {
        self.highlight = highlight
    }

    public static let plain = MarkdownCodeSyntaxHighlighter { code, _ in
        AttributedString(code)
    }

    public static let simple = MarkdownCodeSyntaxHighlighter { code, language in
        SimpleMarkdownCodeSyntaxHighlighter.highlight(code, language: language)
    }
}

private enum MarkdownCodeSyntaxHighlighterKey: EnvironmentKey {
    static let defaultValue: MarkdownCodeSyntaxHighlighter = .simple
}

public extension EnvironmentValues {
    var markdownCodeSyntaxHighlighter: MarkdownCodeSyntaxHighlighter {
        get { self[MarkdownCodeSyntaxHighlighterKey.self] }
        set { self[MarkdownCodeSyntaxHighlighterKey.self] = newValue }
    }
}

public extension View {
    func markdownCodeSyntaxHighlighter(_ highlighter: MarkdownCodeSyntaxHighlighter) -> some View {
        environment(\.markdownCodeSyntaxHighlighter, highlighter)
    }
}

private enum SimpleMarkdownCodeSyntaxHighlighter {
    nonisolated static func highlight(_ code: String, language: String?) -> AttributedString {
        var attributed = AttributedString(code)
        attributed.foregroundColor = .primary

        switch language?.lowercased() {
        case "swift":
            colorWords(
                &attributed,
                words: ["actor", "associatedtype", "async", "await", "case", "class", "enum", "extension", "func", "guard", "if", "import", "in", "let", "nil", "private", "protocol", "public", "return", "self", "static", "struct", "switch", "throws", "try", "var", "while"],
                color: .purple
            )
            colorLineComments(&attributed, color: .secondary)
            colorStrings(&attributed, color: .red)

        case "json":
            colorJSON(&attributed)

        case "markdown", "md":
            colorLinePrefixes(&attributed, prefixes: ["#", ">", "-", "*", "+", "|"], color: .blue)

        default:
            colorLineComments(&attributed, color: .secondary)
        }

        return attributed
    }

    nonisolated private static func colorWords(_ attributed: inout AttributedString, words: Set<String>, color: Color) {
        let string = String(attributed.characters)
        for word in words {
            var searchStart = string.startIndex
            while let range = string[searchStart...].range(of: word) {
                let before = range.lowerBound > string.startIndex ? string[string.index(before: range.lowerBound)] : " "
                let after = range.upperBound < string.endIndex ? string[range.upperBound] : " "
                if before.isIdentifierBoundary && after.isIdentifierBoundary,
                   let attributedRange = Range(range, in: attributed) {
                    attributed[attributedRange].foregroundColor = color
                }
                searchStart = range.upperBound
            }
        }
    }

    nonisolated private static func colorStrings(_ attributed: inout AttributedString, color: Color) {
        let string = String(attributed.characters)
        var index = string.startIndex
        while index < string.endIndex {
            guard string[index] == "\"" else {
                index = string.index(after: index)
                continue
            }

            var end = string.index(after: index)
            var escaped = false
            while end < string.endIndex {
                if escaped {
                    escaped = false
                } else if string[end] == "\\" {
                    escaped = true
                } else if string[end] == "\"" {
                    end = string.index(after: end)
                    break
                }
                end = string.index(after: end)
            }

            if let attributedRange = Range(index..<end, in: attributed) {
                attributed[attributedRange].foregroundColor = color
            }
            index = end
        }
    }

    nonisolated private static func colorLineComments(_ attributed: inout AttributedString, color: Color) {
        let string = String(attributed.characters)
        for lineRange in string.lineRanges {
            guard let commentRange = string[lineRange].range(of: "//") else { continue }
            if let attributedRange = Range(commentRange.lowerBound..<lineRange.upperBound, in: attributed) {
                attributed[attributedRange].foregroundColor = color
            }
        }
    }

    nonisolated private static func colorJSON(_ attributed: inout AttributedString) {
        colorStrings(&attributed, color: .red)
        colorWords(&attributed, words: ["true", "false", "null"], color: .purple)
        colorCharacters(&attributed, characters: "{}[]:,", color: .blue)
    }

    nonisolated private static func colorCharacters(_ attributed: inout AttributedString, characters: String, color: Color) {
        let string = String(attributed.characters)
        for index in string.indices where characters.contains(string[index]) {
            if let attributedRange = Range(index..<string.index(after: index), in: attributed) {
                attributed[attributedRange].foregroundColor = color
            }
        }
    }

    nonisolated private static func colorLinePrefixes(_ attributed: inout AttributedString, prefixes: [Character], color: Color) {
        let string = String(attributed.characters)
        for lineRange in string.lineRanges {
            guard let first = string[lineRange].first, prefixes.contains(first) else { continue }
            if let attributedRange = Range(lineRange, in: attributed) {
                attributed[attributedRange].foregroundColor = color
            }
        }
    }
}

private extension Character {
    nonisolated var isIdentifierBoundary: Bool {
        isLetter == false && isNumber == false && self != "_"
    }
}

private extension String {
    nonisolated var lineRanges: [Range<String.Index>] {
        var result: [Range<String.Index>] = []
        var start = startIndex
        while start < endIndex {
            let end = self[start...].firstIndex(of: "\n") ?? endIndex
            result.append(start..<end)
            start = end < endIndex ? index(after: end) : endIndex
        }
        return result
    }
}
