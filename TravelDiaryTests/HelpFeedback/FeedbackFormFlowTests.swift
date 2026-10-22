import Testing
import SwiftUI
import UIKit
@testable import TravelDiary

@MainActor final class FeedbackFormTestRepository: FeedbackFormRepository {
    var value = HelpServiceConfig(accepting: true, pause_message: "暂时暂停受理", service_hours: "24小时", contact: "", types: [
        .init(code: "usage", name: "使用问题"), .init(code: "suggestion", name: "功能建议"), .init(code: "error", name: "异常报错"),
        .init(code: "order", name: "订单相关"), .init(code: "other", name: "其他")], revision: 1)
    var stored: FeedbackDraft?
    var committed: FeedbackTicket?
    var committedKey: String?
    var uploads = 0
    var creates = 0
    var savedKeys: [String] = []
    var saveFailure = false
    var configFailure = false
    var loseCreationResponse = false
    var uploadSuspends = false
    func config() async throws -> HelpServiceConfig {
        if configFailure { throw URLError(.notConnectedToInternet) }
        return value
    }
    func require(_ owner: String, formal: Bool) throws {}
    func submitted(_ key: String, owner: String) async throws -> FeedbackTicket? { key == committedKey ? committed : nil }
    func create(_ draft: FeedbackDraft, owner: String) async throws -> FeedbackTicket {
        creates += 1
        let ticket = fixtureTicket(title: draft.title)
        committed = ticket
        committedKey = draft.requestID
        if loseCreationResponse { throw URLError(.timedOut) }
        return ticket
    }
    func upload(_ photo: FeedbackPhoto, owner: String) async throws -> FeedbackPhoto {
        uploads += 1
        if uploadSuspends { try await Task.sleep(for: .seconds(20)) }
        var result = photo; result.attachmentID = UUID().uuidString; result.uploadedAt = Date()
        return result
    }
    func normalizePhoto(_ data: Data) throws -> FeedbackPhoto { try HelpFeedbackService().normalizePhoto(data) }
    func save(_ draft: FeedbackDraft, owner: String, name: String) throws {
        if saveFailure { throw CocoaError(.fileWriteOutOfSpace) }
        stored = draft; savedKeys.append(draft.requestID)
    }
    func load(owner: String, name: String) -> FeedbackDraft? { stored }
    func removeDraft(owner: String, name: String) { stored = nil }
    func refreshUnread(owner: String) async {}
    func fixtureTicket(title: String = "不开心") -> FeedbackTicket {
        FeedbackTicket(id: "10000000-0000-4000-8000-000000000001", number: "FB10000000000040008000000000000001", title: title,
                       kind: "usage", status: "submitted", revision: 2, public_sequence: 1, read_sequence: 0, unread: false,
                       allowed_actions: ["reply", "close"], created_at: "2026-10-20T15:00:00Z", last_public_activity_at: "2026-10-20T15:00:00Z")
    }
}

@Suite(.serialized)
@MainActor struct FeedbackFormFlowTests {
    private func fixture(description: String = "导出手帐时照片显示模糊，希望协助查看。") async -> (FeedbackFormViewModel, FeedbackFormTestRepository) {
        let repository = FeedbackFormTestRepository()
        var draft = FeedbackDraft(); draft.title = "不开心"; draft.description = description
        repository.stored = draft
        let model = FeedbackFormViewModel(owner: "feedback-tests", repository: repository)
        await model.prepare(articleID: nil, previousID: nil)
        return (model, repository)
    }
    @Test func sixCharacterReportExplainsTheFourMissingCharacters() async {
        let (model, repository) = await fixture(description: "就是不开心")
        #expect(model.descriptionCount == 5)
        model.draft.description = "就是不开心啊"
        #expect(model.descriptionCount == 6)
        #expect(model.descriptionHint.contains("4"))
        #expect(model.validateForSubmission() == .description)
        #expect(model.fieldError(.description)?.contains("4") == true)
        await model.submit()
        #expect(repository.uploads == 0)
        #expect(repository.creates == 0)
    }
    @Test func visibleValidationAndServerLengthRulesAgreeAtTheBoundary() {
        var draft = FeedbackDraft(); draft.title = "导出问题"; draft.description = "一二三四五六七八九十"
        #expect(FeedbackFormValidation.issues(draft).isEmpty)
        draft.description = "  一二三四五六七八九  "
        #expect(FeedbackFormValidation.issues(draft).first?.field == .description)
        draft.description = String(repeating: "字", count: 2001)
        #expect(FeedbackFormValidation.issues(draft).first?.message.contains("超出 1") == true)
    }
    @Test func loadingASavedDraftDoesNotRegenerateItsRetryKey() async {
        let (model, repository) = await fixture()
        let original = model.draft.requestID
        await model.prepare(articleID: nil, previousID: nil)
        #expect(model.draft.requestID == original)
        model.draft.title = "更新后的问题"
        #expect(model.draft.requestID != original)
        #expect(repository.stored?.requestID == model.draft.requestID)
    }
    @Test func successfulSubmissionUploadsAndRemovesTheDraft() async {
        let (model, repository) = await fixture()
        model.draft.photos = [FeedbackPhoto(bytes: Data([1, 2]))]
        let key = model.draft.requestID
        await model.submit()
        #expect(model.success != nil)
        #expect(repository.creates == 1)
        #expect(repository.uploads == 1)
        #expect(model.draft.requestID == key)
        #expect(repository.stored == nil)
        #expect(model.stage == .idle)
    }
    @Test func lostCreationResponseIsRecoveredWithoutAnotherUploadOrCreation() async {
        let (model, repository) = await fixture()
        model.draft.photos = [FeedbackPhoto(bytes: Data([1]))]
        repository.loseCreationResponse = true
        let key = model.draft.requestID
        await model.submit()
        #expect(model.submissionError != nil)
        #expect(repository.stored?.requestID == key)
        await model.submit()
        #expect(model.success != nil)
        #expect(repository.creates == 1)
        #expect(repository.uploads == 1)
    }
    @Test func pauseIsRecheckedBeforeAnyUpload() async {
        let (model, repository) = await fixture()
        repository.value = HelpServiceConfig(accepting: false, pause_message: "暂停处理", service_hours: "", contact: "", types: repository.value.types, revision: 2)
        await model.submit()
        #expect(model.config?.accepting == false)
        #expect(model.notice == "暂停处理")
        #expect(repository.creates == 0)
        #expect(repository.uploads == 0)
    }
    @Test func failedDraftPersistencePreventsAnUnrecoverableSubmission() async {
        let (model, repository) = await fixture()
        repository.saveFailure = true
        await model.submit()
        #expect(model.draftSaveError != nil)
        #expect(repository.creates == 0)
        #expect(model.success == nil)
    }
    @Test func cancellationStopsBeforeCreationAndKeepsTheDraft() async {
        let (model, repository) = await fixture()
        model.draft.photos = [FeedbackPhoto(bytes: Data([1]))]
        repository.uploadSuspends = true
        let task = Task { await model.submit() }
        for _ in 0..<100 where repository.uploads == 0 { await Task.yield() }
        task.cancel(); await task.value
        #expect(repository.creates == 0)
        #expect(model.stage == .idle)
        #expect(repository.stored != nil)
        #expect(model.notice?.contains("已取消") == true)
    }
    @Test func hiddenOptionalFieldErrorsCanBeLocated() {
        var draft = FeedbackDraft(); draft.title = "问题"; draft.description = "一二三四五六七八九十"; draft.contact = String(repeating: "a", count: 101)
        #expect(FeedbackFormValidation.issues(draft).first?.field == .contact)
        draft.contact = "158"; draft.relatedType = "order"; draft.relatedID = "not-a-uuid"
        #expect(FeedbackFormValidation.issues(draft).first?.field == .related)
    }
    @Test func olderConfigurationWithoutLimitsRemainsCompatible() throws {
        let bytes = Data(#"{"accepting":true,"pause_message":"","service_hours":"24小时","contact":"","types":[{"code":"usage","name":"使用问题"}],"revision":1}"#.utf8)
        let config = try JSONDecoder().decode(HelpServiceConfig.self, from: bytes)
        #expect(config.submission_limits == nil)
        #expect((config.submission_limits ?? .standard).description_min == 10)
    }
    @Test func nativeSubmissionScreenshots() async throws {
        let (model, _) = await fixture(description: "就是不开心啊")
        model.draft.contact = "158"
        model.draft.relatedType = "order"
        model.draft.relatedID = "20000000-0000-4000-8000-000000000001"
        model.draft.relatedTitle = "云南旅行手帐"
        let screenshot = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 130)).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 80, height: 130))
            UIColor.systemGray5.setFill(); context.fill(CGRect(x: 8, y: 12, width: 64, height: 14))
            UIColor.systemBrown.withAlphaComponent(0.25).setFill(); context.fill(CGRect(x: 8, y: 38, width: 64, height: 55))
        }
        model.draft.photos = [FeedbackPhoto(bytes: try #require(screenshot.jpegData(compressionQuality: 0.8)))]
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let priorWindow = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; priorWindow?.makeKey() }
        for (name, scheme, size) in [("light", ColorScheme.light, CGSize(width: 402, height: 874)),
                                     ("dark", ColorScheme.dark, CGSize(width: 402, height: 874)),
                                     ("small", ColorScheme.light, CGSize(width: 375, height: 812)),
                                     ("full", ColorScheme.light, CGSize(width: 402, height: 1700))] {
            let root = NavigationStack { FeedbackFormScreen(viewModel: model) }
                .environment(\.colorScheme, scheme).environment(\.locale, Locale(identifier: "zh_Hans_CN"))
            let host = UIHostingController(rootView: root)
            window.rootViewController = host; window.frame = CGRect(origin: .zero, size: size)
            window.windowLevel = .alert + 1; window.makeKeyAndVisible()
            host.view.frame = window.bounds; host.view.setNeedsLayout(); host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(250))
            host.view.layoutIfNeeded()
            let format = UIGraphicsImageRendererFormat(); format.scale = 2
            let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) }
            let bytes = try #require(image.pngData())
            Attachment.record(ContiguousArray(bytes), named: "feedback-\(name).png")
        }
        model.draft.description = "导出手帐时照片变得很模糊，希望帮我看看。"
        await model.submit()
        #expect(model.success != nil)
        let host = UIHostingController(rootView: NavigationStack { FeedbackFormScreen(viewModel: model) }.environment(\.colorScheme, .light))
        window.frame = CGRect(origin: .zero, size: CGSize(width: 402, height: 874))
        window.rootViewController = host; host.view.frame = window.bounds
        try await Task.sleep(for: .milliseconds(250)); host.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) }
        Attachment.record(ContiguousArray(try #require(image.pngData())), named: "feedback-success.png")
    }
    @Test func replyValidationAcceptsScreenshotsAndExplainsEmptyOrLongText() {
        #expect(FeedbackReplyValidation.issue(text: " \n", photoCount: 0) != nil)
        #expect(FeedbackReplyValidation.issue(text: "", photoCount: 1) == nil)
        #expect(FeedbackReplyValidation.issue(text: " 补充说明 ", photoCount: 0) == nil)
        #expect(FeedbackReplyValidation.issue(text: String(repeating: "字", count: 2000) + "\n", photoCount: 0) == nil)
        #expect(FeedbackReplyValidation.issue(text: String(repeating: "字", count: 2001), photoCount: 0) != nil)
        #expect(FeedbackReplyValidation.issue(text: "截图", photoCount: 7) != nil)
    }

    @Test func supportPresentationUsesNativeLayoutAcrossSchemes() async throws {
        let ticket = FeedbackTicket(id: "fixture", number: "FB4514FBB6D5404D93AA975BEB885A1F9B", title: "导出手帐后，照片显示模糊", kind: "error", status: "waiting_user", revision: 2, public_sequence: 2, read_sequence: 1, unread: true, allowed_actions: ["reply", "close"], created_at: "2026-10-20T13:30:00Z", last_public_activity_at: "2026-10-20T14:15:00Z")
        let message = FeedbackMessage(id: "reply", body: "我们已收到反馈。方便补充一下导出时选择的清晰度吗？也可以附上截图，我们会继续帮你排查。", author_type: "staff", sequence: 2, created_at: "2026-10-20T14:15:00Z", redacted: false, attachments: [])
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; previous?.makeKey() }
        for (name, scheme, width) in [("light", ColorScheme.light, 402.0), ("dark", ColorScheme.dark, 402.0), ("small", ColorScheme.light, 375.0)] {
            let root = NavigationStack {
                SupportCanvas {
                    FeedbackDetailSummary(ticket: ticket)
                    Text("问题与回复").font(.headline)
                    FeedbackMessageRow(message: message, onAttachment: { _ in })
                    FeedbackTicketCard(ticket: ticket)
                }.navigationTitle("反馈详情")
            }.environment(\.colorScheme, scheme).environment(\.locale, Locale(identifier: "zh_Hans_CN"))
            let host = UIHostingController(rootView: root)
            window.rootViewController = host; window.frame = CGRect(x: 0, y: 0, width: width, height: 1050)
            window.windowLevel = .alert + 1; window.makeKeyAndVisible(); host.view.frame = window.bounds
            try await Task.sleep(for: .milliseconds(250)); host.view.layoutIfNeeded()
            let format = UIGraphicsImageRendererFormat(); format.scale = 2
            let image = UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { _ in host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) }
            Attachment.record(ContiguousArray(try #require(image.pngData())), named: "support-pages-\(name).png")
        }
        #expect(ticket.statusTitle == "待补充")
        #expect(ticket.statusExplanation.contains("补充"))
    }

}
