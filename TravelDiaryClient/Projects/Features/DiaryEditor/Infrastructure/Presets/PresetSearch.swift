import Foundation

nonisolated struct PresetSpreadPlanRequest: Encodable, Sendable {
    struct Selection: Encodable, Sendable { let kind: String; let unit_id: String }
    let selection: Selection
}
nonisolated struct PresetSearchAsset: Codable, Sendable {
    var url: String
    var sha256: String
    var asset_id: String
    var expires_at: TimeInterval
}
nonisolated struct PresetSearchField: Codable, Sendable {
    let text: String; let field: String; let source: String; let rank: Int
}
nonisolated struct PresetSearchTerm: Codable, Sendable {
    let id: String; let name: String; let dimension: String; let aliases: [String]; let source: String
}
nonisolated struct PresetTaxonomy: Codable, Sendable {
    struct Term: Codable, Sendable, Identifiable {
        let id: String; let dimension: String; let name: String; let aliases: [String]; let parent_id: String?
    }
    let revision: Int
    let terms: [Term]
}
nonisolated struct PresetSearchEntry: Codable, Sendable, Identifiable {
    struct Match: Codable, Sendable { let term: String; let field: String; let source: String }
    var id: String
    var entity_type: String
    var template_id: String
    var template_book_id: String
    var version: Int
    var unit_id: String?
    var title: String
    var book_title: String
    var series: String
    var book_page_count: Int
    var page_count: Int
    var page_ids: [String]
    var previews: [[String: PresetSearchAsset]]
    var tags: [String]
    var matched_fields: [Match]
    var search_fields: [PresetSearchField]
    var search_terms: [PresetSearchTerm]
    var position: Int? = nil
    var book_position: Int? = nil
    var book: RemotePresetBook {
        RemotePresetBook(id: template_id, title: book_title, series: series, version: version,
            page_count: book_page_count, cover_url: previews.first?["thumbnailPath"]?.url ?? "")
    }
    var previewPages: [RemotePresetPage] {
        page_ids.enumerated().map { index, id in
            let image = previews.indices.contains(index) ? previews[index] : [:]
            return RemotePresetPage(id: id, title: "\(title) · \(index == 0 ? "左页" : "右页")",
                thumbnail_url: image["thumbnailPath"]?.url ?? "", preview_url: image["largePath"]?.url ?? "")
        }
    }
}
nonisolated struct PresetSearchResponse: Decodable, Sendable {
    let entries: [PresetSearchEntry]
    let total: Int
    let next_cursor: String?
    let has_more: Bool
}

/// Uses the same controlled-term tokenization and AND semantics as the server.
nonisolated enum PresetSearchMatcher {
    static func normalize(_ text: String) -> String {
        text.precomposedStringWithCompatibilityMapping.lowercased()
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
    static func words(_ query: String, taxonomy: PresetTaxonomy?) -> [String] {
        let rawTerms: [String] = (taxonomy?.terms ?? []).flatMap { [$0.name] + $0.aliases }
        let normalized: Set<String> = Set(rawTerms.map { normalize($0) })
        let aliases: [String] = normalized.filter { !$0.isEmpty }.sorted { a, b in
            a.count == b.count ? a < b : a.count > b.count
        }
        return normalize(query).split(separator: " ").flatMap { part -> [String] in
            var rest = String(part), result: [String] = []
            while !rest.isEmpty {
                if let prefix = aliases.first(where: { rest.hasPrefix($0) }) {
                    result.append(prefix); rest.removeFirst(prefix.count)
                } else {
                    let boundary = rest.indices.dropFirst().first { i in aliases.contains { rest[i...].hasPrefix($0) } } ?? rest.endIndex
                    result.append(String(rest[..<boundary])); rest = String(rest[boundary...])
                }
            }
            return result
        }
    }
    static func matches(_ entry: PresetSearchEntry, query: String, taxonomy: PresetTaxonomy?, filters: [String: Set<String>]) -> Bool {
        score(entry, query: query, taxonomy: taxonomy, filters: filters) != nil
    }
    static func score(_ entry: PresetSearchEntry, query: String, taxonomy: PresetTaxonomy?, filters: [String: Set<String>]) -> (Int, Int)? {
        for (dimension, ids) in filters where !ids.isEmpty {
            if !entry.search_terms.contains(where: { $0.dimension == dimension && ids.contains($0.id) }) { return nil }
        }
        var ranks: [Int] = []
        for word in words(query, taxonomy: taxonomy) {
            var candidates: [Int] = []
            for field in entry.search_fields {
                let value = normalize(field.text)
                if value.contains(word) { candidates.append(field.field == "title" ? (value == word ? 0 : value.hasPrefix(word) ? 2 : 3) : field.rank) }
            }
            for term in entry.search_terms where ([term.name] + term.aliases).map(normalize).contains(word) {
                candidates.append(["ancestor", "context"].contains(term.source) ? 6 : term.dimension == "location" ? 1 : 5)
            }
            guard let best = candidates.min() else { return nil }
            ranks.append(best)
        }
        return (ranks.max() ?? 9, ranks.reduce(0, +))
    }
}

@MainActor
extension PresetDownloadManager {
    func refreshedSearchEntry(_ entry: PresetSearchEntry) async throws -> PresetSearchEntry {
        if entry.previews.first?["thumbnailPath"]?.url.hasPrefix("file:") == true { return entry }
        let data = try await request("templates/\(entry.template_id)/\(entry.version)/browse/")
        let browse = try JSONDecoder().decode(RemotePresetBrowse.self, from: data)
        let selected = entry.entity_type == "spread" ? entry.page_ids : [browse.cover_page_id]
        var result = entry
        result.previews = selected.map { id in
            guard let page = browse.pages.first(where: { $0.id == id }) else { return [:] }
            return ["thumbnailPath": PresetSearchAsset(url: page.thumbnail_url, sha256: "", asset_id: id, expires_at: browse.expires_at),
                    "largePath": PresetSearchAsset(url: page.preview_url, sha256: "", asset_id: id, expires_at: browse.expires_at)]
        }
        return result
    }
    func search(kind: String, query: String, filters: [String: Set<String>], cursor: String? = nil, seriesID: String? = nil) async throws -> PresetSearchResponse {
        var items = [URLQueryItem(name: "kind", value: kind), URLQueryItem(name: "q", value: query)]
        for (dimension, ids) in filters where !ids.isEmpty {
            items.append(URLQueryItem(name: "\(dimension)_ids", value: ids.sorted().joined(separator: ",")))
        }
        if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
        if let seriesID { items.append(URLQueryItem(name: "series", value: seriesID)) }
        return try JSONDecoder().decode(PresetSearchResponse.self, from: await request("search/", queryItems: items))
    }
    func searchTaxonomy() async throws -> PresetTaxonomy {
        try JSONDecoder().decode(PresetTaxonomy.self, from: await request("taxonomy/"))
    }
    func offlineSearchEntries(ownerID: String, taxonomy: PresetTaxonomy?) -> [PresetSearchEntry] {
        var result: [String: PresetSearchEntry] = [:]
        let terms = Dictionary(uniqueKeysWithValues: (taxonomy?.terms ?? []).map { ($0.id, $0) })
        func expand(_ ids: [String], ancestors: Bool, source: String) -> [PresetSearchTerm] {
            var output: [PresetSearchTerm] = [], seen = Set<String>()
            for id in ids {
                var term = terms[id], origin = source
                while let value = term, seen.insert(value.id).inserted {
                    output.append(PresetSearchTerm(id: value.id, name: value.name, dimension: value.dimension, aliases: value.aliases, source: origin))
                    term = ancestors ? value.parent_id.flatMap { terms[$0] } : nil; origin = "ancestor"
                }
            }
            return output
        }
        for job in jobs where job.owner == ownerID && job.privateOwner == nil && job.customizationID == nil {
            guard let package = preparedPackage(job.id) else { continue }
            let m = package.manifest
            let pageIDs = Set(m.pages.map(\.id))
            var selections: [(String?, String, [String], [PresetSearchField], [PresetSearchTerm])] = []
            if completeCachedPackage(for: RemotePresetBook(id: m.templateBookID, title: m.title, series: m.seriesID, version: m.packageVersion, page_count: m.pages.count, cover_url: "")) != nil && job.wholeBook {
                selections.append((nil, m.title, m.pages.map(\.id), [.init(text: m.title, field: "title", source: "explicit", rank: 0)], []))
            }
            for u in m.readingUnits ?? [] where u.kind == "spread" && u.searchEnabled && u.pairingSource == "explicit" && u.pageIDs.count == 2 && Set(u.pageIDs).isSubset(of: pageIDs) {
                guard u.pageIDs.allSatisfy({ m.pageMetadata?[$0]?.contentRole == "content" }) else { continue }
                let locations = u.locationMode == "explicit" ? u.locationIDs ?? [] : u.locationMode == "inherit" ? m.metadata?.defaultLocationIDs ?? [] : []
                var effective = expand(locations, ancestors: true, source: u.locationMode == "inherit" ? "context" : "explicit") + expand(u.tagIDs ?? [], ancestors: false, source: "explicit")
                var fields = [PresetSearchField(text: u.title, field: "title", source: "explicit", rank: 0)]
                fields += (u.searchKeywords ?? []).map { .init(text: $0, field: "keyword", source: "explicit", rank: 5) }
                for p in u.pageIDs {
                    if let meta = m.pageMetadata?[p] {
                        if let title = meta.displayTitle { fields.append(.init(text: title, field: "page_title", source: "page", rank: 4)) }
                        effective += expand(meta.locationIDs ?? [], ancestors: true, source: "page") + expand(meta.tagIDs ?? [], ancestors: false, source: "page")
                    }
                }
                selections.append((u.id, u.title, u.pageIDs, fields, effective))
            }
            for (unit, title, ids, fields, effective) in selections {
                let sourcePages = (try? package.pages) ?? []
                let selected = unit == nil ? [m.coverPageID] : ids
                let images: [[String: PresetSearchAsset]] = selected.map { id in
                    guard let page = sourcePages.first(where: { $0.id == id }) else { return [:] }
                    return Dictionary(uniqueKeysWithValues: [("thumbnailPath", page.preview.thumbnailPath), ("largePath", page.preview.largePath)].compactMap { key, path in
                        guard let url = try? package.url(path) else { return nil }
                        return (key, PresetSearchAsset(url: url.absoluteString, sha256: "", asset_id: path, expires_at: .greatestFiniteMagnitude))
                    })
                }
                let key = "\(m.templateBookID):\(m.packageVersion):\(unit ?? m.templateBookID)"
                result[key] = PresetSearchEntry(id: key, entity_type: unit == nil ? "book" : "spread", template_id: m.templateBookID, template_book_id: m.templateBookID,
                    version: m.packageVersion, unit_id: unit, title: title, book_title: m.title, series: m.seriesID, book_page_count: m.pages.count,
                    page_count: ids.count, page_ids: ids, previews: images, tags: effective.filter { $0.dimension != "location" }.map(\.name), matched_fields: [], search_fields: fields, search_terms: effective)
                result[key]?.position = m.readingUnits?.first(where: { $0.id == unit })?.position ?? 0
                result[key]?.book_position = m.sortOrder ?? 0
            }
        }
        let latest = Dictionary(grouping: result.values, by: \.template_id).mapValues { $0.map(\.version).max() ?? 0 }
        return result.values.filter { $0.version == latest[$0.template_id] }.sorted { $0.id < $1.id }
    }
}
