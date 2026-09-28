import Foundation

final class SparkMedicalTermsCorrector {
    nonisolated(unsafe) static let shared = SparkMedicalTermsCorrector()

    private let terms: [String] = [
        "MRI", "MRA", "T1WI", "T2WI", "FLAIR", "DWI", "ADC", "SWI", "TOF-MRA",
        "CT", "CTA", "HRCT", "PET-CT", "血常规", "尿常规", "肝功能", "肾功能", "甲状腺功能",
        "AFP", "CEA", "CA199", "CA125", "mmol/L", "mg/dL", "U/L", "mmHg"
    ]

    private let patterns: [(String, String)] = [
        ("FLA[1Il]R", "FLAIR"),
        ("T[0O]F", "TOF"),
        ("T[1Il][一-]?W[1Il]", "T1WI"),
        ("T[2Z][一-]?W[1Il]", "T2WI"),
        ("DW[1Il]", "DWI"),
        ("MR[1Il]", "MRI")
    ]

    nonisolated func correct(_ text: String) -> String {
        var output = text

        for (pattern, replacement) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(output.startIndex..<output.endIndex, in: output)
                output = regex.stringByReplacingMatches(in: output, options: [], range: range, withTemplate: replacement)
            }
        }

        output = normalizeWhitespace(output)
        return fuzzyFix(output)
    }

    nonisolated private func fuzzyFix(_ text: String) -> String {
        var output = text
        for term in terms {
            let pattern = term
                .replacingOccurrences(of: "I", with: "[IiLl1]")
                .replacingOccurrences(of: "O", with: "[Oo0]")
                .replacingOccurrences(of: "A", with: "[Aa4]")
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(output.startIndex..<output.endIndex, in: output)
                output = regex.stringByReplacingMatches(in: output, options: [], range: range, withTemplate: term)
            }
        }
        return output
    }

    nonisolated private func normalizeWhitespace(_ text: String) -> String {
        let cleanedLines = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
        return cleanedLines.replacingOccurrences(of: " {2,}", with: " ", options: .regularExpression)
    }
}
