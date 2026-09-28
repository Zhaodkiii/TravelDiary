import Foundation

enum AIPromptKeywords {
    static let currentDate = "{{CURRENT_DATE}}"

    static func contains(_ keyword: String, in text: String) -> Bool {
        text.contains(keyword)
    }

    static func setting(_ keyword: String, enabled: Bool, in text: String) -> String {
        var lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0 != keyword }
        if enabled {
            lines.append(keyword)
        }
        return lines.joined(separator: "\n")
    }
}
