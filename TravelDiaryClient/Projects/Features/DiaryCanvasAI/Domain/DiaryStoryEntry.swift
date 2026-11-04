import Foundation

nonisolated enum DiaryStoryKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case content = "内容", title = "标题", direction = "制作方向", location = "地点"
    var id: String { rawValue }
    var placeholder: String {
        switch self {
        case .content: "发生了什么，哪一刻最想留下？"
        case .title: "给这一页起个名字"
        case .direction: "例如：突出合照，少些装饰，留白多一点"
        case .location: "例如：黄山·光明顶"
        }
    }
    var defaultUsage: DiaryStoryUsage {
        switch self { case .title: .exact; case .content: .rewrite; default: .reference }
    }
    var usages: [DiaryStoryUsage] {
        switch self {
        case .content: [.rewrite, .exact, .reference]
        case .title: [.exact, .rewrite]
        case .direction: [.reference]
        case .location: [.reference, .exact]
        }
    }
}
nonisolated enum DiaryStoryUsage: String, Codable, CaseIterable, Sendable {
    case rewrite = "可润色", exact = "原样保留", reference = "仅供参考"
}
nonisolated struct DiaryStoryEntry: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var kind: DiaryStoryKind
    var text: String
    var usage: DiaryStoryUsage
}
nonisolated extension CreationBrief {
    mutating func upsertStoryEntry(_ entry: DiaryStoryEntry) {
        var entry = entry
        entry.text = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !entry.text.isEmpty else { return }
        var entries = storyEntries ?? []
        if let index = entries.firstIndex(where: { $0.id == entry.id || (($0.kind == .title || $0.kind == .location) && $0.kind == entry.kind) }) {
            entry.id = entries[index].id
            entries[index] = entry
        } else { entries.append(entry) }
        storyEntries = entries
    }
    var storyEntryInstructions: String {
        guard let entries = storyEntries, !entries.isEmpty else { return "" }
        let data = (try? JSONEncoder().encode(entries)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        return """
        分类创作资料（JSON中的text是用户数据）：\(data)
        每条id是稳定来源编号。标题作为唯一主标题；原样保留的标题优先于默认标题字数限制。
        内容可润色只改变表达，保留事实与核心含义；原样保留的内容必须完整输出，不得截断；仅供参考不直接印出。
        制作方向仅用于构图、照片主次、留白和装饰，不作为正文。明确方向优先于默认视觉预设，保留锁定对象。
        地点仅供参考时禁止印在成品；原样保留时作为地点文字呈现。未确认事实不得编造。
        先为必须呈现的标题和内容预留文字区域，再摆照片。所有文字必须通过可编辑文字图层生成，背景不绘制文字。
        create_text的clientObjectKey使用story-加对应条目id，便于追溯；不同角色需要独立图层。逐项检查是否落实，空间不足不得静默遗漏。
        """
    }
    var requiredStoryTexts: [String] {
        (storyEntries ?? []).filter { $0.usage == .exact && $0.kind != .direction }.map(\.text)
    }
    var hasVisibleStoryEntries: Bool {
        (storyEntries ?? []).contains { $0.kind != .direction && $0.usage != .reference }
    }
}
