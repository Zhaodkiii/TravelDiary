import Foundation
import Combine

@MainActor protocol FeedbackFormRepository: AnyObject {
    func config() async throws -> HelpServiceConfig
    func require(_ owner: String, formal: Bool) throws
    func submitted(_ key: String, owner: String) async throws -> FeedbackTicket?
    func create(_ draft: FeedbackDraft, owner: String) async throws -> FeedbackTicket
    func upload(_ photo: FeedbackPhoto, owner: String) async throws -> FeedbackPhoto
    func normalizePhoto(_ data: Data) throws -> FeedbackPhoto
    func save(_ draft: FeedbackDraft, owner: String, name: String) throws
    func load(owner: String, name: String) -> FeedbackDraft?
    func removeDraft(owner: String, name: String)
    func refreshUnread(owner: String) async
}

extension HelpFeedbackService: FeedbackFormRepository {}

nonisolated enum FeedbackSubmissionStage: Equatable, Sendable {
    case idle, importing, checking, uploading(Int, Int), sending
    var title: String {
        switch self {
        case .idle: "提交反馈"
        case .importing: "正在准备截图…"
        case .checking: "正在确认提交状态…"
        case .uploading(let current, let total): "正在上传截图 \(current)/\(total)…"
        case .sending: "正在发送反馈…"
        }
    }
}

@MainActor final class FeedbackFormViewModel: ObservableObject {
    let owner: String
    private let repository: any FeedbackFormRepository
    private var loaded = false
    private var signature: Data?
    @Published var draft = FeedbackDraft() {
        didSet {
            guard loaded, success == nil else { return }
            let next = editSignature
            guard next != signature else { return }
            signature = next
            if !isWorking { draft.requestID = UUID().uuidString }
            saveDraft()
        }
    }
    @Published private(set) var config: HelpServiceConfig?
    @Published private(set) var configurationLoading = false
    @Published private(set) var configurationError: String?
    @Published private(set) var stage: FeedbackSubmissionStage = .idle
    @Published private(set) var success: FeedbackTicket?
    @Published private(set) var attempted = false
    @Published private(set) var submissionError: String?
    @Published private(set) var draftSaveError: String?
    @Published private(set) var draftSaved = false
    @Published var notice: String?

    init(owner: String, repository: any FeedbackFormRepository = HelpFeedbackService.shared) {
        self.owner = owner
        self.repository = repository
    }
    var limits: FeedbackSubmissionLimits { (config?.submission_limits ?? .standard).validated }
    var isWorking: Bool { stage != .idle }
    var uploadingPhotoID: UUID? {
        guard case .uploading(let current, _) = stage, draft.photos.indices.contains(current - 1) else { return nil }
        return draft.photos[current - 1].id
    }
    var issues: [FeedbackValidationIssue] {
        FeedbackFormValidation.issues(draft, limits: limits, allowedKinds: config?.types.map(\.code))
    }
    var descriptionCount: Int { supportCharacterCount(draft.description.trimmingCharacters(in: .whitespacesAndNewlines)) }
    var descriptionHint: String {
        if descriptionCount == 0 { return "至少 \(limits.description_min) 个字，方便我们了解问题" }
        return issues.first(where: { $0.field == .description })?.message ?? "描述已填写"
    }
    private var editSignature: Data? {
        try? JSONEncoder().encode([draft.title, draft.description, draft.kind, draft.contact, draft.relatedType,
                                  draft.relatedID, draft.relatedTitle ?? "", draft.articleID ?? "", draft.previousID ?? ""] + draft.photos.map { $0.id.uuidString })
    }
    func prepare(articleID: String?, previousID: String?) async {
        if !loaded {
            draft = repository.load(owner: owner, name: "draft") ?? FeedbackDraft()
            if let articleID { draft.articleID = articleID }
            if let previousID { draft.previousID = previousID }
            signature = editSignature
            loaded = true
            draftSaved = !draft.isEmpty
        }
        await refreshConfiguration()
    }
    func refreshConfiguration() async {
        guard !configurationLoading, !isWorking else { return }
        configurationLoading = true
        defer { configurationLoading = false }
        do {
            let value = try await repository.config()
            try Task.checkCancellation()
            apply(value)
        } catch is CancellationError { }
        catch { configurationError = "暂时无法连接反馈服务，请重试。" }
    }
    private func apply(_ value: HelpServiceConfig) {
        config = value
        configurationError = nil
        if !value.types.contains(where: { $0.code == draft.kind }), let first = value.types.first { draft.kind = first.code }
    }
    func validateForSubmission() -> FeedbackInputField? {
        attempted = true
        submissionError = nil
        return issues.first?.field
    }
    func fieldError(_ field: FeedbackInputField) -> String? {
        guard attempted else { return nil }
        return issues.first(where: { $0.field == field })?.message
    }
    func clearDraft() {
        guard !isWorking else { return }
        draft = FeedbackDraft()
        attempted = false
        notice = nil
        submissionError = nil
        repository.removeDraft(owner: owner, name: "draft")
        draftSaved = false
    }
    func importGuestDraft(_ value: FeedbackDraft) {
        guard !isWorking else { return }
        var imported = value
        imported.requestID = UUID().uuidString
        for index in imported.photos.indices { imported.photos[index].attachmentID = nil; imported.photos[index].uploadedAt = nil }
        draft = imported
        notice = "已导入登录前的草稿，请确认内容后提交。"
    }
    func beginPhotoImport() {
        stage = .importing
        submissionError = nil
        draft.requestID = UUID().uuidString
    }
    func addPhoto(_ data: Data) throws {
        try repository.require(owner, formal: false)
        guard draft.photos.count < limits.attachments_max else { throw HelpFailure("最多添加 \(limits.attachments_max) 张截图") }
        let photo = try repository.normalizePhoto(data)
        guard photo.bytes.count <= limits.attachment_bytes_max else { throw HelpFailure("截图过大，请缩小后重试") }
        draft.photos.append(photo)
        saveDraft()
    }
    func endPhotoImport(error: Error? = nil) {
        stage = .idle
        if let error, !(error is CancellationError), !Task.isCancelled { submissionError = error.localizedDescription }
    }
    func saveDraft() {
        guard loaded, success == nil else { return }
        do {
            try repository.save(draft, owner: owner, name: "draft")
            draftSaveError = nil
            draftSaved = !draft.isEmpty
        } catch { draftSaved = false; draftSaveError = "草稿未能保存，请检查设备可用空间。" }
    }
    private func saveBeforeSending() throws {
        try repository.save(draft, owner: owner, name: "draft")
        draftSaveError = nil
        draftSaved = true
    }
    func submit() async {
        guard !isWorking, validateForSubmission() == nil else { return }
        stage = .checking
        defer { stage = .idle }
        do {
            try repository.require(owner, formal: true)
            // Always resolve an ambiguous previous attempt before replacing expiring upload references.
            if let ticket = try await repository.submitted(draft.requestID, owner: owner) { finish(ticket); return }
            let latest = try await repository.config()
            apply(latest)
            guard latest.accepting else { notice = latest.pause_message; return }
            guard issues.isEmpty else { return }
            try saveBeforeSending()
            for index in draft.photos.indices {
                try Task.checkCancellation()
                stage = .uploading(index + 1, draft.photos.count)
                draft.photos[index] = try await repository.upload(draft.photos[index], owner: owner)
                try saveBeforeSending()
            }
            try Task.checkCancellation()
            stage = .sending
            let ticket = try await repository.create(draft, owner: owner)
            finish(ticket)
        } catch is CancellationError {
            notice = "已取消提交，填写内容保留在本机。"
            saveDraft()
        } catch {
            if Task.isCancelled { notice = "已取消提交，填写内容保留在本机。" }
            else { submissionError = error.localizedDescription }
            saveDraft()
        }
    }
    private func finish(_ ticket: FeedbackTicket) {
        success = ticket
        repository.removeDraft(owner: owner, name: "draft")
        draftSaved = false
        Task { await repository.refreshUnread(owner: owner) }
    }
}
