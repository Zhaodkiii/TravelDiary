import Foundation

/// 轻量关键词检索：复用 Memory 模块的分词与同义词策略，对知识库文档做片段召回。
struct KnowledgeSearchEngine: Sendable {
    private let memorySearchEngine = MemorySearchEngine()

    nonisolated init() {}

    nonisolated func search(
        knowledgeBases: [KnowledgeBase],
        query: String,
        limit: Int
    ) -> [KnowledgeSearchHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return [] }

        var hits: [KnowledgeSearchHit] = []
        for base in knowledgeBases {
            for document in base.documents {
                let pseudoRecord = MemoryRecord(
                    id: UUID(uuidString: document.id) ?? UUID(),
                    title: document.title,
                    content: document.content
                )
                let results = memorySearchEngine.search(
                    records: [pseudoRecord],
                    keyword: trimmed,
                    limit: 1
                )
                guard let best = results.first, best.score > 0 else { continue }
                hits.append(
                    KnowledgeSearchHit(
                        knowledgeBaseID: base.id,
                        knowledgeBaseName: base.name,
                        documentID: document.id,
                        title: document.title,
                        snippet: extractSnippet(from: document.content, query: trimmed),
                        score: best.score
                    )
                )
            }
        }

        return hits
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                return $0.title < $1.title
            }
            .prefix(max(1, limit))
            .map { $0 }
    }

    nonisolated private func extractSnippet(from content: String, query: String, radius: Int = 120) -> String {
        let lowered = content.lowercased()
        let terms = memorySearchEngine.tokenize(query)
        guard let term = terms.first(where: { lowered.contains($0) }),
              let range = lowered.range(of: term)
        else {
            return String(content.prefix(radius)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let startOffset = lowered.distance(from: lowered.startIndex, to: range.lowerBound)
        let start = content.index(content.startIndex, offsetBy: max(0, startOffset - radius / 2), limitedBy: content.endIndex) ?? content.startIndex
        let end = content.index(start, offsetBy: radius, limitedBy: content.endIndex) ?? content.endIndex
        var snippet = String(content[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        if start > content.startIndex { snippet = "…" + snippet }
        if end < content.endIndex { snippet += "…" }
        return snippet
    }
}
