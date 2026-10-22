import Foundation

nonisolated enum CustomizationFormStep: Int, CaseIterable, Identifiable {
    case photos, story, review
    var id: Int { rawValue }
    var title: String {
        switch self { case .photos: "选择照片"; case .story: "讲讲故事"; case .review: "确认需求" }
    }
}

nonisolated struct CustomizationFormIssue: Equatable {
    let step: CustomizationFormStep
    let field: String
    let message: String
}

/// 与提交入口共用规则，翻页和最终提交都不能跳过真实照片状态。
nonisolated enum CustomizationFormRules {
    static func storyIssue(_ fields: [String: String]) -> CustomizationFormIssue? {
        let title = fields["title", default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
        let story = fields["description", default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty { return .init(step: .story, field: "title", message: "给这本手帐起个名字。") }
        if title.count > 60 { return .init(step: .story, field: "title", message: "手帐名称最多 60 字。") }
        if story.isEmpty { return .init(step: .story, field: "description", message: "请简单讲讲你想记录的故事。") }
        if story.count > 3000 { return .init(step: .story, field: "description", message: "故事描述最多 3000 字。") }
        if fields["avoid", default: ""].count > 500 {
            return .init(step: .story, field: "avoid", message: "不希望出现的内容最多 500 字。")
        }
        return nil
    }
    static func photoIssue(assets: [CustomAsset], pendingJobs: Int, importing: Bool) -> CustomizationFormIssue? {
        if importing { return .init(step: .photos, field: "photos", message: "照片仍在读取，请稍等。") }
        if assets.count > 30 { return .init(step: .photos, field: "photos", message: "每次定制最多选择 30 张照片。") }
        if pendingJobs > 0 || assets.contains(where: { $0.status != "ready" }) {
            return .init(step: .photos, field: "photos", message: "还有照片未上传完成，请查看进度或重试。")
        }
        if assets.isEmpty { return .init(step: .photos, field: "photos", message: "请至少添加 1 张照片。") }
        return nil
    }
    static func navigationIssue(from current: CustomizationFormStep, to target: CustomizationFormStep,
                                fields: [String: String], selectedPhotos: Int) -> CustomizationFormIssue? {
        guard target.rawValue > current.rawValue else { return nil }
        if selectedPhotos == 0 { return .init(step: .photos, field: "photos", message: "请先添加至少 1 张照片，再讲讲故事。") }
        return target == .review ? storyIssue(fields) : nil
    }
    static func actionTitle(for status: String) -> String {
        switch status {
        case "draft": "继续填写"
        case "needs_info": "补充资料"
        case "delivered": "查看成品"
        case "completed": "查看手帐"
        default: "查看详情"
        }
    }
    static func needsAttention(_ status: String) -> Bool { ["needs_info", "delivered"].contains(status) }
    static func isHistory(_ status: String) -> Bool { ["completed", "cancelled", "rejected"].contains(status) }
    static func stepKey(owner: String, requestID: String) -> String {
        "CustomizationStep.v1." + Data(owner.utf8).base64EncodedString() + "." + requestID
    }
}
