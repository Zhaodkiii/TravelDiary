import Foundation

nonisolated struct FeedbackSubmissionLimits: Codable, Equatable, Sendable {
    var title_max = 60
    var description_min = 10
    var description_max = 2000
    var contact_max = 100
    var attachments_max = 6
    var attachment_bytes_max = 10_000_000

    static let standard = FeedbackSubmissionLimits()
    var validated: Self {
        guard title_max > 0, description_min > 0, description_max >= description_min,
              description_max <= 100_000, contact_max > 0, (1...6).contains(attachments_max),
              attachment_bytes_max > 0 else { return .standard }
        return self
    }
}

nonisolated enum FeedbackInputField: String, Hashable, Sendable {
    case kind, title, description, contact, photos, related
}

nonisolated struct FeedbackValidationIssue: Equatable, Sendable {
    let field: FeedbackInputField
    let message: String
}

nonisolated enum FeedbackFormValidation {
    static func issues(_ draft: FeedbackDraft, limits: FeedbackSubmissionLimits = .standard,
                       allowedKinds: [String]? = nil) -> [FeedbackValidationIssue] {
        let rules = limits.validated
        var issues: [FeedbackValidationIssue] = []
        if let allowedKinds, !allowedKinds.contains(draft.kind) {
            issues.append(.init(field: .kind, message: "请选择一个问题类型"))
        }
        let titleCount = supportCharacterCount(draft.title.trimmingCharacters(in: .whitespacesAndNewlines))
        if titleCount == 0 { issues.append(.init(field: .title, message: "请先用一句话概括问题")) }
        else if titleCount > rules.title_max { issues.append(.init(field: .title, message: "标题请控制在 \(rules.title_max) 字以内")) }
        let count = supportCharacterCount(draft.description.trimmingCharacters(in: .whitespacesAndNewlines))
        if count < rules.description_min {
            let message = count == 0 ? "请描述发生了什么，至少 \(rules.description_min) 个字" : "描述还差 \(rules.description_min - count) 个字，请再补充一点"
            issues.append(.init(field: .description, message: message))
        } else if count > rules.description_max {
            issues.append(.init(field: .description, message: "描述超出 \(count - rules.description_max) 个字，请精简后提交"))
        }
        if supportCharacterCount(draft.contact.trimmingCharacters(in: .whitespacesAndNewlines)) > rules.contact_max {
            issues.append(.init(field: .contact, message: "联系方式请控制在 \(rules.contact_max) 字以内"))
        }
        if draft.photos.count > rules.attachments_max || draft.photos.contains(where: { $0.bytes.count > rules.attachment_bytes_max }) {
            issues.append(.init(field: .photos, message: "最多添加 \(rules.attachments_max) 张截图，单张不超过 \(rules.attachment_bytes_max / 1_000_000) MB"))
        }
        if !draft.relatedID.isEmpty && (UUID(uuidString: draft.relatedID) == nil || !["order", "customization"].contains(draft.relatedType)) {
            issues.append(.init(field: .related, message: "关联记录已失效，请重新选择或移除"))
        }
        return issues
    }
}

nonisolated enum FeedbackReplyValidation {
    static func issue(text: String, photoCount: Int) -> String? {
        let count = supportCharacterCount(text.trimmingCharacters(in: .whitespacesAndNewlines))
        if count > 2000 { return "补充说明最多 2000 个字，请精简后再发送。" }
        if photoCount > 6 { return "最多添加 6 张截图。" }
        if count == 0 && photoCount == 0 { return "请填写补充说明，或添加一张截图。" }
        return nil
    }
}
