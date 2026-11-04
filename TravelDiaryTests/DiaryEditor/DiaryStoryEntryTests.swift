import Testing
import Foundation
@testable import TravelDiary

@MainActor struct DiaryStoryEntryTests {
    @Test func singleTitleKeepsIdentityAndBlankDoesNotErase() throws {
        var brief = CreationBrief()
        let original = DiaryStoryEntry(kind: .title, text: "晚风", usage: .exact)
        brief.upsertStoryEntry(original)
        brief.upsertStoryEntry(.init(kind: .title, text: "山顶晚风", usage: .exact))
        brief.upsertStoryEntry(.init(kind: .content, text: "  \n", usage: .rewrite))
        #expect(brief.storyEntries?.count == 1)
        #expect(brief.storyEntries?.first?.id == original.id)
        #expect(brief.storyEntries?.first?.text == "山顶晚风")
    }
    @Test func persistencePreservesMultipleContentsAndUnsubmittedDraft() throws {
        var brief = CreationBrief()
        brief.upsertStoryEntry(.init(kind: .content, text: "第一件事", usage: .rewrite))
        brief.upsertStoryEntry(.init(kind: .content, text: "第二件事", usage: .exact))
        brief.storyInputDrafts = ["地点": "尚未写完"]
        #expect(try JSONDecoder().decode(CreationBrief.self, from: JSONEncoder().encode(brief)) == brief)
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(brief)) as? [String: Any])
        json.removeValue(forKey: "storyEntries"); json.removeValue(forKey: "storyInputDrafts")
        #expect(try JSONDecoder().decode(CreationBrief.self, from: JSONSerialization.data(withJSONObject: json)).storyEntries == nil)
    }
    @Test func locationPrivacyAndExactTitleAreEnforced() throws {
        var brief = CreationBrief()
        brief.upsertStoryEntry(.init(kind: .location, text: "光明顶", usage: .reference))
        brief.upsertStoryEntry(.init(kind: .title, text: "山顶的晚风", usage: .exact))
        var request = DiaryAIRequest.editorDefaults(.relayout)
        request.creationBrief = brief; request.allowsText = false
        request = request.coordinated()
        #expect(request.allowsText && !request.writesLocation)
        #expect(throws: (any Error).self) { try DiaryAIWorkspaceTools.validateTextEvidence(["text": "光明顶的晚风"], request: request) }
        #expect(throws: (any Error).self) { try DiaryAIWorkspaceTools.validateTextEvidence(["text": "换了标题", "textRole": "title"], request: request) }
        #expect(throws: (any Error).self) { try DiaryAIWorkspaceTools.validateRequiredStoryTexts(["换了标题"], brief: brief) }
        try DiaryAIWorkspaceTools.validateRequiredStoryTexts(["山顶的晚风"], brief: brief)
        #expect(brief.modelInstructions.contains("先为必须呈现"))
    }
}
