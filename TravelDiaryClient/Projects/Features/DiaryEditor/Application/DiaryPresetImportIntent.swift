import Foundation

/// 未选择分类时展示完整模板供挑选，但不允许继续导入。
nonisolated struct DiaryPresetImportCategorySelection {
    var hiddenCategories: Set<DiaryLayerSemanticKind>

    init(resuming intent: DiaryPresetImportIntent? = nil) {
        if let intent {
            // 旧记录没有分类字段时，沿用当时的全部开启行为。
            hiddenCategories = intent.hiddenCategories ?? []
        } else {
            hiddenCategories = Set(DiaryLayerSemanticKind.selectablePresetCategories)
        }
    }

    var hasSelection: Bool {
        DiaryLayerSemanticKind.selectablePresetCategories.contains { !hiddenCategories.contains($0) }
    }

    var previewHiddenCategories: Set<DiaryLayerSemanticKind> {
        hasSelection ? hiddenCategories : []
    }
}

/// UI 意图持久化：异常退出后明确继续同一次导入，不创建重复副本。
nonisolated struct DiaryPresetImportIntent: Codable, Identifiable, Sendable {
    let id: UUID
    let templateID: String
    let version: Int
    let pageIDs: [String]
    let wholeBook: Bool
    let targetID: UUID?
    let afterPageID: UUID?
    let title: String
    var hiddenCategories: Set<DiaryLayerSemanticKind>? = nil
    static func key(_ owner: String) -> String { "DiaryPresetIntent." + Data(owner.utf8).base64EncodedString() }
    static func read(owner: String) -> Self? {
        guard let data = UserDefaults.standard.data(forKey: key(owner)) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }
    func save(owner: String) throws { UserDefaults.standard.set(try JSONEncoder().encode(self), forKey: Self.key(owner)) }
    static func clear(owner: String) { UserDefaults.standard.removeObject(forKey: key(owner)) }
}

/// 文件队列可同步检查取消状态；进入原子发布区后不再接受取消。
nonisolated final class DiaryPresetCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    func check() throws { lock.lock(); let value = cancelled; lock.unlock(); if value { throw CancellationError() } }
}
