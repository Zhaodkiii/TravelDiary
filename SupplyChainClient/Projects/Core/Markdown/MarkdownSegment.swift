import Foundation

enum MarkdownSegment: Equatable, Sendable {
    enum Inline: Equatable, Sendable {
        case text(String)
        case softBreak
        case lineBreak
        case code(String)
        case emphasis([Inline])
        case strong([Inline])
        case strikethrough([Inline])
        case link(text: [Inline], destination: String)
        case image(alt: String, source: String)
        case html(String)
    }

    enum TableAlignment: Equatable, Sendable {
        case leading
        case center
        case trailing
    }

    struct ListItem: Equatable, Sendable {
        let content: [MarkdownSegment]
        let level: Int
        let number: Int?

        var text: String {
            guard case .paragraph(let text) = content.first else { return "" }
            return text
        }
    }

    struct TaskItem: Equatable, Sendable {
        let content: [MarkdownSegment]
        let isDone: Bool
        let level: Int

        var text: String {
            guard case .paragraph(let text) = content.first else { return "" }
            return text
        }
    }

    case heading(level: Int, text: String)
    case paragraph(String)
    case image(alt: String, source: String)
    case unorderedList(items: [ListItem])
    case orderedList(items: [ListItem], start: Int)
    case taskList(items: [TaskItem])
    case blockquote(children: [MarkdownSegment])
    case codeBlock(language: String?, code: String)
    case htmlBlock(String)
    case table(header: [String], alignments: [TableAlignment], rows: [[String]])
    case thematicBreak
}

enum MarkdownSegmentParser {
    static func parse(_ text: String) -> [MarkdownSegment] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        guard lines.isEmpty == false else { return [.paragraph("")] }

        var index = 0
        var result: [MarkdownSegment] = []
        result.reserveCapacity(max(8, lines.count / 2))

        while index < lines.count {
            let rawLine = lines[index]
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.isEmpty {
                index += 1
                continue
            }

            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                let (segment, nextIndex) = parseCodeBlock(lines: lines, start: index)
                result.append(segment)
                index = nextIndex
                continue
            }

            if isThematicBreak(line) {
                result.append(.thematicBreak)
                index += 1
                continue
            }

            if let heading = parseHeading(line) {
                result.append(heading)
                index += 1
                continue
            }

            if let image = parseImageLine(line) {
                result.append(image)
                index += 1
                continue
            }

            if let html = parseHTMLBlock(lines: lines, at: index) {
                result.append(html.segment)
                index = html.nextIndex
                continue
            }

            if isTableHeader(lines: lines, at: index) {
                let (segment, nextIndex) = parseTable(lines: lines, start: index)
                result.append(segment)
                index = nextIndex
                continue
            }

            if line.hasPrefix(">") {
                let (segment, nextIndex) = parseBlockquote(lines: lines, start: index)
                result.append(segment)
                index = nextIndex
                continue
            }

            if parseTaskLine(line) != nil {
                let (segment, nextIndex) = parseTaskList(lines: lines, start: index)
                result.append(segment)
                index = nextIndex
                continue
            }

            if parseUnorderedListItem(line) != nil {
                let (segment, nextIndex) = parseUnorderedList(lines: lines, start: index)
                result.append(segment)
                index = nextIndex
                continue
            }

            if parseOrderedListItem(line) != nil {
                let (segment, nextIndex) = parseOrderedList(lines: lines, start: index)
                result.append(segment)
                index = nextIndex
                continue
            }

            let (segment, nextIndex) = parseParagraph(lines: lines, start: index)
            result.append(segment)
            index = nextIndex
        }

        return result.isEmpty ? [.paragraph("")] : result
    }

    private static func parseCodeBlock(lines: [String], start: Int) -> (MarkdownSegment, Int) {
        let opener = lines[start].trimmingCharacters(in: .whitespaces)
        let fence = opener.hasPrefix("~~~") ? "~~~" : "```"
        let languageToken = opener.replacingOccurrences(of: fence, with: "")
            .trimmingCharacters(in: .whitespaces)
        let language = languageToken.isEmpty ? nil : languageToken

        var index = start + 1
        var content: [String] = []
        while index < lines.count {
            let line = lines[index]
            if line.trimmingCharacters(in: .whitespaces).hasPrefix(fence) {
                return (.codeBlock(language: language, code: content.joined(separator: "\n")), index + 1)
            }
            content.append(line)
            index += 1
        }
        return (.codeBlock(language: language, code: content.joined(separator: "\n")), index)
    }

    private static func parseHeading(_ line: String) -> MarkdownSegment? {
        let leadingHashes = line.prefix { $0 == "#" }.count
        guard (1 ... 6).contains(leadingHashes) else { return nil }
        let remainder = line.dropFirst(leadingHashes)
        guard remainder.first == " " else { return nil }
        return .heading(
            level: leadingHashes,
            text: remainder.trimmingCharacters(in: .whitespaces)
        )
    }

    private static func parseImageLine(_ line: String) -> MarkdownSegment? {
        guard line.hasPrefix("!["), let closeAlt = line.firstIndex(of: "]") else { return nil }
        let openParen = line.index(after: closeAlt)
        guard openParen < line.endIndex, line[openParen] == "(" else { return nil }
        guard line.last == ")" else { return nil }

        let alt = String(line[line.index(line.startIndex, offsetBy: 2)..<closeAlt])
        let sourceStart = line.index(after: openParen)
        let sourceEnd = line.index(before: line.endIndex)
        let source = String(line[sourceStart..<sourceEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard source.isEmpty == false else { return nil }
        return .image(alt: alt, source: source)
    }

    private static func parseBlockquote(lines: [String], start: Int) -> (MarkdownSegment, Int) {
        var index = start
        var quoteLines: [String] = []

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(">") else { break }
            var body = trimmed.dropFirst()
            if body.first == " " { body = body.dropFirst() }
            quoteLines.append(String(body))
            index += 1
        }

        return (.blockquote(children: parse(quoteLines.joined(separator: "\n"))), index)
    }

    private static func parseTaskList(lines: [String], start: Int) -> (MarkdownSegment, Int) {
        var index = start
        var items: [MarkdownSegment.TaskItem] = []
        let baseLevel = indentationLevel(lines[start])

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard let parsed = parseTaskLine(trimmed) else { break }
            let itemLevel = indentationLevel(lines[index])
            guard itemLevel >= baseLevel else { break }
            let nested = collectNestedBlock(lines: lines, start: index + 1, parentLevel: itemLevel)
            let content = makeListItemContent(text: parsed.text, nestedLines: nested.lines)
            items.append(.init(content: content, isDone: parsed.isDone, level: itemLevel))
            index = nested.nextIndex
        }
        return (.taskList(items: items), index)
    }

    private static func parseUnorderedList(lines: [String], start: Int) -> (MarkdownSegment, Int) {
        var index = start
        var items: [MarkdownSegment.ListItem] = []
        let baseLevel = indentationLevel(lines[start])

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard let item = parseUnorderedListItem(trimmed) else { break }
            let itemLevel = indentationLevel(lines[index])
            guard itemLevel >= baseLevel else { break }
            let nested = collectNestedBlock(lines: lines, start: index + 1, parentLevel: itemLevel)
            items.append(.init(content: makeListItemContent(text: item, nestedLines: nested.lines), level: max(0, itemLevel - baseLevel), number: nil))
            index = nested.nextIndex
        }
        return (.unorderedList(items: items), index)
    }

    private static func parseOrderedList(lines: [String], start: Int) -> (MarkdownSegment, Int) {
        var index = start
        var items: [MarkdownSegment.ListItem] = []
        var startNumber: Int?
        var expectedNextNumber: Int?
        let baseLevel = indentationLevel(lines[start])

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard let item = parseOrderedListItem(trimmed) else { break }
            let rawItemLevel = indentationLevel(lines[index])
            guard rawItemLevel >= baseLevel else { break }
            let isSequentialSibling = expectedNextNumber == item.number
            let itemLevel = isSequentialSibling ? baseLevel : rawItemLevel
            startNumber = startNumber ?? item.number
            expectedNextNumber = item.number + 1
            let nested = collectNestedBlock(
                lines: lines,
                start: index + 1,
                parentLevel: itemLevel,
                nextSiblingOrderedNumber: expectedNextNumber
            )
            items.append(.init(content: makeListItemContent(text: item.text, nestedLines: nested.lines), level: max(0, itemLevel - baseLevel), number: item.number))
            index = nested.nextIndex
        }
        return (.orderedList(items: items, start: startNumber ?? 1), index)
    }

    private static func parseParagraph(lines: [String], start: Int) -> (MarkdownSegment, Int) {
        var index = start
        var paragraphLines: [String] = []

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || startsSpecialBlock(lines: lines, at: index) {
                break
            }
            paragraphLines.append(line)
            index += 1
        }

        return (.paragraph(paragraphLines.joined(separator: "\n")), index)
    }

    private static func isTableHeader(lines: [String], at index: Int) -> Bool {
        guard index + 1 < lines.count else { return false }
        let header = lines[index].trimmingCharacters(in: .whitespaces)
        let separator = lines[index + 1].trimmingCharacters(in: .whitespaces)
        return header.contains("|") && isTableSeparator(separator)
    }

    private static func parseTable(lines: [String], start: Int) -> (MarkdownSegment, Int) {
        let header = splitTableRow(lines[start])
        let alignments = parseTableAlignments(lines[start + 1])
        var index = start + 2
        var rows: [[String]] = []

        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.contains("|") == false {
                break
            }
            if startsSpecialBlock(lines: lines, at: index) {
                break
            }
            rows.append(splitTableRow(lines[index]))
            index += 1
        }
        return (.table(header: header, alignments: alignments, rows: rows), index)
    }

    private static func splitTableRow(_ row: String) -> [String] {
        var cells = splitEscaped(row, separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        if cells.first?.isEmpty == true { cells.removeFirst() }
        if cells.last?.isEmpty == true { cells.removeLast() }
        return cells.map { $0.replacingOccurrences(of: "\\|", with: "|") }
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        let allowed = CharacterSet(charactersIn: "|:- ")
        guard line.unicodeScalars.allSatisfy(allowed.contains) else { return false }
        return line.contains("-")
    }

    private static func parseTableAlignments(_ row: String) -> [MarkdownSegment.TableAlignment] {
        splitTableRow(row).map { cell in
            let trimmed = cell.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(":") && trimmed.hasSuffix(":") {
                return .center
            }
            if trimmed.hasSuffix(":") {
                return .trailing
            }
            return .leading
        }
    }

    private static func parseTaskLine(_ line: String) -> MarkdownSegment.TaskItem? {
        guard line.count >= 6 else { return nil }
        guard line.hasPrefix("- [") || line.hasPrefix("* [") || line.hasPrefix("+ [") else { return nil }
        let chars = Array(line)
        guard chars.count >= 6, chars[3] == "]", chars[4] == " " else { return nil }
        let state = chars[2]
        guard state == " " || state == "x" || state == "X" else { return nil }
        let text = String(chars.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        return .init(content: [.paragraph(text)], isDone: state == "x" || state == "X", level: 0)
    }

    private static func parseUnorderedListItem(_ line: String) -> String? {
        guard line.count >= 2 else { return nil }
        let prefix = line.prefix(2)
        guard prefix == "- " || prefix == "* " || prefix == "+ " else { return nil }
        return String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
    }

    private static func parseOrderedListItem(_ line: String) -> (number: Int, text: String)? {
        guard let dot = line.firstIndex(of: ".") else { return nil }
        let numberPart = line[..<dot]
        guard
            numberPart.isEmpty == false,
            numberPart.allSatisfy(\.isNumber),
            let number = Int(numberPart)
        else { return nil }
        let afterDot = line[line.index(after: dot)...]
        if afterDot.isEmpty {
            return (number, "")
        }
        guard afterDot.first == " " else { return nil }
        return (number, afterDot.trimmingCharacters(in: .whitespaces))
    }

    private static func isThematicBreak(_ line: String) -> Bool {
        let compact = line.replacingOccurrences(of: " ", with: "")
        guard compact.count >= 3 else { return false }
        if compact.allSatisfy({ $0 == "-" }) { return true }
        if compact.allSatisfy({ $0 == "*" }) { return true }
        if compact.allSatisfy({ $0 == "_" }) { return true }
        return false
    }

    private static func startsSpecialBlock(lines: [String], at index: Int) -> Bool {
        let line = lines[index].trimmingCharacters(in: .whitespaces)
        if line.isEmpty { return true }
        if line.hasPrefix("```") || line.hasPrefix("~~~") { return true }
        if isThematicBreak(line) { return true }
        if parseHeading(line) != nil { return true }
        if parseImageLine(line) != nil { return true }
        if parseHTMLBlock(lines: lines, at: index) != nil { return true }
        if line.hasPrefix(">") { return true }
        if parseTaskLine(line) != nil { return true }
        if parseUnorderedListItem(line) != nil { return true }
        if parseOrderedListItem(line) != nil { return true }
        if isTableHeader(lines: lines, at: index) { return true }
        return false
    }

    private static func indentationLevel(_ line: String) -> Int {
        let leadingWhitespace = line.prefix { $0 == " " || $0 == "\t" }
        let columns = leadingWhitespace.reduce(0) { partialResult, character in
            partialResult + (character == "\t" ? 4 : 1)
        }
        return max(0, columns / 2)
    }

    private static func collectNestedBlock(
        lines: [String],
        start: Int,
        parentLevel: Int,
        nextSiblingOrderedNumber: Int? = nil
    ) -> (lines: [String], nextIndex: Int) {
        var index = start
        var nestedLines: [String] = []

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                nestedLines.append("")
                index += 1
                continue
            }

            let level = indentationLevel(line)
            if
                let nextSiblingOrderedNumber,
                let ordered = parseOrderedListItem(trimmed),
                ordered.number == nextSiblingOrderedNumber
            {
                break
            }

            if level <= parentLevel {
                if startsSpecialBlock(lines: lines, at: index) {
                    break
                }
            }

            nestedLines.append(removeIndent(from: line, levels: parentLevel + 1))
            index += 1
        }

        while nestedLines.last?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            nestedLines.removeLast()
        }
        return (nestedLines, index)
    }

    private static func makeListItemContent(text: String, nestedLines: [String]) -> [MarkdownSegment] {
        var content: [MarkdownSegment] = text.isEmpty ? [] : [.paragraph(text)]
        if nestedLines.isEmpty == false {
            content.append(contentsOf: parse(nestedLines.joined(separator: "\n")))
        }
        return content
    }

    private static func removeIndent(from line: String, levels: Int) -> String {
        var remainingColumns = levels * 2
        var result = line[...]
        while remainingColumns > 0, let first = result.first {
            if first == " " {
                result = result.dropFirst()
                remainingColumns -= 1
            } else if first == "\t" {
                result = result.dropFirst()
                remainingColumns -= 4
            } else {
                break
            }
        }
        return String(result)
    }

    private static func parseHTMLBlock(lines: [String], at index: Int) -> (segment: MarkdownSegment, nextIndex: Int)? {
        let line = lines[index].trimmingCharacters(in: .whitespaces)
        guard line.hasPrefix("<"), line.hasSuffix(">"), line.contains(" ") || line.contains("/") else { return nil }
        return (.htmlBlock(lines[index]), index + 1)
    }

    private static func splitEscaped(_ text: String, separator: Character) -> [String] {
        var result: [String] = []
        var current = ""
        var isEscaped = false
        for character in text {
            if isEscaped {
                current.append("\\")
                current.append(character)
                isEscaped = false
            } else if character == "\\" {
                isEscaped = true
            } else if character == separator {
                result.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        if isEscaped { current.append("\\") }
        result.append(current)
        return result
    }
}

enum MarkdownInlineParser {
    static func parse(_ text: String, softBreakMode: MarkdownSoftBreakMode = .space) -> [MarkdownSegment.Inline] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        var result: [MarkdownSegment.Inline] = []
        var index = normalized.startIndex

        while index < normalized.endIndex {
            if normalized[index] == "\n" {
                if consumeHardBreakMarker(in: &result) {
                    result.append(.lineBreak)
                    index = normalized.index(after: index)
                    continue
                }
                result.append(softBreakMode == .lineBreak ? .lineBreak : .softBreak)
                index = normalized.index(after: index)
                continue
            }

            if normalized[index] == "\\", let escaped = parseEscapedCharacter(normalized, start: index) {
                result.append(.text(String(escaped.character)))
                index = escaped.nextIndex
                continue
            }

            if normalized[index] == "`", let parsed = parseDelimited(normalized, start: index, marker: "`") {
                result.append(.code(parsed.body))
                index = parsed.nextIndex
                continue
            }

            if normalized[index...].hasPrefix("**"), let parsed = parseDelimited(normalized, start: index, marker: "**") {
                result.append(.strong(parse(parsed.body, softBreakMode: softBreakMode)))
                index = parsed.nextIndex
                continue
            }

            if normalized[index...].hasPrefix("__"), let parsed = parseDelimited(normalized, start: index, marker: "__") {
                result.append(.strong(parse(parsed.body, softBreakMode: softBreakMode)))
                index = parsed.nextIndex
                continue
            }

            if normalized[index...].hasPrefix("~~"), let parsed = parseDelimited(normalized, start: index, marker: "~~") {
                result.append(.strikethrough(parse(parsed.body, softBreakMode: softBreakMode)))
                index = parsed.nextIndex
                continue
            }

            if normalized[index] == "*", let parsed = parseDelimited(normalized, start: index, marker: "*") {
                result.append(.emphasis(parse(parsed.body, softBreakMode: softBreakMode)))
                index = parsed.nextIndex
                continue
            }

            if normalized[index] == "_", let parsed = parseDelimited(normalized, start: index, marker: "_") {
                result.append(.emphasis(parse(parsed.body, softBreakMode: softBreakMode)))
                index = parsed.nextIndex
                continue
            }

            if normalized[index...].hasPrefix("!["),
               let parsed = parseLinkOrImage(normalized, start: index, isImage: true) {
                result.append(.image(alt: parsed.label, source: parsed.destination))
                index = parsed.nextIndex
                continue
            }

            if normalized[index] == "[",
               let parsed = parseLinkOrImage(normalized, start: index, isImage: false) {
                result.append(.link(text: parse(parsed.label, softBreakMode: softBreakMode), destination: parsed.destination))
                index = parsed.nextIndex
                continue
            }

            if normalized[index] == "<", let parsed = parseInlineHTMLOrAutolink(normalized, start: index) {
                result.append(parsed.inline)
                index = parsed.nextIndex
                continue
            }

            if let parsed = parseBareURL(normalized, start: index) {
                result.append(.link(text: [.text(parsed.url)], destination: parsed.url))
                index = parsed.nextIndex
                continue
            }

            let next = nextSpecialIndex(in: normalized, from: index) ?? normalized.endIndex
            result.append(.text(String(normalized[index..<next])))
            index = next
        }

        return coalescingText(result)
    }

    private static func parseDelimited(_ text: String, start: String.Index, marker: String) -> (body: String, nextIndex: String.Index)? {
        let bodyStart = text.index(start, offsetBy: marker.count)
        guard bodyStart < text.endIndex else { return nil }
        guard let endRange = text[bodyStart...].range(of: marker) else { return nil }
        let body = String(text[bodyStart..<endRange.lowerBound])
        guard body.isEmpty == false else { return nil }
        return (body, endRange.upperBound)
    }

    private static func parseLinkOrImage(_ text: String, start: String.Index, isImage: Bool) -> (label: String, destination: String, nextIndex: String.Index)? {
        let labelStart = text.index(start, offsetBy: isImage ? 2 : 1)
        guard let labelEnd = text[labelStart...].firstIndex(of: "]") else { return nil }
        let destinationOpen = text.index(after: labelEnd)
        guard destinationOpen < text.endIndex, text[destinationOpen] == "(" else { return nil }
        let destinationStart = text.index(after: destinationOpen)
        guard let destinationEnd = text[destinationStart...].firstIndex(of: ")") else { return nil }
        let destination = String(text[destinationStart..<destinationEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard destination.isEmpty == false else { return nil }
        return (String(text[labelStart..<labelEnd]), destination, text.index(after: destinationEnd))
    }

    private static func parseInlineHTMLOrAutolink(_ text: String, start: String.Index) -> (inline: MarkdownSegment.Inline, nextIndex: String.Index)? {
        guard let end = text[start...].firstIndex(of: ">") else { return nil }
        let bodyStart = text.index(after: start)
        let body = String(text[bodyStart..<end])
        guard body.isEmpty == false else { return nil }
        let nextIndex = text.index(after: end)

        if body.hasPrefix("http://") || body.hasPrefix("https://") {
            return (.link(text: [.text(body)], destination: body), nextIndex)
        }
        if isEmailAddress(body) {
            return (.link(text: [.text(body)], destination: "mailto:\(body)"), nextIndex)
        }
        return (.html("<\(body)>"), nextIndex)
    }

    private static func parseBareURL(_ text: String, start: String.Index) -> (url: String, nextIndex: String.Index)? {
        let prefixes = ["https://", "http://"]
        guard prefixes.contains(where: { text[start...].hasPrefix($0) }) else { return nil }
        var index = start
        while index < text.endIndex, text[index].isWhitespace == false {
            index = text.index(after: index)
        }
        var url = String(text[start..<index])
        while let last = url.last, ".,;:)".contains(last) {
            url.removeLast()
            index = text.index(before: index)
        }
        return url.isEmpty ? nil : (url, index)
    }

    private static func nextSpecialIndex(in text: String, from start: String.Index) -> String.Index? {
        var index = text.index(after: start)
        while index < text.endIndex {
            let suffix = text[index...]
            if text[index] == "\n" || text[index] == "\\" || text[index] == "`" || text[index] == "*" || text[index] == "_" || text[index] == "[" || text[index] == "<" || suffix.hasPrefix("![") || suffix.hasPrefix("~~") || suffix.hasPrefix("http://") || suffix.hasPrefix("https://") {
                return index
            }
            index = text.index(after: index)
        }
        return nil
    }

    private static func coalescingText(_ inlines: [MarkdownSegment.Inline]) -> [MarkdownSegment.Inline] {
        inlines.reduce(into: []) { result, inline in
            if case .text(let text) = inline, case .text(let previous)? = result.last {
                result[result.count - 1] = .text(previous + text)
            } else {
                result.append(inline)
            }
        }
    }

    private static func parseEscapedCharacter(_ text: String, start: String.Index) -> (character: Character, nextIndex: String.Index)? {
        let next = text.index(after: start)
        guard next < text.endIndex else { return nil }
        let escapable = "\\`*_{}[]<>()#+-.!|"
        guard escapable.contains(text[next]) else { return nil }
        return (text[next], text.index(after: next))
    }

    private static func consumeHardBreakMarker(in inlines: inout [MarkdownSegment.Inline]) -> Bool {
        guard case .text(let text)? = inlines.last else { return false }
        if text.hasSuffix("  ") {
            inlines[inlines.count - 1] = .text(String(text.dropLast(2)))
            return true
        }
        if text.hasSuffix("\\") {
            inlines[inlines.count - 1] = .text(String(text.dropLast()))
            return true
        }
        return false
    }

    private static func isEmailAddress(_ text: String) -> Bool {
        guard text.contains("@"), text.contains(".") else { return false }
        let parts = text.split(separator: "@")
        guard parts.count == 2, parts[0].isEmpty == false, parts[1].contains(".") else { return false }
        return text.allSatisfy { character in
            character.isLetter || character.isNumber || ".!#$%&'*+-/=?^_`{|}~@".contains(character)
        }
    }
}

public enum MarkdownSoftBreakMode: Sendable {
    case space
    case lineBreak
}
