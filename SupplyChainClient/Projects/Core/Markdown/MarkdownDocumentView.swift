import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct MarkdownDocumentStyle: Sendable {
    let textColor: Color
    let secondaryTextColor: Color
    let headingColor: Color
    let linkColor: Color
    let backgroundColor: Color
    let codeBackgroundColor: Color
    let codeForegroundColor: Color
    let quoteBarColor: Color
    let quoteBackgroundColor: Color
    let tableBorderColor: Color
    let tableHeaderBackgroundColor: Color
    let tableAlternateBackgroundColor: Color
    let dividerColor: Color
    let bodyFont: Font
    let codeFont: Font
    let paragraphSpacing: CGFloat
    let blockSpacing: CGFloat

    static let documentation = MarkdownDocumentStyle(
        textColor: .primary,
        secondaryTextColor: .secondary,
        headingColor: .primary,
        linkColor: .accentColor,
        backgroundColor: .clear,
        codeBackgroundColor: Color.primary.opacity(0.08),
        codeForegroundColor: .primary,
        quoteBarColor: .accentColor,
        quoteBackgroundColor: Color.accentColor.opacity(0.08),
        tableBorderColor: Color.secondary.opacity(0.25),
        tableHeaderBackgroundColor: Color.secondary.opacity(0.12),
        tableAlternateBackgroundColor: Color.secondary.opacity(0.06),
        dividerColor: Color.secondary.opacity(0.25),
        bodyFont: .body,
        codeFont: .system(.footnote, design: .monospaced),
        paragraphSpacing: 8,
        blockSpacing: 10
    )

    static func chatBubble(textColor: Color) -> MarkdownDocumentStyle {
        MarkdownDocumentStyle(
            textColor: textColor,
            secondaryTextColor: textColor.opacity(0.78),
            headingColor: textColor,
            linkColor: textColor,
            backgroundColor: .clear,
            codeBackgroundColor: textColor.opacity(0.12),
            codeForegroundColor: textColor,
            quoteBarColor: textColor.opacity(0.75),
            quoteBackgroundColor: textColor.opacity(0.08),
            tableBorderColor: textColor.opacity(0.3),
            tableHeaderBackgroundColor: textColor.opacity(0.12),
            tableAlternateBackgroundColor: textColor.opacity(0.06),
            dividerColor: textColor.opacity(0.24),
            bodyFont: .body,
            codeFont: .system(.footnote, design: .monospaced),
            paragraphSpacing: 6,
            blockSpacing: 8
        )
    }
}

private struct MarkdownImageReference: Equatable {
    let url: URL
    let alt: String
    let source: String
}

private struct MarkdownImagePreviewSheet: Identifiable {
    let id = UUID()
    let inputs: [FilePreviewInput]
    let startIndex: Int
}

struct MarkdownDocumentView: View {
    @Environment(\.markdownCodeSyntaxHighlighter) private var codeSyntaxHighlighter
    @Environment(\.markdownSoftBreakMode) private var softBreakMode
    @State private var activeWebURL: IdentifiableURL?
    @State private var activeImagePreviewSheet: MarkdownImagePreviewSheet?
    @State private var tableHeights: [Int: CGFloat] = [:]

    private let segments: [MarkdownSegment]
    private let imageReferences: [MarkdownImageReference]
    private let style: MarkdownDocumentStyle
    private let baseURL: URL?
    private let imageBaseURL: URL?

    init(
        text: String,
        style: MarkdownDocumentStyle = .documentation,
        baseURL: URL? = nil,
        imageBaseURL: URL? = nil
    ) {
        let segments = MarkdownSegmentParser.parse(text)
        let imageBaseURL = imageBaseURL ?? baseURL
        self.segments = segments
        self.imageReferences = Self.collectImageReferences(in: segments, imageBaseURL: imageBaseURL)
        self.style = style
        self.baseURL = baseURL
        self.imageBaseURL = imageBaseURL
    }

    init(
        segments: [MarkdownSegment],
        style: MarkdownDocumentStyle = .documentation,
        baseURL: URL? = nil,
        imageBaseURL: URL? = nil
    ) {
        let imageBaseURL = imageBaseURL ?? baseURL
        self.segments = segments
        self.imageReferences = Self.collectImageReferences(in: segments, imageBaseURL: imageBaseURL)
        self.style = style
        self.baseURL = baseURL
        self.imageBaseURL = imageBaseURL
    }

    var body: some View {
        VStack(alignment: .leading, spacing: style.blockSpacing) {
            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                render(segment, tableID: index)
            }
        }
        .foregroundStyle(style.textColor)
        .background(style.backgroundColor)
        .environment(\.openURL, OpenURLAction { url in
            guard url.isWebURL else {
                return .systemAction
            }
            activeWebURL = IdentifiableURL(url: url)
            return .handled
        })
        .sheet(item: $activeWebURL) { item in
            SafariWebViewSheet(url: item.url)
                .ignoresSafeArea()
        }
    
        .sheet(item: $activeImagePreviewSheet) { preview in
            UnifiedFilePreview(inputs: preview.inputs, startIndex: preview.startIndex) {
                activeImagePreviewSheet = nil
            }
        }
    }

    private func render(_ segment: MarkdownSegment, tableID: Int? = nil) -> AnyView {
        switch segment {
        case .heading(let level, let text):
            return AnyView(heading(text, level: level))

        case .paragraph(let text):
            return AnyView(markdownInlineFlow(text, font: style.bodyFont, color: style.textColor)
                .lineSpacing(4)
                .padding(.bottom, 8))

        case .image(let alt, let source):
            return AnyView(markdownImage(alt: alt, source: source))

        case .unorderedList(let items):
            return AnyView(VStack(alignment: .leading, spacing: style.paragraphSpacing) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    listRow(marker: bulletMarker(for: item.level), content: item.content, level: item.level)
                }
            }
            .padding(.bottom, 8))

        case .orderedList(let items, let start):
            return AnyView(VStack(alignment: .leading, spacing: style.paragraphSpacing) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    let number = item.number ?? (start + index)
                    listRow(marker: "\(number).", content: item.content, level: item.level)
                }
            }
            .padding(.bottom, 8))

        case .taskList(let items):
            return AnyView(VStack(alignment: .leading, spacing: style.paragraphSpacing) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: item.isDone ? "checkmark.square.fill" : "square")
                            .foregroundStyle(item.isDone ? style.linkColor : style.secondaryTextColor)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: style.paragraphSpacing) {
                            renderListContent(item.content)
                        }
                    }
                    .padding(.leading, CGFloat(item.level) * 18)
                }
            }
            .padding(.bottom, 8))

        case .blockquote(let children):
            return AnyView(HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(style.quoteBarColor)
                    .frame(width: 4)
                VStack(alignment: .leading, spacing: style.paragraphSpacing) {
                    ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                        render(child, colorOverride: style.secondaryTextColor)
                    }
                }
            }
            .padding(.leading, 12)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(style.quoteBackgroundColor)
            )
            .padding(.bottom, 8))

        case .codeBlock(let language, let code):
            return AnyView(VStack(alignment: .leading, spacing: 6) {
                if let language, language.isEmpty == false {
                    Text(language.uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(style.secondaryTextColor)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(highlightedCode(code, language: language))
                        .font(style.codeFont)
                        .foregroundStyle(style.codeForegroundColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .lineSpacing(3)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(style.codeBackgroundColor)
            )
            .padding(.bottom, 8))

        case .table(let header, let alignments, let rows):
            return AnyView(table(header: header, alignments: alignments, rows: rows, id: tableID))

        case .htmlBlock(let html):
            return AnyView(Text(html.strippingHTMLTags())
                .font(style.bodyFont)
                .foregroundStyle(style.secondaryTextColor)
                .textSelection(.enabled)
                .padding(.bottom, 8))

        case .thematicBreak:
            return AnyView(Divider()
                .frame(height: 3)
                .overlay(style.dividerColor)
                .padding(.vertical, 20))
        }
    }

    private func heading(_ text: String, level: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            markdownInlineFlow(text, font: headingFont(level: level), color: level == 6 ? style.secondaryTextColor : style.headingColor)
                .lineSpacing(3)
                .padding(.top, level <= 2 ? 16 : 12)
                .padding(.bottom, level <= 2 ? 8 : 6)
            if level <= 2 {
                Divider().overlay(style.dividerColor)
            }
        }
        .padding(.bottom, 8)
    }

    private func listRow(marker: String, content: [MarkdownSegment], level: Int) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(marker)
                .font(style.bodyFont.weight(.semibold))
                .foregroundStyle(style.textColor)
                .frame(minWidth: 22, alignment: .trailing)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: style.paragraphSpacing) {
                renderListContent(content)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, CGFloat(level) * 18)
    }

    private func renderListContent(_ content: [MarkdownSegment]) -> some View {
        ForEach(Array(content.enumerated()), id: \.offset) { index, child in
            renderListChild(child, isFirst: index == 0)
        }
    }

    private func renderListChild(_ segment: MarkdownSegment, isFirst: Bool) -> AnyView {
        switch segment {
        case .paragraph(let text):
            return AnyView(markdownInlineFlow(text, font: style.bodyFont, color: style.textColor)
                .lineSpacing(4)
                .padding(.bottom, isFirst ? 0 : 4))
        default:
            return render(segment)
        }
    }

    private func table(header: [String], alignments: [MarkdownSegment.TableAlignment], rows: [[String]], id: Int?) -> some View {
        let tableID = id ?? -1
        let allRows = [header] + rows
        let columnCount = max(allRows.map(\.count).max() ?? 0, alignments.count)

        return ScrollView(.horizontal, showsIndicators: false) {
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                ForEach(Array(allRows.enumerated()), id: \.offset) { rowIndex, row in
                    GridRow {
                        ForEach(0..<columnCount, id: \.self) { column in
                            tableCell(
                                row[safe: column] ?? "",
                                alignment: alignments[safe: column] ?? .leading,
                                row: rowIndex,
                                column: column,
                                columnCount: columnCount
                            )
                        }
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 0, style: .continuous)
                    .stroke(style.tableBorderColor, lineWidth: 1)
            )
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: MarkdownTableHeightPreferenceKey.self,
                        value: [tableID: proxy.size.height]
                    )
                }
            )
        }
        .frame(height: tableHeights[tableID])
        .onPreferenceChange(MarkdownTableHeightPreferenceKey.self) { heights in
            guard let height = heights[tableID], height > 0 else { return }
            if abs((tableHeights[tableID] ?? 0) - height) > 0.5 {
                DispatchQueue.main.async {
                    tableHeights[tableID] = height
                }
            }
        }
        .overlay(alignment: .trailing) {
            LinearGradient(
                colors: [Color.clear, style.backgroundColor.opacity(0.65)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 14)
            .allowsHitTesting(false)
        }
        .padding(.bottom, 8)
    }

    private func tableCell(
        _ cell: String,
        alignment: MarkdownSegment.TableAlignment,
        row: Int,
        column: Int,
        columnCount: Int
    ) -> some View {
        let horizontalPadding: CGFloat = 13
        let columnWidth = tableColumnWidth(column: column, columnCount: columnCount)
        let contentWidth = max(columnWidth - horizontalPadding * 2, 1)

        return ZStack(alignment: tableCellAlignment(alignment)) {
            tableCellBackground(row: row)
            markdownInlineFlow(
                cell,
                font: row == 0 ? style.bodyFont.weight(.semibold) : style.bodyFont,
                color: style.textColor
            )
            .frame(width: contentWidth, alignment: tableCellAlignment(alignment))
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 6)
        }
        .frame(width: columnWidth)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(style.tableBorderColor)
                .frame(width: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(style.tableBorderColor)
                .frame(height: 1)
        }
    }

    private func tableColumnWidth(column: Int, columnCount: Int) -> CGFloat {
        if columnCount >= 4 {
            switch column {
            case 0: return 132
            case 1: return 240
            case 2: return 170
            default: return 320
            }
        }
        if column == columnCount - 1 {
            return 320
        }
        return 180
    }

    private func tableCellBackground(row: Int) -> Color {
        if row == 0 {
            return style.tableHeaderBackgroundColor
        }
        if row.isMultiple(of: 2) {
            return style.tableAlternateBackgroundColor
        }
        return .clear
    }

    private func tableCellAlignment(_ alignment: MarkdownSegment.TableAlignment) -> Alignment {
        switch alignment {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    private func render(_ segment: MarkdownSegment, colorOverride: Color?) -> AnyView {
        let originalStyle = style
        switch segment {
        case .paragraph(let text):
            return AnyView(markdownInlineFlow(text, font: originalStyle.bodyFont, color: colorOverride ?? originalStyle.textColor)
                .lineSpacing(4)
                .padding(.bottom, 8))
        default:
            return render(segment)
        }
    }

    @ViewBuilder
    private func markdownInlineText(
        _ text: String,
        font: Font,
        color: Color
    ) -> some View {
        Group {
            if let attributed = try? AttributedString(
                markdown: text,
                options: AttributedString.MarkdownParsingOptions(
                    interpretedSyntax: .inlineOnlyPreservingWhitespace,
                    failurePolicy: .returnPartiallyParsedIfPossible
                )
            ) {
                Text(attributed)
            } else {
                Text(text)
            }
        }
        .font(font)
        .foregroundStyle(color)
        .tint(style.linkColor)
        .multilineTextAlignment(.leading)
        .textSelection(.enabled)
    }

    private func highlightedCode(_ code: String, language: String?) -> AttributedString {
        var attributed = codeSyntaxHighlighter.highlight(code, language)
        attributed.font = style.codeFont
        return attributed
    }

    private func markdownInlineFlow(_ text: String, font: Font, color: Color) -> some View {
        let inlines = MarkdownInlineParser.parse(text, softBreakMode: softBreakMode)
        let containsImage = inlines.containsInlineImage

        return Group {
            if containsImage {
                MarkdownInlineFlowLayout(spacing: 0, lineSpacing: 4) {
                    inlineRuns(
                        flattenedInlineRuns(inlines, splitForLayout: true),
                        font: font,
                        color: color
                    )
                }
            } else {
                Text(inlineAttributedString(
                    flattenedInlineRuns(inlines, splitForLayout: false),
                    font: font,
                    color: color
                ))
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .multilineTextAlignment(.leading)
        .tint(style.linkColor)
        .textSelection(.enabled)
    }

    private func inlineRuns(_ runs: [MarkdownInlineRun], font: Font, color: Color) -> some View {
        ForEach(Array(runs.enumerated()), id: \.offset) { _, run in
            inlineRun(run, font: font, color: color)
        }
    }

    private func inlineRun(_ run: MarkdownInlineRun, font: Font, color: Color) -> AnyView {
        switch run.content {
        case .text(let text):
            let textView = Text(text)
                .font(run.resolvedFont(base: font))
                .foregroundStyle(run.linkDestination == nil ? color : style.linkColor)
                .strikethrough(run.isStrikethrough, color: run.linkDestination == nil ? color : style.linkColor)
                .underline(run.linkDestination != nil)

            if let destination = run.linkDestination,
               let url = resolvedURL(destination, relativeTo: baseURL) {
                return AnyView(Link(destination: url) { textView })
            }

            return AnyView(textView)

        case .softBreak:
            return AnyView(Text(" ").font(font))

        case .lineBreak:
            return AnyView(Color.clear
                .frame(width: 0, height: 0)
                .layoutValue(key: MarkdownInlineLineBreakKey.self, value: true))

        case .code(let code):
            return AnyView(Text(code)
                .font(style.codeFont)
                .foregroundStyle(style.codeForegroundColor)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    Capsule(style: .continuous)
                        .fill(style.codeBackgroundColor)
                ))

        case .image(let alt, let source):
            return AnyView(inlineImage(alt: alt, source: source))
        }
    }

    private func splitTextForWrapping(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""

        for character in text {
            if character.isCJKLike {
                if current.isEmpty == false {
                    result.append(current)
                    current = ""
                }
                result.append(String(character))
                continue
            }

            current.append(character)
            if character.isWhitespace || current.count >= 18 {
                result.append(current)
                current = ""
            }
        }
        if current.isEmpty == false {
            result.append(current)
        }
        return result.isEmpty ? [text] : result
    }

    private func flattenedInlineRuns(_ inlines: [MarkdownSegment.Inline], splitForLayout: Bool) -> [MarkdownInlineRun] {
        var runs: [MarkdownInlineRun] = []
        appendInlineRuns(inlines, attributes: MarkdownInlineAttributes(), splitForLayout: splitForLayout, into: &runs)
        return runs
    }

    private func appendInlineRuns(
        _ inlines: [MarkdownSegment.Inline],
        attributes: MarkdownInlineAttributes,
        splitForLayout: Bool,
        into runs: inout [MarkdownInlineRun]
    ) {
        for inline in inlines {
            appendInlineRun(inline, attributes: attributes, splitForLayout: splitForLayout, into: &runs)
        }
    }

    private func appendInlineRun(
        _ inline: MarkdownSegment.Inline,
        attributes: MarkdownInlineAttributes,
        splitForLayout: Bool,
        into runs: inout [MarkdownInlineRun]
    ) {
        switch inline {
        case .text(let text):
            let decoded = text.decodingHTMLEntities()
            let parts = splitForLayout ? splitTextForWrapping(decoded) : [decoded]
            for part in parts where part.isEmpty == false {
                runs.append(MarkdownInlineRun(content: .text(part), attributes: attributes))
            }

        case .softBreak:
            runs.append(MarkdownInlineRun(content: .softBreak, attributes: attributes))

        case .lineBreak:
            runs.append(MarkdownInlineRun(content: .lineBreak, attributes: attributes))

        case .code(let code):
            runs.append(MarkdownInlineRun(content: .code(code.decodingHTMLEntities()), attributes: attributes))

        case .emphasis(let children):
            var childAttributes = attributes
            childAttributes.isEmphasis = true
            appendInlineRuns(children, attributes: childAttributes, splitForLayout: splitForLayout, into: &runs)

        case .strong(let children):
            var childAttributes = attributes
            childAttributes.isStrong = true
            appendInlineRuns(children, attributes: childAttributes, splitForLayout: splitForLayout, into: &runs)

        case .strikethrough(let children):
            var childAttributes = attributes
            childAttributes.isStrikethrough = true
            appendInlineRuns(children, attributes: childAttributes, splitForLayout: splitForLayout, into: &runs)

        case .link(let children, let destination):
            var childAttributes = attributes
            childAttributes.linkDestination = destination
            appendInlineRuns(children, attributes: childAttributes, splitForLayout: splitForLayout, into: &runs)

        case .image(let alt, let source):
            runs.append(MarkdownInlineRun(content: .image(alt: alt, source: source), attributes: attributes))

        case .html(let html):
            if html.isHTMLLineBreak {
                runs.append(MarkdownInlineRun(content: .lineBreak, attributes: attributes))
            } else {
                let text = html.strippingHTMLTags().decodingHTMLEntities()
                guard text.isEmpty == false else { return }
                let parts = splitForLayout ? splitTextForWrapping(text) : [text]
                for part in parts where part.isEmpty == false {
                    runs.append(MarkdownInlineRun(content: .text(part), attributes: attributes))
                }
            }
        }
    }

    private func inlineAttributedString(_ runs: [MarkdownInlineRun], font: Font, color: Color) -> AttributedString {
        var result = AttributedString()

        for run in runs {
            switch run.content {
            case .text(let text):
                result += attributedInlineText(text, run: run, font: font, color: color)

            case .softBreak:
                result += AttributedString(" ")

            case .lineBreak:
                result += AttributedString("\n")

            case .code(let code):
                var attributed = AttributedString(code)
                attributed.font = style.codeFont
                attributed.foregroundColor = style.codeForegroundColor
                attributed.backgroundColor = style.codeBackgroundColor
                result += attributed

            case .image(let alt, _):
                result += attributedInlineText(alt.isEmpty ? "Image" : alt, run: run, font: font, color: style.secondaryTextColor)
            }
        }

        return result
    }

    private func attributedInlineText(_ text: String, run: MarkdownInlineRun, font: Font, color: Color) -> AttributedString {
        var attributed = AttributedString(text)
        attributed.font = run.resolvedFont(base: font)
        attributed.foregroundColor = run.linkDestination == nil ? color : style.linkColor

        if run.isStrikethrough {
            attributed.strikethroughStyle = .single
        }

        if let destination = run.linkDestination {
            attributed.underlineStyle = .single
            attributed.link = resolvedURL(destination, relativeTo: baseURL)
        }

        return attributed
    }

    @ViewBuilder
    private func inlineImage(alt: String, source: String) -> some View {
        if let url = resolvedURL(source, relativeTo: imageBaseURL) {
            MarkdownRemoteImageView(
                url: url,
                alt: alt,
                maxHeight: 18,
                cornerRadius: 3,
                style: style,
                onPreview: presentImagePreview
            )
        } else {
            Text(alt.isEmpty ? "Image" : alt)
                .font(.caption)
                .foregroundStyle(style.secondaryTextColor)
        }
    }

    @ViewBuilder
    private func markdownImage(alt: String, source: String) -> some View {
        if let url = resolvedURL(source, relativeTo: imageBaseURL) {
            MarkdownRemoteImageView(
                url: url,
                alt: alt,
                maxHeight: nil,
                cornerRadius: 6,
                style: style,
                onPreview: presentImagePreview
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 8)
        } else {
            imageFallback(alt: alt)
                .padding(.bottom, 8)
        }
    }

    @MainActor
    private func presentImagePreview(_ cachedImage: MarkdownCachedRemoteImage) async {
        let window = previewWindow(around: cachedImage.sourceURL)
        var inputs: [FilePreviewInput] = []
        inputs.reserveCapacity(window.references.count)
        var selectedIndex = 0

        for (offset, reference) in window.references.enumerated() {
            do {
                let previewImage = offset == window.startIndex
                    ? cachedImage
                    : try await MarkdownRemoteImageCache.shared.image(for: reference.url)
                if offset == window.startIndex {
                    selectedIndex = inputs.count
                }
                inputs.append(FilePreviewInput(
                    fileURL: previewImage.fileURL,
                    displayName: reference.alt.isEmpty ? previewImage.displayName : reference.alt,
                    mimeType: previewImage.mimeType
                ))
            } catch {
                continue
            }
        }

        if inputs.isEmpty {
            inputs = [
                FilePreviewInput(
                    fileURL: cachedImage.fileURL,
                    displayName: cachedImage.displayName,
                    mimeType: cachedImage.mimeType
                )
            ]
            selectedIndex = 0
        }

        activeImagePreviewSheet = MarkdownImagePreviewSheet(
            inputs: inputs,
            startIndex: min(selectedIndex, max(inputs.count - 1, 0))
        )
    }

    private func previewWindow(around url: URL) -> (references: [MarkdownImageReference], startIndex: Int) {
        guard let imageIndex = imageReferences.firstIndex(where: { $0.url == url }) else {
            return ([MarkdownImageReference(url: url, alt: "", source: url.absoluteString)], 0)
        }

        let lowerBound = max(0, imageIndex - 2)
        let upperBound = min(imageReferences.count - 1, imageIndex + 2)
        return (Array(imageReferences[lowerBound ... upperBound]), imageIndex - lowerBound)
    }

    private static func collectImageReferences(in segments: [MarkdownSegment], imageBaseURL: URL?) -> [MarkdownImageReference] {
        var result: [MarkdownImageReference] = []
        appendImageReferences(in: segments, imageBaseURL: imageBaseURL, into: &result)
        return result
    }

    private static func appendImageReferences(
        in segments: [MarkdownSegment],
        imageBaseURL: URL?,
        into result: inout [MarkdownImageReference]
    ) {
        for segment in segments {
            switch segment {
            case .heading(_, let text), .paragraph(let text):
                appendImageReferences(
                    in: MarkdownInlineParser.parse(text),
                    imageBaseURL: imageBaseURL,
                    into: &result
                )

            case .image(let alt, let source):
                if let url = resolvedImageURL(source, relativeTo: imageBaseURL) {
                    result.append(MarkdownImageReference(url: url, alt: alt, source: source))
                }

            case .unorderedList(let items), .orderedList(let items, _):
                for item in items {
                    appendImageReferences(in: item.content, imageBaseURL: imageBaseURL, into: &result)
                }

            case .taskList(let items):
                for item in items {
                    appendImageReferences(in: item.content, imageBaseURL: imageBaseURL, into: &result)
                }

            case .blockquote(let children):
                appendImageReferences(in: children, imageBaseURL: imageBaseURL, into: &result)

            case .table(let header, _, let rows):
                for cell in header + rows.flatMap({ $0 }) {
                    appendImageReferences(
                        in: MarkdownInlineParser.parse(cell),
                        imageBaseURL: imageBaseURL,
                        into: &result
                    )
                }

            case .codeBlock, .htmlBlock, .thematicBreak:
                break
            }
        }
    }

    private static func appendImageReferences(
        in inlines: [MarkdownSegment.Inline],
        imageBaseURL: URL?,
        into result: inout [MarkdownImageReference]
    ) {
        for inline in inlines {
            switch inline {
            case .image(let alt, let source):
                if let url = resolvedImageURL(source, relativeTo: imageBaseURL) {
                    result.append(MarkdownImageReference(url: url, alt: alt, source: source))
                }

            case .emphasis(let children),
                 .strong(let children),
                 .strikethrough(let children),
                 .link(let children, _):
                appendImageReferences(in: children, imageBaseURL: imageBaseURL, into: &result)

            case .text, .softBreak, .lineBreak, .code, .html:
                break
            }
        }
    }

    private static func resolvedImageURL(_ source: String, relativeTo baseURL: URL?) -> URL? {
        if let url = URL(string: source), url.scheme != nil {
            return url
        }
        return URL(string: source, relativeTo: baseURL)
    }

    private func imageFallback(alt: String) -> some View {
        Text(alt.isEmpty ? "Image" : alt)
            .font(.caption)
            .foregroundStyle(style.secondaryTextColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(style.tableBorderColor, lineWidth: 1)
            )
    }

    private func resolvedURL(_ source: String, relativeTo baseURL: URL?) -> URL? {
        if let url = URL(string: source), url.scheme != nil {
            return url
        }
        return URL(string: source, relativeTo: baseURL ?? self.baseURL)
    }

    private func headingFont(level: Int) -> Font {
        switch level {
        case 1: return .system(.title, design: .default).weight(.semibold)
        case 2: return .title2.weight(.semibold)
        case 3: return .title3.weight(.semibold)
        case 4: return .headline.weight(.semibold)
        case 5: return .subheadline.weight(.semibold)
        default: return .subheadline.weight(.semibold)
        }
    }

    private func bulletMarker(for level: Int) -> String {
        switch level % 3 {
        case 1: return "◦"
        case 2: return "▪"
        default: return "•"
        }
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension Array where Element == MarkdownSegment.Inline {
    var containsInlineImage: Bool {
        contains { inline in
            switch inline {
            case .image:
                return true
            case .emphasis(let children),
                 .strong(let children),
                 .strikethrough(let children),
                 .link(let children, _):
                return children.containsInlineImage
            default:
                return false
            }
        }
    }
}

private extension URL {
    var isWebURL: Bool {
        guard let scheme = scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }
}

private struct MarkdownInlineFlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? fallbackWidth
        return layout(subviews: subviews, maxWidth: width).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(subviews: subviews, maxWidth: bounds.width)
        for item in result.items {
            subviews[item.index].place(
                at: CGPoint(x: bounds.minX + item.origin.x, y: bounds.minY + item.origin.y),
                proposal: ProposedViewSize(item.size)
            )
        }
    }

    private func layout(subviews: Subviews, maxWidth: CGFloat) -> (size: CGSize, items: [(index: Int, origin: CGPoint, size: CGSize)]) {
        var items: [(Int, CGPoint, CGSize)] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var usedWidth: CGFloat = 0
        let availableWidth = max(maxWidth, 1)

        for index in subviews.indices {
            if subviews[index][MarkdownInlineLineBreakKey.self] {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
                continue
            }

            let size = subviews[index].sizeThatFits(.unspecified)
            let shouldWrap = x > 0 && x + size.width > availableWidth
            if shouldWrap {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }

            items.append((index, CGPoint(x: x, y: y), size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            usedWidth = max(usedWidth, x)
        }

        return (CGSize(width: min(usedWidth, availableWidth), height: y + lineHeight), items)
    }

    private var fallbackWidth: CGFloat {
        #if canImport(UIKit)
        max(220, UIScreen.main.bounds.width - 88)
        #else
        320
        #endif
    }
}

nonisolated private struct MarkdownInlineLineBreakKey: LayoutValueKey {
    static let defaultValue = false
}

private struct MarkdownTableHeightPreferenceKey: PreferenceKey {
    static let defaultValue: [Int: CGFloat] = [:]

    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue()) { $1 }
    }
}

private struct MarkdownInlineAttributes: Equatable {
    var isEmphasis = false
    var isStrong = false
    var isStrikethrough = false
    var linkDestination: String?
}

private struct MarkdownInlineRun: Equatable {
    enum Content: Equatable {
        case text(String)
        case softBreak
        case lineBreak
        case code(String)
        case image(alt: String, source: String)
    }

    let content: Content
    let attributes: MarkdownInlineAttributes

    var isStrikethrough: Bool {
        attributes.isStrikethrough
    }

    var linkDestination: String? {
        attributes.linkDestination
    }

    func resolvedFont(base: Font) -> Font {
        var font = base
        if attributes.isStrong {
            font = font.weight(.semibold)
        }
        if attributes.isEmphasis {
            font = font.italic()
        }
        return font
    }
}

private extension String {
    func strippingHTMLTags() -> String {
        replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
    }

    func decodingHTMLEntities() -> String {
        var decoded = self
        let replacements = [
            "&lt;": "<",
            "&gt;": ">",
            "&amp;": "&",
            "&quot;": "\"",
            "&#39;": "'",
            "&apos;": "'",
            "&nbsp;": " "
        ]

        for (entity, value) in replacements {
            decoded = decoded.replacingOccurrences(of: entity, with: value)
        }

        return decoded.decodingNumericHTMLEntities()
    }

    func decodingNumericHTMLEntities() -> String {
        let pattern = "&#([0-9]+);|&#x([0-9A-Fa-f]+);"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return self }

        let nsRange = NSRange(startIndex..., in: self)
        let matches = regex.matches(in: self, range: nsRange).reversed()
        var result = self

        for match in matches {
            guard let matchRange = Range(match.range(at: 0), in: result) else { continue }

            let decimalRange = Range(match.range(at: 1), in: result)
            let hexRange = Range(match.range(at: 2), in: result)
            let value: UInt32?

            if let decimalRange {
                value = UInt32(result[decimalRange], radix: 10)
            } else if let hexRange {
                value = UInt32(result[hexRange], radix: 16)
            } else {
                value = nil
            }

            guard let value, let scalar = UnicodeScalar(value) else { continue }
            result.replaceSubrange(matchRange, with: String(Character(scalar)))
        }

        return result
    }

    var isHTMLLineBreak: Bool {
        range(of: "^<\\s*br\\s*/?\\s*>$", options: [.regularExpression, .caseInsensitive]) != nil
    }
}

private extension Character {
    var isCJKLike: Bool {
        unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x2E80...0x2EFF,
                 0x3000...0x303F,
                 0x3040...0x30FF,
                 0x3400...0x4DBF,
                 0x4E00...0x9FFF,
                 0xF900...0xFAFF,
                 0xFF00...0xFFEF:
                return true
            default:
                return false
            }
        }
    }
}
