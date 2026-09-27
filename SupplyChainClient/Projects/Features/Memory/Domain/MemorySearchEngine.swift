import Foundation

struct MemorySearchEngine: Sendable {
    private let stopWords: Set<String> = [
        "a", "an", "the", "and", "or", "to", "of", "in", "on", "for", "with",
        "我", "你", "他", "她", "它", "的", "了", "是", "在", "和", "或", "吗", "呢"
    ]

    private let stopCharacters: Set<Character> = [
        " ", "\n", "\t", "，", "。", "；", ";", ",", ".", "?", "？", "!", "！", "的", "了"
    ]

    private let synonymMap: [String: [String]] = [
        "喜欢": ["偏好", "爱好", "爱吃", "常用"],
        "不喜欢": ["讨厌", "避免", "不爱"],
        "药": ["药物", "用药", "药品", "medication"],
        "过敏": ["allergy", "敏感"],
        "血糖": ["glucose", "糖化", "hba1c"],
        "血压": ["bp", "收缩压", "舒张压"]
    ]

    nonisolated init() {}

    nonisolated func search(records: [MemoryRecord], keyword: String, limit: Int) -> [MemorySearchResult] {
        let terms = tokenize(keyword)
        guard terms.isEmpty == false else { return [] }
        let expandedSynonyms = makeExpandedSynonyms()

        let scored = records.compactMap { record -> MemorySearchResult? in
            let haystack = "\(record.title)\n\(record.content)".lowercased()
            let words = tokenize(haystack)
            var score = record.pinned ? 2 : 0

            for term in terms {
                let isChinese = term.range(of: #"\p{Han}"#, options: .regularExpression) != nil
                if haystack.contains(term) {
                    score += max(4, term.count * 4)
                }

                for word in words where abs(word.count - term.count) <= 2 {
                    let distance = levenshtein(term, word)
                    if distance <= 2 && distance < term.count {
                        score += max(0, term.count - distance) * 2
                        break
                    }
                }

                if let synonyms = expandedSynonyms[term],
                   synonyms.contains(where: { haystack.contains($0) }) {
                    score += max(2, term.count)
                }

                if isChinese, term.count > 1 {
                    for character in term where stopCharacters.contains(character) == false {
                        if haystack.contains(character) {
                            score += 1
                        }
                    }
                }
            }

            guard score > 0 else { return nil }
            return MemorySearchResult(record: record, score: score)
        }

        return scored
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                if $0.record.pinned != $1.record.pinned { return $0.record.pinned && !$1.record.pinned }
                return $0.record.updatedAt > $1.record.updatedAt
            }
            .prefix(max(1, limit))
            .map { $0 }
    }

    nonisolated func tokenize(_ text: String) -> [String] {
        text
            .lowercased()
            .split { scalar in
                scalar.isWhitespace || scalar.isPunctuation || scalar == ";" || scalar == "；"
            }
            .map(String.init)
            .filter { $0.isEmpty == false && stopWords.contains($0) == false }
    }

    nonisolated private func makeExpandedSynonyms() -> [String: Set<String>] {
        var expanded: [String: Set<String>] = [:]
        for (key, values) in synonymMap {
            for value in values {
                expanded[key, default: []].insert(value)
                expanded[value, default: []].insert(key)
                for other in values where other != value {
                    expanded[value, default: []].insert(other)
                }
            }
        }
        return expanded
    }

    nonisolated private func levenshtein(_ lhs: String, _ rhs: String) -> Int {
        let left = Array(lhs)
        let right = Array(rhs)
        var dp = Array(repeating: Array(repeating: 0, count: right.count + 1), count: left.count + 1)
        for index in 0...left.count { dp[index][0] = index }
        for index in 0...right.count { dp[0][index] = index }
        for i in 1...left.count {
            for j in 1...right.count {
                dp[i][j] = min(
                    dp[i - 1][j] + 1,
                    dp[i][j - 1] + 1,
                    dp[i - 1][j - 1] + (left[i - 1] == right[j - 1] ? 0 : 1)
                )
            }
        }
        return dp[left.count][right.count]
    }
}
