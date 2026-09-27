import SwiftUI

public struct Markdown: View {
    @Environment(\.markdownTheme) private var theme

    private let content: MarkdownContent
    private let baseURL: URL?
    private let imageBaseURL: URL?

    public init(_ content: MarkdownContent, baseURL: URL? = nil, imageBaseURL: URL? = nil) {
        self.content = content
        self.baseURL = baseURL
        self.imageBaseURL = imageBaseURL ?? baseURL
    }

    public init(_ markdown: String, baseURL: URL? = nil, imageBaseURL: URL? = nil) {
        self.init(MarkdownContent(markdown), baseURL: baseURL, imageBaseURL: imageBaseURL)
    }

    public init(baseURL: URL? = nil, imageBaseURL: URL? = nil, @MarkdownContentBuilder content: () -> MarkdownContent) {
        self.init(content(), baseURL: baseURL, imageBaseURL: imageBaseURL)
    }

    public var body: some View {
        return MarkdownDocumentView(
            text: content.markdown,
            style: makeDocumentStyle(from: theme),
            baseURL: baseURL,
            imageBaseURL: imageBaseURL
        )
    }

    private func makeDocumentStyle(from theme: Theme) -> MarkdownDocumentStyle {
        MarkdownDocumentStyle(
            textColor: theme.textColor,
            secondaryTextColor: theme.secondaryTextColor,
            headingColor: theme.textColor,
            linkColor: theme.linkColor,
            backgroundColor: theme.backgroundColor,
            codeBackgroundColor: theme.codeBackgroundColor,
            codeForegroundColor: theme.codeForegroundColor,
            quoteBarColor: theme.quoteBarColor,
            quoteBackgroundColor: theme.quoteBackgroundColor,
            tableBorderColor: theme.borderColor,
            tableHeaderBackgroundColor: theme.tableHeaderBackgroundColor,
            tableAlternateBackgroundColor: theme.tableAlternateBackgroundColor,
            dividerColor: theme.dividerColor,
            bodyFont: theme.bodyFont,
            codeFont: theme.codeFont,
            paragraphSpacing: theme.paragraphSpacing,
            blockSpacing: theme.blockSpacing
        )
    }
}
