import Testing
import Foundation
@testable import TravelDiary

@MainActor
struct DiaryPresetSpreadSearchTests {
    private let taxonomy = PresetTaxonomy(revision: 1, terms: [
        .init(id: "suzhou", dimension: "location", name: "苏州", aliases: ["蘇州", "suzhou"], parent_id: nil),
        .init(id: "lion", dimension: "location", name: "狮子林", aliases: ["獅子林"], parent_id: "suzhou"),
        .init(id: "garden", dimension: "theme", name: "园林", aliases: ["園林"], parent_id: nil)
    ])
    private func entry(garden: Bool) -> PresetSearchEntry {
        var terms = [PresetSearchTerm(id: "suzhou", name: "苏州", dimension: "location", aliases: ["蘇州", "suzhou"], source: "ancestor")]
        if garden { terms += [.init(id: "lion", name: "狮子林", dimension: "location", aliases: ["獅子林"], source: "explicit"), .init(id: "garden", name: "园林", dimension: "theme", aliases: ["園林"], source: "explicit")] }
        let title = garden ? "假山漫游" : "船过蓝调"
        return PresetSearchEntry(id: garden ? "lion" : "boat", entity_type: "spread", template_id: "book", template_book_id: "book", version: 2,
            unit_id: garden ? "lion" : "boat", title: title, book_title: "苏州园林合集", series: "city", book_page_count: 5,
            page_count: 2, page_ids: ["left", "right"], previews: [], tags: [], matched_fields: [],
            search_fields: [.init(text: title, field: "title", source: "explicit", rank: 0)], search_terms: terms)
    }
    @Test func controlledTermsUseLongestMatchAndRetainUnknownRemainder() {
        #expect(PresetSearchMatcher.words("苏州园林", taxonomy: taxonomy) == ["苏州", "园林"])
        #expect(PresetSearchMatcher.words("狮子林", taxonomy: taxonomy) == ["狮子林"])
        #expect(PresetSearchMatcher.words("苏州未知词", taxonomy: taxonomy) == ["苏州", "未知词"])
        #expect(PresetSearchMatcher.normalize(" ＳＵＺＨＯＵ  ") == "suzhou")
    }
    @Test func offlineMatchingDoesNotBroadcastBookTitleToEverySpread() {
        for query in ["园林", "狮子林", "獅子林", "苏州 园林", "蘇州園林"] {
            #expect(PresetSearchMatcher.matches(entry(garden: true), query: query, taxonomy: taxonomy, filters: [:]))
            #expect(!PresetSearchMatcher.matches(entry(garden: false), query: query, taxonomy: taxonomy, filters: [:]))
        }
        #expect(PresetSearchMatcher.matches(entry(garden: false), query: "苏州", taxonomy: taxonomy, filters: [:]))
        #expect(!PresetSearchMatcher.matches(entry(garden: true), query: "苏州未知词", taxonomy: taxonomy, filters: [:]))
        #expect(!PresetSearchMatcher.matches(entry(garden: false), query: "苏州", taxonomy: taxonomy, filters: ["theme": ["garden"]]))
    }
    @Test func explicitPairSurvivesBookRoundtripAndPhysicalParity() throws {
        let pair = UUID()
        var left = DiaryPageEntry(id: UUID(), title: "左页", revisionID: UUID(), size: DiaryPagePreset.a5.size)
        var right = DiaryPageEntry(id: UUID(), title: "右页", revisionID: UUID(), size: DiaryPagePreset.a5.size)
        left.presetSpreadID = pair; left.presetSpreadSide = "left"
        right.presetSpreadID = pair; right.presetSpreadSide = "right"
        var book = DiaryBook(title: "跨页副本"); book.pages = [left, right]; book.coverPageID = left.id
        let reopened = try JSONDecoder().decode(DiaryBook.self, from: JSONEncoder().encode(book))
        #expect(reopened.readingSpreads.count == 1)
        #expect(reopened.readingSpreads[0].compactMap { $0?.id } == [left.id, right.id])
        book.pages = [right]
        #expect(book.readingSpreads[0][0] == nil)
        #expect(book.readingSpreads[0][1]?.id == right.id)
    }
    @Test func spreadPlanSendsUnitIdentityWithoutClientPageOverride() throws {
        let request = PresetSpreadPlanRequest(selection: .init(kind: "spread", unit_id: "lion"))
        let data = try JSONEncoder().encode(request)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["page_ids"] == nil)
        #expect((json["selection"] as? [String: String])?["unit_id"] == "lion")
    }
}
