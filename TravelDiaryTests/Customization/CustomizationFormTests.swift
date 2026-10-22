import Testing
import Foundation
@testable import TravelDiary

struct CustomizationFormTests {
    private let valid = ["title": "云南旅行", "description": "和家人一起走过的小路。"]
    private func photo(_ status: String = "ready") -> CustomAsset {
        CustomAsset(id: UUID().uuidString, client_id: UUID().uuidString, position: 0, note: "", must_use: false,
                    crop_allowed: true, cover_preferred: false, status: status, thumbnail_url: nil,
                    url: nil, job_id: "", error: "")
    }
    @Test func cannotJumpPastRequiredStepsButCanAlwaysGoBack() {
        let noPhotos = CustomizationFormRules.navigationIssue(from: .photos, to: .review, fields: valid, selectedPhotos: 0)
        #expect(noPhotos?.step == .photos)
        #expect(CustomizationFormRules.navigationIssue(from: .photos, to: .review, fields: [:], selectedPhotos: 1)?.field == "title")
        #expect(CustomizationFormRules.navigationIssue(from: .review, to: .photos, fields: [:], selectedPhotos: 0) == nil)
    }
    @Test func canWriteWhileUploadingButCannotSubmitUntilEveryPhotoIsReady() {
        #expect(CustomizationFormRules.navigationIssue(from: .photos, to: .story, fields: [:], selectedPhotos: 2) == nil)
        #expect(CustomizationFormRules.navigationIssue(from: .story, to: .review, fields: valid, selectedPhotos: 2) == nil)
        #expect(CustomizationFormRules.photoIssue(assets: [photo()], pendingJobs: 1, importing: false) != nil)
        #expect(CustomizationFormRules.photoIssue(assets: [photo(), photo("uploading")], pendingJobs: 0, importing: false) != nil)
        #expect(CustomizationFormRules.photoIssue(assets: [photo()], pendingJobs: 0, importing: false) == nil)
    }
    @Test func emptyFailedAndOversizedPhotoSetsCannotSubmit() {
        #expect(CustomizationFormRules.photoIssue(assets: [], pendingJobs: 0, importing: false) != nil)
        #expect(CustomizationFormRules.photoIssue(assets: [photo("failed")], pendingJobs: 0, importing: false) != nil)
        #expect(CustomizationFormRules.photoIssue(assets: [photo()], pendingJobs: 0, importing: true) != nil)
        #expect(CustomizationFormRules.photoIssue(assets: (0..<31).map { _ in photo() }, pendingJobs: 0, importing: false) != nil)
        #expect(CustomizationFormRules.photoIssue(assets: (0..<30).map { _ in photo() }, pendingJobs: 0, importing: false) == nil)
    }
    @Test func namesStoriesAndOptionalRestrictionsAreValidatedWithoutTruncation() {
        #expect(CustomizationFormRules.storyIssue(["title":" \n ", "description":"故事"])?.field == "title")
        #expect(CustomizationFormRules.storyIssue(["title":"标题", "description":" \n"])?.field == "description")
        var fields = valid
        fields["title"] = String(repeating: "字", count: 61)
        #expect(CustomizationFormRules.storyIssue(fields)?.field == "title")
        fields = valid; fields["description"] = String(repeating: "字", count: 3001)
        #expect(CustomizationFormRules.storyIssue(fields)?.field == "description")
        fields = valid; fields["avoid"] = String(repeating: "字", count: 501)
        #expect(CustomizationFormRules.storyIssue(fields)?.field == "avoid")
        fields["avoid"] = String(repeating: "字", count: 500)
        #expect(CustomizationFormRules.storyIssue(fields) == nil)
    }
    @Test func homeHighlightsActionableRequestsWithoutHidingDraftsInHistory() {
        #expect(CustomizationFormRules.needsAttention("needs_info"))
        #expect(CustomizationFormRules.needsAttention("delivered"))
        #expect(!CustomizationFormRules.needsAttention("in_production"))
        #expect(!CustomizationFormRules.isHistory("draft"))
        #expect(!CustomizationFormRules.isHistory("revision_requested"))
        #expect(CustomizationFormRules.isHistory("cancelled"))
        #expect(CustomizationFormRules.isHistory("completed"))
        #expect(CustomizationFormRules.actionTitle(for: "draft") == "继续填写")
        #expect(CustomizationFormRules.actionTitle(for: "delivered") == "查看成品")
    }
    @Test func restoredStepIsScopedToBothAccountAndRequest() {
        let a = CustomizationFormRules.stepKey(owner: "account-a", requestID: "one")
        #expect(a != CustomizationFormRules.stepKey(owner: "account-b", requestID: "one"))
        #expect(a != CustomizationFormRules.stepKey(owner: "account-a", requestID: "two"))
    }
}
